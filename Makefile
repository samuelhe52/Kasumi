# Developer entry points. See `make help` and AGENTS.md.
#
# `build`, `test` and `app` depend on `native`, so a fresh checkout needs no
# manual ./scripts/build-native step. The stamp below makes that step run only
# when a native package's manifest, lockfile or sources change.

SIMULATOR ?= iPhone 18 Pro
DERIVED_DATA ?= build/DerivedData
APP_NAME ?= Kasumi
BUNDLE_ID ?= com.samuelhe.Kasumi
CONFIGURATION ?= Debug
SWIFT_CONFIGURATION ?= debug
SIM_APP_PATH = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(APP_NAME).app
MAC_APP_PATH = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/Kasumi.app
DEVICE_APP_PATH = $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/$(APP_NAME).app
# run-device picks a connected device unless DEVICE=<UDID> is given: USB before
# network, and within the same connection an iPhone before an iPad.
# DEVELOPMENT_TEAM=<team ID> sets the signing team when the project has none.
DEVICE ?=
DEVELOPMENT_TEAM ?=
# ONBOARDING=reset shows the first-run font offer again on this launch. It passes
# -onboarding.fonts-offered NO for that launch only; the stored flag is untouched,
# so a plain run-device afterwards doesn't show the offer.
ONBOARDING ?=
ONBOARDING_ARGS = $(if $(filter reset,$(ONBOARDING)),-- -onboarding.fonts-offered NO)
DEVICE_PROBE = xcrun xcdevice list | /usr/bin/python3 -c 'import json, sys; interface = {"usb": 0, "network": 1}; devices = [device for device in json.load(sys.stdin) if device.get("platform") == "com.apple.platform.iphoneos" and device.get("available") and not device.get("simulator")]; devices.sort(key=lambda device: (interface.get(device.get("interface"), 2), not device.get("modelCode", "").startswith("iPhone"), device.get("identifier", ""))); print(devices[0]["identifier"] if devices else "")'
# Narrow `make test` to matching tests, e.g. `make test FILTER=ParagraphTests`.
FILTER ?=
IOS_TEST_TARGET ?= KasumiMarkdownTests
REFLOW_IDLE_WARMUP ?= 1
BENCHMARK_OUTPUT ?= build/benchmarks/$(shell date -u +%Y%m%dT%H%M%SZ)
BENCHMARK_BUILD = .build/bench
BENCHMARK_BIN = $(shell swift build -c release --scratch-path $(BENCHMARK_BUILD) --show-bin-path)/KasumiReaderBench

