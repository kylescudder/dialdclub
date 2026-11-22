# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Project

Diald Club — native iOS 17+ SwiftUI app for recording specialty-coffee beans, recipes, extraction times, tasting notes, reminders, and brew statistics, plus a static Astro marketing and compliance site. The backend is the Bun API in `Backend/` with PostgreSQL and self-hosted PowerSync on Herman, StoreKit provides the Supporter subscription, and the app includes AppIntents and WidgetKit extensions.

## Shared conventions

Every iOS app uses the same repository layout, app scaffolding and CI. Read
`Scripts/SHARED_IOS_CORE.md` before adding folders, shared UI primitives,
configuration keys or workflows. Five checksum manifests keep shared files
byte-for-byte identical with the other apps, and CI runs all of them:

- `Scripts/check-shared-ios-core.sh` — `AppSecrets`, `AppBootstrap`, `Theme`, `LoadingView`, `LottieAnimationView`, `PrimaryButton`, `Logger`, `AppearanceManager`, `SharedAppSecretsTests`, `setup.sh` and the iOS workflows.
- `Scripts/check-shared-auth.sh` — Better Auth backend and native auth (`SHARED_AUTH.md`).
- `Scripts/check-shared-push-core.sh` — push registration core (`SHARED_PUSH_CORE.md`).
- `Scripts/check-shared-infra.sh` — backend deployment and provisioning (`SHARED_INFRA.md`).
- `Scripts/check-shared-site.sh` — the `Site/` layout, tooling, image and site workflows (`SHARED_SITE.md`).

Never edit a shared file in one app only. Put app-specific values behind the
hooks listed in `SHARED_IOS_CORE.md` (`Theme+App.swift`, `AuthAppConfiguration`,
`project.yml`, `Scripts/setup-extras.sh`), or make the same change in every app
and refresh the manifest with `sh Scripts/check-shared-ios-core.sh --write`.

## Common commands

The Xcode project is generated from `project.yml` and is git-ignored — regenerate after any source, target, signing, or dependency change.

```sh
xcodegen generate                          # rebuild Diald.xcodeproj from project.yml
open Diald.xcodeproj                       # open in Xcode (⌘R to run, ⌘B to build)
xcodebuild build \                         # CLI sanity build (no signing required)
  -project Diald.xcodeproj \
  -scheme Diald \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Diald.xcodeproj -scheme Diald -destination 'platform=iOS Simulator,name=iPhone 16'
./setup.sh                                 # first-run tools, secrets template, backend deps, xcodegen
```

Marketing site:

```sh
bun run dev                                # installs Site dependencies and starts Astro
bun run build                              # builds the static site to Site/dist
bun run preview                            # previews the production build
cd Site && bun run format:check            # check Astro/CSS formatting with Prettier
```

`DialdTests` contains focused subscription/quota behavior tests; `Shared*Tests.swift` are identical in every app. There is no iOS linter or formatter configured. The Astro site has `format` and `format:check` scripts under `Site/package.json`; don't invent additional validation commands.

## Backend

Production runs on Herman. The runtime is `Backend/` (Bun 1.4.4, TypeScript,
PostgreSQL/Drizzle, Better Auth, Brevo and self-hosted PowerSync) on Herman's
shared PostgreSQL server. Read `Backend/deploy/README.md` before release work.
Merging a `Backend/` change to `main` releases the API, migrations, Compose files
and PowerSync config together through deploy-core.

- Native builds require `API_URL`, `POWERSYNC_URL`, optional `SENTRY_DSN`.
- `AuthClient` uses `APIClient` and a Keychain session, binds cached data to the
  original UUID, and preserves SQLite/queues for reauthentication. Settings
  sign-out and reset-password success clear local data; never use them as a
  silent reauthentication path.
- `APIConnector` is the upload boundary. Restricted runtime transactions enforce
  owner RLS, lifetime quota, durable UUID replay rules and tombstones.
