#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p build
python3 scripts/generate-project.py
xcodebuild -project DocBrown.xcodeproj -scheme DocBrown -configuration Release -derivedDataPath "$PWD/build/DerivedData" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
swift build --disable-sandbox -c release --arch arm64 --arch x86_64 --product docbrown-cli
rm -rf build/DocBrown.app
ditto build/DerivedData/Build/Products/Release/DocBrown.app build/DocBrown.app
mkdir -p build/DocBrown.app/Contents/Helpers
cp .build/apple/Products/Release/docbrown-cli build/DocBrown.app/Contents/Helpers/docbrown
codesign --force --deep --sign - build/DocBrown.app
codesign --verify --deep --strict build/DocBrown.app
rm -f build/DocBrown-0.1.0-macOS.zip
ditto -c -k --keepParent build/DocBrown.app build/DocBrown-0.1.0-macOS.zip
shasum -a 256 build/DocBrown-0.1.0-macOS.zip > build/SHA256SUMS.txt
printf '\nReady: %s/build/DocBrown.app\n' "$PWD"
