# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## Project

Diald Club — native iOS 17+ SwiftUI app for recording specialty-coffee beans, recipes, extraction times, tasting notes, reminders, and brew statistics, plus a static Astro marketing and compliance site. The backend is Supabase (Postgres + Auth + Edge Functions), StoreKit provides the Supporter subscription, and the app includes AppIntents and WidgetKit extensions.

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
./setup.sh                                 # first-run tools, secrets template, optional migrations, xcodegen
```

Supabase (CLI must be `supabase login`'d and `supabase link`'d):

```sh
supabase db push
supabase test db
deno test --allow-env --allow-net supabase/functions/_shared/apple_store_verification_test.ts
supabase functions deploy notify-brew-reminder
supabase functions deploy iap-sync-transaction
supabase functions deploy iap-app-store-notifications --no-verify-jwt
```

Marketing site:

```sh
bun run dev                                # installs Site dependencies and starts Astro
bun run build                              # builds the static site to Site/dist
bun run preview                            # previews the production build
cd Site && bun run format:check            # check Astro/CSS formatting with Prettier
```

`DialdTests` contains focused subscription/quota behavior tests. There is no iOS linter or formatter configured. The Astro site has `format` and `format:check` scripts under `Site/package.json`; don't invent additional validation commands.

## Secrets and configuration

- iOS build values live in `Config/Secrets.xcconfig` (git-ignored, copied from `Config/Secrets.xcconfig.example`) and flow through generated `Info.plist` properties into `Diald/App/AppSecrets.swift`. **xcconfig escaping gotcha**: write a URL such as `https://…` as `https:/$()/…`, otherwise `//` starts a comment. `SUPABASE_URL` and `SUPABASE_ANON_KEY` are required for auth; an empty `SENTRY_DSN` intentionally disables Sentry.
- `AppSecrets` detects empty, unresolved, and placeholder Supabase values. Keep that graceful signed-out/configuration-error path intact; simulator and pull-request builds deliberately use the example xcconfig.
- AI provider keys are user-entered runtime data, not build secrets. `AISettingsStore` stores OpenAI and Anthropic keys in the Keychain under service `club.diald.ai`; provider and model preferences live in `UserDefaults`. Never move keys into source, xcconfig, logs, Supabase, or the widget app group.
- Supabase Edge Functions require `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in the Supabase dashboard. The IAP verification functions also require the numeric App Store app ID as `APPLE_APP_ID`. The service-role key must never be shipped in either app target. TestFlight signing and the production xcconfig come from GitHub Actions secrets in `.github/workflows/ios-testflight.yml`.
- The committed `Diald/Resources/StoreKit/Diald.storekit` supplies simulator product data. App Store Connect remains authoritative for TestFlight and production product `club.diald.supporter.monthly`.

## Architecture

### iOS app composition

- `DialdApp` creates one `@StateObject AppServices`, injects it with `environmentObject`, installs `AppDelegate` for APNs registration callbacks, applies the saved appearance, and configures Sentry through `AppBootstrap`.
- `AppServices` (`Diald/App/AppServices.swift`) is the composition root. It owns `AuthClient`, `BillingRepository`, `BeansRepository`, `BrewsRepository`, `StatsRepository`, `NotificationManager`, `ProfileRepository`, `AISettingsStore`, and `AnalysisClient`. It re-broadcasts each child's `objectWillChange`, so views can observe the single environment object.
- `RootView` switches on auth state (`.unknown` / `.signedOut` / `.signedIn`) and handles password-recovery presentation and incoming URLs. The signed-in `MainTabView` is Today / Beans / Stats / Analyse / Settings.
- On sign-in, `AppServices.applyAuth` synchronizes StoreKit entitlements and calls `refreshAll`; that refreshes profile, beans, brews, stats, APNs registration, local reminders, and the widget snapshot. Subscription state is `.active` only after both local StoreKit verification and server confirmation succeed; mirror delays remain `.verifying`. On sign-out it resets the in-memory subscription state.
- New brew creation must continue through `AppServices.canCreateNewExtraction()`: non-subscribers may create five lifetime extractions, including deleted records, while edits remain allowed. The preflight reads `get_extraction_creation_status`; the insert trigger remains the transactional authority. Successful brew mutations should refresh brew data through `refreshBrewData()` so stats and WidgetKit stay in sync.

### Data access and the PowerSync boundary

- The app currently talks **directly to Supabase** through `AuthClient.supabase`. `BeansRepository` and `BrewsRepository` issue owner-scoped PostgREST queries and refresh after mutations; `StatsRepository` calls `get_brew_stats`; `ProfileRepository` reads and updates the current profile. There is no local SQLite database or PowerSync client wired into the iOS target.
- `supabase/powersync/sync_rules.yaml` is a future/offline-first ruleset only. Do not write new app code as if those buckets were active, and do not describe the current app as offline-first. If PowerSync is introduced, its schema, upload queue, auth lifecycle, and conflict behavior need an explicit implementation rather than repository call-site assumptions.
- Postgres schema lives in ordered files under `supabase/migrations/`. `profiles`, `beans`, `brew_sessions`, `brew_steps`, `brew_reminders`, and `device_tokens` are user-owned and protected by RLS. `extraction_creation_quotas` is the protected monotonic counter, while `extraction_creation_events` is the durable per-extraction ledger; clients can read usage only through a security-definer status RPC. `iap_entitlements` is readable only by its user and written by service-role Edge Functions through `record_verified_iap_entitlement`.
- Beans and brew sessions use soft-delete tombstones (`deleted_at`); repository reads filter them out and delete actions set the timestamp. Keep new user-data deletion paths consistent unless a hard delete is explicitly required.
- UUID strings sent to PostgREST are lowercased throughout. Preserve that convention. Swift model coding keys, Postgres columns, enum raw values, check constraints, RPC return shapes, and PowerSync rules must be updated together when a persisted field changes.
- Some backend schema is ahead of the client: `brew_steps` and server-side `brew_reminders` exist, but the current UI does not use them. Local reminders are stored on-device. Do not assume a table is wired merely because it appears in a migration or sync rule.

### Authentication and profiles

- `AuthClient` owns the single `SupabaseClient` and exposes the app's auth state. It supports email/password, native Sign in with Apple, Google through `ASWebAuthenticationSession`, email confirmation, password recovery, and the `delete_my_account` RPC.
- All auth callbacks use the `diald://auth-callback` custom scheme and enter through `QuickActionRouter.handle(url:auth:)`. Recovery state has a one-hour `UserDefaults` fallback and callback handling suppresses duplicates within five seconds; preserve both when changing deep-link routing.
- The `handle_new_user` trigger creates a profile. Apple names are special: Apple normally provides a name only on the first authorization, so `fill_profile_display_name` fills an empty profile without overwriting a user-edited value.

