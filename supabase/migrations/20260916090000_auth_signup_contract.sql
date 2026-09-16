-- Phase 1 integration fix: keep the Auth trigger compatible with the
-- metadata key used by the existing frontend while standardising on the
-- documented `display_name` key for new clients.
--
-- This is a follow-up migration (rather than an edit to the original Auth
-- migration) so it can be applied safely to the shared Supabase project.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_organisation_id uuid;
  v_organisation_type text;
  v_terms_accepted boolean;
  v_privacy_accepted boolean;
  v_display_name text;
begin
  select r.organisation_id, r.organisation_type
    into v_organisation_id, v_organisation_type
  from public.organisation_for_email(new.email) r;

  if v_organisation_id is null then
    raise exception using
      errcode = 'P0001',
      message = '[invalid_domain] The account email is not approved.';
  end if;

  v_terms_accepted := lower(coalesce(
    new.raw_user_meta_data ->> 'terms_accepted',
    new.raw_user_meta_data ->> 'termsAccepted',
    'false'
  )) = 'true';
  v_privacy_accepted := lower(coalesce(
    new.raw_user_meta_data ->> 'privacy_accepted',
    new.raw_user_meta_data ->> 'privacyAccepted',
    'false'
  )) = 'true';

  -- Consent remains mandatory at the database boundary. The frontend must
  -- send both flags; accepting neither flag is never inferred from signup.
  if not v_terms_accepted or not v_privacy_accepted then
    raise exception using
      errcode = 'P0001',
      message = '[consent_required] Terms and privacy consent are required.';
  end if;

  -- `full_name` is retained as a backwards-compatible alias for clients
  -- that were built before the signup contract was documented. New clients
  -- should send `display_name`.
  v_display_name := nullif(btrim(coalesce(
    new.raw_user_meta_data ->> 'display_name',
    new.raw_user_meta_data ->> 'displayName',
    new.raw_user_meta_data ->> 'full_name',
    ''
  )), '');

  insert into public.profiles (
    id,
    organisation_id,
    account_type,
    display_name,
    account_status,
    email_verified_at,
    terms_accepted_at,
    privacy_accepted_at
  ) values (
    new.id,
    v_organisation_id,
    case when v_organisation_type = 'university' then 'student' else 'professional' end,
    v_display_name,
    case when new.email_confirmed_at is null then 'pending' else 'verified' end,
    new.email_confirmed_at,
    now(),
    now()
  );

  return new;
end;
$$;

comment on function public.handle_new_auth_user() is
  'Creates a pending profile for a valid Auth user, records mandatory consent and accepts display_name/full_name metadata aliases.';
