-- Enforce the free lifetime extraction allowance at the database boundary.
-- Locking the owner's profile row serializes inserts from multiple clients so
-- each limit check observes any previously committed insert for that owner.

create index if not exists brew_sessions_owner_id_idx
  on public.brew_sessions (owner_id);

create or replace function public.enforce_free_extraction_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  free_extraction_limit constant integer := 5;
begin
  -- RLS rejects mismatched owners too, but this check runs before the
  -- security-definer function locks or reads another user's rows.
  if auth.uid() is not null and new.owner_id <> auth.uid() then
    raise exception using
      errcode = '42501',
      message = 'brew session owner does not match authenticated user';
  end if;

  perform 1
  from public.profiles
  where id = new.owner_id
  for update;

  if exists (
    select 1
    from public.iap_entitlements
    where user_id = new.owner_id
      and product_id = 'club.diald.supporter.monthly'
      and status = 'active'
      and revoked_at is null
      and (expires_at is null or expires_at > statement_timestamp())
  ) then
    return new;
  end if;

  if (
    select count(*)
    from public.brew_sessions
    where owner_id = new.owner_id
  ) >= free_extraction_limit then
    raise exception using
      errcode = 'P0001',
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
