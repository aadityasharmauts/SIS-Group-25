# Real-time map backend contract

The map uses one privacy-preserving RPC instead of exposing raw user rows:

```js
const { data, error } = await supabase.rpc('active_map_points', {
  p_area_ids: selectedAreaIds.length ? selectedAreaIds : null,
  p_location_id: selectedLocationId ?? null,
  p_include_presence: true,
})
```

The RPC is available only to authenticated, verified users and is scoped to
the viewer's organisation. It returns active user activities, approved and
unexpired official events, and anonymous availability counts grouped by area.
Expired activities, events and availability windows are excluded on every
read, so the client does not need a separate expiry job to hide markers.

## Response format

Every row has the same shape:

| Field | Meaning |
| --- | --- |
| `point_type` | `activity`, `official_event`, or `presence` |
| `point_id` | Activity/event id, or the area id for a presence aggregate |
| `area_id`, `area_name` | Approved approximate area |
| `location_id`, `location_name`, `location_type` | Parent venue/campus |
| `title` | Activity/event title; `null` for presence |
| `category` | Activity category; `null` for presence and current official events |
| `starts_at`, `ends_at` | Activity/event or aggregate availability window |
| `status` | Source status (`open`, `approved`, or `active`) |
| `participant_count` | Accepted activity participants or going RSVPs |
| `participant_limit` | Activity limit, otherwise `null` |
| `available_people` | Anonymous count for a presence row, otherwise `null` |
| `latitude`, `longitude` | Approved public venue coordinates |
| `is_creator` | `true` only when the authenticated viewer created the activity |

The result never contains `user_id`, `creator_id`, email addresses, or exact
user coordinates. `is_creator` is a viewer-relative boolean and does not
identify anyone else. Availability stores only `area_id`; it is deliberately
not published as a raw Realtime table.

## Filters

- `p_area_ids`: pass a UUID array to show only selected areas; use `null` for
  all areas.
- `p_location_id`: pass a location UUID to show only that campus/venue; use
  `null` for all locations.
- `p_include_presence`: set to `false` when the UI only needs activities and
  official events.

Filters can be combined. An empty array intentionally returns no points.

## Realtime refresh channels

The migration `20260930081931_map_realtime_updates.sql` adds activities,
activity participants, official events and event RSVPs to the
`supabase_realtime` publication. Subscribe to changes, then refetch the RPC
to rebuild the complete map response:

```js
const channel = supabase
  .channel(`map-${locationId ?? 'all'}`)
  .on('postgres_changes', {
    event: '*', schema: 'public', table: 'activities',
  }, refreshMap)
  .on('postgres_changes', {
    event: '*', schema: 'public', table: 'activity_participants',
  }, refreshMap)
  .on('postgres_changes', {
    event: '*', schema: 'public', table: 'official_events',
  }, refreshMap)
  .on('postgres_changes', {
    event: '*', schema: 'public', table: 'event_rsvps',
  }, refreshMap)
  .subscribe()

async function refreshMap() {
  // Call active_map_points again with the current filters.
}
```

Realtime is a refresh signal, not a second map API. The RPC must always be
called after a change so that organisation scoping, block filtering, expiry,
and anonymous presence aggregation are applied consistently.

The frontend subscribes to all four tables through
`src/services/events.js`. Any change triggers a fresh `active_map_points()`
request, so the map never trusts an unfiltered raw table payload. User-created
meetups are written through `create-activity`; organisation events use
`create-official-event`, and official RSVPs use `rsvp-to-event`.

## Permission model

- Anonymous users cannot execute `active_map_points` or read the private map
  source tables.
- Pending/unverified users receive no map rows.
- Verified users see only their organisation's active activities/events and
  aggregate availability, with blocked users removed.
- `official_events` and RSVP rows remain protected by their existing RLS
  policies. Realtime subscribers receive only rows they could select.

Run the local verification suite with:

```bash
npx supabase db reset
npx supabase test db
```
