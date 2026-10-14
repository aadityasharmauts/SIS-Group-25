-- Phase 5: chat messages. The rules are written up in docs/backend/chat.md.

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),

  conversation_id uuid not null
    references public.conversations(id)
    on delete cascade,

  sender_id uuid not null default auth.uid()
    references public.profiles(id)
    on delete cascade,

  body text not null,

  created_at timestamptz not null default now(),
  deleted_at timestamptz,

  constraint messages_body_shape check (
    (deleted_at is null and char_length(btrim(body)) between 1 and 2000)
    or (deleted_at is not null and body = '')
  )
);

comment on table public.messages is
  'Chat messages. Deleted ones keep their row with an empty body.';

create index if not exists messages_conversation_created_idx
  on public.messages (conversation_id, created_at);

create index if not exists messages_sender_created_idx
  on public.messages (sender_id, created_at);


-- original text of deleted messages, kept for reports. Separate table
-- because hiding a column on messages would break select('*').
create table if not exists public.message_deleted_bodies (
  message_id uuid primary key
    references public.messages(id)
    on delete cascade,
  original_body text not null,
  deleted_at timestamptz not null default now()
);

comment on table public.message_deleted_bodies is
  'Original text of deleted messages. service_role only.';

-- RLS on with no policies = only service_role can read it
alter table public.message_deleted_bodies enable row level security;

revoke all on table public.message_deleted_bodies from anon, authenticated;
grant all privileges on table public.message_deleted_bodies to service_role;


create or replace function public.guard_message_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conv record;
  v_activity record;
  v_recent int;
begin
  -- server-side calls (no auth.uid()) skip the checks
  if auth.uid() is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
    new.deleted_at := null;

    select c.kind, c.user_a, c.user_b, c.activity_id
      into v_conv
    from public.conversations c
    where c.id = new.conversation_id;

    if v_conv.kind = 'private' then
      -- same error for blocked as for not a member, so blocks stay hidden
      if auth.uid() not in (v_conv.user_a, v_conv.user_b)
         or public.is_blocked_between(v_conv.user_a, v_conv.user_b) then
        raise exception using
          errcode = 'P0001',
          message = '[forbidden] You can''t send messages in this conversation.';
      end if;

      if not public.are_connected(v_conv.user_a, v_conv.user_b) then
        raise exception using
          errcode = 'P0001',
          message = '[not_connected] You''re no longer connected with this person.';
      end if;

    elsif v_conv.kind = 'activity' then
      if not public.is_activity_participant(v_conv.activity_id) then
        raise exception using
          errcode = 'P0001',
          message = '[forbidden] You can''t send messages in this conversation.';
      end if;

      select a.status, a.end_time
        into v_activity
      from public.activities a
      where a.id = v_conv.activity_id;

      if v_activity.status = 'cancelled' then
        raise exception using
          errcode = 'P0001',
          message = '[activity_cancelled] This activity has been cancelled.';
      end if;

      if v_activity.end_time <= now() then
        raise exception using
          errcode = 'P0001',
          message = '[expired] This activity has ended. The chat is read-only now.';
      end if;

    else
      raise exception using
        errcode = 'P0001',
        message = '[forbidden] You can''t send messages in this conversation.';
    end if;

    -- 20 a minute. Counts the caller, not new.sender_id.
    select count(*) into v_recent
    from public.messages m
    where m.sender_id = auth.uid()
      and m.created_at > now() - interval '1 minute';

    if v_recent >= 20 then
      raise exception using
        errcode = 'P0001',
        message = '[rate_limited] You''re sending messages too quickly. Wait a moment and try again.';
    end if;

    return new;
  end if;

  -- updates: the only thing allowed is deleting your own message
  if new.id is distinct from old.id
    or new.conversation_id is distinct from old.conversation_id
    or new.sender_id is distinct from old.sender_id
    or new.created_at is distinct from old.created_at
  then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] Protected message fields cannot be changed.';
  end if;

  if old.deleted_at is not null then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] This message has already been deleted.';
  end if;

  if new.deleted_at is null then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] Messages can''t be edited, only deleted.';
  end if;

  insert into public.message_deleted_bodies (message_id, original_body)
  values (old.id, old.body);

  new.body := '';
  new.deleted_at := now();
  return new;
end;
$$;

comment on function public.guard_message_write() is
  'Checks who can send where, the rate limit, and that updates are only deletes.';

drop trigger if exists on_message_write_guard on public.messages;
create trigger on_message_write_guard
  before insert or update on public.messages
  for each row
  execute function public.guard_message_write();


alter table public.messages enable row level security;

-- the block check also hides a blocked person's messages in group chats
create policy "members can read messages"
  on public.messages
  for select
  to authenticated
  using (
    public.is_verified_user()
    and public.is_conversation_member(conversation_id)
    and not public.is_blocked_between(sender_id)
  );

create policy "members can send messages"
  on public.messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and public.is_verified_user()
    and public.is_conversation_member(conversation_id)
  );

create policy "senders can delete their own messages"
  on public.messages
  for update
  to authenticated
  using (
    sender_id = auth.uid()
    and public.is_verified_user()
  )
  with check (sender_id = auth.uid());

-- no delete policy, deleting is done with an update so the row stays

revoke all on table public.messages from anon;
revoke delete on table public.messages from authenticated;
grant select, insert, update on table public.messages to authenticated;
grant all privileges on table public.messages to service_role;
