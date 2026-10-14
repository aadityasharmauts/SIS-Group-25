-- Phase 5: report user, and who can (and can't) see reports.
-- Run with `npx supabase test db`.

begin;
select plan(25);

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

create or replace function pg_temp.login(p_user uuid) returns void
language sql
as $$ select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true) $$;

select pg_temp.create_test_user('rep.alice@student.uts.edu.au', 'Alice') as alice_id \gset
select pg_temp.create_test_user('rep.bob@student.uts.edu.au', 'Bob') as bob_id \gset
select pg_temp.create_test_user('rep.carol@student.uts.edu.au', 'Carol') as carol_id \gset
select pg_temp.create_test_user('rep.dan@student.uts.edu.au', 'Dan') as dan_id \gset
select pg_temp.create_test_user('rep.erin@student.uts.edu.au', 'Erin') as erin_id \gset
select pg_temp.create_test_user('rep.fay@student.uts.edu.au', 'Fay') as fay_id \gset
select pg_temp.create_test_user('rep.pending@student.uts.edu.au', 'Pending', false) as pending_id \gset
select pg_temp.create_test_user('rep.out@examplecompany.com', 'Outsider') as outsider_id \gset

\set library_area '00000000-0000-0000-0000-000000000201'

-- Alice and Bob connect; Bob sends two messages, Alice one
set local role authenticated;
select pg_temp.login(:'alice_id');
insert into public.connections (requester_id, addressee_id)
values (:'alice_id'::uuid, :'bob_id'::uuid)
returning id as conn_id \gset

select pg_temp.login(:'bob_id');
update public.connections set status = 'accepted' where id = :'conn_id'::uuid;

reset role;
select id as private_conv from public.conversations
where kind = 'private'
  and user_a = least(:'alice_id'::uuid, :'bob_id'::uuid)
  and user_b = greatest(:'alice_id'::uuid, :'bob_id'::uuid) \gset

set local role authenticated;
select pg_temp.login(:'bob_id');
insert into public.messages (conversation_id, body)
values (:'private_conv'::uuid, 'first rude message')
returning id as bob_msg1 \gset
insert into public.messages (conversation_id, body)
values (:'private_conv'::uuid, 'second rude message')
returning id as bob_msg2 \gset

select pg_temp.login(:'alice_id');
insert into public.messages (conversation_id, body)
values (:'private_conv'::uuid, 'please stop')
returning id as alice_msg \gset

-- Alice hosts an activity, Bob requests to join
insert into public.activities (area_id, title, category, start_time, end_time, participant_limit)
values (:'library_area'::uuid, 'Study group', 'study_session',
        now() + interval '10 minutes', now() + interval '70 minutes', 5)
returning id as activity_id \gset

select pg_temp.login(:'bob_id');
insert into public.activity_participants (activity_id, user_id)
values (:'activity_id'::uuid, auth.uid());

-- ---------------------------------------------------------------------
-- 1-5. Filing a report, and who can see it
-- ---------------------------------------------------------------------

select has_table('public', 'reports', 'reports table exists');

select pg_temp.login(:'alice_id');
select lives_ok(
  $$ insert into public.reports (reported_user_id, reason, details, message_id)
     values ('$$ || :'bob_id' || $$', 'harassment', 'keeps messaging me', '$$ || :'bob_msg1' || $$') $$,
  'a user can report a message someone sent them'
);

select is(
  (select count(*)::int from public.reports),
  1,
  'the reporter can see their own report'
);

select pg_temp.login(:'bob_id');
select is(
  (select count(*)::int from public.reports),
  0,
  'the reported user cannot see the report'
);

select pg_temp.login(:'carol_id');
select is(
  (select count(*)::int from public.reports),
  0,
  'other users cannot see the report'
);

-- ---------------------------------------------------------------------
-- 6-8. Nobody but service_role can change a report
-- ---------------------------------------------------------------------

select pg_temp.login(:'bob_id');
select throws_ok(
  $$ update public.reports set status = 'dismissed' $$,
  '42501',
  null,
  'the reported user cannot change a report'
);

select pg_temp.login(:'alice_id');
select throws_ok(
  $$ update public.reports set details = 'edited' $$,
  '42501',
  null,
  'the reporter cannot edit their report'
);

select throws_ok(
  $$ delete from public.reports $$,
  '42501',
  null,
  'the reporter cannot delete their report'
);

-- ---------------------------------------------------------------------
-- 9-16. Invalid reports
-- ---------------------------------------------------------------------

select throws_ok(
  $$ insert into public.reports (reported_user_id, reason)
     values ('$$ || :'alice_id' || $$', 'spam') $$,
  '23514',
  null,
  'a user cannot report themselves'
);

select throws_ok(
  $$ insert into public.reports (reporter_id, reported_user_id, reason)
     values ('$$ || :'carol_id' || $$', '$$ || :'bob_id' || $$', 'spam') $$,
  'P0001',
  '[forbidden] You can only file reports as yourself.',
  'a user cannot file a report as someone else'
);

