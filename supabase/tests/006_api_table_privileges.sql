begin;

select plan(10);

select ok(
  has_table_privilege('anon', 'public.organisation_domains', 'select'),
  'anon can reach approved organisation domains'
);

select ok(
  has_table_privilege('anon', 'public.areas', 'select'),
  'anon can reach campus areas'
);

select ok(
  has_table_privilege('authenticated', 'public.profiles', 'select'),
  'authenticated users can reach profiles for RLS evaluation'
);

select ok(
  has_table_privilege('authenticated', 'public.profiles', 'update'),
  'authenticated users can submit profile updates for RLS evaluation'
);

select ok(
  has_table_privilege('authenticated', 'public.availabilities', 'insert'),
  'authenticated users can create availability for RLS evaluation'
);

select ok(
  has_table_privilege('authenticated', 'public.activities', 'select'),
  'authenticated users can read activities for RLS evaluation'
);

select ok(
  has_table_privilege('authenticated', 'public.activities', 'insert'),
  'authenticated users can create activities for RLS evaluation'
);

select ok(
  has_table_privilege('authenticated', 'public.activity_participants', 'insert'),
  'authenticated users can request activity participation for RLS evaluation'
);

select ok(
  has_table_privilege('authenticated', 'public.interests', 'select'),
  'authenticated users can read interests for RLS evaluation'
);

select ok(
  has_table_privilege('service_role', 'public.profiles', 'select'),
  'service_role can inspect profiles for administration'
);

select * from finish();
rollback;
