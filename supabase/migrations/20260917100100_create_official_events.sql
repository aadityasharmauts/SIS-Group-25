-- Phase 3: Official events
-- Events published by approved organisation accounts (profiles.is_org_admin)
-- on behalf of their own organisation. Events are always attached to a
-- predefined location (campus / office / public venue) and optionally to a
-- smaller area within it.
--
-- Location data: an event carries the PUBLIC VENUE coordinates used to place
-- its marker on the map. They default to the location's coordinates and can
-- be refined by the organiser (e.g. a specific building entrance). They are
-- never a user's position.
--
-- Lifecycle (status):
--   draft     -> organiser is still editing; visible only to that organisation's admins
--   approved  -> published; visible to all verified users until end_time
--   cancelled -> withdrawn by the organisation; hidden from users
--   expired   -> end_time has passed; set automatically (see expire_official_events)

create table if not exists public.official_events (
  id uuid primary key default gen_random_uuid(),

  organisation_id uuid not null
    references public.organisations(id)
    on delete restrict,

  -- Nullable so an event survives the deletion of the admin who created it.
  creator_id uuid
    references public.profiles(id)
    on delete set null,

  title text not null,
  description text,

  location_id uuid not null
    references public.locations(id)
    on delete restrict,

  area_id uuid
    references public.areas(id)
    on delete restrict,

  -- Public venue coordinates for the map marker (defaulted from locations).
  latitude double precision,
  longitude double precision,

  start_time timestamptz not null,
  end_time timestamptz not null,

  status text not null default 'draft'
    check (status in ('draft', 'approved', 'cancelled', 'expired')),

  approved_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint official_events_valid_time
    check (end_time > start_time),

  constraint official_events_title_length
    check (char_length(btrim(title)) between 1 and 120),

  constraint official_events_description_length
    check (description is null or char_length(description) <= 2000),

  constraint official_events_latitude_range
    check (latitude is null or latitude between -90 and 90),

  constraint official_events_longitude_range
    check (longitude is null or longitude between -180 and 180),

  -- Either both coordinates or neither.
  constraint official_events_coordinates_pair
    check ((latitude is null) = (longitude is null))
);

comment on table public.official_events is
  'Official events published by approved organisation admins for their own organisation. Map data type "official_event". Lifecycle draft -> approved -> cancelled/expired; only approved, unexpired events are visible to regular users.';

comment on column public.official_events.latitude is
  'Public venue latitude for the map marker. Defaults to the location''s coordinates. Never a user position.';

comment on column public.official_events.longitude is
  'Public venue longitude for the map marker. Defaults to the location''s coordinates. Never a user position.';


-- =========================================================
-- Indexes
-- =========================================================

create index if not exists official_events_organisation_id_idx
  on public.official_events (organisation_id);

create index if not exists official_events_creator_id_idx
  on public.official_events (creator_id);

create index if not exists official_events_location_id_idx
  on public.official_events (location_id);

create index if not exists official_events_area_id_idx
  on public.official_events (area_id);

create index if not exists official_events_end_time_idx
  on public.official_events (end_time);

create index if not exists official_events_status_end_time_idx
  on public.official_events (status, end_time);

create index if not exists official_events_location_end_time_idx
  on public.official_events (location_id, end_time)
  where status = 'approved';


-- =========================================================
-- Area must belong to the chosen location
-- =========================================================

-- Generic trigger (reads new.location_id / new.area_id) so later tables can
-- reuse it. Guarantees that when an area is given it sits inside the given
-- location, so an event can never point at an inconsistent place.

