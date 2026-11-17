# Developer entry points. See docs/development.md.
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
REFLOW_IDLE_WARMUP ?= 1
BENCHMARK_OUTPUT ?= build/benchmarks/$(shell date -u +%Y%m%dT%H%M%SZ)
BENCHMARK_BUILD = .build/bench
BENCHMARK_BIN = $(shell swift build -c release --scratch-path $(BENCHMARK_BUILD) --show-bin-path)/KasumiReaderBench

NATIVE_STAMP := .build/native/.stamp
NATIVE_INPUTS := scripts/build-native \
	$(shell find packages -type f \( -name Cargo.toml -o -name Cargo.lock -o -name '*.rs' \) \
		-not -path '*/target/*' 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help native build test test-ios app run-sim run-device launch-sim check clean reflow-lab run-reflow-lab check-reflow-lab check-reader-scrolling check-reflow-scrolling check-fast-reflow-scrolling

help: ## List available targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z-]+:.*## / { printf "  %-8s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nVariables: SIMULATOR="%s" FILTER="%s" DERIVED_DATA=%s\n' \
		"$(SIMULATOR)" "$(FILTER)" "$(DERIVED_DATA)"

native: $(NATIVE_STAMP) ## Build the Rust XCFrameworks (only when inputs changed)

$(NATIVE_STAMP): $(NATIVE_INPUTS)
	./scripts/build-native
	@touch $@

build: native ## Build the Swift package
	swift build -c $(SWIFT_CONFIGURATION)

test: native ## Run swift test (optionally FILTER=<name>)
	swift test -c $(SWIFT_CONFIGURATION) $(if $(FILTER),--filter '$(FILTER)')

# Xcode suite identifiers omit (), while function identifiers include it.
# Selecting both forms lets FILTER accept either kind of name.
test-ios: native ## Run package tests on iOS Simulator (optionally FILTER=<name>)
	xcodebuild -scheme KasumiMarkdown-Package -destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath build/iOSTests $(if $(FILTER),'-only-testing:KasumiMarkdownTests/$(FILTER)' '-only-testing:KasumiMarkdownTests/$(FILTER)()') test

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
	newer=$$(find apps/iOS/Kasumi packages -name '*.swift' -newer "$$app_path/$(APP_NAME)" 2>/dev/null | head -3); \
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

clean: ## Remove SwiftPM, native and app build products
	rm -rf .build $(DERIVED_DATA)
