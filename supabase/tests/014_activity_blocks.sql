-- Phase 5: blocks applied to activities, and the join-request rate limit.
-- Run with `npx supabase test db`.

begin;
select plan(20);

create or replace function pg_temp.create_test_user(
  p_email text,
  p_display_name text
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
    now(),
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

-- switch the "logged in" user
create or replace function pg_temp.login(p_user uuid) returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true) $$;

select pg_temp.create_test_user('ab.alice@student.uts.edu.au', 'Alice') as alice_id \gset
select pg_temp.create_test_user('ab.bob@student.uts.edu.au', 'Bob') as bob_id \gset
select pg_temp.create_test_user('ab.carol@student.uts.edu.au', 'Carol') as carol_id \gset
select pg_temp.create_test_user('ab.dan@student.uts.edu.au', 'Dan') as dan_id \gset
select pg_temp.create_test_user('ab.erin@student.uts.edu.au', 'Erin') as erin_id \gset
select pg_temp.create_test_user('ab.frank@student.uts.edu.au', 'Frank') as frank_id \gset
select pg_temp.create_test_user('ab.gina@student.uts.edu.au', 'Gina') as gina_id \gset

\set library_area '00000000-0000-0000-0000-000000000201'

-- Alice hosts an activity (limit 5 so capacity never gets in the way)
set local role authenticated;
select pg_temp.login(:'alice_id');

insert into public.activities (area_id, title, category, start_time, end_time, participant_limit)
values (:'library_area'::uuid, 'Study group', 'study_session',
        now() + interval '10 minutes', now() + interval '70 minutes', 5)
returning id as activity_id \gset

-- ---------------------------------------------------------------------
-- 1-6. Visibility
-- ---------------------------------------------------------------------

select pg_temp.login(:'bob_id');
select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  1,
  'before any block, Bob can see the activity'
);

-- Alice blocks Bob
select pg_temp.login(:'alice_id');
insert into public.blocks (blocker_id, blocked_id)
values (:'alice_id'::uuid, :'bob_id'::uuid)
returning id as bob_block \gset

select pg_temp.login(:'bob_id');
select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  0,
  'a user blocked by the creator can no longer see the activity'
);

select is(
  public.can_view_activity(:'activity_id'::uuid),
  false,
  'can_view_activity() agrees for the blocked user'
);

select is(
  (select count(*)::int from public.active_map_points()
    where point_type = 'activity' and point_id = :'activity_id'::uuid),
  0,
  'the activity is not on the blocked user''s map'
);

-- Dan blocks Alice -- the other direction
select pg_temp.login(:'dan_id');
insert into public.blocks (blocker_id, blocked_id)
values (:'dan_id'::uuid, :'alice_id'::uuid);

select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  0,
  'a user who blocked the creator can''t see the activity either'
);

select pg_temp.login(:'alice_id');
select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  1,
  'the creator still sees their own activity'
);

-- ---------------------------------------------------------------------
-- 7-8. Joining
-- ---------------------------------------------------------------------

select pg_temp.login(:'bob_id');
select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity_id' || $$', auth.uid()) $$,
  'P0001',
  '[forbidden] You can''t request to join this activity.',
  'a blocked user cannot request to join'
);

select pg_temp.login(:'dan_id');
select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity_id' || $$', auth.uid()) $$,
  'P0001',
  '[forbidden] You can''t request to join this activity.',
  'a user who blocked the creator cannot request to join'
);

-- ---------------------------------------------------------------------
-- 9-12. Accepting and removing
-- ---------------------------------------------------------------------

-- Frank requests, then Alice blocks him before responding
select pg_temp.login(:'frank_id');
insert into public.activity_participants (activity_id, user_id)
values (:'activity_id'::uuid, auth.uid())
returning id as frank_row \gset

select pg_temp.login(:'alice_id');
insert into public.blocks (blocker_id, blocked_id)
values (:'alice_id'::uuid, :'frank_id'::uuid);

select throws_ok(
  $$ update public.activity_participants set status = 'accepted'
     where id = '$$ || :'frank_row' || $$' $$,
  'P0001',
  '[forbidden] You can''t accept this request.',
  'the creator cannot accept a blocked user''s request'
);

-- Carol and Erin join and are accepted
select pg_temp.login(:'carol_id');
insert into public.activity_participants (activity_id, user_id)
values (:'activity_id'::uuid, auth.uid())
returning id as carol_row \gset

