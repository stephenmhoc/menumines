#!/usr/bin/env bash
#
# Sets the app version in the one place that defines it.
#
# Both release pipelines read ./VERSION and refuse to build a tag that disagrees with it,
# so this is what keeps the App Store and Direct channels on the same number. The Xcode
# project is updated in step so a local build reports the same version a release would.
#
# Usage: scripts/set-version.sh 1.2.3

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
PROJECT_FILE="$REPO_ROOT/MenuMines.xcodeproj/project.pbxproj"

usage() {
    echo "Usage: $(basename "$0") X.Y.Z" >&2
    exit 1
}

[ $# -eq 1 ] || usage
VERSION="$1"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Version must look like X.Y.Z, got '$VERSION'" >&2
    exit 1
fi

CURRENT="$(tr -d '[:space:]' < "$VERSION_FILE")"

# Both stores reject a version that does not increase, and Sparkle would offer existing
# users a downgrade, so refuse to move backwards rather than discover it mid-release.
LOWEST="$(printf '%s\n%s\n' "$CURRENT" "$VERSION" | sort -V | head -1)"
if [ "$VERSION" != "$CURRENT" ] && [ "$LOWEST" != "$CURRENT" ]; then
    echo "Refusing to go backwards: current version is $CURRENT, asked for $VERSION" >&2
    exit 1
fi

echo "$VERSION" > "$VERSION_FILE"

# Keep the project in step. Releases inject MARKETING_VERSION on the xcodebuild command
# line, so this only affects local builds — which is exactly where a stale value misleads.
# project.yml is the source; the generated project is committed so CI needs no XcodeGen.
/usr/bin/sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_FILE"
/usr/bin/sed -i '' -E "s/MARKETING_VERSION: .+/MARKETING_VERSION: $VERSION/" "$REPO_ROOT/project.yml"

echo "Version set to $VERSION (was $CURRENT)"
echo
echo "Next:"
echo "  git commit -am \"Bump version to $VERSION\" && git push"
echo "  git tag v$VERSION && git push origin v$VERSION                 # App Store / TestFlight"
echo "  git tag v$VERSION-direct && git push origin v$VERSION-direct   # Direct download"
