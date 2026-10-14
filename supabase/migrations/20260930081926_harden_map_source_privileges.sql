-- Map reads are exposed through the authenticated, security-definer
-- active_map_points() function.  Do not let the anonymous PostgREST role
-- reach user-generated or RSVP tables directly: RLS is not a substitute for
-- table privileges, and the map response must not expose raw user rows.

revoke all privileges on table
  public.profiles,
  public.availabilities,
  public.activities,
  public.activity_participants,
  public.official_events,
  public.event_rsvps,
  public.blocks,
  public.connections,
  public.conversations,
  public.messages,
  public.message_deleted_bodies
from anon;

-- Official event and RSVP rows are also delivered through authenticated
-- Realtime subscriptions only.  The publication itself does not grant SQL
-- table access, but keeping the anon role revoked makes the boundary explicit.
