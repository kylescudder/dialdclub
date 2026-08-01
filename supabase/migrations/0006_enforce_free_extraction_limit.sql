-- Preserve lifetime extraction usage independently from mutable brew rows and
-- enforce the free allowance at the database boundary.

-- RLS policies decide which owner-scoped rows are accessible; the table grant
-- is still required for authenticated PostgREST operations on a clean project.
grant select, insert, update, delete on table public.brew_sessions to authenticated;

create table if not exists public.extraction_creation_quotas (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  lifetime_count bigint not null default 0 check (lifetime_count >= 0),
  updated_at timestamptz not null default now()
);

alter table public.extraction_creation_quotas enable row level security;
alter table public.extraction_creation_quotas force row level security;
revoke all on table public.extraction_creation_quotas from anon, authenticated;

-- A durable creation ledger makes retries idempotent without depending on the
-- continued existence of the mutable brew_sessions row. Its rows intentionally
-- do not reference brew_sessions, so a hard delete cannot erase lifetime use.
create table if not exists public.extraction_creation_events (
  brew_session_id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index if not exists extraction_creation_events_user_id_idx
  on public.extraction_creation_events (user_id);

alter table public.extraction_creation_events enable row level security;
alter table public.extraction_creation_events force row level security;
revoke all on table public.extraction_creation_events from anon, authenticated;

-- Entitlement rows written before this migration were decoded but not
-- cryptographically verified. They remain readable for diagnostics but cannot
-- authorize database writes until a verified writer populates these fields.
alter table public.iap_entitlements
  add column if not exists bundle_id text,
  add column if not exists transaction_id text,
  add column if not exists signed_at timestamptz,
  add column if not exists verified_at timestamptz,
  add column if not exists verification_source text;

alter table public.iap_entitlements
  drop constraint if exists iap_entitlements_environment_check;
update public.iap_entitlements
set environment = null
where environment is not null
  and environment not in ('Production', 'Sandbox');
alter table public.iap_entitlements
  add constraint iap_entitlements_environment_check
  check (environment is null or environment in ('Production', 'Sandbox'));

alter table public.iap_entitlements
  drop constraint if exists iap_entitlements_verification_source_check;
alter table public.iap_entitlements
  add constraint iap_entitlements_verification_source_check
  check (verification_source is null or verification_source in ('device', 'notification'));

create or replace function public.reconcile_extraction_creation_quotas()
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.extraction_creation_events (brew_session_id, user_id, created_at)
  select id, owner_id, created_at
  from public.brew_sessions
  on conflict (brew_session_id) do nothing;

  insert into public.extraction_creation_quotas (user_id, lifetime_count, updated_at)
  select owner_id, count(*), statement_timestamp()
  from public.brew_sessions
  group by owner_id
  on conflict (user_id) do update
    set lifetime_count = greatest(
          public.extraction_creation_quotas.lifetime_count,
          excluded.lifetime_count
        ),
        updated_at = statement_timestamp();
$$;

select public.reconcile_extraction_creation_quotas();
revoke all on function public.reconcile_extraction_creation_quotas() from public;

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
  if auth.role() is distinct from 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'verified entitlements may only be recorded by the service role';
  end if;

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
       or excluded.signed_at >= public.iap_entitlements.signed_at;
end;
$$;

revoke all on function public.record_verified_iap_entitlement(
  uuid, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz, text
) from public;
grant execute on function public.record_verified_iap_entitlement(
  uuid, text, text, text, text, text, timestamptz, timestamptz, text, timestamptz, text
) to service_role;

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
  authenticated_user_id uuid := auth.uid();
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
grant execute on function public.get_extraction_creation_status() to authenticated;

create or replace function public.enforce_free_extraction_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  authenticated_user_id uuid := auth.uid();
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
