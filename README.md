# MenuMines

A minimalist Minesweeper for your menu bar.

## What is MenuMines?

MenuMines is a menu bar Minesweeper game for macOS that brings the classic puzzle to your fingertips:

- **Always accessible** - Lives in your menu bar, one click away
- **Daily puzzle** - Same board for everyone, every day
- **No decisions** - Just open and play, no setup required
- **Distraction-free** - No dock icon, no clutter

## Installation

### Download

Download the latest release from the Releases page.

1. Download `MenuMines.dmg`
2. Open the DMG and drag MenuMines to Applications
3. Launch MenuMines from Applications
4. Click the MenuMines grid icon in your menu bar to play

### Build from Source

Requires Xcode 15+ and macOS 14+ (Sonoma).

```bash
git clone https://github.com/smeriwether/menumines.git
cd menumines
xcodebuild build \
  -scheme MenuMines \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=""
```

Build products are generated in Xcode DerivedData (default) unless you override output paths.

## Distribution

MenuMines supports two distribution channels with separate builds:

| Channel | Target | Update Mechanism | Signing |
|---------|--------|------------------|---------|
| App Store | MenuMines | App Store | Apple Distribution |
| Direct | MenuMinesDirect | Sparkle | Developer ID |

### Versioning

The `VERSION` file at the repo root is the single source of truth. Both pipelines read it and
**refuse to build a tag that disagrees with it**, which is what keeps the two channels on the
same number — they previously drifted from 1.0.15 to 1.0.17 without anyone noticing.

Bump it with the script, which also keeps `MARKETING_VERSION` in the Xcode project in step so
local builds report the same version a release would:

```bash
scripts/set-version.sh 1.0.19
```

Then commit before tagging. CI fails if `VERSION` and the project file disagree.

### App Store Release

Triggered by pushing a `v*` tag matching `VERSION`:

```bash
git tag v1.0.19 && git push origin v1.0.19
```

The `release.yml` workflow runs tests, creates temporary App Store signing assets through the
App Store Connect API, archives, exports a signed `.pkg`, uploads it to App Store
Connect/TestFlight along with debug symbols to Sentry, and publishes a GitHub Release.

The `.pkg` is deliberately **not** attached to that release. It is signed for submission and
is not notarized, so Gatekeeper quarantines it as malware for anyone who downloads it; it is
available as a workflow artifact instead. The release is also created with `--latest=false`,
because the `Latest` pointer belongs to the Direct channel (see below).

You can also run the workflow manually from GitHub Actions and provide a version number.

### Direct Distribution Release

Triggered by pushing a `v*-direct` tag whose version matches `VERSION`:

```bash
git tag v1.0.19-direct && git push origin v1.0.19-direct
```

The `release-direct.yml` workflow:
1. Builds with `Release-Direct` configuration
2. Signs with Developer ID certificate
3. Notarizes with Apple
4. Creates a signed DMG
5. Signs the release for Sparkle auto-updates
6. Generates `appcast.xml`
7. Creates a GitHub Release with DMG and appcast
8. Publishes `appcast.xml` to the fixed `appcast` release, which is what `SUFeedURL` points at

The feed lives at a fixed URL rather than `/releases/latest/download/`. That pointer is shared
with the App Store channel, and when an App Store release claimed it the feed 404'd and
auto-updates broke silently for two months. The workflow still marks the Direct release as
`Latest` for builds already in the wild that are pinned to the old URL.

### Direct Release Lessons (Sparkle + Notarization)

A few hard-won constraints to keep in mind when shipping outside the App Store:

- **Treat “Direct” as a separate product**: keep a distinct target/build config (and often bundle ID) so entitlements, signing, and update behavior don’t accidentally affect the App Store build.
- **Sign *everything* inside the app bundle**: the main app, frameworks, login items/helpers, and any embedded tools all need consistent Developer ID signing.
- **Notarization is a pipeline, not a checkbox**: common failures come from missing hardened runtime, incorrect entitlements, unsigned nested binaries, or packaging the wrong artifact.
- **DMG matters**: users experience the DMG first. Make sure the DMG is **signed**, **notarized**, and (ideally) **stapled** so Gatekeeper behaves nicely offline.
- **Sparkle updates require a stable feed + signing key hygiene**:
  - keep the **appcast URL stable** and versioned entries correct
  - keep the **Sparkle private key private** (rotate if ever exposed)
