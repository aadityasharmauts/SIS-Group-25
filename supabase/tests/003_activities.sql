-- Phase 3: User-created activities and participants.
-- Run with `npx supabase test db` (requires Docker -- see
-- supabase/tests/README.md).
--
-- Unlike 001/002 (schema-introspection only), this file also exercises
-- the guard triggers and RLS end-to-end by creating real test users and
-- switching role/JWT context, the same technique used to verify Phase 1
-- before it was merged. That's what actually proves the accept/decline/
-- capacity/rate-limit logic behaves, not just that it exists.

begin;
select plan(40);

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

select pg_temp.create_test_user('alice@student.uts.edu.au', 'Alice') as alice_id \gset
select pg_temp.create_test_user('bob@student.uts.edu.au', 'Bob') as bob_id \gset
select pg_temp.create_test_user('carol@student.uts.edu.au', 'Carol') as carol_id \gset
select pg_temp.create_test_user('dave@student.uts.edu.au', 'Dave', false) as dave_id \gset
select pg_temp.create_test_user('erin@student.uts.edu.au', 'Erin') as erin_id \gset

-- Library area from seed.sql.
\set library_area '00000000-0000-0000-0000-000000000201'

-- ---------------------------------------------------------------------
-- 1-5. Schema and structural privacy
-- ---------------------------------------------------------------------

select has_table('public', 'activities', 'activities table exists');
select has_table('public', 'activity_participants', 'activity_participants table exists');
select has_column('public', 'activities', 'participant_limit', 'activities has participant_limit');
select has_column('public', 'activity_participants', 'is_creator', 'activity_participants has is_creator');
select has_column('public', 'activities', 'location_label', 'activities has public location label');
select has_column('public', 'activities', 'latitude', 'activities has public marker latitude');
select has_column('public', 'activities', 'longitude', 'activities has public marker longitude');

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'activities'
      and column_name = 'address'
  ),
  'activities has no private address column -- area_id remains required'
);

-- ---------------------------------------------------------------------
-- 6-11. Time window, duration cap, and participant_limit bounds, as
-- Alice (verified). Decisions A and the PRD 8.5 limit range.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ insert into public.activities (creator_id, area_id, title, category, start_time, end_time)
     values ('$$ || :'alice_id' || $$', '$$ || :'library_area' || $$', 'Past coffee', 'coffee_break', now() - interval '2 hours', now() - interval '1 hour') $$,
  'P0001',
  null,
  'an activity cannot be created ending in the past'
);

select throws_ok(
  $$ insert into public.activities (creator_id, area_id, title, category, start_time, end_time)
     values ('$$ || :'alice_id' || $$', '$$ || :'library_area' || $$', 'Too long', 'study_session', now() + interval '1 hour', now() + interval '6 hours') $$,
  '23514',
  null,
  'an activity longer than 4 hours is rejected'
);

select throws_ok(
  $$ insert into public.activities (creator_id, area_id, title, category, start_time, end_time, participant_limit)
     values ('$$ || :'alice_id' || $$', '$$ || :'library_area' || $$', 'Zero limit', 'walk', now() + interval '1 hour', now() + interval '2 hours', 0) $$,
  '23514',
  null,
  'participant_limit of 0 is rejected'
);

select throws_ok(
  $$ insert into public.activities (creator_id, area_id, title, category, start_time, end_time, participant_limit)
     values ('$$ || :'alice_id' || $$', '$$ || :'library_area' || $$', 'Six limit', 'walk', now() + interval '1 hour', now() + interval '2 hours', 6) $$,
  '23514',
  null,
  'participant_limit of 6 is rejected (max 5, PRD 8.5)'
);

select throws_ok(
  $$ insert into public.activities (creator_id, area_id, title, category, start_time, end_time)
     values ('$$ || :'bob_id' || $$', '$$ || :'library_area' || $$', 'Impersonation attempt', 'walk', now() + interval '1 hour', now() + interval '2 hours') $$,
  '42501',
  null,
  'a user cannot create an activity with someone else''s creator_id'
);

