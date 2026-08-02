begin;

create extension if not exists pgtap with schema extensions;
select plan(2);

select results_eq(
  $$
    select count(*)::bigint
    from pg_publication_tables
    where pubname = 'powersync'
      and schemaname = 'public'
      and tablename = 'extraction_creation_quotas'
  $$,
  array[1::bigint],
  'PowerSync publishes the owner-scoped extraction quota snapshot source'
);

select results_eq(
  $$
    select count(*)::bigint
    from pg_publication_tables
    where pubname = 'powersync'
      and schemaname = 'public'
      and tablename = 'iap_entitlements'
  $$,
  array[1::bigint],
  'PowerSync publishes the owner-scoped verified entitlement snapshot source'
);

select * from finish();
rollback;
