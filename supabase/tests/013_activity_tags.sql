-- Activity tags and editable map payload contract.

begin;
select plan(4);

select has_column(
  'public', 'activities', 'tags',
  'activities stores optional audience tags'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.activities'::regclass
      and conname = 'activities_tags_count'
  ),
  'activities limit tags to six values'
);

select ok(
  position('description text' in pg_get_function_result(
    'public.active_map_points(uuid[], uuid, boolean)'::regprocedure
  )) > 0,
  'map payload includes activity descriptions'
);

select ok(
  position('tags text[]' in pg_get_function_result(
    'public.active_map_points(uuid[], uuid, boolean)'::regprocedure
  )) > 0,
  'map payload includes activity tags'
);

select * from finish();
rollback;
