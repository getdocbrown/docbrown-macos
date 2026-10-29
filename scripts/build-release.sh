#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
archive="DocBrown-${version}-macOS.zip"
mkdir -p build
python3 scripts/generate-project.py
xcodebuild -project DocBrown.xcodeproj -scheme DocBrown -configuration Release -derivedDataPath "$PWD/build/DerivedData" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
# Separate native SwiftPM builds avoid invoking Xcode's SDK-cache service a
# second time for this Foundation-only helper.
swift build --disable-sandbox -c release --arch arm64 --product docbrown-cli
swift build --disable-sandbox -c release --arch x86_64 --product docbrown-cli
lipo -create .build/arm64-apple-macosx/release/docbrown-cli .build/x86_64-apple-macosx/release/docbrown-cli -output build/docbrown-universal
rm -rf build/DocBrown.app
ditto build/DerivedData/Build/Products/Release/DocBrown.app build/DocBrown.app
mkdir -p build/DocBrown.app/Contents/Helpers
cp build/docbrown-universal build/DocBrown.app/Contents/Helpers/docbrown
codesign --force --deep --options runtime --entitlements Resources/DocBrown.entitlements --sign - build/DocBrown.app
codesign --verify --deep --strict build/DocBrown.app
rm -f "build/$archive"
ditto -c -k --keepParent build/DocBrown.app "build/$archive"
(cd build && shasum -a 256 "$archive" > SHA256SUMS.txt)
printf '\nReady: %s/build/DocBrown.app\n' "$PWD"
