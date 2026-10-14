# User-Created Activities

Phase 3 backend task: small, spontaneous meetups that any verified user can
create and others can join (PRD 8.5, 8.10).

Same architecture as Phases 1-2: every rule is enforced by the database
(constraints, triggers, RLS), not an Edge Function. The frontend talks to
`public.activities` and `public.activity_participants` directly through
`supabase-js`.

## Tables

**`public.activities`**

- `creator_id` -- the verified user who created it.
- `area_id` -- always an approved `public.areas` row. The activity may also
  store a public venue label and marker coordinates; these are never a user's
  live position or a private address.
- `location_label`, `latitude`, `longitude` -- optional public meeting-point
  details used by the event map. Coordinates are range-checked and must be
  supplied as a pair. The approved `area_id` remains mandatory for privacy.
- `title`, `description`, `category`.
- `tags` -- optional audience labels, limited to six values.
- `start_time` / `end_time` -- must fit in a 4-hour window.
- `participant_limit` -- 1 to 5, default 3. This is the number of *other*
  people who can join; it does not count the creator.
- Public marker coordinates must be within 250 metres of the selected area's
  approved location. The marker is a meeting point, not a user's position.
- `status` -- only `open` or `cancelled` is stored. "Full" and "expired" are
  derived (from `activity_accepted_count()` and `end_time`), not columns,
  so nothing needs a scheduler to keep them in sync.

**`public.activity_participants`**

- One row per (activity, user). `status` is `pending`, `accepted`,
  `declined` or `left`.
- The creator gets an auto-inserted `accepted`, `is_creator = true` row the
  moment the activity is created, so "who is in this activity" is always a
  single `status = 'accepted'` query -- this is what Phase 5's activity
  group chat will read from.

## Creating an activity

```js
const { data, error } = await supabase
  .from('activities')
  .insert({
    area_id: selectedArea.id,
    title,
    description,
    category,
    tags: ['first years', 'exam prep'],
    start_time: startTime.toISOString(),
    end_time: endTime.toISOString(),
    participant_limit: 3,
    location_label: 'UTS Building 11, Lab 302',
    latitude: -33.8832,
    longitude: 151.2006,
  })
  .select()
  .single()
```

`creator_id` is never sent by the client -- the insert policy requires it to
equal `auth.uid()`, so leave it out and let the default RLS check catch any
attempt to spoof it. The database rejects the insert with:

- `[invalid_time_window]` if the times are in the past, end before start, or
  span more than 4 hours;
- `[rate_limited]` if the creator already has 3 open (unexpired,
  uncancelled) activities;
- the usual Postgres constraint errors for a too-short/long title or an
  out-of-range `participant_limit`.

## Editing and cancelling

Creators can edit their own activity's fields at any time it's still open
and unexpired -- including after people have already been accepted.
Accepted participants find out through the Realtime subscription on the
row (see below), not a separate notification.

```js
await supabase.from('activities').update({ start_time: newStartTime }).eq('id', activityId)

// Cancelling is a status change, not a delete:
await supabase.from('activities').update({ status: 'cancelled' }).eq('id', activityId)
```

Rejected with:

- `[forbidden]` -- trying to change `id`, `creator_id` or `created_at`.
- `[activity_cancelled]` -- the activity is already cancelled.
- `[expired]` -- the activity's `end_time` has already passed.
- `[activity_full]` -- lowering `participant_limit` below the number of
  already-accepted participants.
- `[invalid_time_window]` -- the new `end_time` is not after `start_time`.

There is no delete policy on either table. Cancelling/leaving/declining are
status changes so history stays available for moderation and reports
(Phase 5).

## Joining, accepting, declining, leaving

Requesting to join creates a `pending` row:

```js
await supabase.from('activity_participants').insert({ activity_id: activityId, user_id: me.id })
```

