-- Realtime feeds for map-visible event/activity changes.
-- RLS and authenticated table privileges still govern which rows a client can
-- receive. Availability rows deliberately stay out of the publication: the
-- map exposes only the aggregate returned by active_map_points(), not raw
-- user availability records.

-- Activities and activity participants are normally in the publication from
-- 20260910011000. Guard every table so this migration is safe when a teammate
-- has already enabled one of these feeds manually on a shared database.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'activities'
  ) then
    alter publication supabase_realtime add table public.activities;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'activity_participants'
  ) then
    alter publication supabase_realtime add table public.activity_participants;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'official_events'
  ) then
    alter publication supabase_realtime add table public.official_events;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'event_rsvps'
  ) then
    alter publication supabase_realtime add table public.event_rsvps;
  end if;
end;
$$;
