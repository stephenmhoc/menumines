#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════════════════════════
# MenuMines Direct Distribution Release Script
# ══════════════════════════════════════════════════════════════════════════════
#
# This script builds, signs, notarizes, and releases MenuMines for direct
# distribution (non-App Store) with Sparkle auto-updates.
#
# Prerequisites:
#   - Xcode 26+ installed (the macOS 26 SDK gives the app the current window chrome)
#   - Developer ID Application certificate in keychain
#   - gh CLI installed and authenticated
#   - Environment variables set (see below)
#
# Required environment variables:
#   APPLE_ID              - Your Apple ID email
#   APPLE_ID_PASSWORD     - App-specific password for notarization
#   APPLE_TEAM_ID         - Your Apple Developer Team ID
#   SPARKLE_PRIVATE_KEY   - EdDSA private key for Sparkle signing
#   SPARKLE_PUBLIC_ED_KEY - Sparkle public key. Without it the app can't verify updates.
#
# Optional environment variables:
#   SENTRY_DSN            - Sentry DSN for crash reporting
#   SENTRY_AUTH_TOKEN     - Uploads dSYMs so crashes arrive symbolicated
#   RELEASE_NOTES_HTML    - Custom HTML release notes for Sparkle update dialog
#
# Usage:
#   ./scripts/release-direct.sh 1.0.1
#   ./scripts/release-direct.sh 1.0.1 --draft    # Create draft release
#   ./scripts/release-direct.sh 1.0.1 --dry-run  # Build only, no release
#
# ══════════════════════════════════════════════════════════════════════════════

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCHEME="MenuMines-Direct"
CONFIGURATION="Release-Direct"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/MenuMines.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_STAGING="$BUILD_DIR/dmg-staging"

# Parse arguments
VERSION="${1:-}"
DRAFT_RELEASE=false
DRY_RUN=false

