begin;

select plan(42);

-- =========================================================
-- Organisation admin flag on profiles
-- =========================================================

-- 1. profiles has is_org_admin
select has_column(
  'public',
  'profiles',
  'is_org_admin',
  'profiles has is_org_admin'
);

-- 2. is_org_admin defaults to false
select col_default_is(
  'public',
  'profiles',
  'is_org_admin',
  'false',
  'is_org_admin defaults to false'
);

-- 3. is_org_admin helper exists
select has_function(
  'public',
  'is_org_admin',
  array['uuid'],
  'is_org_admin(uuid) helper exists'
);

-- 4. clients cannot self-promote (flag is in the protected-field trigger)
select ok(
  position('is_org_admin' in pg_get_functiondef('public.prevent_profile_protected_changes()'::regprocedure)) > 0,
  'is_org_admin is protected from client profile updates'
);

-- =========================================================
-- official_events schema
-- =========================================================

-- 5. table exists
select has_table(
  'public',
  'official_events',
  'official_events table exists'
);

-- 6-11. key columns
select has_column('public', 'official_events', 'organisation_id', 'official_events has organisation_id');
select has_column('public', 'official_events', 'creator_id',      'official_events has creator_id');
select has_column('public', 'official_events', 'location_id',     'official_events has location_id');
select has_column('public', 'official_events', 'status',          'official_events has status');
select has_column('public', 'official_events', 'latitude',        'official_events has public venue latitude');
select has_column('public', 'official_events', 'longitude',       'official_events has public venue longitude');

-- 12. status defaults to draft
select col_default_is(
  'public',
  'official_events',
  'status',
  'draft',
  'official_events status defaults to draft'
);

-- 13. status is limited to the approval lifecycle
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.official_events'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%draft%'
      and pg_get_constraintdef(oid) like '%approved%'
      and pg_get_constraintdef(oid) like '%cancelled%'
      and pg_get_constraintdef(oid) like '%expired%'
  ),
  'official_events status allows draft, approved, cancelled, expired'
);

-- 14. organisation_id links to organisations
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.official_events'::regclass
      and contype = 'f'
      and pg_get_constraintdef(oid)
        like '%FOREIGN KEY (organisation_id)%REFERENCES organisations(id)%'
  ),
  'organisation_id references organisations'
);

-- 15. location_id links to predefined locations
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.official_events'::regclass
      and contype = 'f'
      and pg_get_constraintdef(oid)
        like '%FOREIGN KEY (location_id)%REFERENCES locations(id)%'
  ),
  'location_id references locations'
);

-- 16. end_time must be after start_time
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.official_events'::regclass
      and conname = 'official_events_valid_time'
      and contype = 'c'
  ),
  'official_events has valid time constraint'
);

-- 17. coordinates are range-checked and paired
select is(
  (
    select count(*)
    from pg_constraint
    where conrelid = 'public.official_events'::regclass
      and contype = 'c'
      and conname in (
        'official_events_latitude_range',
        'official_events_longitude_range',
        'official_events_coordinates_pair'
      )
  ),
  3::bigint,
  'official_events coordinate constraints exist'
);

-- 18. area must belong to location (trigger)
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.official_events'::regclass
      and tgname = 'on_official_event_check_area'
      and not tgisinternal
  ),
  'official_events checks area belongs to location'
);

-- 19. venue coordinates default from the location (trigger)
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.official_events'::regclass
      and tgname = 'on_official_event_default_coordinates'
      and not tgisinternal
  ),
  'official_events defaults coordinates from the venue location'
);

-- 20. protected fields / status transitions / updated_at trigger
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.official_events'::regclass
      and tgname = 'on_official_event_updated'
      and not tgisinternal
  ),
  'official_events update trigger exists'
);

-- 21. creation guard trigger
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.official_events'::regclass
      and tgname = 'on_official_event_created_check_time'
      and not tgisinternal
  ),
  'official_events creation guard trigger exists'
);

-- 22. automatic expiry function exists
select has_function(
  'public',
  'expire_official_events',
  array[]::text[],
  'expire_official_events() exists'
);

-- 23. expiry function is not callable by API roles
select ok(
  not has_function_privilege('authenticated', 'public.expire_official_events()', 'execute')
  and not has_function_privilege('anon', 'public.expire_official_events()', 'execute'),
  'expire_official_events() is system-only'
);

-- =========================================================
-- official_events privileges + RLS
-- =========================================================

