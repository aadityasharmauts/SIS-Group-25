# Blocking, Reporting and Moderation

Phase 5 safety features. As elsewhere, the rules live in the database
(constraints, triggers and RLS) and the frontend talks to the tables
directly through `supabase-js`.

Migrations: `20260927100000_create_blocks.sql`,
`20261013090000_activity_block_rules.sql`, `20261013090500_create_reports.sql`.
Tests: `009_blocks.sql`, `014_activity_blocks.sql`, `015_reports.sql`.

## Blocking

```js
// block
await supabase.from('blocks').insert({ blocker_id: me.id, blocked_id: otherUserId })

// my block list
await supabase.from('blocks').select('id, blocked_id, created_at')

// unblock
await supabase.from('blocks').delete().eq('id', blockId)
```

A block in either direction hides the two users from each other. The
blocked user is never told -- they get the same responses as anyone who
simply can't see something.

| Area | Effect of a block |
|---|---|
| Map (`active_map_points`) | The other user's activities and presence disappear; participant counts exclude them |
| Activities | You can't see an activity hosted by someone on the other side of a block (your own activities stay visible) |
| Joining | Requesting to join raises `[forbidden]`; the creator can't accept a blocked user's request |
| Existing participants | The creator can remove a blocked participant: `accepted -> declined` (only allowed when there's a block) |
| Private chat | Hidden from both sides; sending raises `[forbidden]` |
| Activity chat | Each side's messages are hidden from the other |
| Connections | Unchanged -- unblocking restores everything as it was |

Removing a blocked participant:

```js
await supabase
  .from('activity_participants')
  .update({ status: 'declined' })
  .eq('id', participantRowId)
```

## Reporting

```js
await supabase.from('reports').insert({
  reported_user_id: otherUserId,
  reason: 'harassment',   // see list below
  details: 'optional, up to 1000 characters',
  message_id: messageId,  // optional -- the message being reported
  activity_id: activityId // optional -- the activity it happened in
})
```

Reasons: `harassment`, `spam`, `inappropriate_content`, `unsafe_behaviour`,
`impersonation`, `other` (`other` requires `details`).

Rules:

- Only verified users can report, and only users in their own organisation.
- `message_id` must be a message the reported user sent, in a chat the
  reporter is part of. This still works after blocking -- block then report
  is the expected order.
- `activity_id` must be an activity both users were involved in (creator
  or any join request).
- One open report per reporter / reported user / message. A second one
  is a unique violation (`23505`) -- show "you've already reported this".
- 5 reports an hour per user -- `[rate_limited]`.
- Clients can't set `status` or `resolved_at`; every new report starts `open`.
- Reports can't be edited or deleted once filed.

Who can see a report:

| Who | Sees |
|---|---|
| Reporter | Their own reports, including the current `status` |
| Reported user | Nothing -- no policy matches on `reported_user_id` |
| Anyone else | Nothing |
| `service_role` (moderators) | Everything |

The frontend should pair the report form with an offer to block, and
show public-meetup safety guidance alongside it.

## Rate limits (Phase 5 summary)

| What | Limit | Where |
|---|---|---|
| Messages | 20 a minute | `guard_message_write()` |
| Activity join requests | 10 an hour | `guard_activity_participant_write()` |
| Reports | 5 an hour | `guard_report_write()` |
| Activity creation | 3 open at once | `guard_activity_write()` (Phase 3) |

Connection-request limits are part of the Phase 4 connections work.

## Moderation workflow

There's no admin UI in the MVP. Moderators are team members with access to
the Supabase dashboard, working in the SQL editor (which runs as a trusted
role, so RLS doesn't apply).

### 1. Triage -- daily during the pilot

```sql
select r.id, r.created_at, r.reason, r.details,
       reporter.display_name as reporter,
       reported.display_name as reported,
       r.message_id, r.activity_id
from public.reports r
join public.profiles reporter on reporter.id = r.reporter_id
left join public.profiles reported on reported.id = r.reported_user_id
where r.status = 'open'
order by r.created_at;
```

Mark the one you're working on so others skip it:

```sql
update public.reports set status = 'reviewing' where id = '<report id>';
```

Anything describing an immediate threat to someone's safety goes
straight to campus security / emergency services (000) -- don't wait for
the queue.

### 2. Gather context

The reported message, including the original text if it was deleted:

```sql
select m.created_at, m.body, d.original_body
from public.messages m
left join public.message_deleted_bodies d on d.message_id = m.id
where m.id = '<message id>';
```

The surrounding conversation (last 50 messages):

```sql
select m.created_at, p.display_name, coalesce(d.original_body, m.body) as text
from public.messages m
join public.profiles p on p.id = m.sender_id
left join public.message_deleted_bodies d on d.message_id = m.id
where m.conversation_id = (select conversation_id from public.messages where id = '<message id>')
order by m.created_at desc
limit 50;
```

Every report about this user, to spot a pattern:

```sql
select created_at, reason, status, details
from public.reports
where reported_user_id = '<user id>'
order by created_at desc;
```

Only look at the chats a report points to.

### 3. Decide and act

| Outcome | Action |
|---|---|
| No breach | `status = 'dismissed'` |
| Minor / first breach | Warn the user by email from the team address, then `status = 'actioned'` |
| Serious or repeated | Suspend the account, then `status = 'actioned'` |

```sql
-- close a report (resolved_at is filled in automatically)
update public.reports set status = 'actioned' where id = '<report id>';

-- suspend: is_verified_user() becomes false, so RLS cuts off every table,
-- the map and chat at once
update public.profiles set account_status = 'suspended' where id = '<user id>';

-- reinstate
update public.profiles set account_status = 'verified' where id = '<user id>';
```

Suspending doesn't cancel the user's open activities -- cancel them too:

```sql
update public.activities set status = 'cancelled'
where creator_id = '<user id>' and status = 'open' and end_time > now();
```

### 4. Privacy

- Never tell the reported user who reported them.
- The reporter can see the status change (`actioned` / `dismissed`) but
  nothing else -- don't share what action was taken.
- Notes about a decision go in the team's private channel, not in the
  database.

## Error codes

| Prefix | Meaning |
|---|---|
| `[forbidden]` | Not allowed -- also what a blocked user sees, so the block stays hidden |
| `[not_verified]` | Only verified users can report |
| `[rate_limited]` | Too many reports or join requests -- try again later |

These extend the shared table in `docs/backend/api-contract.md`.