- The app opens `diald-v2.sqlite` directly. Explicit sign-out clears that database.
- JWT `sub` is the original UUID, issuer is `BETTER_AUTH_URL`, audience is the
  exact public `POWERSYNC_URL`. Sync config is `Backend/deploy/powersync/`.
- Drizzle migrations are under `Backend/drizzle/`. All authoritative tables have
  statement and deferred COMMIT recovery guards; the API cannot refresh the lease.
- Verified IAP endpoints are `/api/iap/transactions` and `/api/iap/notifications`.
  Cryptographic Apple verification is in `Backend/src/apple-verification.ts`.

Backend checks: `cd Backend && bun install --frozen-lockfile`, `bun run typecheck`,
`bun run lint`, `bun run format:check`, `TEST_DATABASE_URL=... bun test`,
`bun run build`. Tests require a disposable PostgreSQL database and create/drop
additional fixture databases. Never point them at production. Native runtime and
screenshots require a functioning simulator; build-only checks are not flow proof.

## Push notifications

Before changing push registration, APNs delivery, `device_tokens` or notification
producers, read `docs/push-gateway.md` and keep its provider-neutral HTTP contract
identical across all application repositories.

## Secrets and configuration

- iOS build values live in `Config/Secrets.xcconfig` (git-ignored, copied from `Config/Secrets.xcconfig.example`) and flow through generated `Info.plist` properties into `Diald/App/AppSecrets.swift`. **xcconfig escaping gotcha**: write a URL such as `https://…` as `https:/$()/…`, otherwise `//` starts a comment. `API_URL` is required for auth and the API, `POWERSYNC_URL` is required for data sync, and an empty `SENTRY_DSN` intentionally disables Sentry.
- `AppSecrets` detects empty, unresolved, and placeholder API and PowerSync values. Keep those graceful configuration-error paths intact; simulator and pull-request builds deliberately use the example xcconfig.
- Brew analysis is fully local and does not use provider API keys or build secrets. Do not add provider credentials to source, xcconfig, logs, the database, or the widget app group.
- Backend secrets (database URLs, Better Auth, Brevo, Apple sign-in and IAP verification) live in the API's protected `api.env` on Herman; `Backend/deploy/api.env.example` lists them.
- The committed `Diald/Resources/StoreKit/Diald.storekit` supplies simulator product data. App Store Connect remains authoritative for TestFlight and production product `club.diald.supporter.monthly`.

## Architecture

### iOS app composition

- `DialdApp` creates one `@StateObject AppServices`, injects it with `environmentObject`, installs `AppDelegate` for APNs registration callbacks, applies the saved appearance, and configures Sentry through `AppBootstrap`.
- `AppServices` (`Diald/App/AppServices.swift`) is the composition root. It owns `AuthClient`, `PowerSyncManager`, `SyncIssueStore`, `BillingRepository`, `BeansRepository`, `BrewsRepository`, `StatsRepository`, `NotificationManager`, `ProfileRepository`, and `AnalysisClient`. It re-broadcasts each child's `objectWillChange`, so views can observe the single environment object.
- `RootView` switches on auth state (`.unknown` / `.signedOut` / `.signedIn`) and handles password-recovery presentation and incoming URLs. The signed-in `MainTabView` is Today / Beans / Stats / Analyse / Settings.
- On sign-in, `AppServices.applyAuth` starts local database watches, synchronizes StoreKit entitlements, refreshes local snapshots, registers APNs, and refreshes reminders. Subscription state is `.active` only after both local StoreKit verification and server confirmation succeed; mirror delays remain `.verifying`. On sign-out it stops watches and resets in-memory subscription state.
- New brew creation must continue through `AppServices.canCreateNewExtraction()`: non-subscribers may create five lifetime extractions, including deleted records, while edits remain allowed. It prefers the API's `/api/extractions/status` (backed by `get_extraction_creation_status`) and falls back offline to synced quota/entitlement rows plus the device-only pending ledger. The insert trigger remains the transactional authority.