NATIVE_STAMP := .build/native/.stamp
NATIVE_INPUTS := scripts/build-native rust-toolchain.toml \
	$(shell find packages -type f \( -name Cargo.toml -o -name Cargo.lock -o -name '*.rs' \) \
		-not -path '*/target/*' 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help format native native-local native-release build test test-ios app run-sim run-device launch-sim test-syntax-native syntax-notices render app-check app-check-sim check clean benchmark-typography reflow-lab run-reflow-lab check-reflow-lab check-reader-scrolling check-reflow-scrolling check-fast-reflow-scrolling benchmark-build benchmark-corpus benchmark-self-check benchmark-reader benchmark-reader-full benchmark-reflow-lab
.PHONY: check-native-consumer app-mac app-check-mac mac-dmg run-mac

help: ## List available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  %-8s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nVariables: SIMULATOR="%s" FILTER="%s" DERIVED_DATA=%s\n' \
		"$(SIMULATOR)" "$(FILTER)" "$(DERIVED_DATA)"

format: ## Format tracked Swift and Rust sources
	@git ls-files '*.swift' | while IFS= read -r file; do \
		[ -L "$$file" ] || printf '%s\0' "$$file"; \
	done | xargs -0 swift-format format --parallel --in-place
	@for manifest in packages/Native*/Cargo.toml; do \
		cargo fmt --manifest-path "$$manifest" || exit 1; \
	done

native: $(NATIVE_STAMP) ## Build the Rust XCFramework (only when inputs changed)

native-local: native ## Select locally built native binaries for this checkout
	@./scripts/native-mode local

native-release: ## Select release binaries for this checkout
	@./scripts/native-mode release

$(NATIVE_STAMP): $(NATIVE_INPUTS)
	./scripts/build-native
	@touch $@

build: native ## Build the Swift package
	swift build -c $(SWIFT_CONFIGURATION)

test-syntax-native: ## Test the Syntect bridge on the host (no simulator)
	CARGO_TARGET_DIR=$(CURDIR)/.build/native/target cargo test --locked --manifest-path packages/NativeSyntax/Cargo.toml

syntax-notices: ## Extract the pinned grammar bundle's license notices
	CARGO_TARGET_DIR=$(CURDIR)/.build/native/target cargo run --locked --quiet --manifest-path packages/NativeSyntax/Cargo.toml --example grammar-notices > packages/NativeSyntax/Notices/GRAMMAR-LICENSES.md

licenses: ## Regenerate the bundled third-party notices from notices/manifest.json
	./scripts/collect-notices

.PHONY: licenses

# INPUT and OUTPUT are required. RENDER_ARGS accepts the CLI's optional flags.
render: build ## Render a Markdown fixture without launching the app
	@test -n "$(INPUT)" -a -n "$(OUTPUT)" || { echo "Use make render INPUT=<file> OUTPUT=<file.png|jpg|pdf> [RENDER_ARGS=...]" >&2; exit 1; }
	swift run --skip-build KasumiRender "$(INPUT)" "$(OUTPUT)" $(RENDER_ARGS)

test: native ## Run swift test (optionally FILTER=<name>)
	swift test -c $(SWIFT_CONFIGURATION) $(if $(FILTER),--filter '$(FILTER)')

benchmark-typography: native ## Measure bounded language and punctuation cost (optimized, no simulator)
	KASUMI_TYPOGRAPHY_BENCHMARKS=1 swift test -c release --filter TypographyPerformanceTests

# Xcode suite identifiers omit (), while function identifiers include it.
# Selecting both forms lets FILTER accept either kind of name.
# Set IOS_TEST_TARGET=KasumiMarkdownUITests for tests of the reader surface.
test-ios: native ## Run package tests on iOS Simulator (optionally FILTER=<name>)
	xcodebuild -scheme KasumiMarkdown-Package -destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath build/iOSTests $(if $(FILTER),'-only-testing:$(IOS_TEST_TARGET)/$(FILTER)' '-only-testing:$(IOS_TEST_TARGET)/$(FILTER)()') test

app-check: native ## Compile the iOS app without signing or launching a device
	xcodebuild -project apps/iOS/Kasumi.xcodeproj -scheme Kasumi \
		-destination 'generic/platform=iOS' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

app-check-sim: native ## Compile the iOS app for a generic simulator without launching it
	xcodebuild -project apps/iOS/Kasumi.xcodeproj -scheme Kasumi \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath $(DERIVED_DATA) ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build

check-native-consumer: native ## Build and run a macOS Xcode and SwiftPM consumer
	./scripts/check-native-consumer

app-mac: native ## Build the native macOS app
	xcodebuild -project apps/iOS/Kasumi.xcodeproj -scheme KasumiMac \
		-configuration $(CONFIGURATION) -destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) build

app-check-mac: native ## Compile the native macOS app without signing or launching it
	xcodebuild -project apps/iOS/Kasumi.xcodeproj -scheme KasumiMac \
		-configuration $(CONFIGURATION) -destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

mac-dmg: ## Build a Developer ID signed, notarized Kasumi for Mac DMG (NOTARY_PROFILE required)
	@scripts/build-mac-dmg

run-mac: app-mac ## Build and relaunch the native macOS app
	@pkill -f "$(abspath $(MAC_APP_PATH))/Contents/MacOS/" && sleep 1; \
		open -n "$(MAC_APP_PATH)"

app: native ## Build the iOS app for the simulator
	xcodebuild -project apps/iOS/Kasumi.xcodeproj -scheme Kasumi \
		-configuration $(CONFIGURATION) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath $(DERIVED_DATA) build

run-sim: native ## Build, install, and launch on the booted simulator
	@udid=$$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1); \
	[ -n "$$udid" ] || { echo "No booted simulator found. Boot one first (e.g. open -a Simulator)."; exit 1; }; \
	echo "Using simulator $$udid"; \
	xcodebuild -quiet -project apps/iOS/Kasumi.xcodeproj -scheme Kasumi \
		-configuration $(CONFIGURATION) -destination "id=$$udid" \
		-derivedDataPath $(DERIVED_DATA) build
	@$(MAKE) --no-print-directory launch-sim

run-device: native ## Build, install, and launch on a connected iPhone or iPad (DEVICE=<UDID> to choose, ONBOARDING=reset to show first-run onboarding)
	@device="$(DEVICE)"; \
	[ -n "$$device" ] || device=$$($(DEVICE_PROBE)); \
	[ -n "$$device" ] || { echo "No connected iPhone found."; exit 1; }; \
	echo "Using device $$device"; \
	xcodebuild -quiet -project apps/iOS/Kasumi.xcodeproj -scheme Kasumi \
		-configuration $(CONFIGURATION) -destination "id=$$device" \
		-derivedDataPath $(DERIVED_DATA) -allowProvisioningUpdates \
		$(if $(strip $(DEVELOPMENT_TEAM)),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM)) build && \
	xcrun devicectl device install app --device "$$device" "$(DEVICE_APP_PATH)" && \
	xcrun devicectl device process launch --terminate-existing --device "$$device" $(BUNDLE_ID) $(ONBOARDING_ARGS)

