#!/usr/bin/env bash
set -euo pipefail

database_url="${1:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
test_user_id="77777777-7777-4777-8777-777777777777"
test_output_dir="$(mktemp -d)"

cleanup() {
  psql "$database_url" -v ON_ERROR_STOP=1 -qAt \
    -c "delete from auth.users where id = '$test_user_id';" >/dev/null || true
  rm -rf -- "$test_output_dir"
}
trap cleanup EXIT

psql "$database_url" -v ON_ERROR_STOP=1 -q <<SQL
delete from auth.users where id = '$test_user_id';
insert into auth.users (id, email) values ('$test_user_id', 'concurrency@example.com');
set role authenticated;
set request.jwt.claim.sub = '$test_user_id';
insert into public.brew_sessions (
  id, owner_id, method, title, dose_grams, extraction_seconds
)
select gen_random_uuid(), '$test_user_id', 'espresso', 'Initial extraction', 18, 30
from generate_series(1, 4);
SQL

psql "$database_url" -v ON_ERROR_STOP=1 >"$test_output_dir/session-a.log" 2>&1 <<SQL &
begin;
set local role authenticated;
set local request.jwt.claim.sub = '$test_user_id';
insert into public.brew_sessions (owner_id, method, title, dose_grams, extraction_seconds)
values ('$test_user_id', 'espresso', 'Concurrent fifth', 18, 30);
select pg_sleep(2);
commit;
SQL
session_a_pid=$!

sleep 0.25

if psql "$database_url" -v ON_ERROR_STOP=1 >"$test_output_dir/session-b.log" 2>&1 <<SQL
set role authenticated;
set request.jwt.claim.sub = '$test_user_id';
insert into public.brew_sessions (owner_id, method, title, dose_grams, extraction_seconds)
values ('$test_user_id', 'espresso', 'Concurrent sixth', 18, 30);
SQL
then
  echo "expected the concurrent sixth creation to fail" >&2
  exit 1
fi

wait "$session_a_pid"
grep -q "free extraction limit reached" "$test_output_dir/session-b.log"

result="$(psql "$database_url" -v ON_ERROR_STOP=1 -qAt <<SQL
select q.lifetime_count || '|' || count(b.id)
from public.extraction_creation_quotas q
join public.brew_sessions b on b.owner_id = q.user_id
where q.user_id = '$test_user_id'
group by q.lifetime_count;
SQL
)"

if [[ "$result" != "5|5" ]]; then
  echo "expected lifetime quota and brew count to remain 5, got: $result" >&2
  exit 1
fi

echo "concurrent quota check passed: one fifth insert committed and the sixth failed"

"$(dirname "$0")/extraction_creation_quota_deployment_concurrency.sh" "$database_url"