### Data access and PowerSync

- Local SQLite schema is declared in `Diald/Sync/DatabaseSchema.swift`. `PowerSyncManager` connects with a short-lived JWT from the API's `/api/auth/token`, disconnects without clearing on transient signed-out auth state, and wipes local user data plus pending uploads only after explicit sign-out, password-reset sign-out, or account deletion.
- `BeansRepository`, `BrewsRepository`, `ProfileRepository`, and `StatsRepository` read through `database.watch` and write locally through PowerSync. `APIConnector` is the only generic upload path (`/api/sync/upload`). Quota status, IAP mirroring, auth, APNs device registration, and account deletion are deliberate direct API calls (`/api/extractions/status`, `/api/iap/transactions`, `/api/auth/*`, `/api/devices`, `/api/account`).
- PowerSync tables are SQLite views, so use plain parameterized inserts/updates rather than Postgres `ON CONFLICT` SQL locally. Brew uploads use plain server inserts: retrying them via upsert would re-run the quota `BEFORE INSERT` trigger. A duplicate retry is accepted only after verifying that the same brew UUID already exists server-side.
- Known permanent Postgres validation failures are acknowledged and surfaced through `SyncIssueStore`, allowing PowerSync to restore server state instead of blocking the queue forever. Transient/network failures must throw so PowerSync retries them. Do not broaden permanent-error classification without proving the error cannot succeed on retry.
- Sync rules are Edition 3 (`Backend/deploy/powersync/sync-config.yaml`). They sync profile, bean, and brew tombstones, plus read-only owner-scoped quota and verified-entitlement snapshots. `pending_extractions` is local-only and reserves allowance until the server quota stream confirms an accepted insertion.
- Postgres schema lives in ordered Drizzle migrations under `Backend/drizzle/`. `profiles`, `beans`, `brew_sessions`, `brew_steps`, `brew_reminders`, and `device_tokens` are user-owned and protected by RLS. `extraction_creation_quotas` is the protected monotonic counter, while `extraction_creation_events` is the durable per-extraction ledger. Clients read usage only through the security-definer `get_extraction_creation_status` function behind `/api/extractions/status`; PowerSync exposes only the authenticated user's quota snapshot. `iap_entitlements` is written only by the API's verified IAP paths through `record_verified_iap_entitlement`, and PowerSync exposes only the authenticated user's verified row.
- Beans and brew sessions use soft-delete tombstones (`deleted_at`); repository reads filter them out and delete actions set the timestamp. Keep new user-data deletion paths consistent unless a hard delete is explicitly required.
- UUID strings sent to the API are lowercased throughout. Preserve that convention. Swift model coding keys, Postgres columns, enum raw values, check constraints, API/function return shapes, and PowerSync rules must be updated together when a persisted field changes.
- Some backend schema is ahead of the client: `brew_steps` and server-side `brew_reminders` exist, but the current UI and PowerSync streams do not use them. Local reminders are stored on-device. Do not assume a table is wired merely because it appears in a migration or publication.

### Authentication and profiles

- `AuthClient` owns the single `APIClient` session and exposes the app's auth state. It supports email/password, native Sign in with Apple, Google through `ASWebAuthenticationSession`, email confirmation, password recovery, and account deletion (`DELETE /api/account`).
- All auth callbacks use the `diald://auth-callback` custom scheme and enter through `QuickActionRouter.handle(url:auth:)`. Recovery state has a one-hour `UserDefaults` fallback and callback handling suppresses duplicates within five seconds; preserve both when changing deep-link routing.
- The `handle_new_user` trigger creates a profile. Apple names are special: Apple normally provides a name only on the first authorization, so `fill_profile_display_name` fills an empty profile without overwriting a user-edited value.

### Subscriptions

