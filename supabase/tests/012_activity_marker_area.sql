-- Public activity markers must stay close to the approved area location.

begin;
select plan(4);

select ok(
  exists (
    select 1
    from pg_proc
    where oid = 'public.enforce_activity_marker_area()'::regprocedure
  ),
  'activity marker area validation function exists'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.activities'::regclass
      and tgname = 'on_activity_marker_area_check'
      and not tgisinternal
  ),
  'activities validate marker coordinates against the approved area'
);

select throws_ok(
  $$
    insert into public.activities (
      creator_id, area_id, title, category, start_time, end_time,
      latitude, longitude
    ) values (
      (select id from auth.users where email = 'test@student.uts.edu.au'),
      '00000000-0000-0000-0000-000000000201'::uuid,
      'Outside approved area', 'coffee_break',
      now() + interval '10 minutes', now() + interval '40 minutes',
      -33.9000, 151.2005
    )
  $$,
  'P0001',
  '[invalid_marker_area] The public event marker must be within 250 metres of its approved area.',
  'a marker outside the approved area radius is rejected'
);

select lives_ok(
  $$
    insert into public.activities (
      creator_id, area_id, title, category, start_time, end_time,
      latitude, longitude
    ) values (
      (select id from auth.users where email = 'test@student.uts.edu.au'),
      '00000000-0000-0000-0000-000000000201'::uuid,
      'Inside approved area', 'coffee_break',
      now() + interval '10 minutes', now() + interval '40 minutes',
      -33.8835, 151.2005
    )
  $$,
  'a marker inside the approved area radius is accepted'
);

select * from finish();
rollback;
