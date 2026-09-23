-- Phase 4 (matching): block relationships.
--
-- Matching must exclude anyone the user has blocked or been blocked by
-- ("Exclude blocked users -- Safety filtering"). That needs the `blocks`
-- table from the core table list, so this migration creates the minimal
-- schema now. Phase 5 ("Implement block user", `POST /functions/v1/block-user`)
-- owns the workflow on top of it: removing map / activity / chat visibility,
-- reports, moderation. Nothing here should need to change for that.

create table if not exists public.blocks (
  id uuid primary key default gen_random_uuid(),

  blocker_id uuid not null
    references public.profiles(id)
    on delete cascade,

  blocked_id uuid not null
    references public.profiles(id)
    on delete cascade,

  created_at timestamptz not null default now(),

  constraint blocks_unique
    unique (blocker_id, blocked_id),

  constraint blocks_not_self
    check (blocker_id <> blocked_id)
);

comment on table public.blocks is
  'One-directional block: blocker_id no longer wants to see or be seen by blocked_id. Matching, map and activities treat a block in either direction as mutual exclusion. Phase 5 adds the block/report workflow.';


-- =========================================================
-- Indexes
-- =========================================================

create index if not exists blocks_blocker_id_idx
  on public.blocks (blocker_id);

create index if not exists blocks_blocked_id_idx
  on public.blocks (blocked_id);


-- =========================================================
-- Helper: is there a block in either direction?
-- =========================================================

create or replace function public.is_blocked_between(p_user_a uuid, p_user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.blocks b
    where (b.blocker_id = p_user_a and b.blocked_id = p_user_b)
       or (b.blocker_id = p_user_b and b.blocked_id = p_user_a)
  )
$$;

comment on function public.is_blocked_between(uuid, uuid) is
  'True if either user has blocked the other. Used by matching (and later map/activities) to exclude pairs.';

revoke all on function public.is_blocked_between(uuid, uuid) from public, anon;
grant execute on function public.is_blocked_between(uuid, uuid) to authenticated;


-- =========================================================
-- Table privileges (see 20260917090000_grant_api_table_privileges)
-- =========================================================

grant select, insert, delete on table public.blocks to authenticated;
grant all privileges on table public.blocks to service_role;


-- =========================================================
-- Row Level Security
-- =========================================================

alter table public.blocks enable row level security;


-- A user sees only the blocks they created. The blocked person must never
-- learn they were blocked (PRD safety rules), so there is no policy that
-- exposes rows by blocked_id.

create policy "users can read their own blocks"
  on public.blocks
  for select
  to authenticated
  using (
    blocker_id = auth.uid()
    and public.is_verified_user()
  );


-- Verified users can block someone, only as themselves.

create policy "verified users can block as themselves"
  on public.blocks
  for insert
  to authenticated
  with check (
    blocker_id = auth.uid()
    and public.is_verified_user()
  );


-- Unblock = delete own row.

create policy "users can remove their own blocks"
  on public.blocks
  for delete
  to authenticated
  using (
    blocker_id = auth.uid()
    and public.is_verified_user()
  );

-- No UPDATE policy: a block is either present or not.
