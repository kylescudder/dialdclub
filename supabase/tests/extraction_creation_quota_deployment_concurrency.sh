#!/usr/bin/env bash
set -euo pipefail

database_url="${1:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
test_user_id="88888888-8888-4888-8888-888888888888"
historical_brew_id="80000000-0000-4000-8000-000000000001"
concurrent_brew_id="80000000-0000-4000-8000-000000000002"
test_output_dir="$(mktemp -d)"
gap_ready_file="$test_output_dir/backfill-complete"
deployment_pid=""
insert_pid=""

cleanup() {
  if [[ -n "$insert_pid" ]] && kill -0 "$insert_pid" 2>/dev/null; then
    kill "$insert_pid" 2>/dev/null || true
    wait "$insert_pid" 2>/dev/null || true
  fi
  if [[ -n "$deployment_pid" ]] && kill -0 "$deployment_pid" 2>/dev/null; then
    kill "$deployment_pid" 2>/dev/null || true
    wait "$deployment_pid" 2>/dev/null || true
  fi
  psql "$database_url" -v ON_ERROR_STOP=1 -q >/dev/null 2>&1 <<SQL || true
drop trigger if exists brew_sessions_enforce_free_extraction_limit
  on public.brew_sessions;
create trigger brew_sessions_enforce_free_extraction_limit
  before insert on public.brew_sessions
  for each row execute function public.enforce_free_extraction_limit();
delete from auth.users where id = '$test_user_id';
SQL
  rm -rf -- "$test_output_dir"
}
trap cleanup EXIT

psql "$database_url" -v ON_ERROR_STOP=1 -q <<SQL
delete from auth.users where id = '$test_user_id';
insert into auth.users (id, email)
values ('$test_user_id', 'deployment-concurrency@example.com');
set role authenticated;
set request.jwt.claim.sub = '$test_user_id';
insert into public.brew_sessions (
  id, owner_id, method, title, dose_grams, extraction_seconds
) values (
  '$historical_brew_id', '$test_user_id', 'espresso',
  'Historical extraction', 18, 30
);
reset role;
drop trigger brew_sessions_enforce_free_extraction_limit
  on public.brew_sessions;
delete from public.extraction_creation_events where user_id = '$test_user_id';
delete from public.extraction_creation_quotas where user_id = '$test_user_id';
SQL

# Reproduce the relevant migration transaction: acquire the table lock before
# backfill, pause where helper/RPC DDL runs, then install the trigger last.
psql "$database_url" -v ON_ERROR_STOP=1 >"$test_output_dir/deployment.log" 2>&1 <<SQL &
begin;
lock table public.brew_sessions in share row exclusive mode;

insert into public.extraction_creation_events (brew_session_id, user_id, created_at)
select id, owner_id, created_at
from public.brew_sessions
where owner_id = '$test_user_id'
on conflict (brew_session_id) do nothing;

insert into public.extraction_creation_quotas (user_id, lifetime_count, updated_at)
select owner_id, count(*), statement_timestamp()
from public.brew_sessions
where owner_id = '$test_user_id'
group by owner_id
on conflict (user_id) do update
  set lifetime_count = greatest(
        public.extraction_creation_quotas.lifetime_count,
        excluded.lifetime_count
      ),
      updated_at = statement_timestamp();

\! touch "$gap_ready_file"
select pg_sleep(2);

create trigger brew_sessions_enforce_free_extraction_limit
  before insert on public.brew_sessions
  for each row execute function public.enforce_free_extraction_limit();
commit;
SQL
deployment_pid=$!

for _ in {1..100}; do
  [[ -f "$gap_ready_file" ]] && break
  sleep 0.05
done
if [[ ! -f "$gap_ready_file" ]]; then
  echo "deployment transaction did not reach the post-backfill gap" >&2
  cat "$test_output_dir/deployment.log" >&2
  exit 1
fi

psql "$database_url" -v ON_ERROR_STOP=1 >"$test_output_dir/insert.log" 2>&1 <<SQL &
set role authenticated;
set request.jwt.claim.sub = '$test_user_id';
insert into public.brew_sessions (
  id, owner_id, method, title, dose_grams, extraction_seconds
) values (
  '$concurrent_brew_id', '$test_user_id', 'espresso',
  'Insert attempted during deployment', 18, 30
);
SQL
insert_pid=$!

sleep 0.25
if ! kill -0 "$insert_pid" 2>/dev/null; then
  echo "brew insert completed inside the deployment backfill/trigger gap" >&2
  cat "$test_output_dir/insert.log" >&2
  exit 1
fi

visible_brew_count="$(psql "$database_url" -v ON_ERROR_STOP=1 -qAt <<SQL
select count(*)
from public.brew_sessions
where owner_id = '$test_user_id';
SQL
)"
if [[ "$visible_brew_count" != "1" ]]; then
  echo "concurrent brew became visible before trigger installation" >&2
  exit 1
fi

if ! wait "$deployment_pid"; then
  deployment_pid=""
  cat "$test_output_dir/deployment.log" >&2
  exit 1
fi
deployment_pid=""

if ! wait "$insert_pid"; then
  insert_pid=""
  cat "$test_output_dir/insert.log" >&2
  exit 1
fi
insert_pid=""

result="$(psql "$database_url" -v ON_ERROR_STOP=1 -qAt <<SQL
select
  (select count(*) from public.brew_sessions where owner_id = '$test_user_id')
  || '|' ||
  (select count(*) from public.extraction_creation_events where user_id = '$test_user_id')
  || '|' ||
  (select lifetime_count from public.extraction_creation_quotas where user_id = '$test_user_id');
SQL
)"

if [[ "$result" != "2|2|2" ]]; then
  echo "expected brew, event, and quota counts to be 2|2|2, got: $result" >&2
  exit 1
fi

echo "deployment concurrency check passed: the insert waited for trigger installation and committed as brew|event|quota 2|2|2"
