FLUTTER ?= flutter

# Settings compiled into the app (API_URL, CLERK_PUBLISHABLE_KEY) live in
# env/<ENV>.json and are passed with --dart-define-from-file.
ENV ?= production
ENV_FILE = env/$(ENV).json

# `make dev` talks to the backend on this machine. A phone cannot reach
# "localhost", so default to this machine's LAN address.
LAN_IP := $(shell ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || hostname -I 2>/dev/null | awk '{print $$1}')
LOCAL_API_URL ?= http://$(LAN_IP):8080/api/v1

# Optional device id from `make devices`, e.g. make dev DEVICE=00008130-...
DEVICE ?=
DEVICE_FLAG = $(if $(DEVICE),-d $(DEVICE))

# Builds for ENV=local also need the LAN API URL, which env/local.json omits.
DEFINES = --dart-define-from-file=$(ENV_FILE) $(if $(filter local,$(ENV)),--dart-define=API_URL=$(LOCAL_API_URL))

# Android release signing (see android/key.properties.example).
KEYSTORE ?= $(HOME)/.config/open-aiq/upload-keystore.jks

# Release configuration.
RELEASE_BRANCH ?= main
DIST           ?= dist

.PHONY: help init devices dev dev\:prod format\:fix format\:check lint\:check lint\:fix test verify build\:apk build\:aab build\:ios keystore clean release

## help: Show available commands
help:
	@echo "Available commands:"
	@echo ""
	@sed -n 's/^## //p' $(MAKEFILE_LIST) | awk '{ i = index($$0, ": "); if (i) printf "  %-20s %s\n", substr($$0, 1, i - 1), substr($$0, i + 2); else print "" }'

## init: Install Dart/Flutter dependencies and check the toolchain
init:
	$(FLUTTER) --version
	$(FLUTTER) pub get
	@test -f android/key.properties || echo "note: android/key.properties is missing; release builds use the debug key until you run 'make keystore'."

## devices: List connected phones, simulators and emulators
devices:
	$(FLUTTER) devices

## dev: Run against the backend on this machine (LAN IP, port 8080) — make dev [DEVICE=<id>] [LOCAL_API_URL=...]
dev:
	@test -n "$(LAN_IP)" || { echo "error: could not detect this machine's LAN IP; pass LOCAL_API_URL=http://<ip>:8080/api/v1"; exit 1; }
	@echo "API_URL=$(LOCAL_API_URL)"
	$(FLUTTER) run $(DEVICE_FLAG) --dart-define-from-file=env/local.json --dart-define=API_URL=$(LOCAL_API_URL)

## dev:prod: Run against the production backend (api.air-iq.net) — make dev:prod [DEVICE=<id>]
dev\:prod:
	$(FLUTTER) run $(DEVICE_FLAG) --dart-define-from-file=env/production.json

## format:fix: Format Dart sources
format\:fix:
	dart format lib test

## format:check: Check Dart formatting without changing files
format\:check:
	dart format --output=none --set-exit-if-changed lib test

## lint:check: Run the Dart analyzer
lint\:check:
	$(FLUTTER) analyze

## lint:fix: Apply the analyzer's automatic fixes (dart fix)
lint\:fix:
	dart fix --apply

## test: Run unit and widget tests
test:
	$(FLUTTER) test

## verify: Run format:check, lint:check and test
verify:
	@$(MAKE) --no-print-directory format:check
	@$(MAKE) --no-print-directory lint:check
	@$(MAKE) --no-print-directory test

## build:apk: Build a release APK — make build:apk [ENV=production|local]
build\:apk:
	$(FLUTTER) build apk --release $(DEFINES)

## build:aab: Build a Play Store bundle — make build:aab [ENV=production|local]
build\:aab:
	$(FLUTTER) build appbundle --release $(DEFINES)

## build:ios: Build the iOS app without code signing — make build:ios [ENV=production|local]
build\:ios:
	$(FLUTTER) build ios --release --no-codesign $(DEFINES)

## keystore: Create the Android upload keystore — make keystore [KEYSTORE=path]
keystore:
	@test ! -e "$(KEYSTORE)" || { echo "error: $(KEYSTORE) already exists"; exit 1; }
	@mkdir -p "$(dir $(KEYSTORE))"
	keytool -genkeypair -v -keystore "$(KEYSTORE)" -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
	@echo "Now copy android/key.properties.example to android/key.properties and set storeFile=$(KEYSTORE) and the passwords."
	@echo "Back up the keystore and its passwords: updates to an installed app must be signed with the same key."

## clean: Remove build output
clean:
	$(FLUTTER) clean
	rm -rf $(DIST)/

##.
## release: Verify, bump, tag, build the APK, and publish — make release [version=major|minor|patch|1.2.3|1.2.3-rc.1]
release:
	@RELEASE_BRANCH="$(RELEASE_BRANCH)" RELEASE_VERSION="$(version)" DIST="$(DIST)" FLUTTER="$(FLUTTER)" \
		bash scripts/release.sh
