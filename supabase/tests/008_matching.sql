-- Phase 4: matching rules, helper functions and blocks.
-- Run with `npx supabase test db` (requires Docker -- see
-- supabase/tests/README.md).
--
-- Like 003_activities, this creates real test users and switches
-- role/JWT context so the privacy guards and RLS are exercised for real.

begin;

select plan(30);

create or replace function pg_temp.create_test_user(
  p_email text,
  p_display_name text,
  p_confirmed boolean default true
) returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    p_email, crypt('Test-Password1', gen_salt('bf')),
    case when p_confirmed then now() else null end,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'display_name', p_display_name,
      'terms_accepted', true,
      'privacy_accepted', true
    ),
    now(), now(), '', ''
  );
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Fixture
--
--   alice  -- the user we match for. Library, +1h..+3h. Coffee + Chess.
--   bob    -- Library, +1h..+3h, Coffee + Chess  -> 120 min, level 2, 2 shared
--   hank   -- Food court, +2h..+3h, Coffee       ->  60 min, level 1, 1 shared
--   carol  -- Food court, +4h..+5h, Coffee       -> no time overlap
--   dave   -- Library, +1h..+3h, Hiking          -> no shared interest
--   erin   -- Library, +1h..+3h, Coffee, BLOCKED by alice
--   frank  -- Cafe terrace (other location), +1h..+3h, Coffee -> area level 0
--   grace  -- Library, +1h..+3h, Coffee, email NOT confirmed -> not verified
-- ---------------------------------------------------------------------

select pg_temp.create_test_user('alice@student.uts.edu.au', 'Alice') as alice_id \gset
select pg_temp.create_test_user('bob@student.uts.edu.au',   'Bob')   as bob_id   \gset
select pg_temp.create_test_user('hank@student.uts.edu.au',  'Hank')  as hank_id  \gset
select pg_temp.create_test_user('carol@student.uts.edu.au', 'Carol') as carol_id \gset
select pg_temp.create_test_user('dave@student.uts.edu.au',  'Dave')  as dave_id  \gset
select pg_temp.create_test_user('erin@student.uts.edu.au',  'Erin')  as erin_id  \gset
select pg_temp.create_test_user('frank@student.uts.edu.au', 'Frank') as frank_id \gset
select pg_temp.create_test_user('grace@student.uts.edu.au', 'Grace', false) as grace_id \gset

-- Areas from seed.sql (both in UTS City Campus, location ...101).
\set library    '00000000-0000-0000-0000-000000000201'
\set food_court '00000000-0000-0000-0000-000000000202'
-- Extra area in the independent public venue (location ...102).
\set cafe_terrace '00000000-0000-0000-0000-000000000299'

insert into public.areas (id, location_id, name, type)
values (:'cafe_terrace', '00000000-0000-0000-0000-000000000102', 'Cafe Terrace', 'other');

-- Interests may or may not be seeded; upsert by name and read the ids back.
insert into public.interests (name) values ('Coffee'), ('Chess'), ('Hiking')
on conflict (name) do nothing;

select id as coffee from public.interests where name = 'Coffee' \gset
select id as chess  from public.interests where name = 'Chess'  \gset
select id as hiking from public.interests where name = 'Hiking' \gset

insert into public.profile_interests (profile_id, interest_id) values
  (:'alice_id', :'coffee'), (:'alice_id', :'chess'),
  (:'bob_id',   :'coffee'), (:'bob_id',   :'chess'),
  (:'hank_id',  :'coffee'),
  (:'carol_id', :'coffee'),
  (:'dave_id',  :'hiking'),
  (:'erin_id',  :'coffee'),
  (:'frank_id', :'coffee'),
  (:'grace_id', :'coffee');

insert into public.availabilities (user_id, area_id, start_time, end_time) values
  (:'alice_id', :'library',      now() + interval '1 hour', now() + interval '3 hours'),
  (:'bob_id',   :'library',      now() + interval '1 hour', now() + interval '3 hours'),
  (:'hank_id',  :'food_court',   now() + interval '2 hours', now() + interval '3 hours'),
  (:'carol_id', :'food_court',   now() + interval '4 hours', now() + interval '5 hours'),
  (:'dave_id',  :'library',      now() + interval '1 hour', now() + interval '3 hours'),
  (:'erin_id',  :'library',      now() + interval '1 hour', now() + interval '3 hours'),
  (:'frank_id', :'cafe_terrace', now() + interval '1 hour', now() + interval '3 hours'),
  (:'grace_id', :'library',      now() + interval '1 hour', now() + interval '3 hours');

insert into public.blocks (blocker_id, blocked_id) values (:'alice_id', :'erin_id');

-- ---------------------------------------------------------------------
-- 1-5. Schema
-- ---------------------------------------------------------------------

select has_table('public', 'blocks', 'blocks table exists');
select has_function('public', 'area_compatibility', array['uuid', 'uuid'], 'area_compatibility(uuid, uuid) exists');
select has_function('public', 'availability_overlap_minutes', array['uuid', 'uuid'], 'availability_overlap_minutes(uuid, uuid) exists');
select has_function('public', 'shared_interest_count', array['uuid', 'uuid'], 'shared_interest_count(uuid, uuid) exists');
select has_function('public', 'matching_candidates', array['uuid'], 'matching_candidates(uuid) exists');

