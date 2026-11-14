-- DBA-reviewed bootstrap. Never run as the API, and never restart shared PG here.
-- Refuse installation until the operator has arranged logical WAL capacity.
do $$ begin
  if current_setting('wal_level') <> 'logical' then
    raise exception 'Logical WAL is not enabled; coordinate the shared PostgreSQL change first';
  end if;
end $$;
-- Dedicated PowerSync login/password provisioned separately through secret tooling.
-- Never grant replication to dialdclub_runtime or diald_api.
create role dialdclub_sync login replication bypassrls nosuperuser nocreatedb nocreaterole;
-- BYPASSRLS is confined to this replication login; SELECT grants are only the five
-- published tables. Audit CONNECT/table privileges across the shared cluster.
grant connect on database dialdclub to dialdclub_sync;
grant usage on schema public to dialdclub_sync;
grant select on profiles, beans, brew_sessions, extraction_creation_quotas, iap_entitlements to dialdclub_sync;
create publication powersync for table profiles, beans, brew_sessions, extraction_creation_quotas, iap_entitlements;
-- The named replication slot is created/managed by PowerSync, not by the API.
-- Provision a separate powersync storage database and scoped owner. Monitor slot
-- retained WAL, storage growth and max_slot_wal_keep_size before enabling traffic.
