-- Phase 5 (built early for Phase 4 matching): blocks.
-- Run with `npx supabase test db`.

begin;
select plan(13);

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

select pg_temp.create_test_user('blk.alice@student.uts.edu.au', 'Alice') as alice_id \gset
select pg_temp.create_test_user('blk.bob@student.uts.edu.au', 'Bob') as bob_id \gset
select pg_temp.create_test_user('blk.dave@student.uts.edu.au', 'Dave', false) as dave_id \gset

-- 1-2. Schema
select has_table('public', 'blocks', 'blocks table exists');
select has_column('public', 'blocks', 'blocker_id', 'blocks has blocker_id');

-- Alice and Bob connect BEFORE any block exists -- that's the sequence the
-- "blocking leaves the connection alone" rule is actually about.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);
insert into public.connections (requester_id, addressee_id)
values (:'alice_id'::uuid, :'bob_id'::uuid)
returning id as conn_id \gset

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);
update public.connections set status = 'accepted' where id = :'conn_id'::uuid;

reset role;
select set_config('request.jwt.claim.sub', '', true);

-- ---------------------------------------------------------------------
-- 3-5. Creating a block
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id)
     values ('$$ || :'alice_id' || $$', '$$ || :'alice_id' || $$') $$,
  '23514',
  null,
  'a user cannot block themselves'
);

select throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id)
     values ('$$ || :'bob_id' || $$', '$$ || :'alice_id' || $$') $$,
  '42501',
  null,
  'a user cannot create a block on someone else''s behalf'
);

insert into public.blocks (blocker_id, blocked_id)
values (:'alice_id'::uuid, :'bob_id'::uuid)
returning id as block_id \gset

select is(
  (select count(*)::int from public.blocks where id = :'block_id'::uuid),
  1,
  'the blocker can see their own block'
);

select throws_ok(
  $$ insert into public.blocks (blocker_id, blocked_id)
     values ('$$ || :'alice_id' || $$', '$$ || :'bob_id' || $$') $$,
  '23505',
  null,
  'the same block cannot be created twice'
);

-- ---------------------------------------------------------------------
-- 6-8. The blocked user learns nothing, but is blocked both ways
-- ---------------------------------------------------------------------

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

select is(
  (select count(*)::int from public.blocks),
  0,
  'the blocked user cannot see the block'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  public.is_blocked_between(:'alice_id'::uuid, :'bob_id'::uuid),
  true,
  'is_blocked_between is true from the blocker side'
);

select is(
  public.is_blocked_between(:'bob_id'::uuid, :'alice_id'::uuid),
  true,
  'is_blocked_between is true from the blocked side too -- a block is mutual for visibility'
);

-- ---------------------------------------------------------------------
-- 9-10. Blocking leaves the existing connection alone
-- ---------------------------------------------------------------------

select is(
  public.are_connected(:'alice_id'::uuid, :'bob_id'::uuid),
  true,
  'blocking does not tear down an existing connection'
);

select is(
  public.is_blocked_between(:'alice_id'::uuid, :'bob_id'::uuid),
  true,
  'the pair is still blocked while connected -- read paths must filter on it'
);

-- ---------------------------------------------------------------------
-- 11-12. Unblocking
-- ---------------------------------------------------------------------

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

delete from public.blocks where id = :'block_id'::uuid;

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  public.is_blocked_between(:'alice_id'::uuid, :'bob_id'::uuid),
  false,
  'unblocking clears the block'
);

select is(
  public.are_connected(:'alice_id'::uuid, :'bob_id'::uuid),
  true,
  'the connection is intact after unblocking -- they can talk again'
);

select * from finish();
rollback;