-- 24. authenticated can reach the table (RLS restricts rows)
select ok(
  has_table_privilege('authenticated', 'public.official_events', 'select')
  and has_table_privilege('authenticated', 'public.official_events', 'insert')
  and has_table_privilege('authenticated', 'public.official_events', 'update')
  and has_table_privilege('authenticated', 'public.official_events', 'delete'),
  'authenticated has table privileges on official_events'
);

-- 25. anon cannot reach the table
select ok(
  not has_table_privilege('anon', 'public.official_events', 'select'),
  'anon has no privileges on official_events'
);

-- 26. RLS enabled
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.official_events'::regclass
  ),
  'RLS is enabled on official_events'
);

-- 27. five policies
select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'official_events'
  ),
  5::bigint,
  'official_events has five RLS policies'
);

-- 28. INSERT restricted to organisation admins
select ok(
  (
    select
      position('is_org_admin(organisation_id)' in coalesce(with_check, '')) > 0
      and position('creator_id = auth.uid()' in coalesce(with_check, '')) > 0
    from pg_policies
    where schemaname = 'public'
      and tablename = 'official_events'
      and policyname = 'org admins can create events for their organisation'
      and cmd = 'INSERT'
  ),
  'only org admins can create events for their own organisation'
);

-- 29. UPDATE restricted to organisation admins (before and after)
select ok(
  (
    select
      position('is_org_admin(organisation_id)' in coalesce(qual, '')) > 0
      and position('is_org_admin(organisation_id)' in coalesce(with_check, '')) > 0
    from pg_policies
    where schemaname = 'public'
      and tablename = 'official_events'
      and policyname = 'org admins can update their organisation events'
      and cmd = 'UPDATE'
  ),
  'only org admins can manage their organisation events'
);

-- 30. DELETE restricted to organisation admins
select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'official_events'
      and policyname = 'org admins can delete their organisation events'
      and cmd = 'DELETE'
  ),
  'org admins can delete their organisation events'
);

-- 31. only approved, unexpired events are visible to regular users
select ok(
  (
    select
      position('end_time > now()' in coalesce(qual, '')) > 0
      and position('approved' in coalesce(qual, '')) > 0
    from pg_policies
    where schemaname = 'public'
      and tablename = 'official_events'
      and policyname = 'verified users can read active official events'
      and cmd = 'SELECT'
  ),
  'draft, cancelled and expired events are excluded from normal reads'
);

-- 32. no anon policies
select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'official_events'
      and 'anon' = any (roles)
  ),
  'official_events has no anon policies'
);

-- =========================================================
-- event_rsvps schema
-- =========================================================

-- 33. table exists
select has_table(
  'public',
  'event_rsvps',
  'event_rsvps table exists'
);

-- 34-35. key columns
select has_column('public', 'event_rsvps', 'event_id', 'event_rsvps has event_id');
select has_column('public', 'event_rsvps', 'status',   'event_rsvps has status');

-- 36. event_id links to official_events
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.event_rsvps'::regclass
      and contype = 'f'
      and pg_get_constraintdef(oid)
        like '%FOREIGN KEY (event_id)%REFERENCES official_events(id)%'
  ),
  'event_id references official_events'
);

-- 37. one RSVP per user per event
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.event_rsvps'::regclass
      and conname = 'event_rsvps_unique'
      and contype = 'u'
  ),
  'one RSVP per event and user'
);

-- 38. RSVPs rejected for unapproved / expired events (trigger)
select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.event_rsvps'::regclass
      and tgname = 'on_event_rsvp_write'
      and not tgisinternal
  ),
  'event_rsvps write trigger exists'
);

-- 39. aggregate counts RPC exists
select has_function(
  'public',
  'event_rsvp_counts',
  array['uuid'],
  'event_rsvp_counts(uuid) exists'
);

-- =========================================================
-- event_rsvps privileges + RLS
-- =========================================================

-- 40. RLS enabled
select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.event_rsvps'::regclass
  ),
  'RLS is enabled on event_rsvps'
);

-- 41. five policies
select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename = 'event_rsvps'
  ),
  5::bigint,
  'event_rsvps has five RLS policies'
);

-- 42. users can only RSVP as themselves
select ok(
  (
    select
      position('user_id = auth.uid()' in coalesce(with_check, '')) > 0
    from pg_policies
    where schemaname = 'public'
      and tablename = 'event_rsvps'
      and policyname = 'verified users can rsvp as themselves'
      and cmd = 'INSERT'
  ),
  'users can only RSVP as themselves'
);

select * from finish();

rollback;
