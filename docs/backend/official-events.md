# Official Events and RSVPs

Phase 3 backend task: events published by approved organisation accounts
(universities, companies, venues) that verified users can RSVP to
(Backend Docs v0.1, Phase 3 "Official Events").

Same architecture as activities: every rule is enforced by the database
(constraints, triggers, RLS), not an Edge Function. The frontend talks to
`public.official_events` and `public.event_rsvps` directly through
`supabase-js`. A `create-official-event` Edge Function is listed in the
suggested contracts and can be layered on later without changing the schema
(see "Limitations").

Migrations:

- `20260917100000_add_profile_org_admin.sql`
- `20260917100100_create_official_events.sql`
- `20260917100200_create_event_rsvps.sql`

Tests: `supabase/tests/007_official_events.sql`.

## Who can publish: organisation admins

`public.profiles.is_org_admin boolean` (default `false`) marks an account as
an approved organisation account. An admin can only publish for the
organisation their profile belongs to (`profiles.organisation_id`).

The flag is **server-side only**. It is in the protected-field list of the
profiles update trigger, so a client `update` that touches it fails with
`[forbidden]`. Grant it from the dashboard SQL editor / service role:

```sql
update public.profiles
set is_org_admin = true
where id = '<auth user uuid>';
```

Helper for application code and policies:

```sql
public.is_org_admin(p_organisation_id uuid default null) returns boolean
```

True only when the caller is a fully verified user (`is_verified_user()`),
has the flag, and -- when an organisation id is passed -- belongs to that
organisation. Callable by `authenticated` (e.g. to decide whether to show
the "Host an event" button):

```js
const { data: isOrgAdmin } = await supabase.rpc('is_org_admin')
```

## Tables

**`public.official_events`**

| Column | Notes |
|---|---|
| `id` | uuid |
| `organisation_id` | the publishing organisation; must be the admin's own |
| `creator_id` | the admin who created it; nullable so the event survives account deletion |
| `title` | 1-120 chars |
| `description` | up to 2000 chars, optional |
| `location_id` | required; a `public.locations` row (campus / office / public venue) |
| `area_id` | optional; a `public.areas` row that must belong to `location_id` |
| `latitude`, `longitude` | public venue coordinates for the map marker; auto-filled from the location if omitted |
| `start_time`, `end_time` | timestamptz; `end_time > start_time` |
| `status` | `draft` (default), `approved`, `cancelled`, `expired` |
| `approved_at` | set by the database when status becomes `approved` |
| `created_at`, `updated_at` | maintained by trigger |

Coordinates are the **venue's** public position, never a user's. They are
range-checked and must be supplied as a pair (both or neither).

**`public.event_rsvps`**

| Column | Notes |
|---|---|
| `id` | uuid |
| `event_id` | `official_events.id` |
| `user_id` | must equal `auth.uid()` |
| `status` | `going` (default) or `interested` |
| `created_at`, `updated_at` | |

Unique on `(event_id, user_id)` -- one RSVP per user per event.

## Event lifecycle

```
draft ──► approved ──► expired   (automatic, end_time passed)
  │           │
  │           └──► cancelled
  └──► cancelled
approved ──► draft   (unpublish, only while the event has not ended)
```

- Only `approved` events whose `end_time > now()` are visible to regular
  users. Drafts, cancelled and expired events are invisible to them.
- Org admins see every event of their own organisation regardless of status
  (for management screens).
- `expired` is set only by the system. RLS hides an event the instant
  `end_time` passes; the `expire_official_events()` function (scheduled with
  pg_cron every 5 minutes) then records the terminal status so history and
  management views show the real state.
- `cancelled` and `expired` are terminal for clients.

## Creating an event

```js
const { data, error } = await supabase
  .from('official_events')
  .insert({
    organisation_id: profile.organisation_id,
    creator_id: user.id,
    title,
    description,
    location_id: selectedLocation.id,
    area_id: selectedArea?.id ?? null,     // optional
    start_time: startTime.toISOString(),
    end_time: endTime.toISOString(),
    status: 'approved',                     // or omit for a 'draft'
    // latitude / longitude optional: defaults to the location's coordinates
  })
  .select()
  .single()
```

`creator_id` must be the caller and `organisation_id` must be an
organisation the caller administers, otherwise RLS rejects the insert (the
client sees a generic "new row violates row-level security policy" error --
treat it as `forbidden`).

Rejected by the database with:

- `[invalid_area]` -- `area_id` is not inside `location_id`;
- `[expired]` -- `end_time` is already in the past;
- `[invalid_transition]` -- `status` is anything other than `draft` or
  `approved` on insert;
- constraint errors for title/description length, coordinate range, or an
  unpaired latitude/longitude.

## Publishing, editing, cancelling

Any admin of the organisation can manage its events, not only the creator.

```js
// Publish a draft
await supabase.from('official_events').update({ status: 'approved' }).eq('id', eventId)

// Edit details (allowed in draft or approved, until the event ends)
await supabase.from('official_events').update({ title, start_time, end_time }).eq('id', eventId)

// Cancel (a status change, not a delete)
await supabase.from('official_events').update({ status: 'cancelled' }).eq('id', eventId)

// Move a published event back to draft
await supabase.from('official_events').update({ status: 'draft' }).eq('id', eventId)
```

Changing `location_id` without sending new coordinates re-defaults
`latitude`/`longitude` to the new location. Sending explicit coordinates
keeps them.

Rejected with:

- `[forbidden]` -- changing `id`, `organisation_id`, `creator_id`,
  `created_at` or `approved_at`;