- `BillingRepository` uses StoreKit 2 as the authority for whether Apple considers the local subscription active. It watches `Transaction.updates`, loads `club.diald.supporter.monthly`, and checks `Transaction.currentEntitlements`. Local verification moves server-backed access to `.verifying`; only successful server confirmation moves it to `.active`/`isSubscribed`.
- Purchase calls include the signed-in user UUID as `appAccountToken`. Verified transactions are mirrored to `/api/iap/transactions`; App Store Server Notifications V2 update the same `iap_entitlements` row through `/api/iap/notifications`.
- The entitlement row is authoritative only for server-backed database writes, and only when `verified_at`, the exact bundle/product/environment, current expiration, and non-revoked status were recorded by `record_verified_iap_entitlement`. Both API IAP paths use Apple's official server library and bundled Apple roots to verify the JWS certificate chain and signature before validating `bundleId`, environment, product ID, and mandatory `appAccountToken`. Never restore payload-only decoding or direct client writes. Keep purchase, restore, retry, manage-subscription, transaction finishing, and entitlement refresh paths aligned.
- The free limit is `AppServices.freeExtractionLimit == 5`. Migration `0006_enforce_free_extraction_limit.sql` locks `brew_sessions` across backfill and trigger installation, then seeds and atomically increments `extraction_creation_quotas` for every genuine insert, so soft or hard deletion never restores allowance. Reusing a historical hard-deleted `brew_session_id` is rejected by the durable event ledger as an explicit idempotency/safety rule. Any change to the limit or what constitutes an extraction must update the database trigger, status RPC, client gate, tests, and user-facing paywall copy together.

### Local brew analysis

- `AnalysisClient` filters already-loaded brew data and computes an evidence-led report entirely on-device. On supported devices it can use Apple's on-device Foundation Models framework to present the computed findings; every supported device retains the deterministic local report as a fallback.
- Analysis has no provider catalogue, remote inference adapter, API credentials, or server-side function. Keep it usable offline and do not send selected brew data over the network.
- Brew notes participate in local analysis only when `AnalysisFilters.includeNotes` is true. Treat any future change that transmits analysis inputs as privacy-affecting behavior and update `Site/src/pages/privacy.astro` before shipping it.

### Reminders and notifications