launch-sim: ## Install and launch the last built app on the booted simulator, without building
	@udid=$$(xcrun simctl list devices booted | grep -oE '[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}' | head -1); \
	[ -n "$$udid" ] || { echo "No booted simulator found. Boot one first (e.g. open -a Simulator)."; exit 1; }; \
	app_path="$(SIM_APP_PATH)"; \
	[ -d "$$app_path" ] || { echo "No built simulator app at $$app_path. Run make run-sim first."; exit 1; }; \
	newer=$$(find apps/iOS/Kasumi apps/iOS/Shared apps/Common Sources packages -name '*.swift' -newer "$$app_path/$(APP_NAME)" 2>/dev/null | head -3); \
	[ -z "$$newer" ] || echo "Warning: sources are newer than the built app, e.g. $$newer"; \
	xcrun simctl install "$$udid" "$$app_path" && \
	xcrun simctl launch --terminate-running-process "$$udid" $(BUNDLE_ID)

reflow-lab: native ## Build a standalone macOS live-reflow test window (Release)
	swift build -c release --product KasumiReflowLab
	./scripts/package-reflow-lab

run-reflow-lab: reflow-lab ## Open the macOS test window
	open build/KasumiReflowLab.app

check-reflow-lab: reflow-lab ## Run offscreen macOS harness smoke checks
	build/KasumiReflowLab.app/Contents/MacOS/KasumiReflowLab --smoke-check build/reflow-lab-smoke.json

check-reflow-scrolling: reflow-lab ## Check 50k/200k mixed scrolling coverage in the native Mac harness
	build/KasumiReflowLab.app/Contents/MacOS/KasumiReflowLab --scroll-check build/reflow-lab-scrolling.json

check-fast-reflow-scrolling: reflow-lab ## Stress native scrolling after three seconds idle
	KASUMI_REFLOW_IDLE_WARMUP=$(REFLOW_IDLE_WARMUP) build/KasumiReflowLab.app/Contents/MacOS/KasumiReflowLab --fast-scroll-check build/reflow-lab-fast-scrolling.json

benchmark-build: native ## Build the isolated standard Release benchmark executable
	swift build -c release --product KasumiReaderBench --scratch-path $(BENCHMARK_BUILD)

benchmark-corpus: benchmark-build ## Export and verify the fixed benchmark Markdown samples
	python3 benchmarks/reader/run.py --binary $(BENCHMARK_BIN) --output "$(BENCHMARK_OUTPUT)" --corpus-only

benchmark-self-check: ## Check benchmark statistics, manifest and failure handling
	python3 -m unittest discover -s benchmarks/reader -p 'test_*.py'

benchmark-reader: benchmark-build benchmark-self-check ## Run the quick reader engine benchmark (no simulator)
	python3 benchmarks/reader/run.py --binary $(BENCHMARK_BIN) --output "$(BENCHMARK_OUTPUT)" --profile quick

benchmark-reader-full: benchmark-build benchmark-self-check reflow-lab ## Run the full engine, memory and native coverage suite
	python3 benchmarks/reader/run.py --binary $(BENCHMARK_BIN) --output "$(BENCHMARK_OUTPUT)" --profile full --native build/KasumiReflowLab.app/Contents/MacOS/KasumiReflowLab

benchmark-reflow-lab: benchmark-reader ## Legacy alias for benchmark-reader

.PHONY: benchmark-build benchmark-corpus benchmark-self-check benchmark-reader benchmark-reader-full benchmark-reflow-lab

check-reader-scrolling: app ## Profile iOS scrolling on the only booted simulator (DEVICE=<UDID>, CONFIGURATION=Release)
	@test "$(CONFIGURATION)" = Release || { echo "Use CONFIGURATION=Release for scrolling measurements."; exit 1; }
	@test -n "$(DEVICE)" || { echo "Set DEVICE to an already booted simulator UDID."; exit 1; }
	./scripts/check-reader-scrolling --device "$(DEVICE)"

check: ## Check the local toolchain (read-only)
	./scripts/check-environment

clean: ## Remove SwiftPM, native and app/test build products
	rm -rf .build $(DERIVED_DATA) build/iOSTests build/DerivedData-lib \
		build/HandoffDerivedData build/PresetSpacingDerivedData \
		build/TablesDerivedData build/ReleaseCheck
