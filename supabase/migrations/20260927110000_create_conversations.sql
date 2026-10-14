-- Phase 5: chat conversations.
-- One per connected pair and one per activity. The triggers below create
-- them, the client never does.

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),

  kind text not null
    check (kind in ('private', 'activity')),

  -- private chats (sorted so each pair only gets one row)
  user_a uuid references public.profiles(id) on delete cascade,
  user_b uuid references public.profiles(id) on delete cascade,

  -- activity chats
  activity_id uuid references public.activities(id) on delete cascade,

  created_at timestamptz not null default now(),

  constraint conversations_shape check (
    (kind = 'private'
      and user_a is not null and user_b is not null
      and user_a < user_b
      and activity_id is null)
    or
    (kind = 'activity'
      and activity_id is not null
      and user_a is null and user_b is null)
  )
);

comment on table public.conversations is
  'One chat per connected pair or per activity. Created by triggers only.';

create unique index if not exists conversations_private_pair_idx
  on public.conversations (user_a, user_b)
  where kind = 'private';

create unique index if not exists conversations_activity_idx
  on public.conversations (activity_id)
  where kind = 'activity';

create index if not exists conversations_user_b_idx
  on public.conversations (user_b)
  where kind = 'private';


-- Who can read a chat. Private: either person, unless there's a block.
-- Activity: accepted participants (creator counts, 'left' doesn't).
create or replace function public.is_conversation_member(
  p_conversation_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.conversations c
    where c.id = p_conversation_id
      and (
        (c.kind = 'private'
          and p_user_id in (c.user_a, c.user_b)
          and not public.is_blocked_between(c.user_a, c.user_b))
        or
        (c.kind = 'activity'
          and public.is_activity_participant(c.activity_id, p_user_id))
      )
  )
$$;

comment on function public.is_conversation_member(uuid, uuid) is
  'True if the user can read this conversation.';

revoke all on function public.is_conversation_member(uuid, uuid) from public, anon;
grant execute on function public.is_conversation_member(uuid, uuid) to authenticated;


create or replace function public.create_private_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- does nothing if they reconnect, so they keep their old chat
  insert into public.conversations (kind, user_a, user_b)
  values (
    'private',
    least(new.requester_id, new.addressee_id),
    greatest(new.requester_id, new.addressee_id)
  )
  on conflict do nothing;

  return new;
end;
$$;

comment on function public.create_private_conversation() is
  'Opens a private chat when a connection is accepted.';

drop trigger if exists on_connection_accepted_open_conversation on public.connections;
create trigger on_connection_accepted_open_conversation
  after insert or update of status on public.connections
  for each row
  when (new.status = 'accepted')
  execute function public.create_private_conversation();

create or replace function public.create_activity_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.conversations (kind, activity_id)
  values ('activity', new.id)
  on conflict do nothing;

  return new;
end;
$$;

comment on function public.create_activity_conversation() is
  'Opens the group chat when an activity is created.';

drop trigger if exists on_activity_created_open_conversation on public.activities;
create trigger on_activity_created_open_conversation
  after insert on public.activities
  for each row
  execute function public.create_activity_conversation();

-- chats for activities/connections that already exist
insert into public.conversations (kind, activity_id)
select 'activity', a.id
from public.activities a
on conflict do nothing;

insert into public.conversations (kind, user_a, user_b)
select 'private',
       least(c.requester_id, c.addressee_id),
       greatest(c.requester_id, c.addressee_id)
from public.connections c
where c.status = 'accepted'
on conflict do nothing;


alter table public.conversations enable row level security;

-- same logic as is_conversation_member() but written out, because calling
-- it here (it queries this table) breaks insert ... returning
create policy "members can see their conversations"
  on public.conversations
  for select
  to authenticated
  using (
    public.is_verified_user()
    and (
      (kind = 'private'
        and auth.uid() in (user_a, user_b)
        and not public.is_blocked_between(user_a, user_b))
      or
      (kind = 'activity'
        and public.is_activity_participant(activity_id))
    )
  );

-- no write policies, only the triggers write here

revoke all on table public.conversations from anon;
revoke insert, update, delete on table public.conversations from authenticated;
grant select on table public.conversations to authenticated;
grant all privileges on table public.conversations to service_role;
