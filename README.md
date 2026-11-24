# Diald

Native iOS 17+ SwiftUI app for coffee beans, recipes, extractions, tasting notes,
local reminders, on-device analysis and brew statistics, with an Astro marketing
site at **diald.club**. StoreKit provides the Supporter subscription. Free
accounts get five lifetime extractions, including deleted brews.

## Features

- Email/password, Sign in with Apple and Google sign-in (Better Auth on the Herman API)
- Offline-first SQLite mirrored to PostgreSQL on Herman through self-hosted PowerSync
- Beans with roast details, and brews with recipe, grind, extraction timer and tasting notes
- Today dashboard and brew statistics
- On-device brew analysis (Apple Foundation Models where available, with a deterministic local report everywhere); brew data never leaves the device
- Recurring local brew reminders
- Home Screen widgets (quick actions and dashboard) and App Shortcuts to log a brew or start the timer
- Supporter subscription for unlimited extractions
- Light / Dark / System appearance
- Account deletion
- Error reporting through Sentry (optional)

## Stack

| Concern       | Tool                                                                   |
| ------------- | ---------------------------------------------------------------------- |
| UI            | SwiftUI, iOS 17+, WidgetKit, AppIntents                                |
| Backend       | Bun/TypeScript API in `Backend/` with PostgreSQL/Drizzle on Herman     |
| Sync          | [PowerSync Swift SDK](https://github.com/powersync-ja/powersync-swift) |
| Auth          | Better Auth (email, Sign in with Apple, Google), Brevo email           |
| Subscriptions | StoreKit 2, verified server-side with Apple's server library           |
| Push          | APNs through the API or the shared push gateway (`docs/push-gateway.md`) |
| Analysis      | On-device only (Foundation Models)                                     |
| Error logging | `sentry-cocoa`                                                         |
| Project gen   | [XcodeGen](https://github.com/yonaskolb/XcodeGen)                      |

## Repo layout

Every iOS app shares this layout; [Scripts/SHARED_IOS_CORE.md](Scripts/SHARED_IOS_CORE.md)
is the reference.

```
Diald/
  App/             entry point, AppServices, AppSecrets, AppDelegate, routing
  Auth/            AuthClient, APIClient, sign-in views, Apple + Google flows
  Analysis/        on-device brew analysis
  Beans/           beans list and repository
  Billing/         StoreKit repository, access state, paywall
  Brews/           add/edit brew, extraction timer, repository
  Components/      Theme, Theme+App, Card, PrimaryButton, LoadingView, Lottie
  Dashboard/       Today tab
  Extensions/      Foundation helpers
  Intents/         AppIntents and App Shortcuts
  Logging/         OSLog/Sentry wrapper
  Models/          Bean, BrewSession, BrewStats, Profile
  Notifications/   shared push core, reminders and APNs registration
  Resources/       assets, Diald.icon, animations, StoreKit configuration
  Settings/        settings, appearance, profile repository
  Stats/           aggregates and charts
  Sync/            PowerSync schema, manager, connector, sync issues
  Widgets/         widget snapshot store (shared with the extension)
DialdTests/         unit tests
DialdWidgets/       WidgetKit extension

Backend/            Bun API, Drizzle migrations, PowerSync config, Herman deploy
Site/               Astro marketing, support and legal site
Config/             Secrets.xcconfig.example
Scripts/            shared-code checks, CI export options
docs/               push gateway contract
```

## Getting started

```sh
./setup.sh
```

The script checks for Homebrew, XcodeGen and the pinned Bun (1.4.4), copies
`Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` if it doesn't
exist, installs the backend dependencies and generates `Diald.xcodeproj`. It
never touches a production backend.

Fill in `Config/Secrets.xcconfig`:

- `API_URL`: the Diald API origin (`https://auth.diald.club`).
- `POWERSYNC_URL`: the PowerSync origin (`https://sync.diald.club`).
- `PUSH_GATEWAY_URL`: optional; leave blank to register devices with the API.
- `SENTRY_DSN`: optional; leave blank to disable Sentry.

Escape URL slashes as `https:/$()/...` in xcconfig. The example's placeholders
build fine but show configuration errors instead of signing in or syncing.

`Diald.xcodeproj` is git-ignored: run `xcodegen generate` after changing
sources, targets, signing or dependencies, then open it and press ⌘R.

## Development

```sh
xcodebuild build -project Diald.xcodeproj -scheme Diald -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Diald.xcodeproj -scheme Diald \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Backend checks (see [Backend/deploy/README.md](Backend/deploy/README.md)):

```sh
cd Backend
bun install --frozen-lockfile
bun run typecheck
bun run lint
bun run format:check
TEST_DATABASE_URL=postgresql://.../disposable_database bun test
bun run build
```

Integration tests migrate and truncate the named test database and create/drop
additional disposable fixture databases. Never use a production URL.

The site runs with `bun run dev`, `bun run build` and `bun run preview` from the
repository root; see [Site/README.md](Site/README.md) for its checks.

## Apple setup

Running on a device or shipping needs Apple Developer access:

1. App IDs `club.diald` (Sign in with Apple, Push Notifications, App Groups) and
   `club.diald.widgets` (App Groups), both in app group `group.club.diald`.
2. App Store provisioning profiles named **Diald App Store** and **Diald Widgets
   App Store** (the names in `project.yml`).
3. An auto-renewable subscription `club.diald.supporter.monthly`. The committed
   `Diald/Resources/StoreKit/Diald.storekit` serves simulator builds; App Store
   Connect is authoritative for TestFlight and production.
4. App Store Server Notifications V2 pointed at the API's
   `/api/iap/notifications`.
5. Sign in with Apple and Google credentials in the API's protected `api.env` on
   Herman (`Backend/deploy/api.env.example` lists them). The native redirect is
   `diald://auth-callback`.

## Releasing

Merging to `main` releases each changed area.

### Backend

`release-backend.yml` repeats the backend checks, builds and attests the API
image and sends a signed request through Cloudflare Access to the receiver in
`Backend/deploy/app.json` (`deployURL`). On Herman, deploy-core:

1. verifies provenance and backs up the database;
2. requires a fresh off-host recovery proof;
3. runs migrations;
4. installs the image's Compose files, PowerSync configuration and inventory;
5. starts the API and PowerSync, rolling back on failure.

See [Backend/deploy/README.md](Backend/deploy/README.md) and deploy-core's
`docs/shared-backends.md`.

| Setting | Kind | Purpose |
|---|---|---|
| `API_BASE_URL` | repository variable | Public API origin checked after a deploy |
| `API_CF_ACCESS_CLIENT_ID`, `API_CF_ACCESS_CLIENT_SECRET` | `production` secrets | Access service token for the API deploy hostname |
| `API_DEPLOY_WEBHOOK_SECRET` | `production` secret | HMAC key for API deploy requests |

### Site

`release-site.yml` repeats the site checks, publishes an attested image to
`ghcr.io/kylescudder/dialdclub-site` and asks Herman to deploy that digest. See
[Site/README.md](Site/README.md).

| Setting | Kind | Purpose |
|---|---|---|
| `DEPLOY_HOST` | repository variable | Herman deploy hostname, protected by Cloudflare Access |
| `SITE_BASE_URL` | repository variable | Public origin checked for the new revision |
| `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` | `production` secrets | Access service token for the deploy hostname |
| `DEPLOY_WEBHOOK_SECRET` | `production` secret | HMAC key for deploy requests |

### iOS app

`ios-testflight.yml` runs when the app, widgets, `project.yml`, the secrets
example or `Scripts/ci/` change on `main`. It checks that the release API and
PowerSync endpoints are ready, archives with manual signing, checks the archived
configuration and uploads to TestFlight. Run it manually with a delivery UUID to
wait for Apple's processing of an earlier upload.

| Setting | Kind | Purpose |
|---|---|---|
| `API_BASE_URL`, `POWERSYNC_BASE_URL` | repository variables | Release origins written into the build |
| `IOS_SECRETS_XCCONFIG` | secret | Release `Secrets.xcconfig` (the origins above replace its URLs) |
| `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8` | secrets | App Store Connect API key for upload |
| `APPLE_TEAM_ID` | secret | Development team written into `project.yml` |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64`, `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`, `IOS_KEYCHAIN_PASSWORD` | secrets | Distribution certificate and temporary keychain |
| `IOS_DIALD_PROFILE_BASE64`, `IOS_DIALD_WIDGETS_PROFILE_BASE64` | secrets | The two App Store provisioning profiles |

## Shared code

Complimentary billing access follows `Scripts/SHARED_IOS_CORE.md`; see
`docs/complimentary-access.md` for the administrator grant and revoke procedure.

Diald keeps five sets of files byte-for-byte identical with the other iOS apps.
CI fails if any of them drift:

| Check | Covers |
|---|---|
| `Scripts/check-shared-ios-core.sh` | App scaffolding, shared UI primitives, the billing and sync cores, `setup.sh`, iOS workflows ([SHARED_IOS_CORE.md](Scripts/SHARED_IOS_CORE.md)) |
| `Scripts/check-shared-auth.sh` | Better Auth backend and native auth ([SHARED_AUTH.md](Scripts/SHARED_AUTH.md)) |
| `Scripts/check-shared-push-core.sh` | Push registration core ([SHARED_PUSH_CORE.md](Scripts/SHARED_PUSH_CORE.md)) |
| `Scripts/check-shared-infra.sh` | Backend deployment and provisioning ([SHARED_INFRA.md](Scripts/SHARED_INFRA.md)) |
| `Scripts/check-shared-site.sh` | Astro site layout, tooling, image and site workflows ([SHARED_SITE.md](Scripts/SHARED_SITE.md)) |

## Development notes

Each account keeps a separate local database and upload queue. Signing out retains offline changes on this device; signing back in resumes them. Choose **Sign out and remove local data** to discard that account’s local changes explicitly. A fresh sign-in requires connectivity.

[AGENTS.md](AGENTS.md) describes the architecture in detail. In short:

- `AppServices` owns the long-lived services and repositories; views read it with `@EnvironmentObject`.
- Repositories read local SQLite through `database.watch` and write locally; PowerSync uploads through `APIConnector`.
- Deletions are soft (`deleted_at`) and UUIDs are lowercased everywhere.
- Brew analysis stays on the device. Changing that is a privacy change and needs the privacy policy updated first.
