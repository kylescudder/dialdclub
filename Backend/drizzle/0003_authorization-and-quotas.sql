-- Ported transactional quota/verified-entitlement behavior. No Supabase schemas
-- or roles are required. Only the request transaction sets diald.user_id.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'diald_api') then
    create role diald_api nologin;
  end if;
end $$;
grant usage on schema public to diald_api;
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$ begin new.updated_at = now(); return new; end $$;
create or replace function public.has_verified_supporter_entitlement(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.iap_entitlements
    where user_id = target_user_id
      and product_id = 'club.diald.supporter.monthly'
      and bundle_id = 'club.diald'
      and environment in ('Production', 'Sandbox')
      and verification_source in ('device', 'notification')
      and verified_at is not null
      and signed_at is not null
      and status = 'active'
      and revoked_at is null
      and expires_at > statement_timestamp()
  );
$$;

revoke all on function public.has_verified_supporter_entitlement(uuid) from public;

create or replace function public.record_verified_iap_entitlement(
  p_user_id uuid,
  p_product_id text,
  p_bundle_id text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_status text,
  p_expires_at timestamptz,
  p_revoked_at timestamptz,
  p_environment text,
  p_signed_at timestamptz,
  p_verification_source text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin

  if p_product_id <> 'club.diald.supporter.monthly'
     or p_bundle_id <> 'club.diald'
     or p_environment not in ('Production', 'Sandbox')
     or p_verification_source not in ('device', 'notification')
     or p_original_transaction_id is null
     or p_transaction_id is null
     or p_expires_at is null
     or p_signed_at is null
     or p_status not in ('active', 'expired', 'revoked') then
    raise exception using
      errcode = 'DX005',
      message = 'verified entitlement fields are invalid';
  end if;

  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception using
      errcode = 'DX004',
      message = 'profile does not exist';
  end if;

  insert into public.iap_entitlements (
    user_id,
    product_id,
    bundle_id,
    original_transaction_id,
    transaction_id,
    status,
    expires_at,
    revoked_at,
    environment,
    signed_at,
    verified_at,
    verification_source,
    updated_at
  ) values (
    p_user_id,
    p_product_id,
    p_bundle_id,
    p_original_transaction_id,
    p_transaction_id,
    p_status,
    p_expires_at,
    p_revoked_at,
    p_environment,
    p_signed_at,
    statement_timestamp(),
    p_verification_source,
    statement_timestamp()
  )
  on conflict (user_id) do update
    set product_id = excluded.product_id,
        bundle_id = excluded.bundle_id,
        original_transaction_id = excluded.original_transaction_id,
        transaction_id = excluded.transaction_id,
        status = excluded.status,
        expires_at = excluded.expires_at,
        revoked_at = excluded.revoked_at,
        environment = excluded.environment,
        signed_at = excluded.signed_at,
        verified_at = excluded.verified_at,
        verification_source = excluded.verification_source,
        updated_at = excluded.updated_at
    where public.iap_entitlements.signed_at is null
       or excluded.signed_at > public.iap_entitlements.signed_at
       or (excluded.signed_at = public.iap_entitlements.signed_at and
         case excluded.status when 'revoked' then 3 when 'expired' then 2 else 1 end >=
         case public.iap_entitlements.status when 'revoked' then 3 when 'expired' then 2 else 1 end);
end;
$$;

revoke all on function public.record_verified_iap_entitlement(
  uuid, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz, text
) from public;


create or replace function public.get_extraction_creation_status()
returns table (
  lifetime_count bigint,
  free_limit integer,
  has_verified_entitlement boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  authenticated_user_id uuid := nullif(current_setting('diald.user_id', true), '')::uuid;
begin
  if authenticated_user_id is null then
    raise exception using
      errcode = 'DX002',
      message = 'authentication required';
  end if;

  if not exists (select 1 from public.profiles where id = authenticated_user_id) then
    raise exception using
      errcode = 'DX004',
      message = 'profile does not exist';
  end if;

  return query
  select
    coalesce(quota.lifetime_count, 0),
    5,
    public.has_verified_supporter_entitlement(authenticated_user_id)
  from (values (1)) as singleton(value)
  left join public.extraction_creation_quotas as quota
    on quota.user_id = authenticated_user_id;
end;
$$;

revoke all on function public.get_extraction_creation_status() from public;


create or replace function public.enforce_free_extraction_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  authenticated_user_id uuid := nullif(current_setting('diald.user_id', true), '')::uuid;
  updated_lifetime_count bigint;
begin
  if authenticated_user_id is null then
    raise exception using
      errcode = 'DX002',
      message = 'authentication required';
  end if;

  if new.owner_id is null then
    new.owner_id := authenticated_user_id;
  elsif new.owner_id <> authenticated_user_id then
    raise exception using
      errcode = 'DX003',
      message = 'brew session owner does not match authenticated user';
  end if;

  perform 1
  from public.profiles
  where id = authenticated_user_id
  for update;

  if not found then
    raise exception using
      errcode = 'DX004',
      message = 'profile does not exist';
  end if;

  -- A previously unseen extraction ID is a genuine lifetime creation. The
  -- durable unique ledger also prevents hard-delete/reinsert cycles and
  -- concurrent duplicate IDs from bypassing or double-consuming the quota.
  -- All writes roll back together if the brew insert later fails.
  insert into public.extraction_creation_events (brew_session_id, user_id)
  values (new.id, authenticated_user_id);

  insert into public.extraction_creation_quotas (user_id, lifetime_count, updated_at)
  values (authenticated_user_id, 1, statement_timestamp())
  on conflict (user_id) do update
    set lifetime_count = public.extraction_creation_quotas.lifetime_count + 1,
        updated_at = statement_timestamp()
  returning lifetime_count into updated_lifetime_count;

  if updated_lifetime_count > 5
     and not public.has_verified_supporter_entitlement(authenticated_user_id) then
    raise exception using
      errcode = 'DX001',
      message = 'free extraction limit reached';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_free_extraction_limit() from public;

drop trigger if exists brew_sessions_enforce_free_extraction_limit on public.brew_sessions;
create trigger brew_sessions_enforce_free_extraction_limit
  before insert on public.brew_sessions
  for each row execute function public.enforce_free_extraction_limit();

-- The runtime role cannot mint or edit subscription verification or lifetime use.
grant select, insert, update on public.profiles to diald_api;
grant select, insert, update, delete on public.beans, public.brew_sessions, public.device_tokens to diald_api;
grant execute on function public.get_extraction_creation_status() to diald_api;
create or replace function public.initialize_extraction_quota() returns trigger
language plpgsql security definer set search_path = '' as $$ begin
  insert into public.extraction_creation_quotas (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;
revoke all on function public.initialize_extraction_quota() from public;
create trigger profiles_initialize_quota after insert on public.profiles
for each row execute function public.initialize_extraction_quota();
create or replace function public.check_brew_bean_owner() returns trigger
language plpgsql set search_path = '' as $$ begin
  if new.bean_id is not null and not exists (
    select 1 from public.beans where id = new.bean_id and owner_id = new.owner_id
  ) then raise exception using errcode='DX003', message='bean is unavailable'; end if;
  return new;
end $$;
create trigger brew_sessions_check_bean_owner before insert or update on public.brew_sessions
for each row execute function public.check_brew_bean_owner();

alter table public.profiles enable row level security;
create policy own_rows on public.profiles to diald_api using (id = nullif(current_setting('diald.user_id', true), '')::uuid) with check (id = nullif(current_setting('diald.user_id', true), '')::uuid);

alter table public.beans enable row level security;
create policy own_rows on public.beans to diald_api using (owner_id = nullif(current_setting('diald.user_id', true), '')::uuid) with check (owner_id = nullif(current_setting('diald.user_id', true), '')::uuid);

alter table public.brew_sessions enable row level security;
create policy own_rows on public.brew_sessions to diald_api using (owner_id = nullif(current_setting('diald.user_id', true), '')::uuid) with check (owner_id = nullif(current_setting('diald.user_id', true), '')::uuid);

alter table public.device_tokens enable row level security;
create policy own_rows on public.device_tokens to diald_api using (user_id = nullif(current_setting('diald.user_id', true), '')::uuid) with check (user_id = nullif(current_setting('diald.user_id', true), '')::uuid);
create trigger profiles_touch_updated_at before update on public.profiles for each row execute function public.touch_updated_at();
create trigger beans_touch_updated_at before update on public.beans for each row execute function public.touch_updated_at();
create trigger brew_sessions_touch_updated_at before update on public.brew_sessions for each row execute function public.touch_updated_at();
create trigger brew_steps_touch_updated_at before update on public.brew_steps for each row execute function public.touch_updated_at();
create trigger brew_reminders_touch_updated_at before update on public.brew_reminders for each row execute function public.touch_updated_at();
create trigger device_tokens_touch_updated_at before update on public.device_tokens for each row execute function public.touch_updated_at();
create trigger iap_entitlements_touch_updated_at before update on public.iap_entitlements for each row execute function public.touch_updated_at();
alter table public.extraction_creation_quotas enable row level security;
revoke all on public.extraction_creation_quotas from public, diald_api;
alter table public.extraction_creation_events enable row level security;
revoke all on public.extraction_creation_events from public, diald_api;
alter table public.iap_entitlements enable row level security;
revoke all on public.iap_entitlements from public, diald_api;
alter table public.brew_steps enable row level security;
revoke all on public.brew_steps from public, diald_api;
alter table public.brew_reminders enable row level security;
revoke all on public.brew_reminders from public, diald_api;