select pg_temp.login(:'erin_id');
insert into public.activity_participants (activity_id, user_id)
values (:'activity_id'::uuid, auth.uid())
returning id as erin_row \gset

select pg_temp.login(:'alice_id');
update public.activity_participants set status = 'accepted'
where id in (:'carol_row'::uuid, :'erin_row'::uuid);

select throws_ok(
  $$ update public.activity_participants set status = 'declined'
     where id = '$$ || :'erin_row' || $$' $$,
  'P0001',
  '[invalid_transition] Cannot change participant status from accepted to declined.',
  'without a block, the creator still cannot remove an accepted participant'
);

-- Alice blocks Carol after accepting her
insert into public.blocks (blocker_id, blocked_id)
values (:'alice_id'::uuid, :'carol_id'::uuid);

select pg_temp.login(:'carol_id');
select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  0,
  'an accepted participant loses sight of the activity once blocked'
);

select pg_temp.login(:'alice_id');
select lives_ok(
  $$ update public.activity_participants set status = 'declined'
     where id = '$$ || :'carol_row' || $$' $$,
  'the creator can remove a participant they have blocked'
);

-- ---------------------------------------------------------------------
-- 13-14. Unblocking
-- ---------------------------------------------------------------------

delete from public.blocks where id = :'bob_block'::uuid;

select pg_temp.login(:'bob_id');
select is(
  (select count(*)::int from public.activities where id = :'activity_id'::uuid),
  1,
  'after unblocking, the activity is visible again'
);

select lives_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity_id' || $$', auth.uid()) $$,
  'after unblocking, the user can request to join again'
);

-- ---------------------------------------------------------------------
-- 15-17. Unauthorised changes
-- ---------------------------------------------------------------------

-- RLS hides the row from Erin, so the update silently matches nothing
select pg_temp.login(:'erin_id');
update public.activity_participants set status = 'declined'
where id = :'frank_row'::uuid;

reset role;
select is(
  (select status from public.activity_participants where id = :'frank_row'::uuid),
  'pending',
  'a participant cannot respond to someone else''s request'
);
set local role authenticated;
select pg_temp.login(:'erin_id');

select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     values ('$$ || :'activity_id' || $$', '$$ || :'gina_id' || $$') $$,
  '42501',
  null,
  'nobody can request to join on someone else''s behalf'
);

reset role;
set local role anon;
select pg_temp.login(null);
select throws_ok(
  $$ select count(*) from public.activities $$,
  '42501',
  null,
  'anonymous users cannot read activities'
);

-- ---------------------------------------------------------------------
-- 18-20. Join-request rate limit (10 an hour)
-- ---------------------------------------------------------------------

reset role;
select pg_temp.login(null);

-- 12 open activities from 4 hosts (3 each, the per-host cap)
do $$
declare
  v_host uuid;
  i int;
begin
  for h in 1..4 loop
    v_host := pg_temp.create_test_user(format('ab.host%s@student.uts.edu.au', h), format('Host %s', h));
    for i in 1..3 loop
      insert into public.activities (creator_id, area_id, title, category, start_time, end_time, participant_limit)
      values (v_host, '00000000-0000-0000-0000-000000000201', format('Host %s #%s', h, i), 'study_session',
              now() + interval '10 minutes', now() + interval '70 minutes', 5);
    end loop;
  end loop;
end;
$$;

set local role authenticated;
select pg_temp.login(:'gina_id');

select lives_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     select a.id, auth.uid() from public.activities a
     join public.profiles p on p.id = a.creator_id
     where p.display_name like 'Host %'
     order by a.title
     limit 10 $$,
  'ten join requests in an hour are fine'
);

select throws_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     select a.id, auth.uid() from public.activities a
     join public.profiles p on p.id = a.creator_id
     where p.display_name like 'Host %'
     order by a.title
     offset 10 limit 1 $$,
  'P0001',
  '[rate_limited] You''ve sent a lot of join requests. Try again later.',
  'the eleventh join request in an hour is rate limited'
);

select pg_temp.login(:'erin_id');
select lives_ok(
  $$ insert into public.activity_participants (activity_id, user_id)
     select a.id, auth.uid() from public.activities a
     join public.profiles p on p.id = a.creator_id
     where p.display_name like 'Host %'
     order by a.title
     limit 1 $$,
  'the limit is per user -- someone else can still request'
);

reset role;
select pg_temp.login(null);

select * from finish();
rollback;
