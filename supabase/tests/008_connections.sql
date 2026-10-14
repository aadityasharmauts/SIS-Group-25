-- Phase 4: connection requests.
-- Run with `npx supabase test db` (requires Docker -- see
-- supabase/tests/README.md).

begin;
select plan(28);

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

select pg_temp.create_test_user('conn.alice@student.uts.edu.au', 'Alice') as alice_id \gset
select pg_temp.create_test_user('conn.bob@student.uts.edu.au', 'Bob') as bob_id \gset
select pg_temp.create_test_user('conn.carol@student.uts.edu.au', 'Carol') as carol_id \gset
select pg_temp.create_test_user('conn.dave@student.uts.edu.au', 'Dave', false) as dave_id \gset

-- ---------------------------------------------------------------------
-- 1-4. Schema
-- ---------------------------------------------------------------------

select has_table('public', 'connections', 'connections table exists');
select has_column('public', 'connections', 'requester_id', 'connections has requester_id');
select has_column('public', 'connections', 'addressee_id', 'connections has addressee_id');
select has_column('public', 'connections', 'responded_at', 'connections has responded_at');

-- ---------------------------------------------------------------------
-- 5-8. Sending a request
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ insert into public.connections (requester_id, addressee_id)
     values ('$$ || :'alice_id' || $$', '$$ || :'alice_id' || $$') $$,
  '23514',
  null,
  'a user cannot connect with themselves'
);

select throws_ok(
  $$ insert into public.connections (requester_id, addressee_id)
     values ('$$ || :'bob_id' || $$', '$$ || :'carol_id' || $$') $$,
  '42501',
  null,
  'a user cannot send a request on someone else''s behalf'
);

insert into public.connections (requester_id, addressee_id)
values (:'alice_id'::uuid, :'bob_id'::uuid)
returning id as conn_id \gset

select is(
  (select status from public.connections where id = :'conn_id'::uuid),
  'pending',
  'a new connection request starts as pending'
);

-- Same pair, opposite direction -- the unordered unique index must reject it.
select throws_ok(
  $$ insert into public.connections (requester_id, addressee_id)
     values ('$$ || :'alice_id' || $$', '$$ || :'bob_id' || $$') $$,
  '23505',
  null,
  'a duplicate request for the same pair is rejected'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 9-10. An unverified user is not connectable
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'dave_id', true);

select throws_ok(
  $$ insert into public.connections (requester_id, addressee_id)
     values ('$$ || :'dave_id' || $$', '$$ || :'carol_id' || $$') $$,
  'P0001',
  null,
  'an unverified user cannot send a connection request'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol_id', true);

select throws_ok(
  $$ insert into public.connections (requester_id, addressee_id)
     values ('$$ || :'carol_id' || $$', '$$ || :'dave_id' || $$') $$,
  'P0001',
  null,
  'a request to an unverified user is rejected'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 11-14. Only the addressee answers
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ update public.connections set status = 'accepted'
     where id = '$$ || :'conn_id' || $$' $$,
  'P0001',
  null,
  'the requester cannot accept their own request'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol_id', true);

select is(
  (select count(*)::int from public.connections where id = :'conn_id'::uuid),
  0,
  'an unrelated user cannot even see the connection'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

update public.connections set status = 'accepted' where id = :'conn_id'::uuid;

select is(
  (select status from public.connections where id = :'conn_id'::uuid),
  'accepted',
  'the addressee can accept the request'
);

select isnt(
  (select responded_at from public.connections where id = :'conn_id'::uuid),
  null,
  'accepting records responded_at'
);

-- ---------------------------------------------------------------------
-- 15-17. are_connected / has_connection_history
-- ---------------------------------------------------------------------

select is(
  public.are_connected(:'alice_id'::uuid, :'bob_id'::uuid),
  true,
  'are_connected is true once accepted, in either argument order'
);

select is(
  public.are_connected(:'bob_id'::uuid, :'alice_id'::uuid),
  true,
  'are_connected is symmetric'
);

select is(
  public.are_connected(:'alice_id'::uuid, :'carol_id'::uuid),
  false,
  'are_connected is false for an unrelated pair'
);

-- ---------------------------------------------------------------------
-- 18-20. Disconnecting
-- ---------------------------------------------------------------------

update public.connections set status = 'removed' where id = :'conn_id'::uuid;

select is(
  (select status from public.connections where id = :'conn_id'::uuid),
  'removed',
  'either side can remove an accepted connection'
);

select is(
  public.are_connected(:'alice_id'::uuid, :'bob_id'::uuid),
  false,
  'are_connected is false after removal'
);

-- A removed pair can start over immediately -- no cooldown, nobody refused.
update public.connections set status = 'pending' where id = :'conn_id'::uuid;

select is(
  (select status from public.connections where id = :'conn_id'::uuid),
  'pending',
  'a removed connection can be requested again straight away'
);

-- ---------------------------------------------------------------------
-- 21-24. Decline, cooldown, re-request
-- ---------------------------------------------------------------------

update public.connections set status = 'declined' where id = :'conn_id'::uuid;

select is(
  (select status from public.connections where id = :'conn_id'::uuid),
  'declined',
  'the addressee can decline'
);

select throws_ok(
  $$ update public.connections set status = 'pending'
     where id = '$$ || :'conn_id' || $$' $$,
  'P0001',
  null,
  'a declined request cannot be re-sent during the cooldown'
);

select throws_ok(
  $$ update public.connections set responded_at = now() - interval '30 days'
     where id = '$$ || :'conn_id' || $$' $$,
  'P0001',
  null,
  'a client cannot backdate responded_at to escape the cooldown'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- Server-side backdating to simulate the cooldown elapsing.
update public.connections
set responded_at = now() - interval '30 days'
where id = :'conn_id'::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

update public.connections set status = 'pending' where id = :'conn_id'::uuid;

select is(
  (select status from public.connections where id = :'conn_id'::uuid),
  'pending',
  'a declined request can be re-sent once the cooldown has passed'
);

-- ---------------------------------------------------------------------
-- 25-26. Cancelling
-- ---------------------------------------------------------------------

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

select throws_ok(
  $$ update public.connections set status = 'cancelled'
     where id = '$$ || :'conn_id' || $$' $$,
  'P0001',
  null,
  'the addressee cannot cancel a request they received'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

update public.connections set status = 'cancelled' where id = :'conn_id'::uuid;

select is(
  (select status from public.connections where id = :'conn_id'::uuid),
  'cancelled',
  'the requester can cancel their own pending request'
);

-- ---------------------------------------------------------------------
-- 27-28. Blocked users cannot reach each other
-- ---------------------------------------------------------------------

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol_id', true);

insert into public.blocks (blocker_id, blocked_id)
values (:'carol_id'::uuid, :'alice_id'::uuid);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ insert into public.connections (requester_id, addressee_id)
     values ('$$ || :'alice_id' || $$', '$$ || :'carol_id' || $$') $$,
  'P0001',
  null,
  'a blocked user cannot send a connection request to the blocker'
);

select is(
  (select count(*)::int from public.blocks),
  0,
  'the blocked user cannot see that a block exists'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select * from finish();
rollback;
