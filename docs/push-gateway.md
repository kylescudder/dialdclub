# Shared push gateway

Diald registers for remote notifications with the shared APNs gateway that the
other iOS apps also use. The gateway contract (installation registration,
account unbinding and `PushEvent v1`) is the same in every app and every
app's copy of this document must agree. Diald's application identifier is
`diald`, and its APNs topic and bundle identifier are `club.diald`.

## Registration

The transport is selected from `Config/Secrets.xcconfig`:

- `PUSH_GATEWAY_URL` empty: register the device with the Diald API
  (`POST /api/devices`, unbind with `DELETE /api/devices`).
- `PUSH_GATEWAY_URL` set: register the installation with the gateway.

Exactly one transport is active, and the app never writes to both. Inject the
gateway URL through the private `Config/Secrets.xcconfig`/CI configuration like
the other app values. Never commit credentials. `PUSH_GATEWAY_APPLICATION_ID`
stays `diald` in every environment.

The app sends the gateway:

- a stable Keychain-backed installation ID;
- the raw APNs token as lowercase hexadecimal;
- the APNs environment;
- the current Better Auth bearer token.

The gateway validates that session against the Diald API and derives the
principal from it; one installation has exactly one current principal. Sign-out
and account deletion unbind the installation before the session is invalidated;
a failed unbind does not block sign-out, and the next registration rebinds.

## Notifications

Diald's recurring brew reminders are local calendar notifications. Their
schedule, `UserDefaults` persistence, content and scheduling do not use the
gateway. Diald has no server-originated push event yet. A future feature must
define its consent, schedule, routing and `PushEvent v1` source rather than
reusing the local reminder scheduler.

## Checks

- **Unit tests** cover:
  - configuration parsing;
  - the register and unregister request shapes;
  - installation-ID persistence;
  - lifecycle ordering;
  - transport selection.
- **Physical-device checks:** sandbox and TestFlight (production APNs)
  registration and delivery; logout; failed logout; account switch; token
  refresh; two devices; denied permission; background and terminated delivery.
