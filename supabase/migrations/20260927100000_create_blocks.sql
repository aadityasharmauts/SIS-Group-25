-- Phase 5 (built early): blocks.
--
-- Phase 4 matching needs "exclude blocked users" and there was nothing to
-- exclude against, so the table and its helper land here.
--
-- A block does NOT remove an existing connection: unblocking restores the
-- relationship as it was. That means visibility has to be filtered at read
-- time everywhere -- map, activities, matching, chat -- via
-- is_blocked_between() below. Any new read path must call it.

create table if not exists public.blocks (
  id uuid primary key default gen_random_uuid(),

  blocker_id uuid not null
    references public.profiles(id)
    on delete cascade,

  blocked_id uuid not null
    references public.profiles(id)
    on delete cascade,

  created_at timestamptz not null default now(),

  constraint blocks_no_self
    check (blocker_id <> blocked_id),
  constraint blocks_unique_pair
    unique (blocker_id, blocked_id)
);

comment on table public.blocks is
  'One row per block. Directional storage, but is_blocked_between() treats a block in either direction as mutual for visibility. Unblocking is a delete.';

create index if not exists blocks_blocker_id_idx
  on public.blocks (blocker_id);

create index if not exists blocks_blocked_id_idx
  on public.blocks (blocked_id);


-- True when either user has blocked the other. security definer so it can
-- see rows the caller is not allowed to read -- the blocked user must never
-- be able to tell they were blocked.
create or replace function public.is_blocked_between(
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
    from public.blocks b
    where (b.blocker_id = p_user_id and b.blocked_id = p_other_user_id)
       or (b.blocker_id = p_other_user_id and b.blocked_id = p_user_id)
  )
$$;

comment on function public.is_blocked_between(uuid, uuid) is
  'True when either user has blocked the other. Call this from every read path that shows one user to another.';

revoke all on function public.is_blocked_between(uuid, uuid) from public, anon;
grant execute on function public.is_blocked_between(uuid, uuid) to authenticated;


create or replace function public.guard_block_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null for service-role and migration/seed paths, which
  -- are trusted. Same convention as the profile guards.
  if auth.uid() is not null and not public.is_verified_user() then
    raise exception using
      errcode = 'P0001',
      message = '[not_verified] Only verified users can block.';
  end if;

  return new;
end;
$$;

comment on function public.guard_block_write() is
  'Only verified users can create a block.';

drop trigger if exists on_block_write_guard on public.blocks;
create trigger on_block_write_guard
  before insert on public.blocks
  for each row
  execute function public.guard_block_write();


alter table public.blocks enable row level security;

create policy "users can block others"
  on public.blocks
  for insert
  to authenticated
  with check (
    blocker_id = auth.uid()
    and public.is_verified_user()
  );

-- Only the blocker sees the row. The blocked user must not be able to
-- discover the block.
create policy "only the blocker can see their blocks"
  on public.blocks
  for select
  to authenticated
  using (blocker_id = auth.uid());

-- Unblocking is a real delete, unlike the soft-delete pattern used
-- elsewhere -- a lifted block should leave nothing behind.
create policy "users can unblock"
  on public.blocks
  for delete
  to authenticated
  using (blocker_id = auth.uid());

grant select, insert, delete on table public.blocks to authenticated;
grant all privileges on table public.blocks to service_role;
