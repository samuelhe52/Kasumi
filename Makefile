# Developer entry points. See docs-ai/development.md.
#
# `build`, `test` and `app` depend on `native`, so a fresh checkout needs no
# manual ./scripts/build-native step. The stamp below makes that step run only
# when a native package's manifest, lockfile or sources change.

SIMULATOR ?= iPhone 18 Pro
DERIVED_DATA ?= build/DerivedData
APP_NAME ?= Kasumi
BUNDLE_ID ?= com.samuelhe.Kasumi
CONFIGURATION ?= Debug
SIM_APP_PATH = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(APP_NAME).app
DEVICE_APP_PATH = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/$(APP_NAME).app
# run-device picks a connected iPhone (USB first) unless DEVICE=<UDID> is given.
# DEVELOPMENT_TEAM=<team ID> sets the signing team when the project has none.
DEVICE ?=
DEVELOPMENT_TEAM ?=
DEVICE_PROBE = xcrun xcdevice list | /usr/bin/python3 -c 'import json, sys; priority = {"usb": 0, "network": 1}; devices = [device for device in json.load(sys.stdin) if device.get("platform") == "com.apple.platform.iphoneos" and device.get("available") and not device.get("simulator")]; devices.sort(key=lambda device: (priority.get(device.get("interface"), 2), device.get("identifier", ""))); print(devices[0]["identifier"] if devices else "")'
# Narrow `make test` to matching tests, e.g. `make test FILTER=ParagraphTests`.
FILTER ?=

NATIVE_STAMP := .build/native/.stamp
NATIVE_INPUTS := scripts/build-native \
	$(shell find packages -type f \( -name Cargo.toml -o -name Cargo.lock -o -name '*.rs' \) \
		-not -path '*/target/*' 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help native build test test-ios app run-sim run-device launch-sim check clean

help: ## List available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  %-8s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nVariables: SIMULATOR="%s" FILTER="%s" DERIVED_DATA=%s\n' \
		"$(SIMULATOR)" "$(FILTER)" "$(DERIVED_DATA)"

native: $(NATIVE_STAMP) ## Build the Rust XCFrameworks (only when inputs changed)

$(NATIVE_STAMP): $(NATIVE_INPUTS)
	./scripts/build-native
	@touch $@

build: native ## Build the Swift package
	swift build

test: native ## Run swift test (optionally FILTER=<name>)
	swift test $(if $(FILTER),--filter '$(FILTER)')

# Xcode suite identifiers omit (), while function identifiers include it.
# Selecting both forms lets FILTER accept either kind of name.
test-ios: native ## Run package tests on iOS Simulator (optionally FILTER=<name>)
	xcodebuild -scheme KasumiMarkdown-Package -destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath build/iOSTests $(if $(FILTER),'-only-testing:KasumiMarkdownTests/$(FILTER)' '-only-testing:KasumiMarkdownTests/$(FILTER)()') test

app: native ## Build the iOS app for the simulator
	xcodebuild -project apps/iOS/Kasumi.xcodeproj -scheme Kasumi \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath $(DERIVED_DATA) build

run-sim: native ## Build, install, and launch on the booted simulator
	@udid=$$(xcrun simctl list devices booted | awk -F'[()]' '/\(Booted\)/ { print $$2; exit }'); \
	[ -n "$$udid" ] || { echo "No booted simulator found. Boot one first (e.g. open -a Simulator)."; exit 1; }; \
	echo "Using simulator $$udid"; \
	xcodebuild -quiet -project apps/iOS/Kasumi.xcodeproj -scheme Kasumi \
		-configuration $(CONFIGURATION) -destination "id=$$udid" \
		-derivedDataPath $(DERIVED_DATA) build
	@$(MAKE) --no-print-directory launch-sim

run-device: native ## Build, install, and launch on a connected iPhone (DEVICE=<UDID> to choose)
	@device="$(DEVICE)"; \
	[ -n "$$device" ] || device=$$($(DEVICE_PROBE)); \
	[ -n "$$device" ] || { echo "No connected iPhone found."; exit 1; }; \
	echo "Using device $$device"; \
	xcodebuild -quiet -project apps/iOS/Kasumi.xcodeproj -scheme Kasumi \
		-configuration $(CONFIGURATION) -destination "id=$$device" \
		-derivedDataPath $(DERIVED_DATA) -allowProvisioningUpdates \
		$(if $(strip $(DEVELOPMENT_TEAM)),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM)) build && \
	xcrun devicectl device install app --device "$$device" "$(DEVICE_APP_PATH)" && \
	xcrun devicectl device process launch --terminate-existing --device "$$device" $(BUNDLE_ID)

launch-sim: ## Install and launch the last built app on the booted simulator, without building
	@udid=$$(xcrun simctl list devices booted | awk -F'[()]' '/\(Booted\)/ { print $$2; exit }'); \
	[ -n "$$udid" ] || { echo "No booted simulator found. Boot one first (e.g. open -a Simulator)."; exit 1; }; \
	app_path="$(SIM_APP_PATH)"; \
	[ -d "$$app_path" ] || { echo "No built simulator app at $$app_path. Run make run-sim first."; exit 1; }; \
	newer=$$(find apps/iOS/Kasumi packages -name '*.swift' -newer "$$app_path/$(APP_NAME)" 2>/dev/null | head -3); \
	[ -z "$$newer" ] || echo "Warning: sources are newer than the built app, e.g. $$newer"; \
	xcrun simctl install "$$udid" "$$app_path" && \
	xcrun simctl launch --terminate-running-process "$$udid" $(BUNDLE_ID)

check: ## Check the local toolchain (read-only)
	./scripts/check-environment

clean: ## Remove SwiftPM, native and app build products
	rm -rf .build $(DERIVED_DATA)
