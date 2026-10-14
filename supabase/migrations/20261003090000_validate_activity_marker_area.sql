-- Keep a public event marker consistent with its approved area.
-- Areas are approximate privacy scopes, while activity coordinates are public
-- meeting-point markers. The parent location is the MVP boundary because the
-- current schema does not yet store polygon boundaries for each area.

create or replace function public.enforce_activity_marker_area()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_area_latitude double precision;
  v_area_longitude double precision;
  v_distance_m double precision;
  v_max_distance_m constant double precision := 250;
begin
  -- A null pair means the marker falls back to the approved location on the map.
  if new.latitude is null and new.longitude is null then
    return new;
  end if;

  select l.latitude, l.longitude
    into v_area_latitude, v_area_longitude
  from public.areas a
  join public.locations l on l.id = a.location_id
  where a.id = new.area_id;

  -- Do not reject legacy areas that have no geocoded parent location yet.
  if v_area_latitude is null or v_area_longitude is null then
    return new;
  end if;

  v_distance_m := 6371000 * acos(
    least(
      1::double precision,
      greatest(
        -1::double precision,
        sin(radians(v_area_latitude)) * sin(radians(new.latitude))
        + cos(radians(v_area_latitude)) * cos(radians(new.latitude))
        * cos(radians(new.longitude - v_area_longitude))
      )
    )
  );

  if v_distance_m > v_max_distance_m then
    raise exception using
      errcode = 'P0001',
      message = '[invalid_marker_area] The public event marker must be within 250 metres of its approved area.';
  end if;

  return new;
end;
$$;

comment on function public.enforce_activity_marker_area() is
  'Rejects public activity markers outside the MVP radius of their approved area location.';

drop trigger if exists on_activity_marker_area_check on public.activities;
create trigger on_activity_marker_area_check
  before insert or update of area_id, latitude, longitude on public.activities
  for each row
  execute function public.enforce_activity_marker_area();

revoke all on function public.enforce_activity_marker_area() from public, anon, authenticated;
