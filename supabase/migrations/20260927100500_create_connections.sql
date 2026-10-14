-- Phase 4: connection requests between verified users.
--
-- One row per PAIR, not per request. A pair that has been declined and is
-- later re-requested reuses its row (the unique pair index below makes a
-- second row impossible), which is also what enforces the re-request
-- cooldown -- the old responded_at is still there to check against.

create table if not exists public.connections (
  id uuid primary key default gen_random_uuid(),

  requester_id uuid not null
    references public.profiles(id)
    on delete cascade,

  addressee_id uuid not null
    references public.profiles(id)
    on delete cascade,

  -- pending   -> awaiting the addressee's answer
  -- accepted  -> connected
  -- declined  -> refused; re-requestable after the cooldown
  -- cancelled -> requester withdrew before an answer
  -- removed   -> was accepted, then one side disconnected
  status text not null default 'pending'
    check (status in ('pending', 'accepted', 'declined', 'cancelled', 'removed')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz,

  constraint connections_no_self
    check (requester_id <> addressee_id)
);

comment on table public.connections is
  'Connection requests and the resulting connection. One row per pair of users in either direction; status carries the whole lifecycle.';

-- The pair is unordered: A->B and B->A are the same relationship, so the
-- index is on the sorted pair. This is what stops a second request row
-- existing alongside a declined one.
create unique index if not exists connections_unique_pair_idx
  on public.connections (
    least(requester_id, addressee_id),
    greatest(requester_id, addressee_id)
  );

create index if not exists connections_requester_status_idx
  on public.connections (requester_id, status);

create index if not exists connections_addressee_status_idx
  on public.connections (addressee_id, status);

drop trigger if exists on_connection_updated on public.connections;
create trigger on_connection_updated
  before update on public.connections
  for each row
  execute function public.set_updated_at();


-- =========================================================
-- Helpers
-- =========================================================

create or replace function public.are_connected(
  p_user_id uuid,
  p_other_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.connections c
    where c.status = 'accepted'
      and (
        (c.requester_id = p_user_id and c.addressee_id = p_other_user_id)
        or (c.requester_id = p_other_user_id and c.addressee_id = p_user_id)
      )
  )
$$;

comment on function public.are_connected(uuid, uuid) is
  'True when the two users have an accepted connection. For matching (exclude existing connections) and Phase 5 private chat.';

-- Any relationship at all, whatever its state. Matching uses this rather
-- than are_connected() when it should also skip pairs with a pending or
-- recently declined request.
create or replace function public.has_connection_history(
  p_user_id uuid,
  p_other_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.connections c
    where c.status in ('pending', 'accepted', 'declined')
      and (
        (c.requester_id = p_user_id and c.addressee_id = p_other_user_id)
        or (c.requester_id = p_other_user_id and c.addressee_id = p_user_id)
      )
  )
$$;

comment on function public.has_connection_history(uuid, uuid) is
  'True when a pending, accepted or declined relationship exists between the two users.';

revoke all on function public.are_connected(uuid, uuid) from public, anon;
revoke all on function public.has_connection_history(uuid, uuid) from public, anon;
grant execute on function public.are_connected(uuid, uuid) to authenticated;
grant execute on function public.has_connection_history(uuid, uuid) to authenticated;


-- Whether ANOTHER user is verified. is_verified_user() cannot answer this:
-- it only returns true when the id passed is the caller's own, so it says
-- nothing about the person being requested. Matching will want this too.
create or replace function public.is_verified_profile(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.id = p_user_id
      and p.account_status = 'verified'
      and u.email_confirmed_at is not null
      and p.terms_accepted_at is not null
      and p.privacy_accepted_at is not null
  )
$$;

comment on function public.is_verified_profile(uuid) is
  'True when the given user is verified. Unlike is_verified_user(), works for users other than the caller.';

revoke all on function public.is_verified_profile(uuid) from public, anon;
grant execute on function public.is_verified_profile(uuid) to authenticated;


-- =========================================================
-- Guard trigger: who may request, and the status transitions
-- =========================================================

create or replace function public.guard_connection_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cooldown constant interval := interval '7 days';
begin
  if tg_op = 'INSERT' then
    -- auth.uid() is null for service-role and migration/seed paths, which
    -- are trusted. Same convention as the profile guards.
    if auth.uid() is not null and not public.is_verified_user() then
      raise exception using
        errcode = 'P0001',
        message = '[not_verified] Only verified users can send connection requests.';
    end if;

    if not public.is_verified_profile(new.addressee_id) then
      raise exception using
        errcode = 'P0001',
        message = '[not_verified] That user is not available to connect with.';
    end if;

    -- A blocked pair must not be able to reach each other at all. The
    -- message is deliberately identical to the not-verified one above so a
    -- blocked user cannot tell a block apart from an ordinary refusal.
    if public.is_blocked_between(new.addressee_id, new.requester_id) then
      raise exception using
        errcode = 'P0001',
        message = '[not_verified] That user is not available to connect with.';
    end if;

    return new;
  end if;

  -- UPDATE from here.

  -- responded_at is protected because the cooldown is measured from it --
  -- a client that could edit it could re-request immediately after being
  -- declined. The transitions below set it themselves, after this check.
  if new.id is distinct from old.id
    or new.created_at is distinct from old.created_at
    or (auth.uid() is not null
        and new.responded_at is distinct from old.responded_at)
  then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] Protected connection fields cannot be changed.';
  end if;

  if auth.uid() is not null
     and auth.uid() not in (old.requester_id, old.addressee_id)
  then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] You are not part of this connection.';
  end if;

  if new.status = old.status then
    return new;
  end if;

  -- Re-request: a settled pair goes back to pending, and whoever asks this
  -- time becomes the requester, so the direction can flip.
  if new.status = 'pending' then
    if old.status = 'declined' then
      if old.responded_at is not null
         and old.responded_at > now() - v_cooldown then
        raise exception using
          errcode = 'P0001',
          message = '[rate_limited] This request was declined recently. Try again later.';
      end if;
    elsif old.status not in ('cancelled', 'removed') then
      raise exception using
        errcode = 'P0001',
        message = format('[invalid_transition] Cannot change a connection from %s to pending.', old.status);
    end if;

    if public.is_blocked_between(old.requester_id, old.addressee_id) then
      raise exception using
        errcode = 'P0001',
        message = '[not_verified] That user is not available to connect with.';
    end if;

    new.responded_at := null;
    return new;
  end if;

  if old.status <> 'pending' and new.status in ('accepted', 'declined', 'cancelled') then
    raise exception using
      errcode = 'P0001',
      message = format('[invalid_transition] Cannot change a connection from %s to %s.', old.status, new.status);
  end if;

  -- Only the addressee answers a request.
  if new.status in ('accepted', 'declined') then
    if auth.uid() is not null and auth.uid() <> old.addressee_id then
      raise exception using
        errcode = 'P0001',
        message = '[forbidden] Only the person who received the request can accept or decline it.';
    end if;
    new.responded_at := now();
    return new;
  end if;

  -- Only the requester withdraws their own pending request.
  if new.status = 'cancelled' then
    if auth.uid() is not null and auth.uid() <> old.requester_id then
      raise exception using
        errcode = 'P0001',
        message = '[forbidden] Only the person who sent the request can cancel it.';
    end if;
    new.responded_at := now();
    return new;
  end if;

  -- Either side can disconnect, but only from an accepted connection.
  if new.status = 'removed' then
    if old.status <> 'accepted' then
      raise exception using
        errcode = 'P0001',
        message = format('[invalid_transition] Cannot change a connection from %s to removed.', old.status);
    end if;
    new.responded_at := now();
    return new;
  end if;

  raise exception using
    errcode = 'P0001',
    message = format('[invalid_transition] Cannot change a connection from %s to %s.', old.status, new.status);