shift || true
while [[ $# -gt 0 ]]; do
    case $1 in
        --draft)
            DRAFT_RELEASE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# ──────────────────────────────────────────────────────────────────────────────
# Helper functions
# ──────────────────────────────────────────────────────────────────────────────

log_step() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

log_info() {
    echo -e "${GREEN}→${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

check_required_env() {
    local var_name="$1"
    if [[ -z "${!var_name:-}" ]]; then
        log_error "Required environment variable $var_name is not set"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
# Validation
# ──────────────────────────────────────────────────────────────────────────────

log_step "Validating environment"

if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version> [--draft] [--dry-run]"
    echo "Example: $0 1.0.1"
    exit 1
fi

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid version format: $VERSION (expected X.Y.Z)"
    exit 1
fi

log_info "Version: $VERSION"
log_info "Draft release: $DRAFT_RELEASE"
log_info "Dry run: $DRY_RUN"

# Check required tools
if ! command -v xcodebuild &> /dev/null; then
    log_error "xcodebuild not found. Please install Xcode."
    exit 1
fi

XCODE_MAJOR="$(xcodebuild -version | awk '/Xcode/ { split($2, v, "."); print v[1] }')"
if [[ "$XCODE_MAJOR" -lt 26 ]]; then
    log_error "Xcode 26 or later is required (found $(xcodebuild -version | head -1)). Older SDKs ship the old window chrome."
    exit 1
fi

if ! command -v gh &> /dev/null; then
    log_error "gh CLI not found. Please install: brew install gh"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    log_error "gh CLI not authenticated. Please run: gh auth login"
    exit 1
fi

# Check required environment variables
check_required_env "APPLE_ID"
check_required_env "APPLE_ID_PASSWORD"
check_required_env "APPLE_TEAM_ID"
check_required_env "SPARKLE_PRIVATE_KEY"
check_required_env "SPARKLE_PUBLIC_ED_KEY"

REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')

log_info "All prerequisites met"

# ──────────────────────────────────────────────────────────────────────────────
# Clean previous build
# ──────────────────────────────────────────────────────────────────────────────

log_step "Cleaning previous build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log_info "Build directory cleaned"

# ──────────────────────────────────────────────────────────────────────────────
# Store notarization credentials
# ──────────────────────────────────────────────────────────────────────────────

log_step "Storing notarization credentials"

# Store credentials in keychain (will be reused if already stored)
xcrun notarytool store-credentials "MenuMines-Release" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_ID_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    2>/dev/null || true

log_info "Credentials stored"

# ──────────────────────────────────────────────────────────────────────────────
# Resolve dependencies
# ──────────────────────────────────────────────────────────────────────────────

log_step "Resolving Swift Package dependencies"

cd "$PROJECT_DIR"
xcodebuild -resolvePackageDependencies \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/spm-cache"

log_info "Dependencies resolved"

# ──────────────────────────────────────────────────────────────────────────────
# Build archive
# ──────────────────────────────────────────────────────────────────────────────

log_step "Building archive"

# Sparkle compares this number, so it has to beat what's published. The release workflow
# follows the same rule, so the two can't undercut each other.
PUBLISHED_BUILD=$(gh release download appcast -p appcast.xml -O - --repo "$REPO" \
    | sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | head -1)
if [[ -z "$PUBLISHED_BUILD" ]]; then
    log_error "Couldn't read the published build number from the appcast release."
    exit 1
fi
BUILD_NUMBER=$((PUBLISHED_BUILD + 1))
log_info "Build number: $BUILD_NUMBER"

xcodebuild clean archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/spm-cache" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    SENTRY_DSN="${SENTRY_DSN:-}" \
    SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
    | xcpretty || xcodebuild clean archive \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -clonedSourcePackagesDirPath "$BUILD_DIR/spm-cache" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    SENTRY_DSN="${SENTRY_DSN:-}" \
    SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY"

log_info "Archive created at $ARCHIVE_PATH"

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
    log_warn "SENTRY_AUTH_TOKEN is not set, so crashes from this build will arrive unsymbolicated."
elif command -v sentry-cli &> /dev/null; then
    SENTRY_ORG=merimerimeri-software SENTRY_PROJECT=menumines \
        sentry-cli debug-files upload --include-sources "$ARCHIVE_PATH/dSYMs"
else
    log_warn "sentry-cli not found, so dSYMs were not uploaded: brew install getsentry/tools/sentry-cli"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Export archive
# ──────────────────────────────────────────────────────────────────────────────

log_step "Exporting archive"

# Create ExportOptions.plist
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_PATH"

log_info "Archive exported to $EXPORT_PATH"

# ──────────────────────────────────────────────────────────────────────────────
# Notarize app
# ──────────────────────────────────────────────────────────────────────────────

log_step "Notarizing app"

APP_PATH="$EXPORT_PATH/MenuMinesDirect.app"

if [[ ! -d "$APP_PATH" ]]; then
    log_error "App not found at $APP_PATH"
    exit 1
fi

# Create ZIP for notarization
log_info "Creating ZIP for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/MenuMines-notarize.zip"

# Submit for notarization
log_info "Submitting for notarization (this may take a few minutes)..."
xcrun notarytool submit "$BUILD_DIR/MenuMines-notarize.zip" \
    --keychain-profile "MenuMines-Release" \
    --wait

# Staple the notarization ticket
log_info "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

log_info "App notarized and stapled"

# ──────────────────────────────────────────────────────────────────────────────
# Create DMG
# ──────────────────────────────────────────────────────────────────────────────

log_step "Creating DMG"

DMG_PATH="$BUILD_DIR/MenuMines-$VERSION.dmg"

# Create staging directory
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app (rename to MenuMines.app for cleaner user experience)
cp -R "$APP_PATH" "$DMG_STAGING/MenuMines.app"

# Create Applications symlink
ln -s /Applications "$DMG_STAGING/Applications"

# Create DMG
hdiutil create -volname "MenuMines" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

log_info "DMG created at $DMG_PATH"

# ──────────────────────────────────────────────────────────────────────────────
# Notarize DMG
# ──────────────────────────────────────────────────────────────────────────────

log_step "Notarizing DMG"

log_info "Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "MenuMines-Release" \
    --wait

log_info "Stapling DMG..."
xcrun stapler staple "$DMG_PATH"

log_info "DMG notarized and stapled"

# ──────────────────────────────────────────────────────────────────────────────
# Create ZIP for Sparkle updates
# ──────────────────────────────────────────────────────────────────────────────

log_step "Creating ZIP for Sparkle updates"

ZIP_PATH="$BUILD_DIR/MenuMines-$VERSION.zip"
ditto -c -k --keepParent "$DMG_STAGING/MenuMines.app" "$ZIP_PATH"

log_info "ZIP created at $ZIP_PATH"

# ──────────────────────────────────────────────────────────────────────────────
# Sign for Sparkle
# ──────────────────────────────────────────────────────────────────────────────

log_step "Signing for Sparkle"

# Write private key to temp file
SPARKLE_KEY_FILE=$(mktemp)
echo "$SPARKLE_PRIVATE_KEY" > "$SPARKLE_KEY_FILE"
trap "rm -f $SPARKLE_KEY_FILE" EXIT

# Find sign_update tool
SIGN_UPDATE=$(find "$BUILD_DIR/spm-cache" -name "sign_update" -type f 2>/dev/null | head -1)

if [[ -z "$SIGN_UPDATE" ]]; then
    log_warn "sign_update not found in SPM cache, building from source..."

    SPARKLE_BUILD_DIR="$BUILD_DIR/sparkle-build"
    git clone --depth 1 --branch 2.5.0 https://github.com/sparkle-project/Sparkle.git "$SPARKLE_BUILD_DIR/Sparkle"

    cd "$SPARKLE_BUILD_DIR/Sparkle"
    xcodebuild -project Sparkle.xcodeproj \
        -scheme sign_update \
        -configuration Release \
        -derivedDataPath "$SPARKLE_BUILD_DIR/derived" \
        ONLY_ACTIVE_ARCH=NO

    SIGN_UPDATE="$SPARKLE_BUILD_DIR/derived/Build/Products/Release/sign_update"
    cd "$PROJECT_DIR"
fi

# Sign the ZIP - sign_update outputs: sparkle:edSignature="..." length="..."
SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH" --ed-key-file "$SPARKLE_KEY_FILE")
log_info "sign_update output: $SIGN_OUTPUT"

# Extract just the signature value
SPARKLE_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
log_info "Sparkle signature: $SPARKLE_SIGNATURE"

# Extract length from sign_update output, fall back to stat
SIGN_LENGTH=$(echo "$SIGN_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')
ZIP_SIZE=${SIGN_LENGTH:-$(stat -f%z "$ZIP_PATH")}
log_info "ZIP size: $ZIP_SIZE bytes"

# ──────────────────────────────────────────────────────────────────────────────
# Generate appcast.xml
# ──────────────────────────────────────────────────────────────────────────────

log_step "Generating appcast.xml"

PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# Use custom release notes or sensible default
RELEASE_NOTES="${RELEASE_NOTES_HTML:-<h2>MenuMines v$VERSION</h2><p>Bug fixes and improvements.</p>}"

cat > "$BUILD_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MenuMines Updates</title>
    <link>https://github.com/$REPO/releases</link>
    <description>Most recent updates to MenuMines</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <description><![CDATA[$RELEASE_NOTES]]></description>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="https://github.com/$REPO/releases/download/v$VERSION-direct/MenuMines-$VERSION.zip"
        sparkle:edSignature="$SPARKLE_SIGNATURE"
        length="$ZIP_SIZE"
        type="application/octet-stream" />
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
EOF

log_info "Appcast generated at $BUILD_DIR/appcast.xml"

# ──────────────────────────────────────────────────────────────────────────────
# Create GitHub Release
# ──────────────────────────────────────────────────────────────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
    log_step "Dry run complete"
    log_info "Build artifacts:"
    log_info "  - DMG: $DMG_PATH"
    log_info "  - ZIP: $ZIP_PATH"
    log_info "  - Appcast: $BUILD_DIR/appcast.xml"
    log_info "  - Archive: $ARCHIVE_PATH"
    exit 0
fi

log_step "Creating GitHub release"

TAG_NAME="v$VERSION-direct"
RELEASE_NAME="v$VERSION (Direct Distribution)"

# Build release notes
RELEASE_BODY=$(cat <<EOF
## MenuMines v$VERSION - Direct Distribution

Download the DMG and drag MenuMines to your Applications folder.

**Note**: This is the direct distribution build with auto-updates.
For the App Store version, download from the Mac App Store.

---
Built on $(date '+%Y-%m-%d %H:%M:%S')
EOF
)

# Create release arguments
RELEASE_ARGS=(
    "$TAG_NAME"
    --title "$RELEASE_NAME"
    --notes "$RELEASE_BODY"
    "$DMG_PATH"
    "$ZIP_PATH"
    "$BUILD_DIR/appcast.xml"
)

if [[ "$DRAFT_RELEASE" == "true" ]]; then
    RELEASE_ARGS+=(--draft)
fi

# Delete existing release if it exists
if gh release view "$TAG_NAME" &>/dev/null; then
    log_warn "Release $TAG_NAME already exists, deleting..."
    gh release delete "$TAG_NAME" --yes
    git tag -d "$TAG_NAME" 2>/dev/null || true
    git push origin ":refs/tags/$TAG_NAME" 2>/dev/null || true
fi

# Create new release
log_info "Creating release $TAG_NAME..."
gh release create "${RELEASE_ARGS[@]}"

# A draft isn't downloadable, so publishing its appcast would point Sparkle at nothing.
if [[ "$DRAFT_RELEASE" == "true" ]]; then
    log_warn "Draft release: the update feed still points at the previous version."
else
    # Installed copies read the feed from this release. Some older ones read it from Latest.
    gh release edit "$TAG_NAME" --latest
    if ! gh release view appcast &>/dev/null; then
        gh release create appcast \
            --title "Sparkle Appcast (not a release)" \
            --notes "Permanent home for the Sparkle update feed. Not a downloadable version of MenuMines — see the \`-direct\` releases for those." \
            --prerelease \
            --latest=false
    fi
    gh release upload appcast "$BUILD_DIR/appcast.xml" --clobber
    log_info "Update feed published"
fi

# ──────────────────────────────────────────────────────────────────────────────
# Done
# ──────────────────────────────────────────────────────────────────────────────

log_step "Release complete!"

echo ""
echo -e "${GREEN}✓${NC} Version: $VERSION"
echo -e "${GREEN}✓${NC} Tag: $TAG_NAME"
echo -e "${GREEN}✓${NC} Release URL: https://github.com/$REPO/releases/tag/$TAG_NAME"
echo ""
echo "Build artifacts:"
echo "  - DMG: $DMG_PATH"
echo "  - ZIP: $ZIP_PATH"
echo "  - Appcast: $BUILD_DIR/appcast.xml"
echo "  - Archive: $ARCHIVE_PATH"