`user_id` must equal `auth.uid()`. Requests are limited to 10 an hour per
user (`[rate_limited]`), and you can't request to join an activity whose
creator is on the other side of a block (`[forbidden]`). Rejected with `[activity_cancelled]` /
`[expired]` / `[activity_full]` as appropriate, or `[forbidden]` if the
creator tries to request to join their own activity, or a duplicate-key
error if they've already requested (the unique constraint on
`(activity_id, user_id)` also blocks re-requesting after a decline -- a
declined row already occupies that slot).

The creator responds by updating the participant's row:

```js
await supabase
  .from('activity_participants')
  .update({ status: 'accepted' }) // or 'declined'
  .eq('id', participantRowId)
```

Allowed transitions: `pending -> accepted`, `pending -> declined`, and
`declined -> accepted` if the creator changes their mind -- but never the
reverse; a declined participant cannot make themselves
`pending` or `accepted` again. A participant can only ever set their own
row to `left`. Anything else raises `[invalid_transition]`. The creator's
own auto-inserted row can never change status at all -- cancel the
activity instead. If there's a block between the creator and a
participant, the creator can also remove them (`accepted -> declined`),
and can't accept their request.

`activity_accepted_count(activity_id)` (a `security definer` SQL function)
is what `participant_limit` is checked against, and is safe to call from the
frontend too if you need the current headcount without a full row fetch.

## Visibility

A verified user sees an activity if it's open and unexpired, or if they're
the creator, or if they're an accepted participant -- so a creator or
accepted participant keeps seeing their own activity even after it expires
or fills up. Unverified users see nothing. A block between the viewer and
the creator hides the activity from the viewer (the creator always sees
their own) -- see `docs/backend/moderation.md`. This is enforced by the
`activities` and `activity_participants` SELECT policies directly; there is
also a `can_view_activity(activity_id)` helper function with the same logic
for use in application code, but it's deliberately not what the policy
itself calls -- see the comment on that policy in
`20260910010500_create_activity_participants.sql`.

## Realtime

```js
const channel = supabase
  .channel(`activity-${activityId}`)
  .on(
    'postgres_changes',
    { event: '*', schema: 'public', table: 'activities', filter: `id=eq.${activityId}` },
    handleActivityChange,
  )
  .on(
    'postgres_changes',
    { event: '*', schema: 'public', table: 'activity_participants', filter: `activity_id=eq.${activityId}` },
    handleParticipantChange,
  )
  .subscribe()
```

The frontend uses the `create-activity` Edge Function for this write. The
function forwards the request through the caller's Supabase JWT, so the same
RLS, trigger and rate-limit rules apply. A direct `supabase-js` insert is kept
as a local-development fallback when the Edge Function runtime is not running.

RLS still applies to Realtime -- a subscriber only receives change events for
rows they could `select` anyway.

## Error code reference

| Prefix | User-facing meaning |
|---|---|
| `[invalid_time_window]` | Fix the start/end time (past, backwards, or over 4 hours). |
| `[rate_limited]` | You already have 3 open activities, or you've sent 10 join requests in the last hour. |
| `[activity_full]` | This activity is already at its participant limit. |
| `[activity_cancelled]` | This activity has been cancelled. |
| `[expired]` | This activity has already ended. |
| `[forbidden]` | That field or action isn't allowed here. |
| `[invalid_transition]` | That status change isn't allowed. |

These extend the shared table in `docs/backend/api-contract.md`.

## Local verification checklist

Before opening a pull request:

1. Apply migrations with `npx supabase db reset` while Docker is running.
2. Confirm a too-long (>4h) or backwards time window is rejected.
3. Confirm a 4th open activity from the same creator is rate-limited.
4. Confirm the creator cannot request to join their own activity.
5. Confirm capacity, cancellation and expiry are all enforced on join
   requests and on edits.
6. Confirm a declined participant cannot re-request, but the creator can
   still accept that same row later.
7. Confirm an unverified user cannot create, see, or join an activity.
8. Run `npx supabase test db`.
