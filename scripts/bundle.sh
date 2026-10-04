#!/bin/sh
# Turns the SwiftPM build into build/Pacemark.app and signs it.
# Usage: scripts/bundle.sh                    a local build, as install.sh makes
#        scripts/bundle.sh --release X.Y.Z    a release build, as release.sh makes
set -eu

cd "$(dirname "$0")/.."

case "${1:-}" in
    "") RELEASE= ;;
    --release)
        [ $# -eq 2 ] && [ -n "$2" ] || { echo "Usage: $0 [--release X.Y.Z]" >&2; exit 2; }
        RELEASE=1
        VERSION=$2
        ;;
    *) echo "Usage: $0 [--release X.Y.Z]" >&2; exit 2 ;;
esac

APP=build/Pacemark.app
CONTENTS="$APP/Contents"
PLIST="$CONTENTS/Info.plist"

# 1. Build.
swift build -c release --product Pacemark
BINARY="$(swift build -c release --show-bin-path)/Pacemark"

# 2. Copy the binary.
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS"
cp "$BINARY" "$CONTENTS/MacOS/Pacemark"

# 3. Compile the icon into Assets.car plus a fallback AppIcon.icns. actool
#    can exit 0 without writing them when it can't read the icon, so check.
#    It reports errors as a plist on stdout: keep it for when a step fails.
#    Its paths are absolute, since actool can resolve relative ones against
#    the checkout it ran in before.
mkdir -p "$CONTENTS/Resources"
ACTOOL_REPORT=build/actool-report.plist
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$CONTENTS/Resources" \
    --app-icon AppIcon --platform macosx --target-device mac \
    --minimum-deployment-target 27.0 --output-partial-info-plist "$PWD/build/partial.plist" \
    >"$ACTOOL_REPORT" || {
    echo "actool failed on Resources/AppIcon.icon. Its report:" >&2
    cat "$ACTOOL_REPORT" >&2
    exit 1
}
for FILE in Assets.car AppIcon.icns; do
    if [ ! -f "$CONTENTS/Resources/$FILE" ]; then
        echo "actool didn't produce $FILE from Resources/AppIcon.icon. Its report:" >&2
        cat "$ACTOOL_REPORT" >&2
        exit 1
    fi
done

# 4. Write Info.plist. CFBundleVersion is the commit count, since macOS
#    expects digits and dots there; the commit hash goes to PacemarkGitCommit.
#    A local build carries the version of the last release it contains.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -z "$RELEASE" ]; then
        LAST_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
        VERSION="${LAST_TAG#v}"
    fi
    BUNDLE_VERSION="$(git rev-list --count HEAD)"
    COMMIT="$(git rev-parse --short HEAD)"
    if [ -n "$(git status --porcelain)" ]; then
        COMMIT="$COMMIT-dirty"
    fi
else
    BUNDLE_VERSION=1
    COMMIT=
fi
VERSION="${VERSION:-0.1}"

plutil -create xml1 "$PLIST"
plutil -insert CFBundleIdentifier -string xyz.chrismetz.pacemark "$PLIST"
plutil -insert CFBundleName -string Pacemark "$PLIST"
plutil -insert CFBundleDisplayName -string Pacemark "$PLIST"
plutil -insert CFBundleExecutable -string Pacemark "$PLIST"
plutil -insert CFBundlePackageType -string APPL "$PLIST"
plutil -insert CFBundleShortVersionString -string "$VERSION" "$PLIST"
plutil -insert CFBundleVersion -string "$BUNDLE_VERSION" "$PLIST"
if [ -n "$COMMIT" ]; then
    plutil -insert PacemarkGitCommit -string "$COMMIT" "$PLIST"
fi
plutil -insert LSMinimumSystemVersion -string 27.0 "$PLIST"
plutil -insert LSUIElement -bool YES "$PLIST"
plutil -insert CFBundleDevelopmentRegion -string en "$PLIST"
# Add actool's CFBundleIconName and CFBundleIconFile (both AppIcon).
/usr/libexec/PlistBuddy -c "Merge build/partial.plist" "$PLIST"

# 5. Sign. A release build gets the first Developer ID Application identity,
#    with the hardened runtime and a secure timestamp, as notarization
#    requires. A local build gets the first Apple Development identity, else
#    ad hoc. No hardened runtime and no notarization: a locally built app
#    isn't quarantined. A release build doesn't print the identity's name, so
#    release logs don't carry it.
if [ -n "$RELEASE" ]; then
    KIND="Developer ID Application: "
else
    KIND="Apple Development"
fi
IDENTITY_LINE="$(security find-identity -v -p codesigning | grep -m 1 "\"$KIND")" || true
IDENTITY_HASH="$(echo "$IDENTITY_LINE" | awk '{ print $2 }')"
if [ -n "$RELEASE" ]; then
    if [ -z "$IDENTITY_HASH" ]; then
        echo "No Developer ID Application identity found in the keychain" >&2
        exit 1
    fi
    echo "Signing with the Developer ID Application identity"
    codesign --force --options runtime --timestamp --sign "$IDENTITY_HASH" "$APP"
elif [ -n "$IDENTITY_HASH" ]; then
    echo "Signing with $(echo "$IDENTITY_LINE" | awk -F'"' '{ print $2 }')"
    codesign --force --sign "$IDENTITY_HASH" "$APP"
else
    echo "No Apple Development identity found, signing ad hoc"
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "Built $APP (version $VERSION, build $BUNDLE_VERSION${COMMIT:+, commit $COMMIT})"