### Subscriptions

- `BillingRepository` uses StoreKit 2 as the authority for whether Apple considers the local subscription active. It watches `Transaction.updates`, loads `club.diald.supporter.monthly`, and checks `Transaction.currentEntitlements`. Local verification moves server-backed access to `.verifying`; only successful server confirmation moves it to `.active`/`isSubscribed`.
- Purchase calls include the signed-in Supabase user UUID as `appAccountToken`. Verified transactions are mirrored to `iap-sync-transaction`; App Store Server Notifications V2 can update the same `iap_entitlements` row through `iap-app-store-notifications`.
- The entitlement row is authoritative only for server-backed database writes, and only when `verified_at`, the exact bundle/product/environment, current expiration, and non-revoked status were recorded by the service-role RPC. Both IAP Edge Functions use Apple's official server library and bundled Apple roots to verify the JWS certificate chain and signature before validating `bundleId`, environment, product ID, and mandatory `appAccountToken`. Never restore payload-only decoding or direct client writes. Keep purchase, restore, retry, manage-subscription, transaction finishing, and entitlement refresh paths aligned.
- The free limit is `AppServices.freeExtractionLimit == 5`. Migration `0006_enforce_free_extraction_limit.sql` locks `brew_sessions` across backfill and trigger installation, then seeds and atomically increments `extraction_creation_quotas` for every genuine insert, so soft or hard deletion never restores allowance. Reusing a historical hard-deleted `brew_session_id` is rejected by the durable event ledger as an explicit idempotency/safety rule. Any change to the limit or what constitutes an extraction must update the database trigger, status RPC, client gate, tests, and user-facing paywall copy together.

### AI brew analysis

- `AnalysisClient` filters already-loaded brew data on-device, builds a text prompt, and calls either OpenAI Responses (`/v1/responses`) or Anthropic Messages (`/v1/messages`) directly. There is no AI proxy or server-side key.
- `AISettingsStore` is the single source for provider, model, and Keychain-backed API keys. Adding another provider means updating the provider enum, settings UI/storage, request/response handling, and the privacy/legal disclosures on the marketing site.
- Brew notes are omitted only when `AnalysisFilters.includeNotes` is false. Treat changes to prompt contents as privacy-affecting behavior and keep `Site/src/pages/privacy.astro` accurate.

### Reminders and notifications

- `NotificationManager` is a `@MainActor` singleton. It owns authorization status, uploads APNs tokens to `device_tokens`, and schedules recurring local notifications through `UNUserNotificationCenter`.
- The reminders shown in Settings are persisted as encoded `BrewReminderSchedule` values in `UserDefaults`, then expanded into one calendar trigger per weekday. `refreshLocalReminderState` also migrates the old single `daily-brew-reminder` request.
- `AppDelegate` only forwards APNs registration success/failure to `NotificationManager`. Keep UIKit delegate work at this boundary.
- `notify-brew-reminder` currently looks up device tokens and logs the intended recipient count; it does **not** send APNs requests. Do not present it as production push fan-out until APNs authentication and delivery are actually implemented.

