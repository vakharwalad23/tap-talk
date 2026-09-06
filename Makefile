.PHONY: all rust bindings xcode build run install kill clean release notarize staple dmg dmg-unsigned

# Single source of truth is project.yml; anything else drifts from the bundle.
VERSION := $(shell awk -F'"' '/^ *MARKETING_VERSION:/{print $$2; exit}' project.yml)

all: build

rust:
	cd core && cargo build --release

bindings: rust
	cd core && cargo run --release --bin uniffi-bindgen generate \
		--library target/release/libtap_talk_core.a \
		--language swift \
		--out-dir ../TapTalk/Generated

xcode: bindings
	xcodegen generate

build: xcode
	xcodebuild -project TapTalk.xcodeproj -scheme TapTalk -configuration Debug \
		-derivedDataPath build ONLY_ACTIVE_ARCH=YES 2>&1 | tail -20

run: build
	open build/Build/Products/Debug/TapTalk.app

# Builds an optimized app and installs it to /Applications as a STATIC binary.
# Because it isn't rebuilt on every launch, macOS keeps the mic + accessibility
# grants (unlike `make run`, whose ad-hoc hash changes each build and resets them).
# Grant permissions once after installing; re-grant only after the next `make install`.
install:
	cd core && cargo build --release
	cd core && cargo run --release --bin uniffi-bindgen generate \
		--library target/release/libtap_talk_core.a \
		--language swift --out-dir ../TapTalk/Generated
	xcodegen generate
	xcodebuild -project TapTalk.xcodeproj -scheme TapTalk -configuration Release \
		-derivedDataPath build ONLY_ACTIVE_ARCH=YES \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
	@pkill -x TapTalk 2>/dev/null || true
	rm -rf /Applications/TapTalk.app
	cp -R build/Build/Products/Release/TapTalk.app /Applications/TapTalk.app
	@echo ""
	@echo "Installed /Applications/TapTalk.app - launch from Spotlight and grant"
	@echo "Microphone + Accessibility once. Grants persist until the next 'make install'."

kill:
	@pkill -x TapTalk 2>/dev/null && echo "TapTalk stopped" || echo "TapTalk not running"

release:
	cd core && cargo build --release
	cd core && cargo run --release --bin uniffi-bindgen generate \
		--library target/release/libtap_talk_core.a \
		--language swift --out-dir ../TapTalk/Generated
	xcodegen generate
	xcodebuild -project TapTalk.xcodeproj -scheme TapTalk \
		-configuration Release -derivedDataPath build \
		ONLY_ACTIVE_ARCH=NO 2>&1 | tail -5

notarize: release
	ditto -c -k --keepParent \
		build/Build/Products/Release/TapTalk.app \
		build/TapTalk.zip
	xcrun notarytool submit build/TapTalk.zip \
		--keychain-profile "notarytool-profile" \
		--wait

staple:
	xcrun stapler staple build/Build/Products/Release/TapTalk.app

dmg: notarize staple
	mkdir -p dist
	hdiutil create -volname "TapTalk" \
		-srcfolder build/Build/Products/Release/TapTalk.app \
		-ov -format UDZO dist/TapTalk-$(VERSION).dmg

dmg-unsigned:
	cd core && cargo build --release
	cd core && cargo run --release --bin uniffi-bindgen generate \
		--library target/release/libtap_talk_core.a \
		--language swift --out-dir ../TapTalk/Generated
	xcodegen generate
	xcodebuild -project TapTalk.xcodeproj -scheme TapTalk \
		-configuration Release -derivedDataPath build \
		ONLY_ACTIVE_ARCH=YES \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
	mkdir -p dist
	create-dmg \
		--volname "TapTalk" \
		--volicon "resources/TapTalk.icns" \
		--background "resources/dmg-background.png" \
		--window-size 540 380 \
		--icon-size 128 \
		--icon "TapTalk.app" 130 180 \
		--app-drop-link 400 180 \
		--no-internet-enable \
		dist/TapTalk-$(VERSION).dmg \
		build/Build/Products/Release/TapTalk.app

clean:
	cd core && cargo clean
	rm -rf TapTalk.xcodeproj build

clean-state:
	@pkill -x TapTalk 2>/dev/null || true
	@rm -rf ~/Library/Saved\ Application\ State/talk.tap.app.savedState
	@rm -rf ~/Library/Application\ Support/talk.tap.app
	@rm -rf ~/Library/Caches/talk.tap.app
	@rm -rf ~/Library/HTTPStorages/talk.tap.app
	@defaults delete talk.tap.app 2>/dev/null || true
	@echo "TapTalk state + models + binaries cleaned"