select throws_ok(
  $$ insert into public.reports (reported_user_id, reason, message_id)
     values ('$$ || :'bob_id' || $$', 'harassment', '$$ || :'bob_msg1' || $$') $$,
  '23505',
  null,
  'the same message cannot be reported twice while the first report is open'
);

select throws_ok(
  $$ insert into public.reports (reported_user_id, reason, message_id)
     values ('$$ || :'bob_id' || $$', 'harassment', '$$ || :'alice_msg' || $$') $$,
  'P0001',
  '[forbidden] You can''t report this message.',
  'the message must have been sent by the reported user'
);

select pg_temp.login(:'carol_id');
select throws_ok(
  $$ insert into public.reports (reported_user_id, reason, message_id)
     values ('$$ || :'bob_id' || $$', 'harassment', '$$ || :'bob_msg2' || $$') $$,
  'P0001',
  '[forbidden] You can''t report this message.',
  'a user cannot report a message from a chat they are not in'
);

select throws_ok(
  $$ insert into public.reports (reported_user_id, reason, activity_id)
     values ('$$ || :'bob_id' || $$', 'unsafe_behaviour', '$$ || :'activity_id' || $$') $$,
  'P0001',
  '[forbidden] You can''t report this user for this activity.',
  'a user cannot attach an activity they were not part of'
);

select throws_ok(
  $$ insert into public.reports (reported_user_id, reason)
     values ('$$ || :'outsider_id' || $$', 'spam') $$,
  'P0001',
  '[forbidden] You can''t report this user.',
  'a user cannot report someone outside their organisation'
);

select throws_ok(
  $$ insert into public.reports (reported_user_id, reason)
     values ('$$ || :'bob_id' || $$', 'other') $$,
  '23514',
  null,
  'reason "other" needs details'
);

-- ---------------------------------------------------------------------
-- 17-19. Valid edge cases
-- ---------------------------------------------------------------------

-- block first, then report -- the normal order
select pg_temp.login(:'alice_id');
insert into public.blocks (blocker_id, blocked_id)
values (:'alice_id'::uuid, :'bob_id'::uuid);

select lives_ok(
  $$ insert into public.reports (reported_user_id, reason, message_id)
     values ('$$ || :'bob_id' || $$', 'harassment', '$$ || :'bob_msg2' || $$') $$,
  'a user can still report a message after blocking the sender'
);

select lives_ok(
  $$ insert into public.reports (reported_user_id, reason, activity_id)
     values ('$$ || :'bob_id' || $$', 'unsafe_behaviour', '$$ || :'activity_id' || $$') $$,
  'a user can report someone from their activity'
);

insert into public.reports (reported_user_id, reason, status, resolved_at)
values (:'carol_id'::uuid, 'spam', 'open', null)
returning id as carol_report \gset

reset role;
select pg_temp.login(null);
update public.reports set status = 'dismissed'
where id = :'carol_report'::uuid;
set local role authenticated;
select pg_temp.login(:'alice_id');

select lives_ok(
  $$ insert into public.reports (reported_user_id, reason)
     values ('$$ || :'carol_id' || $$', 'spam') $$,
  'once a report is closed, the same person can be reported again'
);

-- ---------------------------------------------------------------------
-- 20-22. Rate limit, unverified and anonymous users
-- ---------------------------------------------------------------------

-- Alice has filed 5 reports this hour (including the dismissed one)
select throws_ok(
  $$ insert into public.reports (reported_user_id, reason)
     values ('$$ || :'dan_id' || $$', 'spam') $$,
  'P0001',
  '[rate_limited] You''ve sent a lot of reports. Try again later.',
  'the sixth report in an hour is rate limited'
);

select pg_temp.login(:'pending_id');
select throws_ok(
  $$ insert into public.reports (reported_user_id, reason)
     values ('$$ || :'bob_id' || $$', 'spam') $$,
  'P0001',
  '[not_verified] Only verified users can report.',
  'unverified users cannot report'
);

reset role;
set local role anon;
select pg_temp.login(null);
select throws_ok(
  $$ select count(*) from public.reports $$,
  '42501',
  null,
  'anonymous users cannot touch reports'
);

-- ---------------------------------------------------------------------
-- 23-25. Moderation (service_role)
-- ---------------------------------------------------------------------

reset role;
set local role authenticated;
select pg_temp.login(:'erin_id');
insert into public.reports (reported_user_id, reason, status)
values (:'fay_id'::uuid, 'spam', 'dismissed')
returning id as erin_report \gset

reset role;
select is(
  (select status from public.reports where id = :'erin_report'::uuid),
  'open',
  'clients cannot pre-set a report''s status'
);

set local role service_role;
select pg_temp.login(null);
update public.reports set status = 'actioned' where id = :'erin_report'::uuid;

select isnt(
  (select resolved_at from public.reports where id = :'erin_report'::uuid),
  null,
  'closing a report stamps resolved_at'
);

select is(
  (select count(*)::int from public.reports where reported_user_id = :'bob_id'::uuid),
  3,
  'service_role sees every report about a user'
);

reset role;

select * from finish();
rollback;