-- ---------------------------------------------------------------------
-- 6-9. Area compatibility
-- ---------------------------------------------------------------------

select is(public.area_compatibility(:'library', :'library'), 2::smallint, 'same area -> level 2');
select is(public.area_compatibility(:'library', :'food_court'), 1::smallint, 'same location, different area -> level 1');
select is(public.area_compatibility(:'library', :'cafe_terrace'), 0::smallint, 'different location -> level 0');
select is(public.area_compatibility(null, :'library'), 0::smallint, 'null area -> level 0');

-- ---------------------------------------------------------------------
-- 10-13. Time overlap (server-side caller, auth.uid() is null)
-- ---------------------------------------------------------------------

select is(public.availability_overlap_minutes(:'alice_id', :'bob_id'), 120, 'alice/bob overlap 120 minutes');
select is(public.availability_overlap_minutes(:'alice_id', :'hank_id'), 60, 'alice/hank overlap 60 minutes');
select is(public.availability_overlap_minutes(:'alice_id', :'carol_id'), 0, 'alice/carol do not overlap in time');
select is(public.availability_overlap_minutes(:'alice_id', :'frank_id'), 0, 'alice/frank overlap in time but not in a compatible area');

-- ---------------------------------------------------------------------
-- 14-17. Shared interests and blocks
-- ---------------------------------------------------------------------

select is(public.shared_interest_count(:'alice_id', :'bob_id'), 2, 'alice/bob share 2 interests');
select is(public.shared_interest_count(:'alice_id', :'dave_id'), 0, 'alice/dave share no interests');
select ok(public.is_blocked_between(:'alice_id', :'erin_id'), 'block detected blocker -> blocked');
select ok(public.is_blocked_between(:'erin_id', :'alice_id'), 'block detected in reverse direction');

-- ---------------------------------------------------------------------
-- 18-20. Matching result for alice (server-side caller)
-- ---------------------------------------------------------------------

select results_eq(
  $$ select candidate_id from public.matching_candidates('$$ || :'alice_id' || $$') $$,
  $$ values ('$$ || :'bob_id' || $$'::uuid), ('$$ || :'hank_id' || $$'::uuid) $$,
  'alice is matched with bob then hank, in that order'
);

select results_eq(
  $$ select candidate_id, score from public.matching_candidates('$$ || :'alice_id' || $$') $$,
  $$ values ('$$ || :'bob_id' || $$'::uuid, 15::numeric), ('$$ || :'hank_id' || $$'::uuid, 6::numeric) $$,
  'scores: bob = 4 (120min) + 6 (2 interests) + 4 (same area) + 1 (same org); hank = 2 + 3 + 0 + 1'
);

select ok(
  not exists (
    select 1 from public.matching_candidates(:'alice_id')
    where candidate_id in (:'carol_id', :'dave_id', :'erin_id', :'frank_id', :'grace_id')
  ),
  'no-overlap, no-shared-interest, blocked, incompatible-area and unverified users are excluded'
);

-- ---------------------------------------------------------------------
-- 21. Determinism: same data, same order
-- ---------------------------------------------------------------------

select is(
  (select array_agg(candidate_id) from (select candidate_id from public.matching_candidates(:'alice_id')) a),
  (select array_agg(candidate_id) from (select candidate_id from public.matching_candidates(:'alice_id')) b),
  'matching_candidates is deterministic'
);

-- ---------------------------------------------------------------------
-- 22-25. Client context: alice can only ask about herself
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select is(
  (select count(*) from public.matching_candidates()),
  2::bigint,
  'as alice, matching_candidates() with default arg returns her 2 candidates'
);

select is(
  (select count(*) from public.matching_candidates(:'bob_id')),
  0::bigint,
  'as alice, asking for bob''s candidates returns nothing'
);

select is(
  public.availability_overlap_minutes(:'bob_id', :'hank_id'),
  0,
  'as alice, overlap between two other users is hidden'
);

select is(
  public.shared_interest_ids(:'bob_id', :'hank_id'),
  '{}'::uuid[],
  'as alice, shared interests between two other users are hidden'
);

-- ---------------------------------------------------------------------
-- 26-28. Blocks RLS
-- ---------------------------------------------------------------------

select is(
  (select count(*) from public.blocks),
  1::bigint,
  'alice sees the block she created'
);

select throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id)
     values ('$$ || :'alice_id' || $$', '$$ || :'alice_id' || $$') $$,
  '23514',
  null,
  'a user cannot block themselves'
);

select throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id)
     values ('$$ || :'bob_id' || $$', '$$ || :'carol_id' || $$') $$,
  '42501',
  null,
  'a user cannot create a block on behalf of someone else'
);

select set_config('request.jwt.claim.sub', :'erin_id', true);

select is(
  (select count(*) from public.blocks),
  0::bigint,
  'erin cannot see that she has been blocked'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 30. anon has no access to matching
-- ---------------------------------------------------------------------

select ok(
  not has_function_privilege('anon', 'public.matching_candidates(uuid)', 'execute'),
  'anon cannot execute matching_candidates'
);

select * from finish();

rollback;
