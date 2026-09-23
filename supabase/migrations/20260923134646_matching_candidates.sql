-- Phase 4 (matching): shared interests and the deterministic matching query.
-- Depends on: 20260923134644_create_blocks (is_blocked_between) and
-- 20260923134645_matching_compatibility (area_compatibility, availability_overlap_minutes).
--
-- Implements the matching rules from Backend Docs v0.1 as database
-- functions (spec: docs/backend/matching.md):
--
--   1. Both users are verified.
--   2. They belong to an approved community (a profile always has an
--      approved organisation; same organisation is a score bonus).
--   3. Their availability overlaps ...
--   4. ... in compatible approximate areas (same area, or same location).
--   5. They share at least one interest.
--   6. There is no block relationship (either direction).
--   7. They are not already connected -- NOT implemented here; see the
--      marked hook in matching_candidates(). Owner: "Exclude existing
--      connections" task, once the connections table exists.
--
-- Everything is a plain SQL function so the result is deterministic for
-- the same data: no randomness, ties broken by candidate id.


-- =========================================================
-- Shared interests
-- =========================================================

-- Privacy: clients may only ask about pairs that include themselves
-- (empty array otherwise); server-side callers may ask about any pair.

create or replace function public.shared_interest_ids(p_user_a uuid, p_user_b uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(array_agg(a.interest_id order by a.interest_id), '{}'::uuid[])
  from public.profile_interests a
  join public.profile_interests b
    on b.interest_id = a.interest_id
   and b.profile_id = p_user_b
  where a.profile_id = p_user_a
    and (auth.uid() is null or auth.uid() in (p_user_a, p_user_b))
$$;

comment on function public.shared_interest_ids(uuid, uuid) is
  'Sorted ids of interests both users selected (empty array if none).';

create or replace function public.shared_interest_count(p_user_a uuid, p_user_b uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select cardinality(public.shared_interest_ids(p_user_a, p_user_b))
$$;

comment on function public.shared_interest_count(uuid, uuid) is
  'Number of interests both users selected.';


-- =========================================================
-- Matching candidates
-- =========================================================

-- Ranked candidates for p_user_id. A caller may only ask about themselves
-- (auth.uid()); server-side callers (auth.uid() is null) may pass any id.
--
-- Score (see docs/backend/matching.md for rationale):
--   + 1 per 30 minutes of compatible overlap
--   + 3 per shared interest
--   + 4 if they will be in the exact same area at an overlapping time
--   + 1 if same organisation
-- Ordering: score desc, overlap desc, shared interests desc, candidate id
-- asc -- fully deterministic. The suggestions endpoint applies `limit 3`.

create or replace function public.matching_candidates(p_user_id uuid default auth.uid())
returns table (
  candidate_id uuid,
  display_name text,
  organisation_id uuid,
  same_organisation boolean,
  overlap_minutes integer,
  best_area_level smallint,
  shared_interest_count integer,
  shared_interest_ids uuid[],
  score numeric
)
language sql
stable
security definer
set search_path = public
as $$
  with me as (
    select p.id, p.organisation_id
    from public.profiles p
    where p.id = p_user_id
      and (auth.uid() is null or p_user_id = auth.uid())
      and p.account_status = 'verified'
      and p.email_verified_at is not null
  ),
  my_avail as (
    select a.area_id,
           tstzrange(greatest(a.start_time, now()), a.end_time) as avail_window
    from public.availabilities a
    join me on a.user_id = me.id
    where a.end_time > now()
  ),
  pool as (
    select p.id, p.display_name, p.organisation_id,
           p.organisation_id = me.organisation_id as same_organisation
    from public.profiles p
    cross join me
    where p.id <> me.id
      -- 1. verified
      and p.account_status = 'verified'
      and p.email_verified_at is not null
      -- 2. approved community (organisation must still exist and be approved)
      and exists (
        select 1 from public.organisations o
        where o.id = p.organisation_id
          and o.type in ('university', 'company')
      )
      -- 6. no block in either direction
      and not public.is_blocked_between(me.id, p.id)
      -- 7. not already connected -- HOOK for the connections task:
      --    and not exists (select 1 from public.connections c
      --                    where (c.user_a = me.id and c.user_b = p.id)
      --                       or (c.user_a = p.id and c.user_b = me.id))
      -- 5. at least one shared interest
      and exists (
        select 1
        from public.profile_interests pi
        join public.profile_interests mi
          on mi.interest_id = pi.interest_id
         and mi.profile_id = me.id
        where pi.profile_id = p.id
      )
      -- 3 + 4. some future availability overlapping mine in a compatible area
      and exists (
        select 1
        from public.availabilities a
        join my_avail m
          on tstzrange(greatest(a.start_time, now()), a.end_time) && m.avail_window
         and public.area_compatibility(a.area_id, m.area_id) > 0
        where a.user_id = p.id
          and a.end_time > now()
      )
  ),
  scored as (
    select
      pool.id,
      pool.display_name,
      pool.organisation_id,
      pool.same_organisation,
      public.availability_overlap_minutes(me.id, pool.id) as overlap_minutes,
      (
        select max(public.area_compatibility(a.area_id, m.area_id))
        from public.availabilities a
        join my_avail m
          on tstzrange(greatest(a.start_time, now()), a.end_time) && m.avail_window
        where a.user_id = pool.id
          and a.end_time > now()
      )::smallint as best_area_level,
      public.shared_interest_ids(me.id, pool.id) as shared_ids
    from pool
    cross join me
  )
  select
    s.id,
    s.display_name,
    s.organisation_id,
    s.same_organisation,
    s.overlap_minutes,
    s.best_area_level,
    cardinality(s.shared_ids),
    s.shared_ids,
    (
      floor(s.overlap_minutes / 30.0)
      + cardinality(s.shared_ids) * 3
      + case when s.best_area_level = 2 then 4 else 0 end
      + case when s.same_organisation then 1 else 0 end
    )::numeric as score
  from scored s
  where s.overlap_minutes > 0
  -- positional: score desc, overlap desc, shared interests desc, id asc
  order by 9 desc, 5 desc, 7 desc, 1 asc
$$;

comment on function public.matching_candidates(uuid) is
  'Deterministic ranked matching candidates for a user (self only from the client). Suggestions endpoint applies the limit.';


-- =========================================================
-- Privileges
-- =========================================================

revoke all on function public.shared_interest_ids(uuid, uuid) from public, anon;
revoke all on function public.shared_interest_count(uuid, uuid) from public, anon;
revoke all on function public.matching_candidates(uuid) from public, anon;

grant execute on function public.shared_interest_ids(uuid, uuid) to authenticated;
grant execute on function public.shared_interest_count(uuid, uuid) to authenticated;
grant execute on function public.matching_candidates(uuid) to authenticated;


-- =========================================================
-- Supporting index
-- =========================================================

-- profile_interests already has (profile_id) and (interest_id) indexes;
-- the shared-interest join benefits from the pair.
create index if not exists profile_interests_interest_profile_idx
  on public.profile_interests (interest_id, profile_id);
