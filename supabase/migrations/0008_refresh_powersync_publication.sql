-- Include the read-only quota and verified entitlement snapshots required for
-- safe offline creation decisions. Alter the existing publication in place so
-- deployed PowerSync replication slots are not disrupted.

alter publication powersync add table
  public.extraction_creation_quotas,
  public.iap_entitlements;
