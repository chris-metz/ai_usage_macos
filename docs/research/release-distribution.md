# Release distribution: findings (parked)

Research for [How does a release reach users?](https://github.com/chris-metz/pacemark/issues/15), as of 2026-10-03. That ticket decided that v1 is built locally only, which put public releases out of scope for v1. These findings are kept so that a later effort on public releases can start from them.

Confidence per point: **H** = high (primary source or code), **M** = medium, **U** = couldn't confirm.

## Where things stood

- **Install route chosen before the deferral:** both. The GitHub release is the source, and a Homebrew cask in a personal tap (`chris-metz/homebrew-tap`) points to the same file. The human agreed to this before parking the topic.
- **Open question at the time of parking:** whose name signs the app. The only local signing identity is `Apple Development: Kimberly Metz (BWB3QV333X)`, subject `O=Kimberly Metz, OU=D33L6SHDHW`. That is an individual membership, so a Developer ID certificate would read `Developer ID Application: Kimberly Metz (D33L6SHDHW)`. The options were to use this account, which needs the Account Holder to create the certificate, or to use another account (99 USD a year, plus a few days of enrollment).
- **Local toolchain:** macOS 27.0.1, Xcode 27.0, Swift 6.4, notarytool 1.1.3, Homebrew 7.0.7. No Developer ID certificate and no notarytool keychain profile exist yet.

## 1. GitHub-hosted runners

- **No `macos-27` label exists.** macOS 27 runs under `xcode-27` / `xcode-27-xlarge` (arm64 only), in public preview since 2026-07-16. The base OS switched to macOS 27 on 2026-09-16. GitHub now ships one image per major Xcode version. H. [runner-images#14404](https://github.com/actions/runner-images/issues/14404), [changelog](https://github.blog/changelog/2026-07-16-xcode-27-runner-image-now-in-public-preview/)
- **What `xcode-27` ships:** macOS 27.0 with Xcode 27.0 (default), 27.1 and 27.2 beta. It is a free standard runner for public repos. H. [image readme](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md), [runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- **`macos-26` can't build a macOS 27 target.** It only has Xcode 26.x, which caps the deployment target at 26.5. H. [macos-26 readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), [Xcode support](https://developer.apple.com/support/xcode/)
- **Snapshot tests on CI:** the reference images were rendered locally. A CI image could differ, so this is untested.

## 2. Homebrew casks in a third-party tap

- **Quarantine:** every cask download is quarantined, whatever the tap. Gatekeeper judges the app on first launch. H. [Security docs](https://docs.brew.sh/Homebrew-Security-and-Supply-Chain)
- **`--no-quarantine`:** removed in Homebrew 6.0.0. H. [5.0.0 notes](https://brew.sh/2025/11/12/homebrew-5.0.0/)
- **Unsigned casks:** Homebrew doesn't refuse them at install time. The signing audit only runs for official taps, or for others with `brew audit --signing`. The September 2026 removal of casks that fail Gatekeeper applies to `homebrew/cask` only. H. [audit.rb](https://github.com/Homebrew/brew/blob/main/Library/Homebrew/cask/audit.rb)
- **No translocation:** Homebrew sets the no-translocation quarantine bit, so brew-installed apps are never translocated. H. [quarantine.rb](https://github.com/Homebrew/brew/blob/main/Library/Homebrew/cask/quarantine.rb)
- **Auto-tap:** `brew install --cask chris-metz/tap/pacemark` taps `chris-metz/homebrew-tap` automatically. H. [Taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- **Tap trust (since 6.0.0):** a fully qualified install trusts that cask, and the trust persists. A short-name install needs `brew trust` first. H. [Tap Trust](https://docs.brew.sh/Tap-Trust)
- **Cask stanzas:**
  - Required: `version`, `sha256`, `url`, `name`, `desc`, `homepage`, `app`.
  - The symbol for macOS 27 is `depends_on macos: :golden_gate`.
  - For livecheck, `livecheck { url :url; strategy :github_latest }` fits. M.
  - `zap` is optional. H. [Cask Cookbook](https://docs.brew.sh/Cask-Cookbook), [macos_version.rb](https://github.com/Homebrew/brew/blob/main/Library/Homebrew/macos_version.rb)
- **A running app on upgrade:** add `uninstall quit: "xyz.chrismetz.pacemark"`. It quits the app, upgrades it, and reopens it (since 5.1.12). It may ask for Automation permission. Without it, the bundle is replaced under the running process. M. [upgrade.rb](https://github.com/Homebrew/brew/blob/main/Library/Homebrew/cask/upgrade.rb)
- **`brew upgrade`:** covers casks from trusted third-party taps. Don't set `auto_updates true`, or the cask is skipped. Since 6.0.10, an upgrade keeps the user's Gatekeeper approval when the signing identity matches. H.

## 3. Signing and notarization

- **Developer ID certificate:** only the Account Holder can create one, and there's a limit of 5. Its name reads `Developer ID Application: <Team name> (<Team ID>)`. H. [Apple](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- **notarytool credentials:** use a team API key or an Apple ID with an app-specific password, stored via `xcrun notarytool store-credentials <profile>`.
  - Once stored, `xcrun notarytool submit … --keychain-profile <profile> --wait` runs unattended. H. [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
  - Whether individual API keys work is contradictory in Apple's sources. U.
- **Hardened runtime:** spawning the separately signed `claude` binary needs no entitlement. H. [Hardened runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- **SwiftPM gotchas:**
  - Build with `-c release`, because debug builds inject `get-task-allow`, which notarization rejects.
  - Sign with `--options runtime --timestamp --force`, without `--deep`. H. [Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)
- **ZIP or DMG:**
  - A ZIP can't be stapled: staple the `.app`, then `ditto -c -k --keepParent`.
  - A DMG can be signed, notarized and stapled, which also makes it tamper-protected. H. [Packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- **Gatekeeper:** macOS 15 removed the Control-click override for un-notarized apps. No changes for macOS 26/27 were found. H/U. [Apple news](https://developer.apple.com/news/?id=saqachfa)

## 4. App Translocation and launch at login

- **Translocation:** a quarantined app launched in place, for example from `~/Downloads`, is translocated to a random read-only path until the user moves it in Finder. H. [forum](https://developer.apple.com/forums/thread/724969)
- **Effect on `SMAppService`:** Apple doesn't document how translocation affects it. Third-party reports say the login item stores the concrete path, so registering from a translocated copy or a DMG can leave a stale item. M/U. [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [report](https://github.com/joaodavidsilva/brightboi/issues/97)
- **What helps:** a DMG with an `/Applications` symlink nudges users toward copying the app into `/Applications`. Homebrew avoids translocation altogether. M.