- **Versioning must be consistent**: ensure the version/build numbers Sparkle reads match what you publish in releases/appcast.

### Required GitHub Secrets

#### App Store (release.yml)

| Secret | Description |
|--------|-------------|
| `ASC_API_KEY_P8_BASE64` | Base64-encoded App Store Connect API key (.p8) |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `SENTRY_DSN` | Optional: Sentry DSN for error tracking |

Run `ruby Tools/app_store_connect_signing.rb create-certs` once to create durable signing certificates. It stores `APPLE_DISTRIBUTION_CERT_*` and `MAC_INSTALLER_CERT_*` (`_ID`, `_BASE64`, `_PASSWORD`, `_SHA1`) straight in GitHub Secrets, and needs `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_API_KEY_PATH` in the environment. Run it again when they near expiry. Without them, each release makes a new certificate pair until Apple's certificate limit stops it, because certificates can't be revoked while TestFlight builds need them.

#### Direct Distribution (release-direct.yml)

| Secret | Description |
|--------|-------------|
| `DEVELOPER_ID_CERT_BASE64` | Base64-encoded Developer ID Application certificate |
| `DEVELOPER_ID_CERT_PASSWORD` | Certificate password |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_ID_PASSWORD` | App-specific password for notarization |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `SPARKLE_PRIVATE_KEY` | Sparkle Ed25519 private key |
| `SPARKLE_PUBLIC_ED_KEY` | Sparkle Ed25519 public key |
| `SENTRY_DSN` | Optional: Sentry DSN for error tracking |

### Generating Sparkle Keys

After adding the Sparkle package, build the project to generate the key tool:

```bash
# Build to fetch Sparkle package
xcodebuild -scheme MenuMines-Direct -configuration Release-Direct

# Find and run the key generator
./DerivedData/MenuMines-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

This outputs:
- Private key saved to `~/.sparkle_private_key`
- Public key printed to stdout

Add both keys to GitHub Secrets as described above.

## Development

`project.yml` generates the Xcode project: edit it, then run `xcodegen generate`. Debug builds use the `com.merimerimeri.MenuMines.dev` identity and a separate icon, so they run alongside a real install without sharing its data. `scripts/test.sh` runs the tests and builds both shipping configurations.

## How to Play

Clear the 9x9 board without hitting any of the 12 hidden mines.

### Controls

| Action | Mouse | Keyboard |
|--------|-------|----------|
| Reveal cell | Left-click | Space |
| Toggle flag | Right-click or Control+Click | F |
| Move selection | - | Arrow keys |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘R | Reset game |
| ⌘, | Settings |
| ⌘Q | Quit |

### Rules

- Numbers show how many mines are in adjacent cells (including diagonals)
- Flag cells you think contain mines
- Reveal all non-mine cells to win
- Hit a mine and it's game over

## Daily Board

Every day, MenuMines generates a new puzzle using a deterministic seed based on the date. This means:

- Everyone gets the same board on the same day
- You can compare times with friends
- Come back tomorrow for a fresh challenge

Continuous Play is enabled by default. After completing the daily puzzle, you can keep playing unlimited random puzzles. Only the daily puzzle counts toward streaks.

Each daily board starts fully covered, with the same safe opening cell marked by a dot, so every player can begin from the identical position. Opening a mine on a daily loses. Random puzzles guarantee a safe first click instead.

## Accessibility

MenuMines is designed to be fully playable with VoiceOver:

- **Screen reader support** - All cells and controls have descriptive labels
- **Keyboard navigation** - Full game control via arrow keys, Space, and F
- **State announcements** - Win/loss states are announced automatically

To enable VoiceOver, press Cmd+F5 or go to System Settings → Accessibility → VoiceOver.

## Requirements

- macOS 14.0 (Sonoma) or later

## License

PolyForm Noncommercial 1.0.0 - See [LICENSE](LICENSE) for details.
