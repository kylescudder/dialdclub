# Diald

Native iOS 17+ SwiftUI app for coffee beans, recipes, extractions, tasting notes,
local reminders, on-device analysis and brew statistics, with an Astro marketing
site. StoreKit provides the Supporter subscription. Free accounts get five
lifetime extractions, including deleted brews.

This branch prepares the direct replacement of Supabase with a Bun/TypeScript
API, PostgreSQL/Drizzle, Better Auth/Brevo and self-hosted PowerSync. It has **not
cut production over**. The old `supabase/` directory remains source-migration and
rollback evidence; the new app does not import its SDK or call its endpoints.

## Development

Use Bun 1.4.4 throughout. `./setup.sh` installs backend dependencies, preserves
existing local secrets, and generates the Xcode project on macOS.

For iOS, copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` and
configure `API_URL`, `POWERSYNC_URL`, and optional `SENTRY_DSN`. Escape URL slashes
as `https:/$()/...` in xcconfig. Regenerate with `xcodegen generate`, then open
`Diald.xcodeproj`. Example endpoints deliberately show configuration errors.

```sh
xcodebuild build -project Diald.xcodeproj -scheme Diald -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
cd Backend
bun install --frozen-lockfile
bun run typecheck
bun run lint
bun run format:check
TEST_DATABASE_URL=postgresql://.../disposable_database bun test
```

Integration tests migrate and truncate the named test database and create/drop
additional disposable fixture databases. Never use a production URL.

The static site still uses `bun run dev`, `bun run build`, and `bun run preview`
from the repository root, or its own scripts under `Site/`.

## Authentication, sync and subscriptions

Public signup supports verified email/password, native Sign in with Apple and
Google through `ASWebAuthenticationSession`. Native sessions are stored in the
Keychain. The API issues short-lived JWTs for PowerSync; user UUIDs remain the
original IDs used by StoreKit `appAccountToken` and all owner data.

Repositories retain local SQLite reads and writes. Migration reauthentication
preserves the old cache and queue and rejects a different account. Legacy queues
replay through the new owner-scoped API, then a separate SQLite database performs
a fresh first sync. The app switches databases only after that staging succeeds;
old service checkpoints are never reused on the new service. Explicit sign-out
and account deletion clear both databases and pending writes.

Apple JWS verification retains the official server library and bundled Apple
roots, exact product/bundle/environment/account binding, expiry, revocation and
signed-event ordering. Server-backed access stays verifying until confirmation.
Notifications are retained in a private durable spool; fenced delivery returns
503 so Apple also continues retrying. The background worker reconciles retained
signed payloads after recovery proof and imported accounts are available.

## Deployment and migration

See [Backend/deploy/README.md](Backend/deploy/README.md) for the deployment
candidate, recovery lease contract, export/import/reconciliation, JWT contract,
resource limits, and cutover/rollback gates. See
[Backend/deploy/verification.md](Backend/deploy/verification.md) for evidence and
remaining access/device gaps. Main CI publishes an attested image; this branch
has no automatic production deployment. Never route old binaries to an unfinished
API or use Settings sign-out to reauthenticate during migration.
