# Chat

Private chat between connected users, and group chat for each activity
(PRD Phase 5). Like the rest of the backend, the rules live in the
database -- constraints, triggers and RLS -- and the frontend talks to the
tables directly through `supabase-js`.

## Tables

**`conversations`** -- one per connected pair (`kind = 'private'`, with
`user_a` < `user_b`) and one per activity (`kind = 'activity'`). The
frontend never creates these:

- a private conversation opens the first time a connection is accepted,
  and is reused if the pair disconnects and reconnects, so history carries
  over;
- an activity conversation opens when the activity is created.

**`messages`** -- `conversation_id`, `sender_id`, `body`, `created_at`,
`deleted_at`. Body is 1-2000 characters.

**`message_deleted_bodies`** -- the original text of deleted messages, for
moderation. `service_role` only; clients can't read it at all.

## Rules

| Situation | Read | Send |
|---|---|---|
| Connected pair | yes | yes |
| Pair has disconnected | yes (old messages) | no -- `[not_connected]` |
| Either side has blocked the other | no, hidden from both | no -- `[forbidden]` |
| Unblocked again | yes, everything comes back | yes, if still connected |
| Accepted activity participant (incl. creator) | yes | yes |
| Pending / declined / left participant | no | no -- `[forbidden]` |
| Activity has ended | yes, members only | no -- `[expired]` |
| Activity cancelled | yes, members only | no -- `[activity_cancelled]` |

A blocked user gets the same `[forbidden]` as a non-member, so they can't
tell they've been blocked. Inside a shared activity chat, a blocked
person's messages are hidden from the blocker and vice versa.

Sending is limited to **20 messages a minute** per user -- `[rate_limited]`.

## Using it from the frontend

List my conversations:

```js
const { data } = await supabase
  .from('conversations')
  .select('id, kind, user_a, user_b, activity_id')
```

RLS only returns the ones you're a member of.

Load and send messages:

```js
const { data: messages } = await supabase
  .from('messages')
  .select('id, sender_id, body, created_at, deleted_at')
  .eq('conversation_id', conversationId)
  .order('created_at')

await supabase
  .from('messages')
  .insert({ conversation_id: conversationId, body })
  .select()
  .single()
```

Don't send `sender_id` -- it defaults to the signed-in user, and anything
else is rejected.

Delete your own message (this is the only update allowed; editing is
rejected):

```js
await supabase
  .from('messages')
  .update({ deleted_at: new Date().toISOString() })
  .eq('id', messageId)
```

The row stays, with `body` set to `''` and `deleted_at` filled in. Show it
as "message deleted".

## Realtime

```js
supabase
  .channel(`conversation-${conversationId}`)
  .on(
    'postgres_changes',
    { event: '*', schema: 'public', table: 'messages', filter: `conversation_id=eq.${conversationId}` },
    handleMessage,
  )
  .subscribe()
```

`INSERT` is a new message, `UPDATE` is a deletion. RLS applies, so a
subscriber only receives what they could read anyway. Subscribing to
`conversations` tells you when a new chat opens (a connection accepted, an
activity created).

## Error codes

| Prefix | Meaning |
|---|---|
| `[not_connected]` | You're no longer connected with this person. |
| `[forbidden]` | Not a member of this conversation, or trying to edit/re-delete a message. |
| `[expired]` | The activity has ended; its chat is read-only. |
| `[activity_cancelled]` | The activity was cancelled. |
| `[rate_limited]` | Sending too fast -- wait a moment. |

## Local verification

1. `npx supabase db reset` (Docker running).
2. `npx supabase test db` -- `010_chat.sql` covers everything in the table
   above.
