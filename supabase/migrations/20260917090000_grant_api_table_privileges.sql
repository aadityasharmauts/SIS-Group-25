-- Ensure PostgREST roles can reach the tables protected by the RLS policies.
-- RLS controls which rows are visible; table privileges control whether the
-- API roles can access the table at all. Both layers are required.

grant usage on schema public to anon, authenticated, service_role;

-- Reference data is readable before a session exists so the signup flow and
-- map can resolve approved organisations and campus areas.
grant select on table
  public.organisations,
  public.organisation_domains,
  public.locations,
  public.areas
to anon, authenticated;

-- Authenticated profile access is still restricted by the profiles RLS
-- policies; these grants only make the protected API surface reachable.
grant select, update on table public.profiles to authenticated;

grant select, insert, update, delete on table public.availabilities
to authenticated;

grant select, insert, update on table public.activities
to authenticated;

grant select, insert, update on table public.activity_participants
to authenticated;

grant select on table public.interests to authenticated;
grant select, insert, delete on table public.profile_interests to authenticated;

-- Admin/service-role calls must also have table privileges. RLS is bypassed
-- by service_role, but PostgreSQL table grants are still required.
grant all privileges on all tables in schema public to service_role;

