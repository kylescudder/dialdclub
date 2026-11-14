# Verification and open release gates

Source: `t3/diald-cutover-app-changes`, originating at
`448597a6aec61b64570ab9cde67dec94739c2713`; original unpublished skeleton preserved
from `codex/self-hosted-backend` without modifying its checkout. Implementation
and evidence date: 14 November 2026. The PR head and ignored evidence manifest
record the final revision; local image verification is distinct from a main-built
GHCR release with workflow provenance.

## Passed locally

- Bun 1.4.4 frozen install, TypeScript, ESLint, Prettier and API bundle build.
- 18 PostgreSQL 18.6 integration tests: verified password/bearer signup/sign-in;
  unauthenticated denial; owner isolation; concurrent lifetime quota/idempotent
  replay; tombstone and historical hard-deleted UUID handling; missing/stale/
  future/failed proof; runtime cannot refresh recovery proof or forge quota;
  COMMIT-time lease expiry rollback; bcrypt and single-use password reset;
  unsafe callback refusal; JWT signature/original UUID/issuer/audience/lifetime;
  proof-bound one-use native codes; forged Apple rejection; account deletion
  isolation; email budgets; entitlement revocation/ordering/expiry; consistent
  source restore preserving identities and full domain fingerprints.
- Source fixture export, target dry-run, target import, full-row reconciliation,
  UUID/password/Apple/Google subject preservation, and historical replay refusal.
  Nonempty object storage fails closed rather than silently losing files.
- ARM64 API image built, non-root/read-only with empty capabilities, restricted
  runtime database login, four-connection pool; API readiness/JWKS passed.
- PowerSync 1.28.3 pinned digest, non-root/read-only, scoped replication login and
  separate PostgreSQL storage login: five-table initial replication and readiness.
- Real SQLite SDK smoke: close/reopen an offline queue, strict API replay,
  separate target database/fresh checkpoint, uploaded row present and another
  account's sync excludes it. This uses the Node SDK through Bun with SQLite;
  it is **not** execution of the Swift migration code.
- `xcodebuild build` and `build-for-testing`, unsigned generic iOS Simulator,
  Xcode 27.2. The new Swift offline-upgrade/ambiguous-owner tests compile.
  CI on `66ec324` also ran the 14-test native suite: 12 passed, and the two new
  tests failed during Keychain cleanup in the unsigned test host, before their
  assertions. Tests now use an injected session store and private preferences
  suite while keeping real PowerSync SQLite. Production defaults retain the
  Keychain and its error handling. Runtime recheck is pending.
- Astro production build/format check and workflow `actionlint`/shell syntax.
- Production-built privacy page in T3 browser at 1280×900 and 390×844: new
  provider/retention copy present, no horizontal overflow, no console errors.
  Saved desktop/mobile screenshots inspected. These are web, not native evidence.

Local idle sample: API 45.09 MiB, PowerSync 134.9 MiB; sync fixture storage 8398 kB.
These are tiny local fixtures on Forge, not production capacity/RPO/RTO proof.
Candidate caps total 768 MiB for API+sync before PostgreSQL/overheads. The audited
Herman VM had only about 781 MiB available, so deployment is **not** capacity-cleared.

## Reproduce backend verification

Use Bun 1.4.4. The database URL must be disposable and have permission to create
additional fixture databases. Tests migrate/truncate it. Never use live data.

```sh
cd Backend
bun install --frozen-lockfile
bun run typecheck
bun run lint
bun run format:check
TEST_DATABASE_URL=postgresql://.../disposable_test bun test
bun run build
```

For the optional self-hosted sync smoke, run the checked image, PostgreSQL 18.6
with logical WAL, and pinned PowerSync service using the candidate config in an
isolated Docker network. Seed the verified owner/other fixtures via `bun test`.
Test-only loopback published ports are acceptable locally; the host candidate
publishes none. Provide `TEST_DATABASE_URL`, `TEST_API_URL`, `TEST_SYNC_URL` and,
on macOS, `POWERSYNC_SQLITE_LIBRARY` pointing to Homebrew's full SQLite dylib:

```sh
bun scripts/verification/sync-smoke.ts
```

The script uses temporary SQLite files and prints only result flags. Test-only
source identities and credentials must not be reused for deployment. Supporting
logs are in ignored `Backend/artifacts/` and `DerivedData/cutover-evidence/`.

## Not yet verified / genuine gates

- T3 device discovery timed out: `xcrun simctl list devices --json` did not respond
  within 30 seconds. Open returned `No ios devices were found on host local`.
  Xcode reported the CoreSimulator service older than its installed build.
  Local native test execution and screenshots remain unavailable. CI native
  test execution is reported above; no successful native OAuth, purchase/restore,
  or Swift offline-upgrade/persistence result is claimed until its recheck passes.
- SSH to `kyle@herman.local` returned `Permission denied`; the secure credential
  request timed out. The separate source PostgreSQL URL request also timed out. Actual runbook/skills/recovery.py output, current capacity,
  private settings and installed deploy-core release were not re-audited. The
  backup-verifier adapter and central hooks/receiver installation are pending.
- Source production database/object inventory, user/provider policy edge cases,
  final fence, export/import/reconciliation and actual source-volume restore.
  Nonempty files require byte/metadata/ACL/URL migration before import can pass.
- Live Apple/Google provider configuration, Brevo authenticated sender and actual
  delivery, genuine Apple signed transaction/notification acceptance. Cryptographic
  negative tests do not prove a real purchase or OAuth round trip.
- Main-built immutable GHCR image/workflow provenance, reviewed central release,
  PowerSync production version/license, scoped publication/slot/storage budget,
  and app-specific receiver installation. Nothing was deployed on Herman.
- Independently recoverable keys, full-sized <4-hour service restore including
  sync/API/images/keys and native acceptance; <=15-minute committed-loss proof.
- Native release availability, old-binary writer fence, callback/notification
  coordination, <=1-hour downtime record and Kyle's actual native smoke test.

Keep the PR a draft until these implementation/acceptance gaps are resolved.
Never describe the migration or production cutover as complete from this evidence.
