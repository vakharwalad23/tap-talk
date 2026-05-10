.PHONY: all rust bindings xcode build run kill clean release notarize staple dmg

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
		-ov -format UDZO dist/TapTalk-1.0.dmg

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
