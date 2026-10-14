-- chat tests (private + activity). run with: npx supabase test db

begin;
select plan(36);

create or replace function pg_temp.create_test_user(
  p_email text,
  p_display_name text
) returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
    p_email, crypt('Test-Password1', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
      'display_name', p_display_name,
      'terms_accepted', true,
      'privacy_accepted', true
    ),
    now(), now(), '', ''
  );
  return v_id;
end;
$$;

select pg_temp.create_test_user('chat.alice@student.uts.edu.au', 'Alice') as alice_id \gset
select pg_temp.create_test_user('chat.bob@student.uts.edu.au', 'Bob') as bob_id \gset
select pg_temp.create_test_user('chat.carol@student.uts.edu.au', 'Carol') as carol_id \gset
select pg_temp.create_test_user('chat.erin@student.uts.edu.au', 'Erin') as erin_id \gset

\set library_area '00000000-0000-0000-0000-000000000201'

-- 1-3. tables exist

select has_table('public', 'conversations', 'conversations table exists');
select has_table('public', 'messages', 'messages table exists');
select has_table('public', 'message_deleted_bodies', 'message_deleted_bodies table exists');

-- 4-5. accepting a connection opens a private chat

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);
insert into public.connections (requester_id, addressee_id)
values (:'alice_id'::uuid, :'bob_id'::uuid)
returning id as conn_id \gset

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);
update public.connections set status = 'accepted' where id = :'conn_id'::uuid;

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::int from public.conversations
    where kind = 'private'
      and user_a = least(:'alice_id'::uuid, :'bob_id'::uuid)
      and user_b = greatest(:'alice_id'::uuid, :'bob_id'::uuid)),
  1,
  'accepting a connection opens one private conversation'
);

select id as private_conv from public.conversations
where kind = 'private'
  and user_a = least(:'alice_id'::uuid, :'bob_id'::uuid)
  and user_b = greatest(:'alice_id'::uuid, :'bob_id'::uuid) \gset

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ insert into public.conversations (kind, user_a, user_b)
     values ('private', least('$$ || :'alice_id' || $$'::uuid, '$$ || :'carol_id' || $$'::uuid),
                        greatest('$$ || :'alice_id' || $$'::uuid, '$$ || :'carol_id' || $$'::uuid)) $$,
  '42501',
  null,
  'clients cannot create conversations themselves'
);

-- 6-11. sending and reading

insert into public.messages (conversation_id, body)
values (:'private_conv'::uuid, 'hey bob')
returning id as alice_msg \gset

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

select is(
  (select count(*)::int from public.messages where conversation_id = :'private_conv'::uuid),
  1,
  'the other person can read the message'
);

select throws_ok(
  $$ insert into public.messages (conversation_id, sender_id, body)
     values ('$$ || :'private_conv' || $$', '$$ || :'alice_id' || $$', 'fake') $$,
  '42501',
  null,
  'nobody can send a message as someone else'
);

select throws_ok(
  $$ insert into public.messages (conversation_id, body)
     values ('$$ || :'private_conv' || $$', '   ') $$,
  '23514',
  null,
  'an empty message is rejected'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'carol_id', true);

select is(
  (select count(*)::int from public.conversations),
  0,
  'an outsider sees none of other people''s conversations'
);

select is(
  (select count(*)::int from public.messages where conversation_id = :'private_conv'::uuid),
  0,
  'an outsider cannot read other people''s messages'
);

select throws_ok(
  $$ insert into public.messages (conversation_id, body)
     values ('$$ || :'private_conv' || $$', 'let me in') $$,
  'P0001',
  '[forbidden] You can''t send messages in this conversation.',
  'an outsider cannot post into someone else''s conversation'
);

-- 12-15. removing and reconnecting

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);
update public.connections set status = 'removed' where id = :'conn_id'::uuid;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select throws_ok(
  $$ insert into public.messages (conversation_id, body)
     values ('$$ || :'private_conv' || $$', 'still there?') $$,
  'P0001',
  '[not_connected] You''re no longer connected with this person.',
  'after a removal, nothing new can be sent'
);

select is(
  (select count(*)::int from public.messages where conversation_id = :'private_conv'::uuid),
  1,
  'after a removal, old messages stay readable'
);

update public.connections set status = 'pending' where id = :'conn_id'::uuid;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);
update public.connections set status = 'accepted' where id = :'conn_id'::uuid;

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::int from public.conversations
    where kind = 'private'
      and user_a = least(:'alice_id'::uuid, :'bob_id'::uuid)
      and user_b = greatest(:'alice_id'::uuid, :'bob_id'::uuid)),
  1,
  'reconnecting reuses the same conversation, so the history carries over'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);
insert into public.messages (conversation_id, body)
values (:'private_conv'::uuid, 'good to be back');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

select is(
  (select count(*)::int from public.messages where conversation_id = :'private_conv'::uuid),
  2,
  'sending works again after reconnecting'
);

-- 16-19. blocking and unblocking

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);
insert into public.blocks (blocker_id, blocked_id) values (:'alice_id'::uuid, :'bob_id'::uuid);

select is(
  (select count(*)::int from public.messages where conversation_id = :'private_conv'::uuid),
  0,
  'the blocker no longer sees the conversation'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

select is(
  (select count(*)::int from public.messages where conversation_id = :'private_conv'::uuid),
  0,
  'the blocked person does not see it either'
);

select throws_ok(
  $$ insert into public.messages (conversation_id, body)
     values ('$$ || :'private_conv' || $$', 'why can''t I see anything') $$,
  'P0001',
  '[forbidden] You can''t send messages in this conversation.',
  'a blocked person cannot send, and the error does not reveal the block'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);
delete from public.blocks where blocker_id = :'alice_id'::uuid and blocked_id = :'bob_id'::uuid;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'bob_id', true);

