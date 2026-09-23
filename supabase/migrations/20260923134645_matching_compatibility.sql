-- Phase 4 (matching): compatibility helpers.
--
-- Rules 3 and 4 of the matching specification (docs/backend/matching.md):
-- two users' availability must overlap in time AND in compatible
-- approximate areas. Both helpers are plain SQL functions so results are
-- deterministic; matching_candidates() builds on them.


-- =========================================================
-- Area compatibility
-- =========================================================

-- 2 = same area, 1 = different areas in the same location (campus / office /
-- venue), 0 = not compatible. Null-safe.

create or replace function public.area_compatibility(p_area_a uuid, p_area_b uuid)
returns smallint
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_area_a is null or p_area_b is null then 0
    when p_area_a = p_area_b then 2
    when exists (
      select 1
      from public.areas x
      join public.areas y on y.location_id = x.location_id
      where x.id = p_area_a
        and y.id = p_area_b
    ) then 1
    else 0
  end::smallint
$$;

comment on function public.area_compatibility(uuid, uuid) is
  'Area compatibility level: 2 same area, 1 same location, 0 incompatible.';


-- =========================================================
-- Time overlap
-- =========================================================

-- Total minutes two users are BOTH available, from now onwards, counting
-- only availability pairs whose areas are compatible (being free at the
-- same time in different places is not a match). Expired windows are
-- ignored; windows already in progress count from now().
--
-- Privacy: a client may only ask about pairs that include themselves
-- (returns 0 otherwise). Server-side callers (auth.uid() is null) may ask
-- about any pair.

create or replace function public.availability_overlap_minutes(p_user_a uuid, p_user_b uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    sum(
      extract(epoch from (
        least(a.end_time, b.end_time)
        - greatest(a.start_time, b.start_time, now())
      )) / 60
    )::integer,
    0
  )
  from public.availabilities a
  join public.availabilities b
    on b.user_id = p_user_b
   and b.end_time > now()
   and tstzrange(greatest(a.start_time, now()), a.end_time)
       && tstzrange(greatest(b.start_time, now()), b.end_time)
   and public.area_compatibility(a.area_id, b.area_id) > 0
  where a.user_id = p_user_a
    and a.end_time > now()
    and (auth.uid() is null or auth.uid() in (p_user_a, p_user_b))
$$;

comment on function public.availability_overlap_minutes(uuid, uuid) is
  'Remaining minutes both users are available in compatible areas (0 if none).';


-- =========================================================
-- Privileges
-- =========================================================

revoke all on function public.area_compatibility(uuid, uuid) from public, anon;
revoke all on function public.availability_overlap_minutes(uuid, uuid) from public, anon;

grant execute on function public.area_compatibility(uuid, uuid) to authenticated;
grant execute on function public.availability_overlap_minutes(uuid, uuid) to authenticated;
