#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
archive="DocBrown-${version}-macOS.zip"
tool=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
test -x "$tool"
test -f "build/$archive"
mkdir -p build/updates
cp "build/$archive" build/updates/
awk -v version="$version" '$0 == "## " version { found=1; next } found && /^## / { exit } found { print }' CHANGELOG.md > "build/updates/DocBrown-${version}-macOS.md"
args=(--download-url-prefix "https://github.com/getdocbrown/docbrown-macos/releases/download/v${version}/" --embed-release-notes --maximum-deltas 0 --maximum-versions 1)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    # The secret goes through stdin, never command arguments or a logged command.
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$tool" --ed-key-file - "${args[@]}" build/updates
else
    if [[ -n "${CI:-}" ]]; then echo 'SPARKLE_PRIVATE_KEY is required to publish updates.' >&2; exit 1; fi
    "$tool" --account ai.docbrown.macos.sparkle "${args[@]}" build/updates
fi
cp build/updates/appcast.xml build/appcast.xml
echo 'Signed appcast generated.'
