-- Unified, privacy-preserving payload for the real-time map.
--
-- The function intentionally returns area/location metadata and aggregates,
-- never creator_id, user_id, email, or a user's coordinates.  Activities and
-- official events are individual map points; current availability is one
-- anonymous aggregate point per area.

create or replace function public.active_map_points(
  p_area_ids uuid[] default null,
  p_location_id uuid default null,
  p_include_presence boolean default true
)
returns table (
  point_type text,
  point_id uuid,
  area_id uuid,
  area_name text,
  location_id uuid,
  location_name text,
  location_type text,
  title text,
  category text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text,
  participant_count integer,
  participant_limit smallint,
  available_people integer,
  latitude double precision,
  longitude double precision
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_organisation_id uuid;
begin
  -- A map response is never available to anon or unverified users.
  if v_user_id is null or not public.is_verified_user(v_user_id) then
    return;
  end if;

  select p.organisation_id
    into v_organisation_id
  from public.profiles p
  where p.id = v_user_id
    and p.account_status = 'verified';

  if v_organisation_id is null then
    return;
  end if;

  return query
  select
    'activity'::text,
    a.id,
    a.area_id,
    ar.name,
    l.id,
    l.name,
    l.type,
    a.title,
    a.category,
    a.start_time,
    a.end_time,
    a.status,
    (
      select count(*)::integer
      from public.activity_participants ap
      where ap.activity_id = a.id
        and ap.status = 'accepted'
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = v_user_id and b.blocked_id = ap.user_id)
             or (b.blocker_id = ap.user_id and b.blocked_id = v_user_id)
        )
    ),
    a.participant_limit,
    null::integer,
    l.latitude,
    l.longitude
  from public.activities a
  join public.areas ar on ar.id = a.area_id
  join public.locations l on l.id = ar.location_id
  join public.profiles creator on creator.id = a.creator_id
  where creator.organisation_id = v_organisation_id
    and a.status = 'open'
    and a.end_time > now()
    and (p_area_ids is null or a.area_id = any (p_area_ids))
    and (p_location_id is null or l.id = p_location_id)
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = v_user_id and b.blocked_id = a.creator_id)
         or (b.blocker_id = a.creator_id and b.blocked_id = v_user_id)
    )

  union all

  select
    'official_event'::text,
    e.id,
    e.area_id,
    ar.name,
    l.id,
    l.name,
    l.type,
    e.title,
    -- Official events do not currently have a category column. Keep the
    -- unified map contract stable and let clients treat this as null until
    -- event categorisation is added to the event schema.
    null::text,
    e.start_time,
    e.end_time,
    e.status,
    (
      select count(*)::integer
      from public.event_rsvps r
      where r.event_id = e.id
        and r.status = 'going'
        and not exists (
          select 1
          from public.blocks b
          where (b.blocker_id = v_user_id and b.blocked_id = r.user_id)
             or (b.blocker_id = r.user_id and b.blocked_id = v_user_id)
        )
    ),
    null::smallint,
    null::integer,
    coalesce(e.latitude, l.latitude),
    coalesce(e.longitude, l.longitude)
  from public.official_events e
  join public.locations l on l.id = e.location_id
  left join public.areas ar on ar.id = e.area_id
  where e.organisation_id = v_organisation_id
    and e.status = 'approved'
    and e.end_time > now()
    and (p_area_ids is null or e.area_id = any (p_area_ids))
    and (p_location_id is null or l.id = p_location_id)

  union all

  select
    'presence'::text,
    a.id,
    a.id,
    a.name,
    l.id,
    l.name,
    l.type,
    null::text,
    'available'::text,
    min(av.start_time),
    max(av.end_time),
    'active'::text,
    null::integer,
    null::smallint,
    count(distinct av.user_id)::integer,
    l.latitude,
    l.longitude
  from public.availabilities av
  join public.profiles available_user on available_user.id = av.user_id
  join public.areas a on a.id = av.area_id
  join public.locations l on l.id = a.location_id
  where p_include_presence
    and available_user.organisation_id = v_organisation_id
    and av.start_time <= now()
    and av.end_time > now()
    and (p_area_ids is null or av.area_id = any (p_area_ids))
    and (p_location_id is null or l.id = p_location_id)
    and not exists (
      select 1
      from public.blocks b
      where (b.blocker_id = v_user_id and b.blocked_id = av.user_id)
         or (b.blocker_id = av.user_id and b.blocked_id = v_user_id)
    )
  group by a.id, a.name, l.id, l.name, l.type, l.latitude, l.longitude;
end;
$$;

comment on function public.active_map_points(uuid[], uuid, boolean) is
  'Returns organisation-scoped active activities/events plus anonymous current-availability counts by area. Never exposes user IDs or exact user coordinates.';

revoke all on function public.active_map_points(uuid[], uuid, boolean)
from public, anon;
grant execute on function public.active_map_points(uuid[], uuid, boolean)
to authenticated;