- `[invalid_transition]` -- any change out of `cancelled` / `expired`, or
  setting `expired` from the client;
- `[expired]` -- approving an event whose `end_time` has passed, or editing
  an expired event;
- `[invalid_area]` -- new area not inside the (new) location.

A delete policy exists for org admins (`delete from official_events`), but
prefer `cancelled` so RSVPs and history remain available.

## Reading events (map and feed)

```js
const { data: events } = await supabase
  .from('official_events')
  .select(`
    id, title, description, start_time, end_time, status,
    latitude, longitude,
    organisation:organisations ( id, name, type ),
    location:locations ( id, name, type ),
    area:areas ( id, name, type )
  `)
  .order('start_time', { ascending: true })
```

No `status` / time filter is needed: RLS already returns only approved,
unexpired events to regular users. Org admins additionally get their own
organisation's drafts/cancelled/expired rows, so a management screen should
filter on `status` client-side.

Map payload: use `latitude` / `longitude` from the row for the marker with
data type `official_event`. These are venue coordinates, so exposing them
does not leak any user position.

## RSVPs

```js
// RSVP (or change an existing RSVP)
await supabase
  .from('event_rsvps')
  .upsert({ event_id: eventId, user_id: user.id, status: 'going' }, { onConflict: 'event_id,user_id' })

// Withdraw
await supabase.from('event_rsvps').delete().eq('event_id', eventId).eq('user_id', user.id)

// The current user's RSVPs (for "you're going" badges)
const { data: mine } = await supabase.from('event_rsvps').select('event_id, status')
```

`user_id` must equal `auth.uid()`. Rejected with:

- `[expired]` -- the event is not `approved` or its `end_time` has passed;
- `[forbidden]` -- changing `event_id` / `user_id` on an existing RSVP;
- a check-constraint error for a status other than `going` / `interested`.

Regular users can read only their own RSVP rows. Org admins can read the
full RSVP list for their organisation's events:

```js
const { data: attendees } = await supabase
  .from('event_rsvps')
  .select('status, created_at, profile:profiles ( id, display_name, avatar_url )')
  .eq('event_id', eventId)
```

For public counts without exposing who RSVP'd:

```js
const { data } = await supabase.rpc('event_rsvp_counts', { p_event_id: eventId })
// data[0] -> { going_count: 12, interested_count: 4 }
```

Returns zeros for an event the caller is not allowed to see.

## Visibility summary

| Caller | `official_events` | `event_rsvps` |
|---|---|---|
| anon | nothing (no table privileges) | nothing |
| unverified user | nothing | nothing |
| verified user | approved and unexpired events | own rows only |
| org admin | above + all events of own organisation | above + all RSVPs on own organisation's events |
| service role | everything | everything |

## Realtime

`official_events` and `event_rsvps` are **not yet** added to the
`supabase_realtime` publication (activities are, via
`20260910011000_activities_realtime.sql`). Until a follow-up migration adds
them, poll or refetch after writes. When enabled, RLS still applies: a
subscriber only receives events for rows they could `select`.

## Error code reference

| Prefix | User-facing meaning |
|---|---|
| `[invalid_area]` | The chosen area isn't part of the chosen location. |
| `[expired]` | This event has already ended (or you tried to create/approve one in the past). |
| `[invalid_transition]` | That status change isn't allowed. |
| `[forbidden]` | That field or action isn't allowed here. |
| RLS violation on insert/update | You are not an admin of this organisation. |

These extend the shared table in `docs/backend/api-contract.md`.

## Limitations and open decisions

- **Approval is self-service.** An org admin publishes their own draft
  (`draft -> approved`). Backend Docs v0.1 calls event approval a sensitive
  action suited to an Edge Function; a platform-admin gate can be added
  later by restricting that transition in the trigger and moving it behind
  `POST /functions/v1/create-official-event`. The schema does not need to
  change.
- **No RSVP capacity or waitlist.** Events have no attendee limit.
- **No Realtime yet** for these two tables (see above).
- **No Edge Functions yet** (`create-official-event`, `rsvp-to-event`).
  All rules are enforced by RLS/triggers, so direct `supabase-js` calls are
  safe; the functions would add a stable `{ data, error }` envelope and
  friendlier error codes.
- **pg_cron.** The expiry schedule is created by the migration if the
  extension can be installed; otherwise a `notice` is raised and only RLS
  hides expired events. Verify on a project with
  `select jobname, schedule, active from cron.job;`.

## Local verification checklist

Before opening a pull request:

1. Apply migrations with `npx supabase db reset` while Docker is running.
2. Grant `is_org_admin` to a test user via SQL; confirm a normal profile
   `update` cannot set it (`[forbidden]`).
3. Confirm a non-admin insert into `official_events` is rejected by RLS, and
   an admin insert for a *different* organisation is also rejected.
4. Confirm `area_id` from another location is rejected (`[invalid_area]`).
5. Confirm an event with `end_time` in the past cannot be created or
   approved (`[expired]`).
6. Confirm a regular user sees only `approved` events; drafts and cancelled
   events are invisible; the admin sees all of their organisation's.
7. Confirm `cancelled -> approved` and client-set `expired` fail with
   `[invalid_transition]`.
8. Confirm RSVP to a draft / cancelled / ended event fails (`[expired]`), a
   second RSVP by the same user hits the unique constraint, and a user
   cannot read another user's RSVP row.
9. Confirm `select public.expire_official_events();` marks a past-dated
   approved event `expired`.
10. Run `npx supabase test db`.