end;
$$;

comment on function public.guard_connection_write() is
  'Who may request a connection, and the pending/accepted/declined/cancelled/removed transition rules including the re-request cooldown.';

drop trigger if exists on_connection_write_guard on public.connections;
create trigger on_connection_write_guard
  before insert or update on public.connections
  for each row
  execute function public.guard_connection_write();


-- =========================================================
-- Row Level Security
-- =========================================================

alter table public.connections enable row level security;

create policy "verified users can send connection requests"
  on public.connections
  for insert
  to authenticated
  with check (
    requester_id = auth.uid()
    and public.is_verified_user()
    and status = 'pending'
  );

-- Direct column checks rather than a helper that re-queries connections --
-- a select policy that re-queries its own table breaks insert/update ...
-- returning, which is the pattern supabase-js uses.
create policy "users can see their own connections"
  on public.connections
  for select
  to authenticated
  using (
    requester_id = auth.uid()
    or addressee_id = auth.uid()
  );

create policy "either side can act on their own connection"
  on public.connections
  for update
  to authenticated
  using (
    requester_id = auth.uid()
    or addressee_id = auth.uid()
  )
  with check (
    requester_id = auth.uid()
    or addressee_id = auth.uid()
  );

-- No delete policy: disconnecting is status = 'removed' so the history
-- stays for moderation.

grant select, insert, update on table public.connections to authenticated;
grant all privileges on table public.connections to service_role;