-- Alice creates a normal, valid activity with a 2-person limit
-- (participant_limit excludes the creator).
insert into public.activities (creator_id, area_id, title, category, start_time, end_time, participant_limit)
values (:'alice_id'::uuid, :'library_area'::uuid, 'Library coffee break', 'coffee_break', now() + interval '10 minutes', now() + interval '40 minutes', 2)
returning id as activity_id \gset

select is(
  (select status from public.activity_participants where activity_id = :'activity_id'::uuid and user_id = :'alice_id'::uuid),
  'accepted',
  'the creator gets an auto-accepted participant row'
);

select is(
  (select is_creator from public.activity_participants where activity_id = :'activity_id'::uuid and user_id = :'alice_id'::uuid),
  true,
  'the creator''s auto row is flagged is_creator'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 12. An unverified (pending) user cannot create an activity at all.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'dave_id', true);

select throws_ok(
  $$ insert into public.activities (creator_id, area_id, title, category, start_time, end_time)
     values ('$$ || :'dave_id' || $$', '$$ || :'library_area' || $$', 'Unverified attempt', 'walk', now() + interval '1 hour', now() + interval '2 hours') $$,
  '42501',
  null,
  'an unverified user cannot create an activity'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 13-14. Visibility: verified users see it, unverified users don't.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  1,
  'another verified user can see the open activity'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'dave_id', true);

select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  0,
  'an unverified user cannot see the activity'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 15-17. Join requests: request pending, duplicate rejected, creator
-- can't join their own activity.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

insert into public.activity_participants (activity_id, user_id)
values (:'activity_id'::uuid, :'bob_id'::uuid)
returning id as bob_participant_id \gset

select is(
  (select status from public.activity_participants where id = :'bob_participant_id'::uuid),
  'pending',
  'a verified user''s join request starts as pending'
);

select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity_id' || $$', '$$ || :'bob_id' || $$') $$,
  '23505',
  null,
  'requesting to join the same activity twice is rejected as a duplicate'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity_id' || $$', '$$ || :'alice_id' || $$') $$,
  'P0001',
  null,
  'the creator cannot request to join their own activity'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 18. A non-creator cannot update someone else's activity.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

with updated as (
  update public.activities set title = 'Hacked title' where id = :'activity_id'::uuid returning 1
)
select is(
  (select count(*)::int from updated),
  0,
  'a non-creator cannot edit the activity (0 rows affected)'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 19-21. Creator accepts Bob; responded_at set; capacity math updates.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

update public.activity_participants set status = 'accepted' where id = :'bob_participant_id'::uuid;

select is(
  (select status from public.activity_participants where id = :'bob_participant_id'::uuid),
  'accepted',
  'the creator can accept a pending request'
);

select isnt(
  (select responded_at from public.activity_participants where id = :'bob_participant_id'::uuid),
  null,
  'accepting a request sets responded_at'
);

select is(
  public.activity_accepted_count(:'activity_id'::uuid),
  1,
  'activity_accepted_count is 1 after accepting Bob (the creator does not count)'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 22-23. Capacity: limit is 2 (one slot left besides Bob). Carol fills
-- it; a further request from Erin is rejected as full.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol_id', true);

insert into public.activity_participants (activity_id, user_id)
values (:'activity_id'::uuid, :'carol_id'::uuid)
returning id as carol_participant_id \gset

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

update public.activity_participants set status = 'accepted' where id = :'carol_participant_id'::uuid;

select is(
  (select status from public.activity_participants where id = :'carol_participant_id'::uuid),
  'accepted',
  'the creator accepts Carol, filling the 2-person limit'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'erin_id', true);

select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity_id' || $$', '$$ || :'erin_id' || $$') $$,
  'P0001',
  null,
  'requesting to join a full activity is rejected with activity_full'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 24. Lowering participant_limit below the accepted count is rejected.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ update public.activities set participant_limit = 1 where id = '$$ || :'activity_id' || $$' $$,
  'P0001',
  null,
  'lowering participant_limit below the current accepted count is rejected'
);

