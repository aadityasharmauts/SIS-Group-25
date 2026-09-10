# API Response Format

Phase 0 deliverable: "Define API response format" -> this document.

Recess has two ways the frontend talks to the backend (PRD section 10):

1. **Direct Supabase client queries** (`supabase.from(...).select()` etc.)
   for anything RLS can safely protect on its own -- reading organisations,
   locations, areas, profiles, activities, events, etc.
2. **Supabase Edge Functions** for sensitive actions that need logic beyond
   RLS: matching, event approval, connection requests, block/report, and
   anything listed under "Suggested API and Function Contracts" in
   Backend Docs v0.1.

This document defines the response shape for (2). Direct client queries
(1) follow whatever shape `supabase-js` already returns
(`{ data, error }`) -- no extra wrapping needed there.

## Success response

```json
{
  "data": { "...": "..." },
  "error": null
}
```

- `data` is always present on success, `null` on failure.
- HTTP status: `200` for a normal success, `201` for a resource created
  (e.g. `create-activity`).

## Error response

```json
{
  "data": null,
  "error": {
    "code": "invalid_domain",
    "message": "person@gmail.com is not an approved institutional email."
  }
}
```

- `error.code` is a stable, machine-readable `snake_case` string the
  frontend can switch on. `error.message` is a human-readable string safe
  to show directly to the user (never leak internal details like SQL
  errors or stack traces here).
- HTTP status follows the error's nature:
  - `400` -- validation error (bad input shape, invalid domain, etc.)
  - `401` -- not authenticated
  - `403` -- authenticated but not authorised (unverified account, blocked, not a participant, etc.)
  - `404` -- referenced resource doesn't exist (or isn't visible under RLS)
  - `409` -- conflict (duplicate request, already connected, activity full)
  - `429` -- rate limited (messages, requests, activity creation)
  - `500` -- unexpected server error

## Error code reference (grows per phase)

| Code | Meaning |
|---|---|
| `invalid_domain` | Email domain isn't in `organisation_domains` |
| `consent_required` | Terms and Privacy Policy consent was not provided |
| `not_verified` | Account exists but email isn't verified yet |
| `unsupported_account_type` | The domain resolves to an organisation type that cannot join the MVP |
| `forbidden` | A protected account/profile field cannot be changed by the client |
| `blocked` | Action blocked due to a block relationship |
| `already_connected` | Connection request rejected -- already connected |
| `request_pending` | Duplicate connection/join request |
| `activity_full` | Activity already at its participant limit |
| `invalid_area` | `area_id` does not belong to the given `location_id` (official events) |
| `expired` | The activity/event/availability referenced has expired |
| `rate_limited` | Too many requests/messages in the current window |
| `invalid_time_window` | Activity start/end time is invalid (in the past, end before start, or over the 4-hour max) |
| `activity_cancelled` | The activity has been cancelled and can no longer be joined or edited |
| `invalid_transition` | The requested participant status change isn't allowed (e.g. a declined request trying to become pending/accepted again) |

Add new codes here as each phase's Edge Functions are implemented --
this table is the shared contract frontend can rely on across phases.

## Naming

Edge Function routes are `kebab-case` verbs, matching Backend Docs v0.1,
e.g. `POST /functions/v1/create-activity`,
`POST /functions/v1/respond-to-connection-request`.
