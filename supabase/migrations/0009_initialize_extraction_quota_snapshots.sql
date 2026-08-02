-- PowerSync must be able to distinguish a confirmed zero lifetime count from
-- an account whose quota stream has not completed its first download.

create or replace function public.initialize_extraction_creation_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.extraction_creation_quotas (user_id, lifetime_count, updated_at)
  values (new.id, 0, statement_timestamp())
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.initialize_extraction_creation_quota() from public;

drop trigger if exists profiles_initialize_extraction_creation_quota on public.profiles;
create trigger profiles_initialize_extraction_creation_quota
  after insert on public.profiles
  for each row execute function public.initialize_extraction_creation_quota();

-- Existing zero-use accounts were not included by the original grouped brew
-- backfill. Give every profile a materialized snapshot row without changing
-- any lifetime count already recorded by the authoritative trigger. Count the
-- durable ledger as a defensive backfill if a non-zero row is also missing.
insert into public.extraction_creation_quotas (user_id, lifetime_count, updated_at)
select profile.id, count(event.brew_session_id), statement_timestamp()
from public.profiles as profile
left join public.extraction_creation_events as event
  on event.user_id = profile.id
group by profile.id
on conflict (user_id) do nothing;