select is(
  (select count(*)::int from public.messages where conversation_id = :'private_conv'::uuid),
  2,
  'unblocking brings the whole conversation back'
);

-- 20-26. deleting messages

insert into public.messages (conversation_id, body)
values (:'private_conv'::uuid, 'keep this one')
returning id as bob_keep \gset

insert into public.messages (conversation_id, body)
values (:'private_conv'::uuid, 'oops wrong chat')
returning id as bob_msg \gset

update public.messages set deleted_at = now() where id = :'bob_msg'::uuid;

select throws_ok(
  $$ update public.messages set deleted_at = now()
     where id = '$$ || :'bob_msg' || $$' $$,
  'P0001',
  '[forbidden] This message has already been deleted.',
  'a message cannot be deleted twice'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select is(
  (select body from public.messages where id = :'bob_msg'::uuid),
  '',
  'a deleted message shows with its text cleared'
);

select isnt(
  (select deleted_at from public.messages where id = :'bob_msg'::uuid),
  null,
  'and is marked as deleted'
);

select throws_ok(
  $$ select * from public.message_deleted_bodies $$,
  '42501',
  null,
  'clients cannot read the original text of deleted messages'
);

update public.messages set deleted_at = now() where id = :'bob_keep'::uuid;

select is(
  (select deleted_at from public.messages where id = :'bob_keep'::uuid),
  null,
  'nobody can delete someone else''s message'
);

select throws_ok(
  $$ update public.messages set body = 'edited'
     where id = '$$ || :'alice_msg' || $$' $$,
  'P0001',
  '[forbidden] Messages can''t be edited, only deleted.',
  'messages cannot be edited'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select original_body from public.message_deleted_bodies where message_id = :'bob_msg'::uuid),
  'oops wrong chat',
  'the original text is kept server-side for reports'
);

-- 27-35. activity group chat

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

insert into public.activities (area_id, title, category, start_time, end_time, participant_limit)
values (:'library_area'::uuid, 'Library study session', 'study_session',
        now() + interval '10 minutes', now() + interval '70 minutes', 3)
returning id as activity_id \gset

reset role;
select set_config('request.jwt.claim.sub', '', true);

select is(
  (select count(*)::int from public.conversations
    where kind = 'activity' and activity_id = :'activity_id'::uuid),
  1,
  'creating an activity opens its group chat'
);

select id as activity_conv from public.conversations
where kind = 'activity' and activity_id = :'activity_id'::uuid \gset

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);
insert into public.messages (conversation_id, body)
values (:'activity_conv'::uuid, 'meet at the entrance');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'erin_id', true);

insert into public.activity_participants (activity_id, user_id)
values (:'activity_id'::uuid, :'erin_id'::uuid)
returning id as erin_part \gset

select is(
  (select count(*)::int from public.messages where conversation_id = :'activity_conv'::uuid),
  0,
  'someone with a pending join request cannot read the group chat'
);

select throws_ok(
  $$ insert into public.messages (conversation_id, body)
     values ('$$ || :'activity_conv' || $$', 'can I come?') $$,
  'P0001',
  '[forbidden] You can''t send messages in this conversation.',
  'nor post in it'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);
update public.activity_participants set status = 'accepted' where id = :'erin_part'::uuid;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'erin_id', true);

select is(
  (select count(*)::int from public.messages where conversation_id = :'activity_conv'::uuid),
  1,
  'once accepted, they can read the group chat'
);

insert into public.messages (conversation_id, body)
values (:'activity_conv'::uuid, 'see you there');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select is(
  (select count(*)::int from public.messages where conversation_id = :'activity_conv'::uuid),
  2,
  'and post in it'
);

insert into public.blocks (blocker_id, blocked_id) values (:'alice_id'::uuid, :'erin_id'::uuid);

select is(
  (select count(*)::int from public.messages where conversation_id = :'activity_conv'::uuid),
  1,
  'in a shared group chat, a blocked person''s messages are hidden'
);

delete from public.blocks where blocker_id = :'alice_id'::uuid and blocked_id = :'erin_id'::uuid;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', :'erin_id', true);
update public.activity_participants set status = 'left' where id = :'erin_part'::uuid;

select is(
  (select count(*)::int from public.messages where conversation_id = :'activity_conv'::uuid),
  0,
  'leaving the activity drops you out of its chat'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

update public.activities
set start_time = now() - interval '2 hours',
    end_time = now() - interval '1 hour'
where id = :'activity_id'::uuid;

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

select is(
  (select count(*)::int from public.messages where conversation_id = :'activity_conv'::uuid),
  2,
  'after the activity ends, members can still read the chat'
);

select throws_ok(
  $$ insert into public.messages (conversation_id, body)
     values ('$$ || :'activity_conv' || $$', 'anyone still here?') $$,
  'P0001',
  '[expired] This activity has ended. The chat is read-only now.',
  'but nobody can post in it any more'
);

-- 36. rate limit (last, it uses up alice's messages)

reset role;
select set_config('request.jwt.claim.sub', '', true);

select 20 - count(*)::int as remaining
from public.messages
where sender_id = :'alice_id'::uuid
  and created_at > now() - interval '1 minute' \gset

set local role authenticated;
select set_config('request.jwt.claim.sub', :'alice_id', true);

insert into public.messages (conversation_id, body)
select :'private_conv'::uuid, 'message ' || g
from generate_series(1, :remaining) g;

select throws_ok(
  $$ insert into public.messages (conversation_id, body)
     values ('$$ || :'private_conv' || $$', 'one too many') $$,
  'P0001',
  '[rate_limited] You''re sending messages too quickly. Wait a moment and try again.',
  'the 21st message within a minute is rate-limited'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select * from finish();
rollback;