create or replace function public.enforce_area_belongs_to_location()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.area_id is not null and not exists (
    select 1
    from public.areas a
    where a.id = new.area_id
      and a.location_id = new.location_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = '[invalid_area] The selected area does not belong to the selected location.';
  end if;

  return new;
end;
$$;

comment on function public.enforce_area_belongs_to_location() is
  'Trigger: rejects rows whose area_id is not inside location_id.';

drop trigger if exists on_official_event_check_area
  on public.official_events;

create trigger on_official_event_check_area
  before insert or update of location_id, area_id on public.official_events
  for each row
  execute function public.enforce_area_belongs_to_location();


-- =========================================================
-- Default the marker to the public venue's coordinates
-- =========================================================

-- If the organiser did not supply coordinates (or changed the location
-- without changing them), copy the location's public lat/lng.

create or replace function public.default_official_event_coordinates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.latitude is null
    or (tg_op = 'UPDATE'
        and new.location_id is distinct from old.location_id
        and new.latitude is not distinct from old.latitude
        and new.longitude is not distinct from old.longitude)
  then
    select l.latitude, l.longitude
      into new.latitude, new.longitude
    from public.locations l
    where l.id = new.location_id;
  end if;

  return new;
end;
$$;

comment on function public.default_official_event_coordinates() is
  'Trigger: fills official_events.latitude/longitude from the venue location when not provided.';

drop trigger if exists on_official_event_default_coordinates
  on public.official_events;

create trigger on_official_event_default_coordinates
  before insert or update of location_id, latitude, longitude on public.official_events
  for each row
  execute function public.default_official_event_coordinates();


-- =========================================================
-- New events must not already be over
-- =========================================================

create or replace function public.check_official_event_not_expired_on_create()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.end_time <= now() then
    raise exception using
      errcode = 'P0001',
      message = '[expired] An event cannot be created with an end time in the past.';
  end if;

  -- Clients never create directly in a system-only state.
  if auth.uid() is not null and new.status not in ('draft', 'approved') then
    raise exception using
      errcode = 'P0001',
      message = '[invalid_transition] New events must be created as draft or approved.';
  end if;

  if new.status = 'approved' then
    new.approved_at := coalesce(new.approved_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists on_official_event_created_check_time
  on public.official_events;

create trigger on_official_event_created_check_time
  before insert on public.official_events
  for each row
  execute function public.check_official_event_not_expired_on_create();


-- =========================================================
-- Protect immutable fields, enforce status transitions,
-- maintain updated_at
-- =========================================================

-- Allowed client transitions:
--   draft     -> approved  (publish)
--   draft     -> cancelled
--   approved  -> cancelled
--   approved  -> draft     (unpublish, only while the event has not ended)
-- 'expired' is set only by the system (auth.uid() is null).
-- cancelled / expired are terminal for clients.

create or replace function public.protect_official_event_changes()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_is_client boolean := auth.uid() is not null;
begin
  if v_is_client and (
    new.id is distinct from old.id
    or new.organisation_id is distinct from old.organisation_id
    or new.creator_id is distinct from old.creator_id
    or new.created_at is distinct from old.created_at
    or new.approved_at is distinct from old.approved_at
  ) then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] Protected event fields cannot be changed by the client.';
  end if;

  if new.status is distinct from old.status then
    if v_is_client then
      if old.status in ('cancelled', 'expired') then
        raise exception using
          errcode = 'P0001',
          message = format('[invalid_transition] A %s event cannot be changed.', old.status);
      end if;

      if new.status not in ('draft', 'approved', 'cancelled') then
        raise exception using
          errcode = 'P0001',
          message = format('[invalid_transition] Cannot change event status from %s to %s.', old.status, new.status);
      end if;

      if new.status = 'approved' and new.end_time <= now() then
        raise exception using
          errcode = 'P0001',
          message = '[expired] An event that has already ended cannot be approved.';
      end if;
    end if;

    if new.status = 'approved' then
      new.approved_at := now();
    end if;
  end if;

  -- Editing details of a finished event is not allowed for clients.
  if v_is_client and old.status = 'expired' then
    raise exception using
      errcode = 'P0001',
      message = '[expired] This event has ended and can no longer be edited.';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists on_official_event_updated
  on public.official_events;

create trigger on_official_event_updated
  before update on public.official_events
  for each row
  execute function public.protect_official_event_changes();


-- =========================================================
-- Automatic expiry
-- =========================================================

-- RLS already hides events once end_time has passed (instant). This job
-- additionally records the terminal 'expired' status so management screens
-- and analytics see the real lifecycle without re-deriving it.

create or replace function public.expire_official_events()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.official_events
  set status = 'expired'
  where status in ('draft', 'approved')
    and end_time <= now();

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

comment on function public.expire_official_events() is
  'Marks draft/approved events whose end_time has passed as expired. Run by pg_cron; returns the number of rows updated.';

revoke all on function public.expire_official_events() from public, anon, authenticated;

-- Schedule every 5 minutes when pg_cron is available (Supabase hosted and
-- local stacks both ship it). If the extension cannot be created the
-- migration still succeeds; RLS keeps expired events hidden regardless.
do $$
begin
  begin
    create extension if not exists pg_cron;
  exception when others then
    raise notice 'pg_cron not available (%). Skipping automatic expiry schedule.', sqlerrm;
    return;
  end;

  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'expire_official_events';

  perform cron.schedule(
    'expire_official_events',
    '*/5 * * * *',
    $job$ select public.expire_official_events(); $job$
  );
end;
$$;


-- =========================================================
-- Table privileges (see 20260917090000_grant_api_table_privileges)
-- =========================================================

grant select, insert, update, delete on table public.official_events
to authenticated;

grant all privileges on table public.official_events to service_role;


-- =========================================================
-- Row Level Security
-- =========================================================

alter table public.official_events enable row level security;


-- Verified users see approved events that have not yet ended.
-- Draft, cancelled and expired events are invisible to them.

create policy "verified users can read active official events"
  on public.official_events
  for select
  to authenticated
  using (
    public.is_verified_user()
    and status = 'approved'
    and end_time > now()
  );


-- Organisation admins additionally see every event of their own
-- organisation (drafts, cancelled, expired) for management screens.

create policy "org admins can read their organisation events"
  on public.official_events
  for select
  to authenticated
  using (
    public.is_org_admin(organisation_id)
  );


-- Only approved organisation admins can create, and only for their own
-- organisation. creator_id must be the caller.

create policy "org admins can create events for their organisation"
  on public.official_events
  for insert
  to authenticated
  with check (
    creator_id = auth.uid()
    and public.is_org_admin(organisation_id)
  );


-- Any admin of the organisation can manage (edit / publish / cancel) its events.

create policy "org admins can update their organisation events"
  on public.official_events
  for update
  to authenticated
  using (
    public.is_org_admin(organisation_id)
  )
  with check (
    public.is_org_admin(organisation_id)
  );


create policy "org admins can delete their organisation events"
  on public.official_events
  for delete
  to authenticated
  using (
    public.is_org_admin(organisation_id)
  );
