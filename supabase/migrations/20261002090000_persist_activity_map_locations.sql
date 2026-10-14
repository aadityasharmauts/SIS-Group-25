-- User-created activities may publish a public venue/meeting-point location.
-- This is never a user's live position: area_id remains required for the
-- privacy boundary and the coordinates are only the public event marker.

alter table public.activities
  add column if not exists location_label text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.activities'::regclass
      and conname = 'activities_location_label_length'
  ) then
    alter table public.activities
      add constraint activities_location_label_length
      check (location_label is null or char_length(btrim(location_label)) between 1 and 120);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.activities'::regclass
      and conname = 'activities_latitude_range'
  ) then
    alter table public.activities
      add constraint activities_latitude_range
      check (latitude is null or latitude between -90 and 90);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.activities'::regclass
      and conname = 'activities_longitude_range'
  ) then
    alter table public.activities
      add constraint activities_longitude_range
      check (longitude is null or longitude between -180 and 180);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.activities'::regclass
      and conname = 'activities_coordinates_pair'
  ) then
    alter table public.activities
      add constraint activities_coordinates_pair
      check ((latitude is null) = (longitude is null));
  end if;
end $$;

create index if not exists activities_map_coordinates_idx
  on public.activities (latitude, longitude)
  where latitude is not null and longitude is not null;

comment on column public.activities.location_label is
  'Public venue or meeting-point label; never a private address or live user location.';
comment on column public.activities.latitude is
  'Public activity marker latitude. This is not the creator''s current position.';
comment on column public.activities.longitude is
  'Public activity marker longitude. This is not the creator''s current position.';