-- ---------------------------------------------------------------------
-- 25-27. A second activity to test decline/re-request in isolation from
-- the first activity's capacity state.
-- ---------------------------------------------------------------------

insert into public.activities (creator_id, area_id, title, category, start_time, end_time, participant_limit)
values (:'alice_id'::uuid, :'library_area'::uuid, 'Study session', 'study_session', now() + interval '10 minutes', now() + interval '40 minutes', 3)
returning id as activity2_id \gset

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

insert into public.activity_participants (activity_id, user_id)
values (:'activity2_id'::uuid, :'bob_id'::uuid)
returning id as bob_participant2_id \gset

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

update public.activity_participants set status = 'declined' where id = :'bob_participant2_id'::uuid;

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity2_id' || $$', '$$ || :'bob_id' || $$') $$,
  '23505',
  null,
  'a declined requester cannot re-request -- the unique constraint stands'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

update public.activity_participants set status = 'accepted' where id = :'bob_participant2_id'::uuid;

select is(
  (select status from public.activity_participants where id = :'bob_participant2_id'::uuid),
  'accepted',
  'the creator can still accept a previously-declined row if they change their mind'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 28-30. Leaving, and the transition guard rejecting invalid changes.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

update public.activity_participants set status = 'left' where id = :'bob_participant2_id'::uuid;

select is(
  (select status from public.activity_participants where id = :'bob_participant2_id'::uuid),
  'left',
  'a participant can set their own accepted row to left'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol_id', true);

insert into public.activity_participants (activity_id, user_id)
values (:'activity2_id'::uuid, :'carol_id'::uuid)
returning id as carol_participant2_id \gset

select throws_ok(
  $$ update public.activity_participants set status = 'accepted' where id = '$$ || :'carol_participant2_id' || $$' $$,
  'P0001',
  null,
  'a participant cannot set their own pending row to accepted'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ update public.activity_participants set status = 'left'
     where activity_id = '$$ || :'activity2_id' || $$' and is_creator = true $$,
  'P0001',
  null,
  'the creator''s own participant row can never change status'
);

-- ---------------------------------------------------------------------
-- 31-33. Cancelling; further edits and join requests are then rejected.
-- ---------------------------------------------------------------------

update public.activities set status = 'cancelled' where id = :'activity2_id'::uuid;

select is(
  (select status from public.activities where id = :'activity2_id'::uuid),
  'cancelled',
  'the creator can cancel their own activity'
);

select throws_ok(
  $$ update public.activities set title = 'New title' where id = '$$ || :'activity2_id' || $$' $$,
  'P0001',
  null,
  'a cancelled activity cannot be edited further'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'erin_id', true);

select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity2_id' || $$', '$$ || :'erin_id' || $$') $$,
  'P0001',
  null,
  'requesting to join a cancelled activity is rejected'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 34-35. An expired activity (past end_time) is hidden from a
-- non-participant but stays visible to the creator; no client deletes.
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

update public.activities
set start_time = now() - interval '3 hours', end_time = now() - interval '2 hours'
where id = :'activity_id'::uuid;

select is(
  public.activity_is_active(:'activity_id'::uuid),
  false,
  'an activity whose end_time has passed is no longer active'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'erin_id', true);

select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  0,
  'an expired activity is hidden from a non-participant'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  1,
  'the creator can still see their own expired activity'
);

with deleted as (
  delete from public.activities where id = :'activity_id'::uuid returning 1
)
select is(
  (select count(*)::int from deleted),
  0,
  'even the creator cannot delete an activity -- no delete policy exists'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select * from finish();
rollback;
