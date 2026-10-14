-- Phase 5: report user. The workflow is in docs/backend/moderation.md.
--
-- Clients can file a report and see their own reports. The reported user
-- can never see a report about them. Reviewing and closing reports is
-- service_role only (Supabase dashboard / SQL editor).

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),

  reporter_id uuid not null default auth.uid()
    references public.profiles(id)
    on delete cascade,

  -- set null so a report survives the reported account being deleted
  reported_user_id uuid
    references public.profiles(id)
    on delete set null,

  reason text not null
    check (reason in (
      'harassment',
      'spam',
      'inappropriate_content',
      'unsafe_behaviour',
      'impersonation',
      'other'
    )),

  details text
    check (details is null or char_length(details) <= 1000),

  -- optional context: the message or activity the report is about
  message_id uuid
    references public.messages(id)
    on delete set null,

  activity_id uuid
    references public.activities(id)
    on delete set null,

  status text not null default 'open'
    check (status in ('open', 'reviewing', 'actioned', 'dismissed')),

  created_at timestamptz not null default now(),
  resolved_at timestamptz,

  constraint reports_no_self
    check (reporter_id <> reported_user_id),
  constraint reports_other_needs_details
    check (reason <> 'other' or char_length(btrim(coalesce(details, ''))) > 0),
  constraint reports_resolved_shape
    check ((status in ('actioned', 'dismissed')) = (resolved_at is not null))
);

comment on table public.reports is
  'User reports. Reporters see their own; the reported user never sees them. Moderation is service_role only.';

create index if not exists reports_status_created_idx
  on public.reports (status, created_at);

create index if not exists reports_reported_user_idx
  on public.reports (reported_user_id);

create index if not exists reports_reporter_created_idx
  on public.reports (reporter_id, created_at);

-- one open report per reporter / reported user / message
create unique index if not exists reports_one_open_per_target_idx
  on public.reports (
    reporter_id,
    reported_user_id,
    coalesce(message_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  where status in ('open', 'reviewing');


create or replace function public.guard_report_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recent integer;
  v_message record;
begin
  -- service_role / SQL editor: trusted, used for moderation updates
  if auth.uid() is null then
    if tg_op = 'UPDATE' then
      if new.status in ('actioned', 'dismissed') and old.status not in ('actioned', 'dismissed') then
        new.resolved_at := now();
      elsif new.status in ('open', 'reviewing') then
        new.resolved_at := null;
      end if;
    end if;
    return new;
  end if;

  -- clients have no update policy; this is a second line of defence
  if tg_op <> 'INSERT' then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] Reports can''t be changed once filed.';
  end if;

  if not public.is_verified_user() then
    raise exception using
      errcode = 'P0001',
      message = '[not_verified] Only verified users can report.';
  end if;

  if new.reporter_id is distinct from auth.uid() then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] You can only file reports as yourself.';
  end if;

  if new.reported_user_id is null then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] Choose who you are reporting.';
  end if;

  -- reported user must be in the same organisation as the reporter
  if not exists (
    select 1
    from public.profiles me
    join public.profiles them on them.organisation_id = me.organisation_id
    where me.id = auth.uid()
      and them.id = new.reported_user_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] You can''t report this user.';
  end if;

  -- message context: you were in the conversation and they sent it.
  -- Checked against the conversation directly rather than
  -- is_conversation_member(), because that hides private chats after a
  -- block -- and blocking then reporting is the normal order.
  if new.message_id is not null then
    select m.sender_id, c.kind, c.user_a, c.user_b, c.activity_id
      into v_message
    from public.messages m
    join public.conversations c on c.id = m.conversation_id
    where m.id = new.message_id;

    if not found
      or v_message.sender_id <> new.reported_user_id
      or not (
        (v_message.kind = 'private' and auth.uid() in (v_message.user_a, v_message.user_b))
        or (v_message.kind = 'activity' and exists (
          select 1 from public.activity_participants ap
          where ap.activity_id = v_message.activity_id
            and ap.user_id = auth.uid()
        ))
      )
    then
      raise exception using
        errcode = 'P0001',
        message = '[forbidden] You can''t report this message.';
    end if;
  end if;

  -- activity context: both of you were involved (creator or any request)
  if new.activity_id is not null then
    if not exists (
      select 1 from public.activity_participants ap
      where ap.activity_id = new.activity_id and ap.user_id = auth.uid()
    ) or not exists (
      select 1 from public.activity_participants ap
      where ap.activity_id = new.activity_id and ap.user_id = new.reported_user_id
    ) then
      raise exception using
        errcode = 'P0001',
        message = '[forbidden] You can''t report this user for this activity.';
    end if;
  end if;

  -- 5 reports an hour
  select count(*) into v_recent
  from public.reports r
  where r.reporter_id = auth.uid()
    and r.created_at > now() - interval '1 hour';

  if v_recent >= 5 then
    raise exception using
      errcode = 'P0001',
      message = '[rate_limited] You''ve sent a lot of reports. Try again later.';
  end if;

  -- clients can't pre-set moderation fields
  new.status := 'open';
  new.resolved_at := null;
  new.created_at := now();

  return new;
end;
$$;

comment on function public.guard_report_write() is
  'Validates new reports (verified, same organisation, real context, rate limit). Only service_role can change status.';

drop trigger if exists on_report_write_guard on public.reports;
create trigger on_report_write_guard
  before insert or update on public.reports
  for each row
  execute function public.guard_report_write();


alter table public.reports enable row level security;

create policy "verified users can file reports"
  on public.reports
  for insert
  to authenticated
  with check (
    reporter_id = auth.uid()
    and public.is_verified_user()
  );

-- Only the reporter. There is deliberately no policy that matches on
-- reported_user_id.
create policy "reporters can see their own reports"
  on public.reports
  for select
  to authenticated
  using (reporter_id = auth.uid());

-- no update/delete policies: reports are immutable for clients

revoke all on table public.reports from anon, authenticated;
grant select, insert on table public.reports to authenticated;
grant all privileges on table public.reports to service_role;
