# Diald

Native iOS 17+ SwiftUI app for coffee beans, recipes, extractions, tasting notes,
local reminders, on-device analysis and brew statistics, with an Astro marketing
site. StoreKit provides the Supporter subscription. Free accounts get five
lifetime extractions, including deleted brews.

The backend is a Bun/TypeScript API with PostgreSQL/Drizzle, Better Auth/Brevo and
self-hosted PowerSync, running on Herman's shared PostgreSQL server (`Backend/`).
The API is served at `auth.diald.club` and PowerSync at `sync.diald.club`.

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
Keychain. The API issues short-lived JWTs for PowerSync; the user UUID is the
JWT subject, the StoreKit `appAccountToken` and the owner of all user data.

The app opens `diald-v2.sqlite` directly for offline reads, writes and sync.
Reauthentication preserves its queue and requires the same account. Explicit
sign-out and account deletion clear the active database and its pending writes.

Apple JWS verification retains the official server library and bundled Apple
roots, exact product/bundle/environment/account binding, expiry, revocation and
signed-event ordering. Server-backed access stays verifying until confirmation.
App Store Server Notifications are retained in a private durable spool; fenced
delivery returns 503 so Apple also continues retrying. A background worker
replays retained signed payloads once writes are allowed again.

## Deployment

Merging to `main` releases each changed area:

- **Backend** (`Backend/`): `release-backend.yml` builds and attests the API
  image and sends a signed request through Cloudflare Access to the receiver in
  `Backend/deploy/app.json` (`deployURL`). On Herman, deploy-core:
  1. verifies provenance and backs up the database;
  2. requires a fresh off-host recovery proof;
  3. runs migrations;
  4. installs the image's Compose files, PowerSync configuration and inventory;
  5. starts the API and PowerSync, rolling back on failure.

  See [Backend/deploy/README.md](Backend/deploy/README.md) and deploy-core's
  `docs/shared-backends.md`.
- **Site** (`Site/`): `release-site.yml`; see [Site/README.md](Site/README.md).
- **iOS app**: `ios-testflight.yml` archives and uploads to TestFlight.

The `production` environment holds `API_CF_ACCESS_CLIENT_ID`,
`API_CF_ACCESS_CLIENT_SECRET` and `API_DEPLOY_WEBHOOK_SECRET` for the API, and
`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` and `DEPLOY_WEBHOOK_SECRET` for
the site. `API_BASE_URL` is checked after each API deploy.
