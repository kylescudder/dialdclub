begin;

create extension if not exists pgtap with schema extensions;
select plan(22);

select has_table(
  'public',
  'extraction_creation_quotas',
  'the protected lifetime quota table exists'
);

select has_table(
  'public',
  'extraction_creation_events',
  'the protected durable creation ledger exists'
);

select results_eq(
  $$select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.extraction_creation_quotas'::regclass$$,
  array[true],
  'quota rows use forced RLS'
);

insert into auth.users (id, email) values
  ('11111111-1111-4111-8111-111111111111', 'free@example.com'),
  ('22222222-2222-4222-8222-222222222222', 'other@example.com'),
  ('33333333-3333-4333-8333-333333333333', 'subscriber@example.com'),
  ('44444444-4444-4444-8444-444444444444', 'untrusted@example.com'),
  ('55555555-5555-4555-8555-555555555555', 'missing-profile@example.com'),
  ('66666666-6666-4666-8666-666666666666', 'seed@example.com');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';

select throws_ok(
  $$select * from public.extraction_creation_quotas$$,
  '42501',
  'permission denied for table extraction_creation_quotas',
  'authenticated clients cannot read the protected quota table directly'
);

select throws_ok(
  $$select * from public.extraction_creation_events$$,
  '42501',
  'permission denied for table extraction_creation_events',
  'authenticated clients cannot read the durable creation ledger directly'
);