- `NotificationManager` is a `@MainActor` singleton. It owns authorization status, registers APNs tokens (with the API's `/api/devices`, or the shared push gateway when `PUSH_GATEWAY_URL` is set; see `docs/push-gateway.md`), and schedules recurring local notifications through `UNUserNotificationCenter`.
- The reminders shown in Settings are persisted as encoded `BrewReminderSchedule` values in `UserDefaults`, then expanded into one calendar trigger per weekday.
- `AppDelegate` only forwards APNs registration success/failure to `NotificationManager`. Keep UIKit delegate work at this boundary.
- Diald has no server-originated push producer yet. Brew reminders are local calendar notifications.

### Widgets, shortcuts, and deep links

- `DialdWidgets` contains a quick-action widget and a dashboard widget. The dashboard extension never calls the backend; `AppServices.publishWidgetSnapshot()` writes a Codable snapshot to app-group `UserDefaults` (`group.club.diald`) and reloads the `DialdDashboardWidget` timeline.
- Widget links use `diald://shortcut/logBrew` and `diald://shortcut/startTimer`. `QuickActionRouter` translates them into `NotificationCenter` events that `MainTabView` uses to present `AddBrewView`, optionally with the extraction timer already running.
- AppIntents route through the same `QuickActionRouter` and set `openAppWhenRun = true`. Keep widgets, AppIntents, URL path names, `AppQuickAction` raw values, and notification names synchronized.

### Marketing site

- `Site/` is a static Astro 7 site in the shared site layout (`Scripts/SHARED_SITE.md`). The shared `BaseLayout` owns global CSS, document metadata, header, and footer; the home page composes focused `Home*` section components, while privacy, terms, and support wrap their copy in the shared `LegalArticle`. Diald's values (name, origin, pages, contact) live in `Site/app.json`.
- The site has no runtime configuration or backend. Merging a `Site/` change to `main` builds an attested image and deploys it to Herman through deploy-core at the `DEPLOY_HOST` repository variable (`release-site.yml`).
- Legal and support copy is part of the product behavior contract. Update it whenever authentication providers, analytics/error reporting, subscriptions, AI data sharing, retention, or support contact behavior changes.

### Other notable wiring

- `Log` (`Diald/Logging/Logger.swift`) is the OSLog/Sentry wrapper. Sentry setup is a no-op when `SENTRY_DSN` is empty; keep repository and service errors going through `Log` rather than ad hoc prints.
- `Theme`, `Card`, `PrimaryButton`, and `LoadingView` under `Diald/Components/` are the UI primitives. Reuse them before introducing one-off colors, spacing, or loading treatments. Diald's brand colors (`amber`, `blue`) and loading animation live in `Theme+App.swift`; otherwise use the shared semantic colors (`textPrimary`, `textSecondary`, `accent`, `separator`).
- The app and widget must retain the same `group.club.diald` app-group entitlement. The main app additionally has Sign in with Apple and APNs entitlements.
- The app is iOS/iPadOS 17+, portrait-only on iPhone, and supports all standard orientations on iPad. `Info.plist` is committed (XcodeGen rewrites it with sorted keys); `project.yml` layers generated properties, secrets, URL schemes, and background modes onto it.
- GitHub Actions regenerates the Xcode project. Pull requests get an unsigned simulator build; pushes to `main` that touch iOS paths archive and upload to TestFlight using manual signing.

## Strict concurrency

`SWIFT_STRICT_CONCURRENCY: complete` is set in `project.yml`. Services and repositories are generally `@MainActor`, and notification delegate callbacks use `nonisolated` only where the protocol requires it. When introducing work across actor boundaries, use `Sendable` values and explicit actor hops; don't silence compiler findings with `@unchecked Sendable` without a concrete thread-safety justification.

## SDK drift

The dependency lower bounds live in `project.yml`; generated Xcode package state is not committed. Areas most likely to need coordinated changes after an update:

- **PowerSync Swift SDK** — local schema/view behavior, typed CRUD payloads, status streams, transaction APIs, and disconnect/clear semantics converge under `Diald/Sync/` and the local repositories. Re-test permanent rejection acknowledgement and quota-trigger retry idempotency after updates.
- **StoreKit 2** — `Product.purchase`, verification results, entitlement iteration, transaction JWS access, subscription management, and the committed StoreKit configuration must remain aligned with `BillingRepository`.
- **Swift strict concurrency / iOS SDKs** — `UNUserNotificationCenterDelegate`, `ASWebAuthenticationSession`, AppIntents, WidgetKit timelines, and UIKit callbacks can gain isolation requirements between toolchains.
- **Astro / Prettier** — site dependencies are pinned through `Site/bun.lock`; keep the lockfile with intentional updates and run both the production build and `format:check`.

When an SDK bump breaks compilation, check the dependency's release notes and update the shared abstraction rather than scattering compatibility workarounds across views.

## Folder casing

The app folders are `Diald/`, `DialdTests/` and `DialdWidgets/`, the marketing site is `Site/` (capital S), the backend is `Backend/`, and the only lowercase top-level folders are `docs/` and `deploy/`. Always preserve those spellings in code, scripts, workflow paths, and documentation so the repository works on case-sensitive filesystems.

## What not to commit

`Config/Secrets.xcconfig`, `.env*`, `Diald.xcodeproj/`, `build/`, `DerivedData/`, `.build/`, `.swiftpm/`, `Package.resolved`, `Site/node_modules/`, `Site/.astro/`, `Site/dist/`, or signing certificates/provisioning profiles. These are already git-ignored where applicable; don't add overrides.
