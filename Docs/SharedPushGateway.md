# Shared push gateway

Diald's user-facing remote notification registration is prepared for the
shared APNs gateway. The application identifier is `diald`; its APNs topic and
bundle identifier are `club.diald`.

## Current state

`PUSH_GATEWAY_URL` is deliberately empty in the checked-in example
configuration. An empty or malformed URL selects the existing Supabase
`device_tokens` registration path, so merging this change does not move
production traffic. When a valid URL is supplied, Diald selects the gateway
transport exclusively; it never dual-writes.

The app sends the gateway a stable Keychain-backed installation ID, the raw
APNs token encoded as lowercase hexadecimal, the APNs environment, and the
current bearer token. The gateway derives the principal from the verified
token. The shared notification code contains no Supabase identity or table
types; `AuthClient` is the temporary identity adapter and the legacy transport
is the temporary rollback adapter.

Diald's recurring brew reminders remain local calendar notifications. Their
schedule model, `UserDefaults` persistence, legacy reminder migration,
notification content, cancellation, and scheduling do not use the gateway.
The existing `notify-brew-reminder` Edge Function is still a non-delivering
placeholder and is not changed or presented as a producer by this migration.

## Activation gates

Do not populate `PUSH_GATEWAY_URL` until the shared gateway staging stack and
its `diald` application configuration exist. Follow the canonical gateway
testing and rollout plan before activation, including:

- issuer/JWKS and `club.diald` topic configuration;
- sandbox physical-device registration and delivery without relying on an
  iCloud account;
- logout, failed logout, account switch, token refresh, two-device, denied
  permission, background, terminated-app, and TestFlight production-APNs
  checks;
- confirmation that one installation has one current principal and only one
  registration transport is active;
- monitoring, alarms, DLQ ownership, and a tested infrastructure rollback.

No server-originated Diald event exists yet. A future product feature must
define its consent, schedule, routing, and canonical `PushEvent v1` source; it
must not repurpose the local brew-reminder scheduler implicitly.

## Deployment and rollback

Inject a stage-appropriate HTTPS gateway URL through the same private
`Config/Secrets.xcconfig`/CI configuration mechanism as the other app values.
Do not commit credentials or a production hostname. The application ID remains
`diald` in every environment.

For this Phase 1 change, rollback is configuration-only: clear
`PUSH_GATEWAY_URL` and rebuild to select the unchanged legacy Supabase token
upsert. Keep that adapter and `device_tokens` available for at least one
release after gateway activation. Do not remove the placeholder Edge Function
or any Supabase notification storage as part of this client PR.
