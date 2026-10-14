-- Real-time map contract, filtering and privacy tests.
-- Run with: npx supabase test db

begin;
select plan(25);

create or replace function pg_temp.create_map_test_user(
  p_email text,
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
    '{"display_name":"Map test user","terms_accepted":true,"privacy_accepted":true}'::jsonb,
    now(), now(), '', ''
  );
  return v_id;
end;
$$;

-- 1-8. Function contract, execution boundary and publication membership.
select has_function(
  'public', 'active_map_points', array['uuid[]', 'uuid', 'boolean'],
  'active_map_points(uuid[], uuid, boolean) exists'
);

select ok(
  (select prosecdef from pg_proc
   where oid = 'public.active_map_points(uuid[], uuid, boolean)'::regprocedure),
  'active_map_points is security definer'
);

select ok(
  has_function_privilege('authenticated', 'public.active_map_points(uuid[], uuid, boolean)', 'execute'),
  'authenticated users can execute active_map_points'
);

select ok(
  not has_function_privilege('anon', 'public.active_map_points(uuid[], uuid, boolean)', 'execute'),
  'anonymous users cannot execute active_map_points'
);

select ok(
  position('point_type' in pg_get_function_result(
    'public.active_map_points(uuid[], uuid, boolean)'::regprocedure
  )) > 0
  and position('available_people' in pg_get_function_result(
    'public.active_map_points(uuid[], uuid, boolean)'::regprocedure
  )) > 0
  and position('latitude' in pg_get_function_result(
    'public.active_map_points(uuid[], uuid, boolean)'::regprocedure
  )) > 0
  and position('host_name' in pg_get_function_result(
    'public.active_map_points(uuid[], uuid, boolean)'::regprocedure
  )) > 0,
  'map response has the documented point fields'
);

select ok(
  position('user_id' in pg_get_function_result(
    'public.active_map_points(uuid[], uuid, boolean)'::regprocedure
  )) = 0
  and position('creator_id' in pg_get_function_result(
    'public.active_map_points(uuid[], uuid, boolean)'::regprocedure
  )) = 0,
  'map response does not expose user identity columns'
);

select ok(
  has_table_privilege('anon', 'public.official_events', 'select') = false
  and has_table_privilege('anon', 'public.event_rsvps', 'select') = false
  and has_table_privilege('anon', 'public.activities', 'select') = false
  and has_table_privilege('anon', 'public.availabilities', 'select') = false,
  'anonymous table privileges are revoked for map source tables'
);

select ok(
  exists (select 1 from pg_publication_tables
          where pubname = 'supabase_realtime' and schemaname = 'public'
            and tablename = 'activities')
  and exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public'
                and tablename = 'activity_participants')
  and exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public'
                and tablename = 'official_events')
  and exists (select 1 from pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public'
                and tablename = 'event_rsvps'),
  'activity and event tables are in supabase_realtime'
);

-- 9-10. Availability remains approximate and is not a raw Realtime feed.
select ok(
  not exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'availabilities'
               and column_name in ('latitude', 'longitude')),
  'availability does not store exact coordinates'
);

select ok(
  not exists (select 1 from pg_publication_tables
             where pubname = 'supabase_realtime' and schemaname = 'public'
               and tablename = 'availabilities'),
  'raw availability rows are not published to Realtime'
);

select pg_temp.create_map_test_user('map.verified@student.uts.edu.au', true) as verified_id \gset
select pg_temp.create_map_test_user('map.pending@student.uts.edu.au', false) as pending_id \gset

-- 11. A pending/unverified account gets an empty result, not an error or leak.
set local role authenticated;
select set_config('request.jwt.claim.sub', :'pending_id', true);
select is(
  (select count(*)::int from public.active_map_points()),
  0,
  'unverified users receive no map points'
);

-- 12. Anonymous execution is rejected at the function boundary.
reset role;
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select throws_ok(
  $$ select * from public.active_map_points() $$,
  '42501', null,
  'anonymous users cannot call the map RPC'
);

-- 13-21. A verified user can see active activity, presence and an official
-- event from the same organisation, but no identity-level availability data.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'verified_id', true);

insert into public.activities (
  creator_id, area_id, title, category, start_time, end_time
) values (
  :'verified_id'::uuid,
  '00000000-0000-0000-0000-000000000201'::uuid,
  'Map test activity', 'coffee_break', now() + interval '5 minutes', now() + interval '45 minutes'
) returning id as activity_id \gset

