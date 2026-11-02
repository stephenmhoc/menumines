#!/usr/bin/env bash
#
# Runs the tests, then compiles both shipping configurations. Tests run on Debug, which has
# iCloud, Game Center and Sparkle compiled out, so only building the others proves that code
# still compiles. Run this before every commit.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

DERIVED_DATA="${1:-build/DerivedData}"
BUILD_ARGS=(-destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="")

xcodegen generate

BUNDLE_ID="$(xcodebuild -scheme MenuMines -configuration Debug -showBuildSettings 2>/dev/null \
    | awk '$1 == "PRODUCT_BUNDLE_IDENTIFIER" { print $3; exit }')"
if [[ "$BUNDLE_ID" == "com.merimerimeri.MenuMines" ]]; then
    echo "Refusing to run: tests would use the installed app's preferences." >&2
    exit 1
fi

xcodebuild test -scheme MenuMines -configuration Debug "${BUILD_ARGS[@]}"
xcodebuild build -scheme MenuMines -configuration Release "${BUILD_ARGS[@]}"
xcodebuild build -scheme MenuMines-Direct -configuration Release-Direct "${BUILD_ARGS[@]}"
