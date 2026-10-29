#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
cat Sources/DocBrownCore/BrandGeometry.swift scripts/generate-icon.swift > build/render-icon.swift
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" swift build/render-icon.swift "$PWD/build/AppIcon.iconset"
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
