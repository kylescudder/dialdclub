# Diald API release and cutover

This is a deployment candidate, not an installed backend. Production cutover is
blocked until all gates below pass. Existing Supabase stays authoritative until
the coordinated final export. No live source writes were fenced by this work.

## Image and deployment contract

`release-backend.yml` tests and publishes arm64/amd64 images on main, binds the
source SHA in the OCI label, and attests the digest with the GitHub workflow/ref.
Herman must verify the immutable GHCR digest and main/workflow provenance through
deploy-core. Local test image hashes are not a production release.

The Compose candidate has no builds or host ports, is non-root/read-only, drops
capabilities, and separates API, replication and storage credentials. API pool:
four connections. API limit: 256 MiB/0.5 CPU. PowerSync limit: 512 MiB/1 CPU, V8
heap 384 MiB. These are candidate limits, not measured production capacity.

PowerSync 1.28.3 was tested on arm64 using
`journeyapps/powersync-service@sha256:effc8cfae91dcb2d4b5767b3b0a795d933701aa957a81af2bfce7fb15c2f47b4`.
It ran the five owner streams with PostgreSQL 18.6 storage and logical replication.
The upstream package reports Apache-2.0; confirm the selected distribution/license
for production before installation. Source config follows the official
`powersync-ja/self-host-demo` Postgres bucket-storage example. Telemetry is off.

Read the actual Herman skills, platform runbook and installed deploy-core README
before host changes. Host SSH access was unavailable during implementation.
`deploy-core-candidate/` contains proposed app-specific central hooks/registry
metadata. Review and install these in a proper central release, never edit an
installed immutable release. The existing static-site receiver is unrelated.
Provision a separate receiver through deploy-core's image/provenance machinery;
its URL and Access/HMAC secrets must be established on Herman before wiring a
release request. This branch deliberately does not enable a deploy webhook.

Run `provision-roles.sql` once as DBA before owner migrations. Owner migrations
must use the private owner credential, never the API's runtime URL. After
migrations, review/run `provision.sql` with logical WAL already enabled. It refuses
to change shared PostgreSQL settings. A shared restart needs coordinated approval.
Give the dedicated replication role SELECT on exactly the five published tables;
BYPASSRLS/REPLICATION belong only to that login. Audit its other-database CONNECT
and object privileges before use. The runtime must have neither privilege.
Provision a separate PowerSync storage database/login. Monitor replication slot
retained WAL, storage growth/rebuild time, and total connections. Do not grant
API users create/admin/replication rights. Do not prune shared host images.

Create the notification spool mode 0700 owned by the container UID, include it
in encrypted project backups, and retain signed bytes across endpoint changes.
Mount `.env` files mode 0600 from the protected project directory. Fill the
example settings without printing values. Default `TARGET_WRITES_ENABLED=false`
fails closed even when an image runs. It may change only at the reviewed first
write boundary after reconciliation/native release availability.

## Recovery lease

Every authoritative table has a statement guard and a deferred COMMIT guard.
These cover signup/auth callbacks/sessions, CRUD uploads, entitlements, notification
processing, background writes and account deletion. A trusted backup verifier
publishes a singleton recovery lease. It is valid only when snapshot START is
less than 600 seconds old, not future-dated, and verified after start. Transactions
are limited to 60 seconds and API connections use 55-second statement/idle limits.
The runtime cannot update the lease. Missing/stale/failed proof returns 503.

`publish-recovery-lease.ts` accepts a protected JSON file containing exactly
`snapshotStartedAt`, `verifiedAt`, `snapshotID`, `nasVerified: true`, and uses the
separate `RECOVERY_DATABASE_URL`. These are a proposed verifier-to-app contract,
**not** a claim that existing Herman `recovery.py` emits that format. Inspect its
actual NAS verification output and wire/test the adapter before enabling writes.
Never substitute backup completion time or a local-only backup status. Never
refresh the lease from the API clock without a newly verified NAS snapshot.

The notification spool retains verified signed payloads even while the database
is fenced, but the endpoint returns 503 until processing commits. Apple retains
its retry responsibility; no fenced delivery is acknowledged as successfully
processed. Replays are idempotent and event ordering prevents older grants from
replacing newer revocations, including equal-time revocation precedence.

