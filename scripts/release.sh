#!/bin/sh
# Builds and publishes a release (docs/adr/0003-signed-releases-via-own-homebrew-tap.md):
# a signed, notarized DMG on GitHub Releases and the cask in the tap.
# Everything up to the verified DMG is local and --dry-run stops there, so a
# failure before the public steps publishes nothing.
# Usage: scripts/release.sh [--dry-run] X.Y.Z
set -eu

cd "$(dirname "$0")/.."

REPO=chris-metz/pacemark
TAP_REPO=chris-metz/homebrew-tap
NOTARY_PROFILE=pacemark-notary

usage() {
    echo "Usage: $0 [--dry-run] X.Y.Z" >&2
    exit 2
}
fail() {
    echo "Can't release: $1" >&2
    exit 1
}
step() { printf '\n==> %s\n' "$1"; }

# version_above A B: whether version A is above version B, both X.Y.Z.
version_above() {
    echo "$1 $2" | awk '{
        split($1, a, "."); split($2, b, ".")
        for (i = 1; i <= 3; i++) if (a[i] != b[i]) exit !(a[i] + 0 > b[i] + 0)
        exit 1
    }'
}

# notarize FILE: submits FILE to Apple's notary service and waits for the
# verdict. Unless Apple accepts it, prints Apple's log and stops.
notarize() {
    RESULT="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" \
        --wait --output-format plist)" || true
    STATUS="$(printf '%s' "$RESULT" | plutil -extract status raw -o - - 2>/dev/null)" || true
    if [ "$STATUS" != Accepted ]; then
        echo "Notarizing $1 failed${STATUS:+ with status $STATUS}." >&2
        if ID="$(printf '%s' "$RESULT" | plutil -extract id raw -o - - 2>/dev/null)"; then
            xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
        else
            printf '%s\n' "$RESULT" >&2
        fi
        exit 1
    fi
    echo "Apple accepted $1"
}

DRY_RUN=
VERSION=
for ARG in "$@"; do
    case $ARG in
        --dry-run) DRY_RUN=1 ;;
        -*) usage ;;
        *)
            [ -z "$VERSION" ] || usage
            VERSION=$ARG
            ;;
    esac
done
[ -n "$VERSION" ] || usage

TAG="v$VERSION"
APP=build/Pacemark.app
ZIP=build/Pacemark.zip
DMG="build/Pacemark-$VERSION.dmg"
DMG_ROOT=build/dmg
NOTES=build/release-notes.md
CASK=build/pacemark.rb

# 1. Check everything a release needs, before building anything.
step "Checking"
echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "$VERSION isn't of the form X.Y.Z"
[ "$(git branch --show-current)" = main ] || fail "not on main"
[ -z "$(git status --porcelain)" ] || fail "the working tree isn't clean"
git fetch --quiet --tags origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main isn't in sync with origin/main"
if git rev-parse --quiet --verify "refs/tags/$TAG" >/dev/null; then
    fail "the tag $TAG exists already"
fi
LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)" || LAST_TAG=
if [ -n "$LAST_TAG" ] && ! version_above "$VERSION" "${LAST_TAG#v}"; then
    fail "$VERSION isn't above the last tag $LAST_TAG"
fi
gh auth status >/dev/null 2>&1 || fail "gh isn't logged in, run gh auth login"
[ "$(gh api "repos/$TAP_REPO" --jq .permissions.push 2>/dev/null)" = true ] ||
    fail "gh can't push to $TAP_REPO"
DEVELOPER_ID="$(security find-identity -v -p codesigning | awk '/"Developer ID Application: / { print $2; exit }')"
[ -n "$DEVELOPER_ID" ] ||
    fail "no Developer ID Application identity in the keychain, see scripts/setup-release.sh"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
    fail "the notarytool profile $NOTARY_PROFILE doesn't work, see scripts/setup-release.sh"
mkdir -p build
scripts/release-notes.sh "$LAST_TAG" >"$NOTES"
[ -s "$NOTES" ] || fail "nothing was merged into main since $LAST_TAG"
echo "Releasing $VERSION${LAST_TAG:+ after $LAST_TAG}"

# 2. Test.
step "Testing"
swift test
scripts/release-notes-test.sh

# 3. Build, then notarize and staple the app on its own, so it also passes
#    Gatekeeper offline once it's copied out of the DMG.
step "Building"
scripts/bundle.sh --release "$VERSION"

step "Notarizing the app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
rm "$ZIP"
xcrun stapler staple "$APP"

# 4. The DMG: the app and a link to /Applications, signed, notarized and
#    stapled.
step "Packaging"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/Pacemark.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -quiet -ov -volname Pacemark -srcfolder "$DMG_ROOT" -format UDZO "$DMG"
rm -rf "$DMG_ROOT"
codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"

step "Notarizing the DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

step "Verifying"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
# Without --verbose, which would print the identity's name.
spctl --assess --type execute "$APP"
spctl --assess --type open --context context:primary-signature "$DMG"
echo "Gatekeeper accepts $APP and $DMG"

# 5. The cask, for the stapled DMG.
step "Writing the cask"
SHA256="$(shasum -a 256 "$DMG" | awk '{ print $1 }')"
cat >"$CASK" <<EOF
cask "pacemark" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPO/releases/download/v#{version}/Pacemark-#{version}.dmg"
  name "Pacemark"
  desc "Menu bar app showing how much of your AI subscription limits you have used"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :golden_gate

  app "Pacemark.app"

  uninstall quit: "xyz.chrismetz.pacemark"

  zap trash: [
    "~/Library/Caches/xyz.chrismetz.pacemark",
    "~/Library/Preferences/xyz.chrismetz.pacemark.plist",
  ]
end
EOF
echo "Wrote $CASK"

if [ -n "$DRY_RUN" ]; then
    printf '\nDry run done: %s is notarized and verified. Nothing is published.\n' "$DMG"
    printf 'The release notes would be:\n\n'
    cat "$NOTES"
    exit
fi

# 6. Publish: the tag, the GitHub release, then the cask in the tap. A rerun
#    stops at the existing tag, so a failure here needs finishing by hand.
step "Publishing"
trap '[ $? -eq 0 ] || echo "Publishing stopped half way. Finish its remaining steps by hand from build/ (the DMG, release notes and cask), or delete the GitHub release and the tag $TAG and run again." >&2' EXIT
git tag -a "$TAG" -m "Pacemark $VERSION"
git push --quiet origin "$TAG"
gh release create "$TAG" "$DMG" --repo "$REPO" --verify-tag \
    --title "Pacemark $VERSION" --notes-file "$NOTES"

CASK_PATH=Casks/pacemark.rb
# The contents API needs the blob of the cask it replaces, if there is one.
CASK_BLOB="$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq .sha 2>/dev/null)" || CASK_BLOB=
set -- --method PUT "repos/$TAP_REPO/contents/$CASK_PATH" \
    -f message="pacemark $VERSION" -f content="$(base64 -i "$CASK")"
[ -z "$CASK_BLOB" ] || set -- "$@" -f sha="$CASK_BLOB"
gh api --silent "$@"
echo "Updated $CASK_PATH in $TAP_REPO"

printf '\nReleased Pacemark %s: brew install --cask chris-metz/tap/pacemark\n' "$VERSION"
