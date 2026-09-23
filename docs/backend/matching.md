# Matching Rules and Functions

Phase 4 backend tasks: "Define matching rules", "Create matching
query/function", "Add time-overlap calculation", "Add area compatibility",
"Add shared-interest calculation", "Exclude blocked users".

Not covered here (separate Phase 4 tasks): excluding existing connections,
the suggestions endpoint (`POST /functions/v1/refresh-suggestions`,
up-to-three limit), connection requests and their RLS, performance tests.
Hooks for those are marked below.

Migrations:

- `20260923134644_create_blocks.sql` -- `blocks` table, `is_blocked_between()`
- `20260923134645_matching_compatibility.sql` -- `area_compatibility()`, `availability_overlap_minutes()`
- `20260923134646_matching_candidates.sql` -- `shared_interest_ids/count()`, `matching_candidates()`

Tests: `supabase/tests/008_matching.sql` (30 checks, end-to-end with real
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
| 7 | They are not already connected | **Hook only** (see `matching_candidates()` comment). Added by the connections task. |

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

All are `security definer`, `stable`, callable by `authenticated`; `anon`
has no access.

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

From a client the function only answers for the caller: passing another
user's id returns no rows. It never returns email, exact location,
availability rows or anything not already readable under the `profiles`
RLS.

```js
const { data: candidates } = await supabase.rpc('matching_candidates')
// -> [{ candidate_id, display_name, overlap_minutes, shared_interest_ids, score, ... }, ...]
```

The suggestions endpoint owner should wrap this with `limit 3` (and any
persistence / cooldown logic) rather than have the client call it directly
in production, per Backend Docs v0.1 ("matching ... should be handled by
Edge Functions"). The RPC is exposed to `authenticated` so the frontend can
prototype against it now.

## 3. Blocks (scaffold for Phase 5)

`public.blocks (blocker_id, blocked_id)` -- one row per direction, unique
pair, no self-block. Created here because rule 6 needs it. RLS:

- A user reads, creates and deletes only rows where they are `blocker_id`.
- There is deliberately **no** policy exposing rows by `blocked_id`: a
  blocked user must never learn they were blocked.

Phase 5 ("Implement block user", `POST /functions/v1/block-user`) builds the
workflow on top: applying `is_blocked_between()` to map, activities and
chat visibility, and the report flow. The table should not need to change.

```js
// Block (Phase 5 will move this behind an Edge Function)
await supabase.from('blocks').insert({ blocker_id: user.id, blocked_id: otherId })
// Unblock
await supabase.from('blocks').delete().eq('blocked_id', otherId)
```

## 4. Hooks left for the other Phase 4 tasks

- **Exclude existing connections** -- add the `not exists (... connections ...)`
  predicate at the marked line in `matching_candidates()` once the
  `connections` table exists. Consider also excluding pairs with a pending
  `connection_requests` row.
- **Suggestions endpoint** -- `select * from matching_candidates(uid) limit 3`
  inside `refresh-suggestions`, returning the shared `{ data, error }`
  envelope.
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
3. Optional: as a real user in the app, `supabase.rpc('matching_candidates')`
   should return only people you actually overlap with.
