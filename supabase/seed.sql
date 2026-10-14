-- Development seed data.
-- Applied automatically by `supabase db reset` / `supabase start` on a
-- local dev stack. NOT applied automatically to a shared/staging/prod
-- project -- see docs/backend/environment-setup.md.

insert into public.organisations (id, name, type) values
  ('00000000-0000-0000-0000-000000000001', 'University of Technology Sydney', 'university'),
  ('00000000-0000-0000-0000-000000000002', 'Example Co', 'company')
on conflict (id) do nothing;

insert into public.organisation_domains (organisation_id, domain) values
  ('00000000-0000-0000-0000-000000000001', 'uts.edu.au'),
  ('00000000-0000-0000-0000-000000000001', 'student.uts.edu.au'),
  ('00000000-0000-0000-0000-000000000002', 'examplecompany.com')
on conflict (domain) do nothing;

insert into public.locations (id, organisation_id, name, type, latitude, longitude) values
  ('00000000-0000-0000-0000-000000000101', '00000000-0000-0000-0000-000000000001', 'UTS City Campus', 'campus', -33.8835, 151.2005),
  ('00000000-0000-0000-0000-000000000102', null, 'Central Park Cafe', 'public_venue', -33.8830, 151.1996)
on conflict (id) do nothing;

insert into public.areas (id, location_id, name, type) values
  ('00000000-0000-0000-0000-000000000201', '00000000-0000-0000-0000-000000000101', 'UTS Library', 'library'),
  ('00000000-0000-0000-0000-000000000202', '00000000-0000-0000-0000-000000000101', 'Central Food Court', 'food_court'),
  ('00000000-0000-0000-0000-000000000203', '00000000-0000-0000-0000-000000000101', 'Building 11', 'building')
on conflict (id) do nothing;

-- Local-only development account, recreated after every local db reset.
-- These are public test credentials, not production secrets. Never apply
-- this seed to a remote project (including via db push --include-seed).
do $$
declare
  v_user_id uuid;
begin
  select id into v_user_id
  from auth.users
  where lower(email) = 'test@student.uts.edu.au';

  if v_user_id is null then
    v_user_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, confirmation_sent_at, raw_app_meta_data,
      raw_user_meta_data, created_at, updated_at, confirmation_token,
      recovery_token, email_change, email_change_token_new,
      reauthentication_token
    ) values (
      '00000000-0000-0000-0000-000000000000', v_user_id,
      'authenticated', 'authenticated', 'test@student.uts.edu.au',
      crypt('test1234', gen_salt('bf')), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"display_name":"Test User","terms_accepted":true,"privacy_accepted":true}'::jsonb,
      now(), now(), '', '', '', '', ''
    );
  else
    update auth.users
    set encrypted_password = crypt('test1234', gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        updated_at = now()
    where id = v_user_id;
  end if;
end $$;
