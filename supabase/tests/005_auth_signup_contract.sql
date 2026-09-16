begin;

select plan(5);

-- Use deterministic IDs so the rows can be removed before the transaction
-- rolls back even if a test fails part-way through.
select lives_ok($$
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000501',
    'authenticated', 'authenticated', 'signup-alias@student.uts.edu.au',
    crypt('Test-Password1', gen_salt('bf')), null,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'full_name', 'Signup Alias',
      'terms_accepted', true,
      'privacy_accepted', true
    ),
    now(), now(), '', ''
  )
$$, 'signup accepts the legacy full_name metadata alias');

select is(
  (select display_name from public.profiles
   where id = '00000000-0000-0000-0000-000000000501'::uuid),
  'Signup Alias',
  'full_name is copied to profiles.display_name'
);

select is(
  (select account_status from public.profiles
   where id = '00000000-0000-0000-0000-000000000501'::uuid),
  'pending',
  'an unconfirmed signup starts with pending status'
);

select throws_ok($$
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-0000-0000-000000000502',
    'authenticated', 'authenticated', 'missing-consent@student.uts.edu.au',
    crypt('Test-Password1', gen_salt('bf')), null,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', 'Missing Consent'),
    now(), now(), '', ''
  )
$$, 'P0001', '[consent_required] Terms and privacy consent are required.',
  'signup without both consent flags is rejected');

select is(
  (select count(*) from public.profiles
   where id = '00000000-0000-0000-0000-000000000502'::uuid),
  0::bigint,
  'a rejected signup does not create a profile'
);

select * from finish();
rollback;
