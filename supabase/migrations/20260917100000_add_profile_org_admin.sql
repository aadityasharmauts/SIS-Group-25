-- Phase 3: organisation admin flag.
--
-- Official events may only be published by approved organisation accounts.
-- A profile with is_org_admin = true is allowed to publish and manage
-- official events on behalf of its own organisation (profiles.organisation_id).
--
-- The flag is granted server-side only (service role / SQL), never by the
-- client. It is added to the protected-field list so a normal profile
-- update cannot self-promote.

alter table public.profiles
  add column if not exists is_org_admin boolean not null default false;

comment on column public.profiles.is_org_admin is
  'True for approved organisation accounts that may publish official events for their organisation. Granted server-side only.';

create index if not exists profiles_is_org_admin_idx
  on public.profiles (organisation_id)
  where is_org_admin;


-- =========================================================
-- Protect the flag from client updates
-- =========================================================

create or replace function public.prevent_profile_protected_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- auth.uid() is null for Auth triggers/service-role operations. Those
  -- server-side paths are allowed to update verification state. A normal
  -- authenticated client can edit only the user-facing profile fields.
  if auth.uid() is not null and (
    new.id is distinct from old.id
    or new.organisation_id is distinct from old.organisation_id
    or new.account_type is distinct from old.account_type
    or new.account_status is distinct from old.account_status
    or new.email_verified_at is distinct from old.email_verified_at
    or new.terms_accepted_at is distinct from old.terms_accepted_at
    or new.privacy_accepted_at is distinct from old.privacy_accepted_at
    or new.is_org_admin is distinct from old.is_org_admin
    or new.created_at is distinct from old.created_at
  ) then
    raise exception using
      errcode = 'P0001',
      message = '[forbidden] Protected profile fields cannot be changed by the client.';
  end if;

  new.updated_at := now();
  return new;
end;
$$;


-- =========================================================
-- Helper: is the current user an approved organisation admin?
-- =========================================================

-- Returns true only when the caller is a fully verified user, has the
-- is_org_admin flag, and (when p_organisation_id is given) belongs to that
-- organisation. Used by official_events / event_rsvps RLS policies.

create or replace function public.is_org_admin(p_organisation_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_verified_user()
    and exists (
      select 1
      from public.profiles p
      where p.id = auth.uid()
        and p.is_org_admin
        and (p_organisation_id is null or p.organisation_id = p_organisation_id)
    )
$$;

comment on function public.is_org_admin(uuid) is
  'True when the caller is a verified organisation admin (optionally for the given organisation).';

revoke all on function public.is_org_admin(uuid) from public, anon;
grant execute on function public.is_org_admin(uuid) to authenticated;
