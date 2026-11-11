# Open AIQ mobile app

Flutter companion app for Open AIQ air monitors (ESP32-S3 Rust firmware).

- **Sign in** with the same Clerk account as the web dashboard.
- **Add a monitor over Bluetooth.** Pair with a passkey, register it in your
  account if it is new (the device key goes straight to the monitor), send WiFi
  and the phone's location, then wait for the first reading online. That can
  take 3 to 5 minutes, because the monitor samples the air first.
- **Live readings.** Over BLE, temperature and humidity refresh every 20 s.
  Particles and AQI change every 5 minutes, because the monitor rests its
  particle sensor between 60 s sampling bursts. The online view sits alongside
  (last-hour average, history chart).
- **Every portal setting.** Name, outdoor, public, location sharing, rotate key
  (re-provisioned in the same step) and delete. Settings stored on the monitor
  itself: WiFi, location, details and factory reset.
- **Firmware updates.** An "Update available" badge, owner approval, and
  progress while the monitor downloads and installs.
- **Device logs.** Warnings, errors and important events uploaded by the
  monitor.
- **Your account.** Change your username, manage the ways you sign in (email
  addresses, Google, GitHub and a password) and delete your account, which also
  deletes every monitor and its data.

## Configuration

Values are compiled in with `--dart-define-from-file`, one file per environment:

| File | `API_URL` | Clerk key |
| --- | --- | --- |
| [`env/local.json`](env/local.json) | `http://<this machine's LAN IP>:8080/api/v1`, added by `make dev` | development instance (`pk_test_...`) |
| [`env/production.json`](env/production.json) | `https://api.air-iq.net/api/v1` | production instance (`pk_live_...`) |

Clerk publishable keys are public, so these files are committed. Override the
local URL with `make dev LOCAL_API_URL=http://192.168.1.10:8080/api/v1`.

To make `make dev` work over plain HTTP, debug Android builds allow cleartext
traffic and iOS allows local-network hosts only (`NSAllowsLocalNetworking`).
Release builds and internet traffic still require HTTPS.

The backend must accept native Clerk tokens, which have no `azp` claim. Set
`CLERK_ALLOW_NATIVE_CLIENTS=true` in its environment, and enable the Native API
in the Clerk dashboard.

## Bluetooth

- The protocol lives in [`lib/ble/protocol.dart`](lib/ble/protocol.dart) and
  must stay in sync with `device/src/ble/mod.rs`, `device/src/main.rs` and
  `device/README.md`.
- The monitor only advertises in pairing mode: hold both buttons for 3 s, or
  type `BTN:PAIR` in the serial monitor.
- Every command requires passkey pairing. The 6-digit code is shown on the
  monitor's screen and in its serial log.
- **iOS 18+** uses AccessorySetupKit (`ios/Runner/AppDelegate.swift`, channel
  `org.openaiq/accessory_setup`). A system sheet picks the monitor, so there is
  no general Bluetooth permission prompt. Earlier iOS versions and Android use a
  FlutterBluePlus scan filtered by the Nordic UART service.
- FlutterBluePlus 2.x is distributed under the FlutterBluePlus License, which
  requires a paid commercial license for for-profit use. `AppConfig.bleLicense`
  in [`lib/config.dart`](lib/config.dart) declares the license used on connect.

## Development

Run `make help` for every command.

```sh
make init                  # flutter pub get + toolchain check
make devices               # find your phone's device id
make dev                   # run against the backend on this machine (cd ../backend && make dev)
make dev:prod              # run against production
make gallery               # the shared components with mock data, no sign-in
make gallery:web           # the gallery as a static web page, for the hosted prototype
make dev DEVICE=<id>       # pick a device when several are connected
make verify                # format-check, analyze, test
make build:apk             # release APK; ENV=local builds against the local backend
make build:ios             # unsigned iOS build
```

## Releases

Releases follow the other Open AIQ repositories: SemVer tags with a `v` prefix,
cut from a clean `main`, with GitHub release notes generated from commits.

```sh
make release                    # prompts for major/minor/patch/x.y.z
make release version=minor
make release version=1.2.0-rc.1
```

`scripts/release.sh` verifies the app, builds the signed APK into `dist/` with a
`SHA256SUMS` file, sets `version:` in `pubspec.yaml`, commits "Release vX.Y.Z",
tags it, pushes branch and tag together, and creates the GitHub release with
the APK attached. The build number (Android `versionCode`, iOS
`CFBundleVersion`) is derived from the version: `1.2.3` becomes `10203`.

### Android signing

Release builds need an upload key. Create it once and back it up; every update
of an installed app must be signed with the same key.

```sh
make keystore                                      # ~/.config/open-aiq/upload-keystore.jks
cp android/key.properties.example android/key.properties   # then fill in path and passwords
```

`android/key.properties` and keystores are git-ignored. Without them, local
release builds fall back to the debug key and `make release` refuses to run.

The tests run the protocol, the API client and the provisioning wizard against
an in-memory device emulator ([`test/support/fake_device.dart`](test/support/fake_device.dart))
and a mocked HTTP backend.

### Look and feel

Colors, radii, motion and AQI bands come from the shared design tokens in
`docs/src/data/tokens.json`. Change them there and run `make tokens:sync` in
`docs/`, which rewrites `lib/tokens.g.dart`. The docs site's visual playground
page is the spec for the monitor card, the view inside a monitor and the shared
states. `make gallery` shows the app's versions so you can compare them.

### Gallery and prototype

`make gallery` runs [`lib/main_gallery.dart`](lib/main_gallery.dart) with no
sign-in or network. It opens on the component gallery, and it can also open the
app's real screens on mock data: monitors from
[`lib/gallery/fixtures.dart`](lib/gallery/fixtures.dart) (the same ones as the
web's `make review`), a mock backend in
[`lib/gallery/mock_api.dart`](lib/gallery/mock_api.dart) and a sample account in
[`lib/gallery/mock_account_actions.dart`](lib/gallery/mock_account_actions.dart).
Changes you make there last until you reload. Bluetooth isn't faked, so
Bluetooth actions won't find a monitor.

`make gallery:web` builds it for the hosted prototype, whose Mobile view loads
`mobile/?screen=<key>`:

| Key | Screen |
| --- | --- |
| `gallery` (or none) | The component gallery |
| `monitors` | My monitors |
| `monitor` | Back garden, Overview |
| `monitor-new` | New sensor, which has no readings yet |
| `monitor-logs` | Back garden, Logs |
| `monitor-settings` | Back garden, Settings |
| `settings` | App settings |
| `account` | Your account: username, sign-in methods and deleting it |

The keys live in `galleryScreens` in
[`lib/gallery/gallery_app.dart`](lib/gallery/gallery_app.dart). The prototype's
Screen picker (`frontend/prototype/index.html`) uses the same keys, so change
them together.

### Layout

```text
lib/
  api/            Backend client and models (Clerk bearer token, problem+json errors)
  ble/            Protocol (pure Dart), FlutterBluePlus transport, discovery, connection manager
  features/       account, auth, devices, device_detail (online + live), provisioning, settings, firmware, logs
  gallery/        Mock-data gallery and prototype screens for `make gallery`
  widgets/        Monitor card, AQI tiles, OTA badge, loading/empty/error states
  aqi.dart        US EPA bands, from the shared design tokens
  theme.dart      Sand & Sage theme, built from tokens.g.dart
  tokens.g.dart   Generated from docs/src/data/tokens.json; don't edit
```
