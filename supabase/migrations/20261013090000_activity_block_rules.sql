-- Phase 5: blocking applies to activities, plus join-request rate limit.
--
-- The map (active_map_points) and chat already filter on blocks. This
-- covers the two activity extension points left for Phase 5 in the
-- activities plan: the visibility check and the join-request trigger.
--
-- Rules (a block in either direction counts):
--   * you can't see an activity whose creator you've blocked or who has
--     blocked you -- unless it's your own activity;
--   * you can't request to join it, and the creator can't accept you;
--   * the creator can remove a blocked participant (accepted -> declined).
-- A blocked user gets the same generic [forbidden] as anyone else, so they
-- can't tell a block exists.
--
-- Uses public.is_blocked_between() from the blocks migration as-is
-- (positional arguments only, no changes to that migration).


-- ---------------------------------------------------------------------
-- Visibility
-- ---------------------------------------------------------------------

create or replace function public.can_view_activity(p_activity_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_verified_user()
    and (
      public.activity_is_active(p_activity_id)
      or public.is_activity_creator(p_activity_id)
      or public.is_activity_participant(p_activity_id)
    )
    and (
      public.is_activity_creator(p_activity_id)
      or not exists (
        select 1
        from public.activities a
        where a.id = p_activity_id
          and public.is_blocked_between(a.creator_id, auth.uid())
      )
    )
$$;

comment on function public.can_view_activity(uuid) is
  'Visibility gate for activities, for application code. Hidden when the viewer and creator have a block between them. Not used by the activities select policy -- see that policy''s comment.';

-- Same logic inlined as column checks -- see the comment on the original
-- policy for why it can't call can_view_activity(). Keep the two in sync.
drop policy if exists "users can view activities they're allowed to see"
  on public.activities;

create policy "users can view activities they're allowed to see"
  on public.activities
  for select
  to authenticated
  using (
    public.is_verified_user()
    and (
      (status = 'open' and end_time > now())
      or creator_id = auth.uid()
      or public.is_activity_participant(id)
    )
    and (
      creator_id = auth.uid()
      or not public.is_blocked_between(creator_id, auth.uid())
    )
  );


-- ---------------------------------------------------------------------
-- Join requests and responses
-- ---------------------------------------------------------------------

create or replace function public.guard_activity_participant_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activity record;
  v_recent integer;
begin
  select a.creator_id, a.status, a.end_time, a.participant_limit
    into v_activity
  from public.activities a
  where a.id = coalesce(new.activity_id, old.activity_id)
  for update;

  if tg_op = 'INSERT' then
    -- the creator's own row comes from insert_creator_as_participant();
    -- RLS already blocks a real client from setting is_creator = true
    if new.is_creator then
      return new;
    end if;

    if new.user_id = v_activity.creator_id then
      raise exception using
        errcode = 'P0001',
        message = '[forbidden] The creator is already a participant in their own activity.';
    end if;

    -- Same message a non-member would get, so a block isn't revealed.
    if public.is_blocked_between(new.user_id, v_activity.creator_id) then
      raise exception using
        errcode = 'P0001',
        message = '[forbidden] You can''t request to join this activity.';
    end if;

    if v_activity.status = 'cancelled' then
      raise exception using
        errcode = 'P0001',
        message = '[activity_cancelled] This activity has been cancelled.';
    end if;

    if v_activity.end_time <= now() then
      raise exception using
        errcode = 'P0001',
        message = '[expired] This activity has already ended.';
    end if;

    if public.activity_accepted_count(new.activity_id) >= v_activity.participant_limit then
      raise exception using
        errcode = 'P0001',
        message = '[activity_full] This activity already has its maximum number of participants.';
    end if;

    -- 10 join requests an hour. Only for real clients -- auth.uid() is null
    -- for service_role and seed paths.
    if auth.uid() is not null then
      select count(*) into v_recent
      from public.activity_participants ap
      where ap.user_id = auth.uid()
        and ap.is_creator = false
        and ap.created_at > now() - interval '1 hour';

      if v_recent >= 10 then
        raise exception using
          errcode = 'P0001',
          message = '[rate_limited] You''ve sent a lot of join requests. Try again later.';
      end if;
    end if;

    return new;
  end if;

  -- UPDATE from here -- accept/decline/leave transition rules. A
  -- declined request can never become pending/accepted again by the
  -- requester; only the creator can move declined -> accepted.
  if old.is_creator then
    if new.status <> old.status then
      raise exception using
        errcode = 'P0001',
        message = '[invalid_transition] The creator''s own participant row cannot change status -- cancel the activity instead.';
    end if;
    return new;
  end if;

  if auth.uid() = v_activity.creator_id then
    if new.status = 'accepted'
      and old.status in ('pending', 'declined')
      and public.is_blocked_between(old.user_id, v_activity.creator_id)
    then
      raise exception using
        errcode = 'P0001',
        message = '[forbidden] You can''t accept this request.';
    end if;

    if old.status = 'pending' and new.status = 'accepted' then
      if public.activity_accepted_count(new.activity_id) >= v_activity.participant_limit then
        raise exception using
          errcode = 'P0001',
          message = '[activity_full] This activity already has its maximum number of participants.';
      end if;
      new.responded_at := now();
      return new;
    elsif old.status = 'pending' and new.status = 'declined' then
      new.responded_at := now();
      return new;
    elsif old.status = 'declined' and new.status = 'accepted' then
      if public.activity_accepted_count(new.activity_id) >= v_activity.participant_limit then
        raise exception using
          errcode = 'P0001',
          message = '[activity_full] This activity already has its maximum number of participants.';
      end if;
      new.responded_at := now();
      return new;
    elsif old.status = 'accepted' and new.status = 'declined'
      and public.is_blocked_between(old.user_id, v_activity.creator_id)
    then
      -- removing someone you've blocked (or who blocked you)
      new.responded_at := now();
      return new;
    else
      raise exception using
        errcode = 'P0001',
        message = format('[invalid_transition] Cannot change participant status from %s to %s.', old.status, new.status);
    end if;
  elsif auth.uid() = old.user_id then
    -- own row: only leaving is allowed
    if new.status = 'left' and old.status in ('pending', 'accepted') then
      new.responded_at := now();
      return new;
    else
      raise exception using
        errcode = 'P0001',
        message = format('[invalid_transition] Cannot change participant status from %s to %s.', old.status, new.status);
    end if;
  end if;

  raise exception using
    errcode = 'P0001',
    message = '[forbidden] You are not allowed to change this participant row.';
end;
$$;

comment on function public.guard_activity_participant_write() is
  'Who can join, block checks, the join-request rate limit, and the accept/decline/leave transition rules.';

create index if not exists activity_participants_user_created_idx
  on public.activity_participants (user_id, created_at);
