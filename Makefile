.PHONY: all rust bindings xcode build run clean

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

clean:
	cd core && cargo clean
	rm -rf TapTalk.xcodeproj build
