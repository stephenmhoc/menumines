# App Store and TestFlight Setup

This repo is configured to publish the Mac App Store build of `MenuMines` to App Store Connect from GitHub Actions.

## Bundle ID

Register this explicit App ID in the Apple Developer portal:

| Target | Bundle ID |
| --- | --- |
| macOS app | `com.merimerimeri.MenuMines` |

The App Store target reuses the existing App Store Connect app record and bundle identity: `com.merimerimeri.MenuMines`. The Direct/Sparkle target intentionally keeps the same existing direct-distribution identity so the App Store release remains the continuation of the current MenuMines app identity.

## App Store Connect

Create one app record:

| Field | Value |
| --- | --- |
| Platform | `macOS` |
| Name | `MenuMines` |
| Bundle ID | `com.merimerimeri.MenuMines` |
| SKU | `menumines` |
| Primary category | `Utilities` |
| Privacy Policy URL | `https://menumines.app/privacy.html` |

The App Store Connect category should match the Xcode category, which is `public.app-category.utilities`.

## Apple Developer Assets

The release workflow signs with the durable Apple Distribution and Mac Installer Distribution certificates stored in GitHub Secrets (see "Required GitHub Secrets" in the README for `create-certs`), and creates a temporary Mac App Store provisioning profile through the App Store Connect API that it removes after the run. Without those certificate secrets it falls back to creating a new certificate pair on every run. The app archive is signed with Apple Distribution; the exported `.pkg` is signed with Mac Installer Distribution.

The App Store build enables Game Center with the `com.apple.developer.game-center` entitlement. The release workflow ensures the `GAME_CENTER` capability is enabled on the Bundle ID before creating the temporary Mac App Store provisioning profile, so the signed app and profile stay aligned with App Store Connect.

## GitHub Secrets

Add these repository secrets to `smeriwether/menumines`:

| Secret | Description |
| --- | --- |
| `ASC_API_KEY_P8_BASE64` | Base64-encoded App Store Connect API key `.p8` |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect issuer ID |
| `SENTRY_DSN` | Optional Sentry DSN for crash reporting |

The App Store Connect API key must be allowed to manage certificates, identifiers, profiles, and app uploads. Admin access is the least ambiguous option for first setup.

## Export Compliance

The App Store build declares `ITSAppUsesNonExemptEncryption = false` in `MenuMines/Info.plist`. This matches the current app behavior: MenuMines does not implement its own cryptography and only uses operating-system/network-stack encryption through linked services such as HTTPS.

If future app code adds non-exempt encryption, update this key and answer the App Store Connect encryption documentation flow before uploading a release build.

## Screenshots

Store polished macOS screenshots in `AppStoreScreenshots/`. Apple accepts macOS screenshots at 16:10 sizes such as `2880x1800`, `2560x1600`, `1440x900`, or `1280x800`.

To regenerate the current 2880x1800 screenshot set from the Debug-only exporter (`MenuMines/AppStoreScreenshotExporter.swift`):

```sh
xcodebuild build -scheme MenuMines -destination 'platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
MENUMINES_EXPORT_APP_STORE_SCREENSHOTS=1 \
  MENUMINES_SCREENSHOT_OUTPUT_DIR="$PWD/AppStoreScreenshots" \
  ~/Library/Developer/Xcode/DerivedData/MenuMines-*/Build/Products/Debug/MenuMines.app/Contents/MacOS/MenuMines
```

Current initial set:

1. Fresh daily puzzle
2. Puzzle in progress
3. Completed daily result with share button

## Release

Tag-based release:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Manual release:

1. Open GitHub Actions.
2. Run `Release to TestFlight`.
3. Enter a version such as `1.0.0`.

The workflow:

1. Runs the local Xcode test suite.
2. Prepares App Store signing assets.
3. Archives the macOS app.
4. Exports an App Store Connect `.pkg`.
5. Uploads the `.pkg` to App Store Connect/TestFlight.
6. Creates or updates the GitHub Release. The `.pkg` is kept as a workflow artifact and deliberately not attached (see the README).
7. Cleans up temporary signing assets.

## After Upload

After the workflow completes:

1. Check the GitHub Actions run for green status.
2. Go to App Store Connect -> TestFlight and wait for the build to finish processing.
3. Confirm the build is no longer blocked by export compliance.
4. Add the build to the App Store version.
5. Finish app metadata, screenshots, age rating, Content Rights, pricing, availability, and review contact information.
6. Submit for review.