select lives_ok(
  $$
    insert into public.brew_sessions (
      id, owner_id, method, title, dose_grams, extraction_seconds
    )
    select ('10000000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
           '11111111-1111-4111-8111-111111111111',
           'espresso', 'Free extraction', 18, 30
    from generate_series(1, 5) as series(value)
  $$,
  'five free creations succeed'
);

select results_eq(
  $$select lifetime_count from public.get_extraction_creation_status()$$,
  array[5::bigint],
  'the authoritative lifetime count is five'
);

select throws_ok(
  $$
    insert into public.brew_sessions (owner_id, method, title, dose_grams, extraction_seconds)
    values ('11111111-1111-4111-8111-111111111111', 'espresso', 'Sixth', 18, 30)
  $$,
  'DX001',
  'free extraction limit reached',
  'the sixth free creation fails'
);

select lives_ok(
  $$
    update public.brew_sessions
    set deleted_at = statement_timestamp()
    where owner_id = '11111111-1111-4111-8111-111111111111'
  $$,
  'soft deletion remains available'
);

select throws_ok(
  $$
    insert into public.brew_sessions (owner_id, method, title, dose_grams, extraction_seconds)
    values ('11111111-1111-4111-8111-111111111111', 'espresso', 'After soft delete', 18, 30)
  $$,
  'DX001',
  'free extraction limit reached',
  'soft deletion does not restore allowance'
);

select lives_ok(
  $$delete from public.brew_sessions where owner_id = '11111111-1111-4111-8111-111111111111'$$,
  'hard deletion is possible through the existing owner policy'
);

select throws_ok(
  $$
    insert into public.brew_sessions (owner_id, method, title, dose_grams, extraction_seconds)
    values ('11111111-1111-4111-8111-111111111111', 'espresso', 'After hard delete', 18, 30)
  $$,
  'DX001',
  'free extraction limit reached',
  'hard deletion does not restore allowance'
);

select throws_ok(
  $$
    insert into public.brew_sessions (
      id, owner_id, method, title, dose_grams, extraction_seconds
    ) values (
      '10000000-0000-4000-8000-000000000001',
      '11111111-1111-4111-8111-111111111111',
      'espresso', 'Reused hard-deleted ID', 18, 30
    )
  $$,
  '23505',
  'duplicate key value violates unique constraint "extraction_creation_events_pkey"',
  'a historical hard-deleted brew ID cannot be reused'
);

select throws_ok(
  $$
    insert into public.brew_sessions (owner_id, method, title, dose_grams, extraction_seconds)
    values ('22222222-2222-4222-8222-222222222222', 'espresso', 'Spoofed owner', 18, 30)
  $$,
  'DX003',
  'brew session owner does not match authenticated user',
  'owner spoofing fails before privileged trigger work'
);

reset request.jwt.claim.sub;
select throws_ok(
  $$
    insert into public.brew_sessions (method, title, dose_grams, extraction_seconds)
    values ('espresso', 'No auth', 18, 30)
  $$,
  'DX002',
  'authentication required',
  'creation requires auth.uid()'
);

reset role;
delete from public.profiles where id = '55555555-5555-4555-8555-555555555555';
set local role authenticated;
set local request.jwt.claim.sub = '55555555-5555-4555-8555-555555555555';
select throws_ok(
  $$
    insert into public.brew_sessions (owner_id, method, title, dose_grams, extraction_seconds)
    values ('55555555-5555-4555-8555-555555555555', 'espresso', 'Missing profile', 18, 30)
  $$,
  'DX004',
  'profile does not exist',
  'a missing profile fails explicitly and safely'
);

reset role;
insert into public.iap_entitlements (
  user_id, product_id, bundle_id, original_transaction_id, transaction_id,
  status, expires_at, environment, signed_at, verified_at, verification_source
) values (
  '33333333-3333-4333-8333-333333333333',
  'club.diald.supporter.monthly',
  'club.diald',
  'verified-original',
  'verified-transaction',
  'active',
  statement_timestamp() + interval '1 month',
  'Sandbox',
  statement_timestamp(),
  statement_timestamp(),
  'device'
);

set local role authenticated;
set local request.jwt.claim.sub = '33333333-3333-4333-8333-333333333333';
select lives_ok(
  $$
    insert into public.brew_sessions (
      id, owner_id, method, title, dose_grams, extraction_seconds
    )
    select gen_random_uuid(), '33333333-3333-4333-8333-333333333333',
           'espresso', 'Subscriber extraction', 18, 30
    from generate_series(1, 6)
  $$,
  'an active server-verified entitlement bypasses the free limit'
);

select results_eq(
  $$select lifetime_count from public.get_extraction_creation_status()$$,
  array[6::bigint],
  'subscriber creations still increment lifetime usage'
);

reset role;
insert into public.iap_entitlements (
  user_id, product_id, status, expires_at, environment
) values (
  '44444444-4444-4444-8444-444444444444',
  'club.diald.supporter.monthly',
  'active',
  statement_timestamp() + interval '1 month',
  'Sandbox'
);

set local role authenticated;
set local request.jwt.claim.sub = '44444444-4444-4444-8444-444444444444';
select throws_ok(
  $$
    select public.record_verified_iap_entitlement(
      '44444444-4444-4444-8444-444444444444',
      'club.diald.supporter.monthly',
      'club.diald',
      'forged-original',
      'forged-transaction',
      'active',
      statement_timestamp() + interval '1 month',
      null,
      'Sandbox',
      statement_timestamp(),
      'device'
    )
  $$,
  '42501',
  'permission denied for function record_verified_iap_entitlement',
  'authenticated clients cannot fabricate verified entitlement input'
);

select lives_ok(
  $$
    insert into public.brew_sessions (
      id, owner_id, method, title, dose_grams, extraction_seconds
    )
    select gen_random_uuid(), '44444444-4444-4444-8444-444444444444',
           'espresso', 'Untrusted mirror extraction', 18, 30
    from generate_series(1, 5)
  $$,
  'an unverified mirror does not affect the first five creations'
);

select throws_ok(
  $$
    insert into public.brew_sessions (owner_id, method, title, dose_grams, extraction_seconds)
    values ('44444444-4444-4444-8444-444444444444', 'espresso', 'Forged sixth', 18, 30)
  $$,
  'DX001',
  'free extraction limit reached',
  'an unverified or forged mirror cannot bypass the limit'
);

reset role;
alter table public.brew_sessions disable trigger brew_sessions_enforce_free_extraction_limit;
insert into public.brew_sessions (
  owner_id, method, title, dose_grams, extraction_seconds, deleted_at
) values
  ('66666666-6666-4666-8666-666666666666', 'espresso', 'Existing active', 18, 30, null),
  ('66666666-6666-4666-8666-666666666666', 'espresso', 'Existing deleted', 18, 30, statement_timestamp());
alter table public.brew_sessions enable trigger brew_sessions_enforce_free_extraction_limit;
select public.reconcile_extraction_creation_quotas();

select results_eq(
  $$
    select lifetime_count
    from public.extraction_creation_quotas
    where user_id = '66666666-6666-4666-8666-666666666666'
  $$,
  array[2::bigint],
  'quota seeding counts every existing brew, including soft-deleted rows'
);

select * from finish();
rollback;