Prove a full-sized restore including keys/config/spool, immutable image retrieval,
Postgres/API/sync rebuild, and native acceptance in under four hours. Prove no
more than 15 minutes of committed data loss under backup failure. Current local
lease tests and tiny source fixtures are not that proof. Independent off-host key
retrieval, FileVault unlock, GUI login/Colima and operator availability remain
gates; do not rely only on the host-local age identity.

## Identity and JWT contract

The native app uses an opaque Better Auth bearer session. Configure
`APPLE_ENVIRONMENTS=Production,Sandbox` to retain production and TestFlight
verification; each JWS environment must be signed and explicitly allowed. Local
StoreKit Xcode payloads are never accepted by the API. Apple native tokens
are verified by Better Auth against Apple's keys, issuer, bundle audience and
nonce. Google uses Better Auth's server OAuth state, plus a random two-minute
single-use code bound to the native SHA-256 proof key; no session token travels
in a custom-scheme URL. Account auto-linking is disabled. Imported provider
subjects bind to their original UUID rather than merging accounts by email.

`/api/auth/token` signs a five-minute JWT: `sub` is the original account UUID,
`iss` is the exact `BETTER_AUTH_URL`, and `aud` the exact public `POWERSYNC_URL`.
PowerSync trusts only this app's `/api/auth/jwks` key set and the configured
single audience. Never reuse signing keys across apps. JWKS private keys and
Better Auth secret must be recovered together. API URLs must use HTTPS in
production; local HTTP is for isolated tests only.

## Source export/import/reconciliation

Read-only consistent source export:

```sh
MIGRATION_DATABASE_URL=... bun scripts/source-migration.ts export /protected/source.json
```

The file is created exclusively with mode 0600, contains password hashes and
identity metadata, and must never enter git, logs or PR attachments. Encrypt it
for transfer/storage. Export uses a repeatable-read snapshot and includes all
nine domain tables, user UUIDs/passwords and raw identity records. Final export
requires an operator-proven fence and drained transactions on every old mutation
path. This command alone does not fence the source.

Target dry-run and apply (owner credential, writes disabled, fresh recovery proof):

```sh
MIGRATION_DATABASE_URL=... bun scripts/source-migration.ts import /protected/source.json
EXPECTED_SNAPSHOT_SHA256=<reviewed-export-fingerprint> MIGRATION_DATABASE_URL=... bun scripts/source-migration.ts import /protected/source.json --apply
```

Import locks an empty target, suppresses quota/timestamp triggers only inside the
restore transaction, preserves all domain columns, reconciles complete row
fingerprints, restores triggers, rechecks the lease and commits only on `--apply`.
Repeat application refuses a nonempty target. Auth archives are private and
cascade on account deletion. Existing bcrypt hashes remain valid; email/password
verification state and Apple/Google subjects keep original user UUIDs. Unexpected
anonymous/deleted/banned accounts or unsupported providers/hashes fail closed for
explicit policy resolution; no source accounts are silently omitted.

Nonempty source object storage currently blocks import. The current native schema
has no persisted object references, but actual source inventory has not been
available: if it contains objects, implement and reconcile bytes, ACLs, metadata
and URL references before cutover. Do not waive this gate or claim zero files.
Likewise, unknown source columns/schema drift abort rather than dropping data.

## Cutover and rollback

Before starting the at-most-one-hour planned downtime, establish live project
IDs/config, source row/file sizes, actual bundled URLs, OAuth provider settings,
Apple notification endpoints, Brevo sender delivery, capacity and key recovery.
Make the tested native release available. Old binaries cannot be assumed to show
an upgrade message or follow new URLs.

Fence every old writer (auth, API, upload, entitlement callbacks/background jobs),
drain transactions, final-export, import and reconcile all rows/permissions/quota
and ledger state. Retain and replay signed notifications across the switch.
Coordinate callback/provider settings and bundled URLs; validate immutable image
health, fresh lease, sync, sign-in, subscriptions and offline-upgrade recovery.
Record downtime and the exact first target-write boundary, then obtain Kyle's
actual native smoke test. Do not migrate another app in this work.

Before any target-only writes, restore the old authority only after proving none
exist. After target writes, an image or endpoint rollback alone loses data: reconcile
new accounts/writes/tombstones/files/entitlements or repair forward. Keep the old
Supabase fenced for 14 days; deleting it requires explicit approval.
