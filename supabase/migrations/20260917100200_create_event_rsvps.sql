-- Phase 3: Event RSVPs
-- Verified users indicate participation in an official event.
-- One RSVP row per (event, user); the status can be changed or the row
-- deleted to withdraw.

create table if not exists public.event_rsvps (
  id uuid primary key default gen_random_uuid(),

  event_id uuid not null
    references public.official_events(id)
    on delete cascade,

  user_id uuid not null
    references public.profiles(id)
    on delete cascade,

  status text not null default 'going'
    check (status in ('going', 'interested')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint event_rsvps_unique
    unique (event_id, user_id)
);

comment on table public.event_rsvps is
  'RSVP of a verified user to an official event (going / interested). One row per event and user.';


-- =========================================================
-- Indexes
-- =========================================================

create index if not exists event_rsvps_event_id_idx
  on public.event_rsvps (event_id);

create index if not exists event_rsvps_user_id_idx
  on public.event_rsvps (user_id);


-- =========================================================
-- RSVPs are only accepted for approved events that have not ended
-- =========================================================

create or replace function public.check_event_rsvp_allowed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE' and (
    new.id is distinct from old.id
    or new.event_id is distinct from old.event_id
    or new.user_id is distinct from old.user_id
    or new.created_at is distinct from old.created_at
  ) then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] Protected RSVP fields cannot be changed.';
  end if;

  if not exists (
    select 1
    from public.official_events e
    where e.id = new.event_id
      and e.status = 'approved'
      and e.end_time > now()
  ) then
    raise exception using
      errcode = 'P0001',
      message = '[expired] This event is no longer accepting RSVPs.';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists on_event_rsvp_write
  on public.event_rsvps;

create trigger on_event_rsvp_write
  before insert or update on public.event_rsvps
  for each row
  execute function public.check_event_rsvp_allowed();


-- =========================================================
-- Aggregate counts (safe to expose: no user identities)
-- =========================================================

-- Regular users cannot read other people's RSVP rows, so the frontend uses
-- this function to show "12 going / 4 interested" on an event card.

create or replace function public.event_rsvp_counts(p_event_id uuid)
returns table (going_count bigint, interested_count bigint)
language sql
stable
security definer
set search_path = public
as $$
  select
    count(*) filter (where r.status = 'going')      as going_count,
    count(*) filter (where r.status = 'interested') as interested_count
  from public.event_rsvps r
  join public.official_events e on e.id = r.event_id
  where r.event_id = p_event_id
    and public.is_verified_user()
    and (
      (e.status = 'approved' and e.end_time > now())
      or public.is_org_admin(e.organisation_id)
    )
$$;

comment on function public.event_rsvp_counts(uuid) is
  'Going / interested totals for an event the caller is allowed to see.';

revoke all on function public.event_rsvp_counts(uuid) from public, anon;
grant execute on function public.event_rsvp_counts(uuid) to authenticated;


-- =========================================================
-- Table privileges (see 20260917090000_grant_api_table_privileges)
-- =========================================================

grant select, insert, update, delete on table public.event_rsvps
to authenticated;

grant all privileges on table public.event_rsvps to service_role;


-- =========================================================
-- Row Level Security
-- =========================================================

alter table public.event_rsvps enable row level security;


-- Users can read their own RSVPs.

create policy "users can read their own rsvps"
  on public.event_rsvps
  for select
  to authenticated
  using (
    user_id = auth.uid()
    and public.is_verified_user()
  );


-- Organisation admins can read the RSVP list for their own events.

create policy "org admins can read rsvps for their events"
  on public.event_rsvps
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.official_events e
      where e.id = event_id
        and public.is_org_admin(e.organisation_id)
    )
  );


-- Verified users can RSVP only as themselves. The trigger above rejects
-- expired / cancelled events.

create policy "verified users can rsvp as themselves"
  on public.event_rsvps
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and public.is_verified_user()
  );


create policy "users can update their own rsvp"
  on public.event_rsvps
  for update
  to authenticated
  using (
    user_id = auth.uid()
    and public.is_verified_user()
  )
  with check (
    user_id = auth.uid()
    and public.is_verified_user()
  );


create policy "users can withdraw their own rsvp"
  on public.event_rsvps
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    and public.is_verified_user()
  );