insert into public.availabilities (user_id, area_id, start_time, end_time)
values (
  :'verified_id'::uuid,
  '00000000-0000-0000-0000-000000000201'::uuid,
  now() - interval '5 minutes', now() + interval '45 minutes'
);

-- Multiple overlapping windows for one person still count as one person on
-- the map, rather than inflating the anonymous presence aggregate.
insert into public.availabilities (user_id, area_id, start_time, end_time)
values (
  :'verified_id'::uuid,
  '00000000-0000-0000-0000-000000000201'::uuid,
  now() - interval '1 minute', now() + interval '30 minutes'
);

-- Insert an approved event as a system-side operation. This also exercises
-- the official-event branch of the RPC, including its nullable category.
reset role;
select set_config('request.jwt.claim.sub', '', true);
insert into public.official_events (
  organisation_id, title, location_id, area_id,
  start_time, end_time, status
) values (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'Map test official event',
  '00000000-0000-0000-0000-000000000101'::uuid,
  '00000000-0000-0000-0000-000000000201'::uuid,
  now() + interval '10 minutes', now() + interval '2 hours', 'approved'
) returning id as event_id \gset

set local role authenticated;
select set_config('request.jwt.claim.sub', :'verified_id', true);

select is(
  (select count(*)::int from public.active_map_points() where point_type = 'activity'),
  1,
  'active activity is returned'
);

select is(
  (select category from public.active_map_points() where point_id = :'activity_id'::uuid),
  'coffee_break',
  'activity category is preserved in the map contract'
);

select is(
  (select host_name from public.active_map_points() where point_id = :'activity_id'::uuid),
  'Map test user',
  'activity host_name is the creator display_name'
);

select is(
  (select count(*)::int from public.active_map_points() where point_type = 'presence'),
  1,
  'availability is returned as one aggregate presence point'
);

select is(
  (select available_people from public.active_map_points() where point_type = 'presence'),
  1,
  'presence exposes an anonymous count'
);

select is(
  (select count(*)::int from public.active_map_points() where point_type = 'official_event'),
  1,
  'active official event is returned'
);

select is(
  (select category from public.active_map_points() where point_id = :'event_id'::uuid),
  null,
  'official event category is null until event categories are added'
);

select is(
  (select count(*)::int from public.active_map_points(
    array['00000000-0000-0000-0000-000000000201'::uuid], null, true
  )),
  3,
  'area filter returns activity, presence and event in the selected area'
);

select is(
  (select count(*)::int from public.active_map_points(
    array['00000000-0000-0000-0000-000000000202'::uuid], null, true
  )),
  0,
  'area filter excludes points outside the selected area'
);

select is(
  (select count(*)::int from public.active_map_points(
    null, '00000000-0000-0000-0000-000000000101'::uuid, false
  )),
  2,
  'location filter works and include_presence=false excludes presence'
);

select ok(
  (select latitude = -33.8835 and longitude = 151.2005
   from public.active_map_points() where point_id = :'activity_id'::uuid),
  'activity marker uses the approved venue coordinates, not a user coordinate'
);

select is(
  (select count(*)::int from public.active_map_points(
    array['00000000-0000-0000-0000-000000000201'::uuid],
    '00000000-0000-0000-0000-000000000101'::uuid, true
  )),
  3,
  'area and location filters can be combined'
);

-- Time passing does not itself emit a Postgres Changes event. The RPC must
-- nevertheless exclude a source row as soon as it expires on a subsequent
-- refresh (the frontend schedules that refresh at the nearest ends_at).
reset role;
select set_config('request.jwt.claim.sub', '', true);
update public.activities
set status = 'cancelled',
    start_time = now() - interval '2 minutes',
    end_time = now() - interval '1 minute'
where id = :'activity_id'::uuid;
update public.official_events
set start_time = now() - interval '2 minutes',
    end_time = now() - interval '1 minute'
where id = :'event_id'::uuid;
update public.availabilities
set start_time = now() - interval '2 minutes',
    end_time = now() - interval '1 minute'
where user_id = :'verified_id'::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', :'verified_id', true);
select is(
  (select count(*)::int from public.active_map_points()),
  0,
  'expired activity, event and availability rows disappear after refresh'
);

select * from finish();
rollback;
