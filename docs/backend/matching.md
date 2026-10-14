# Matching Rules and Functions

Phase 4 backend tasks: "Define matching rules", "Create matching
query/function", "Add time-overlap calculation", "Add area compatibility",
"Add shared-interest calculation", "Exclude blocked users".

This implementation also excludes pending, accepted and declined connection
history, exposes a top-three suggestions RPC, and provides the
`POST /functions/v1/refresh-suggestions` Edge Function. Connection requests
and their RLS remain in the existing connections migration.

Migrations:

- `20260927100000_create_blocks.sql` -- `blocks` table, `is_blocked_between()`
- `20261014090000_matching_compatibility.sql` -- `area_compatibility()`, `availability_overlap_minutes()`
- `20261014090500_matching_candidates.sql` -- shared interests, `matching_candidates()`, `matching_suggestions()`

Tests: `supabase/tests/008_matching.sql` (43 checks, end-to-end with real
test users).

## 1. Matching specification

User **B** is a candidate for user **A** when **all** of the following hold.

| # | Rule (Backend Docs v0.1) | Precise definition |
|---|---|---|
| 1 | Both users are verified | `profiles.account_status = 'verified'` and `profiles.email_verified_at is not null` for both |
| 2 | They belong to an approved community | B's `profiles.organisation_id` points at an `organisations` row of type `university` or `company`. Same organisation is **not** required (a UTS student and a nearby professional can match at a shared public venue); it is a score bonus. |
| 3 | Their availability overlaps | At least one pair of unexpired `availabilities` rows (A's, B's) whose time windows intersect **from now onwards** ... |
| 4 | Their approximate areas are compatible | ... **and** whose `area_id`s are compatible: identical area (level 2) or different areas in the same `location` (level 1). Different locations are level 0 and never match. Time and area are evaluated on the same availability pair, so "free at the same time but on different campuses" is not a match. |
| 5 | They have at least one shared interest | `profile_interests` intersection is non-empty |
| 6 | There is no block relationship | No `blocks` row in either direction |
| 7 | They are not already connected | No pending, accepted or declined connection history exists between the pair. |

Additional invariants:

- A is never a candidate for themselves.
- Expired availability (`end_time <= now()`) never counts, matching the
  Phase 2 rule "expired availability must not appear in matching".
- Only approximate `area_id`s are used. No coordinates are read or exposed.

### Scoring (deterministic)

Candidates that pass all rules are ranked by:

```
score = floor(overlap_minutes / 30)          -- 1 point per 30 min together
      + shared_interest_count * 3            -- 3 points per shared interest
      + (best_area_level = 2 ? 4 : 0)        -- exact same area bonus
      + (same_organisation ? 1 : 0)          -- same community bonus
```

Order: `score desc, overlap_minutes desc, shared_interest_count desc,
candidate_id asc`. No randomness; the same data always produces the same
list. The suggestions endpoint takes the top three.

Rationale for the weights: two people who are actually in the same library
at the same time (level 2) should beat two people merely on the same campus,
and one shared interest (3) should roughly equal 90 minutes of overlap, so
neither dimension dominates. Weights are constants in
`matching_candidates()` and can be tuned without schema changes.

## 2. Functions

The database helpers are `security definer` and `stable`. Verified
authenticated users can call the compatibility and shared-interest helpers;
`matching_candidates()` is service-role-only, and clients use the top-three
`matching_suggestions()` wrapper or the Edge Function. `anon` has no access.

### `area_compatibility(area_a uuid, area_b uuid) → smallint`

`2` same area, `1` same location, `0` otherwise (including nulls). Pure
reference-data lookup; safe to call with any ids.

### `availability_overlap_minutes(user_a uuid, user_b uuid) → integer`

Sum, over all pairs of unexpired availabilities with
`area_compatibility > 0`, of the minutes the two windows intersect, clamped
to start no earlier than `now()`. Returns `0` if none.

Privacy guard: from a client, one of the two ids must be `auth.uid()`;
otherwise the function returns `0`. Server-side callers (Edge Functions with
the service role, triggers) may query any pair.

### `shared_interest_ids(user_a, user_b) → uuid[]` and `shared_interest_count(user_a, user_b) → integer`

Sorted interest ids both users selected / their count. Same privacy guard
(returns `{}` / `0` for pairs not involving the caller).

### `is_blocked_between(user_a, user_b) → boolean`

True if either user has blocked the other. Defined in `create_blocks.sql`.

### `matching_candidates(p_user_id uuid default auth.uid()) → table`

The matching query. Returns every candidate that passes rules 1-6, ranked.

| Column | Meaning |
|---|---|
| `candidate_id` | `profiles.id` of the candidate |
| `display_name` | for the card |
| `organisation_id`, `same_organisation` | community info |
| `overlap_minutes` | total compatible overlap from now |
| `best_area_level` | 2 if you'll be in the exact same area at an overlapping time, else 1 |
| `shared_interest_count`, `shared_interest_ids` | for "You both like ..." |
| `score` | see above |

This internal query is callable only by `service_role`; it never returns
email, exact location or availability rows.

### `matching_suggestions(p_user_id uuid default auth.uid()) → table`

Returns the first three rows from `matching_candidates()`. Client calls remain
restricted to the caller, and the Edge Function is the frontend-facing route:

```js
const { data } = await supabase.functions.invoke('refresh-suggestions', {
  body: {},
})
```

The wrapper only returns suggestions for the authenticated caller and caps
the result at three. The Edge Function checks authentication and verified
organisation email and returns the shared `{ data, error }` response shape.

## 3. Blocks (scaffold for Phase 5)

`public.blocks (blocker_id, blocked_id)` -- one row per direction, unique
pair, no self-block. Created here because rule 6 needs it. RLS:

- A user reads, creates and deletes only rows where they are `blocker_id`.
- There is deliberately **no** policy exposing rows by `blocked_id`: a
  blocked user must never learn they were blocked.

Phase 5 applies `is_blocked_between()` to map, activities and chat visibility,
and adds the report flow. The table does not need to change.

```js
// Block (Phase 5 will move this behind an Edge Function)
await supabase.from('blocks').insert({ blocker_id: user.id, blocked_id: otherId })
// Unblock
await supabase.from('blocks').delete().eq('blocked_id', otherId)
```

## 4. Hooks left for the other Phase 4 tasks

- **Performance** -- the query is set-based over indexed columns
  (`availabilities (area_id, end_time)`, `profile_interests (interest_id,
  profile_id)` added here, `blocks (blocker_id)` / `(blocked_id)`). With a
  campus-sized user base this is well under 100 ms; measure with
  `explain analyze select * from matching_candidates('<uuid>')` on
  `recess-dev` once there is real data.

## 5. Error codes

No new codes. Blocking uses the existing `blocked` code in
`docs/backend/api-contract.md`; a duplicate block hits the
`blocks_unique` constraint (`23505`), a self-block hits `blocks_not_self`
(`23514`).

## 6. Local verification checklist

1. `npx supabase db reset` (Docker running).
2. `npx supabase test db` -- `008_matching.sql` builds an 8-user fixture and
   asserts: area levels 2/1/0, overlap 120/60/0 minutes, shared-interest
   counts, block symmetry, the exact ranked result `[bob, hank]` with scores
   `15` and `6`, exclusion of no-overlap / no-interest / blocked /
   wrong-location / unverified users, determinism, the self-only privacy
   guards under an `authenticated` JWT, and blocks RLS.
3. `008_matching.sql` also verifies the deterministic top three, pending /
   accepted / declined connection exclusions, cancelled-request re-eligibility,
   verified-user privacy guards, and RPC privileges.
