#!/bin/bash
# Génère le projet et construit build/Bar27.app (Debug, signée Developer ID).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
/opt/homebrew/bin/xcodegen generate --quiet
xcodebuild -project Bar27.xcodeproj -scheme Bar27 -configuration "${CONFIG:-Debug}" -derivedDataPath build/DerivedData -quiet build
rm -rf build/Bar27.app && ditto "build/DerivedData/Build/Products/${CONFIG:-Debug}/Bar27.app" build/Bar27.app
codesign --verify --strict build/Bar27.app && codesign -dvv build/Bar27.app 2>&1 | rg '^Authority=Developer ID|^TeamIdentifier'