### Widgets, shortcuts, and deep links

- `DialdWidgets` contains a quick-action widget and a dashboard widget. The dashboard extension never queries Supabase; `AppServices.publishWidgetSnapshot()` writes a Codable snapshot to app-group `UserDefaults` (`group.club.diald`) and reloads the `DialdDashboardWidget` timeline.
- Widget links use `diald://shortcut/logBrew` and `diald://shortcut/startTimer`. `QuickActionRouter` translates them into `NotificationCenter` events that `MainTabView` uses to present `AddBrewView`, optionally with the extraction timer already running.
- AppIntents route through the same `QuickActionRouter` and set `openAppWhenRun = true`. Keep widgets, AppIntents, URL path names, `AppQuickAction` raw values, and notification names synchronized.

### Marketing site

- `Site/` is a static Astro 7 site. `BaseLayout` owns global CSS, document metadata, header, and footer; the home page composes focused section components, while privacy, terms, and support use the shared legal layout/components.
- There is no client-side Supabase configuration or runtime backend in the site. Netlify builds with base `Site`, command `bun run build`, and publishes `Site/dist`; its ignore rule skips deploys when only unrelated paths changed.
- Legal and support copy is part of the product behavior contract. Update it whenever authentication providers, analytics/error reporting, subscriptions, AI data sharing, retention, or support contact behavior changes.

### Other notable wiring

- `Log` (`Diald/Logging/Logger.swift`) is the OSLog/Sentry wrapper. Sentry setup is a no-op when `SENTRY_DSN` is empty; keep repository and service errors going through `Log` rather than ad hoc prints.
- `Theme`, `Card`, `PrimaryButton`, and `LoadingView` under `Diald/Components/` are shared UI primitives. Reuse them before introducing one-off colors, spacing, or loading treatments.
- The app and widget must retain the same `group.club.diald` app-group entitlement. The main app additionally has Sign in with Apple and APNs entitlements.
- The app is iOS/iPadOS 17+, portrait-only on iPhone, and supports all standard orientations on iPad. `Info.plist` is committed; `project.yml` layers generated properties, secrets, URL schemes, and background modes onto it.
- GitHub Actions regenerates the Xcode project. Pull requests get an unsigned simulator build; pushes to `main` that touch iOS paths archive and upload to TestFlight using manual signing.

## Strict concurrency

`SWIFT_STRICT_CONCURRENCY: complete` is set in `project.yml`. Services and repositories are generally `@MainActor`, and notification delegate callbacks use `nonisolated` only where the protocol requires it. When introducing work across actor boundaries, use `Sendable` values and explicit actor hops; don't silence compiler findings with `@unchecked Sendable` without a concrete thread-safety justification.

## SDK drift

The dependency lower bounds live in `project.yml`; generated Xcode package state is not committed. Areas most likely to need coordinated changes after an update:

- **`supabase-swift` 2.x** — auth event/session APIs, OAuth URL construction, `signInWithIdToken`, PostgREST filters, RPC parameter encoding, and response decoding converge in `AuthClient` and the repositories.
- **StoreKit 2** — `Product.purchase`, verification results, entitlement iteration, transaction JWS access, subscription management, and the committed StoreKit configuration must remain aligned with `BillingRepository`.
- **Swift strict concurrency / iOS SDKs** — `UNUserNotificationCenterDelegate`, `ASWebAuthenticationSession`, AppIntents, WidgetKit timelines, and UIKit callbacks can gain isolation requirements between toolchains.
- **Astro / Prettier** — site dependencies are pinned through `Site/bun.lock`; keep the lockfile with intentional updates and run both the production build and `format:check`.

When an SDK bump breaks compilation, check the dependency's release notes and update the shared abstraction rather than scattering compatibility workarounds across views.

## Folder casing

The app folders are `Diald/` and `DialdWidgets/`, the marketing site is `Site/` (capital S), and the backend is `supabase/` (lowercase). Always preserve those spellings in code, scripts, workflow paths, and documentation so the repository works on case-sensitive filesystems.

## What not to commit

`Config/Secrets.xcconfig`, `.env*`, `Diald.xcodeproj/`, `build/`, `DerivedData/`, `.build/`, `.swiftpm/`, `Package.resolved`, `Site/node_modules/`, `Site/.astro/`, `Site/dist/`, `supabase/.temp/`, `supabase/.branches/`, `.netlify/`, or signing certificates/provisioning profiles. These are already git-ignored where applicable; don't add overrides.
