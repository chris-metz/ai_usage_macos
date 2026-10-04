# Releases signed with an existing team's Developer ID and installed via an own Homebrew tap

Pacemark is released as a DMG on GitHub Releases, signed with a Developer ID and notarized, and installed via the cask `pacemark` in the own tap `chris-metz/homebrew-tap` (`brew install --cask chris-metz/tap/pacemark`). The Developer ID belongs to an existing paid individual team that isn't the human's own: the human's Apple ID only has a free Personal Team, which can't issue a Developer ID. The Account Holder of that team agreed that every copy shows their full name and Team ID, which is all a Developer ID certificate exposes (its country field always reads `US`): no address or contact data. The repo itself names neither; the scripts pick the first `Developer ID Application` identity in the keychain. The tap is a repo of its own because Homebrew installs casks only from a tap, and only a repo named `homebrew-<name>` allows the one-line install.

## Considered Options

- **An own paid membership for the human:** their own name on the app and no dependency on someone else's membership, but 99 USD a year and an enrollment that takes days.
- **No Developer ID (ad hoc signed):** no name public at all, but Gatekeeper blocks the first launch and likely every update. Since macOS 15 the user has to allow the app in System Settings, and Homebrew 6 removed `--no-quarantine`.
- **The cask in the app repo:** no second repo, but installing takes `brew tap` with an explicit URL plus `brew install`, and Homebrew clones the whole app repo.
- **A cask with `version :latest`** pointing at `releases/latest`: never needs updating, but a plain `brew upgrade` skips it.
- **`homebrew/cask`:** rejects apps that aren't notable yet.
- **Building releases on GitHub Actions:** would put the Developer ID key and the notarization access into GitHub secrets, and macOS 27 runs there only on the preview image `xcode-27`.

## Consequences

- **Hard to reverse:** a different signer makes macOS see the app as someone else's, and Homebrew keeps a user's Gatekeeper approval across upgrades only while the signing identity stays the same. Moving the tap breaks `brew upgrade` for everyone who installed from it.
- **The Account Holder's part:** only they can create the Developer ID certificate and the notarization access (`scripts/setup-release.sh` walks through it), and new releases need their membership to stay active. Releases already out keep working.
- **Built locally** by `scripts/release.sh <version>` on the human's Mac, so the Developer ID key never leaves its login keychain. Moving to CI later keeps the script.
- **A DMG with a link to `/Applications`,** because launch at login remembers where the app lives, and a quarantined app started from `~/Downloads` is translocated. Homebrew users aren't affected either way.
- **Versions** are `X.Y.Z` with tags `vX.Y.Z`; the first release is `1.0.0`, matching the v1 spec. Release notes are the titles of the merge commits on `main` since the last tag, so features keep landing as merges.
- **Local builds stay as they are** (`scripts/install.sh`, Apple Development identity, no notarization, see [How does a release reach users?](https://github.com/chris-metz/pacemark/issues/15)). The human's own Mac doesn't install Pacemark via Homebrew, because `install.sh` and Homebrew both write `/Applications/Pacemark.app`.
