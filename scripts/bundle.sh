#!/bin/sh
# Turns the SwiftPM build into build/Pacemark.app and signs it.
set -eu

cd "$(dirname "$0")/.."

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
mkdir -p "$CONTENTS/Resources"
xcrun actool Resources/AppIcon.icon --compile "$CONTENTS/Resources" \
    --app-icon AppIcon --platform macosx --target-device mac \
    --minimum-deployment-target 27.0 --output-partial-info-plist build/partial.plist \
    >/dev/null
for FILE in Assets.car AppIcon.icns; do
    if [ ! -f "$CONTENTS/Resources/$FILE" ]; then
        echo "actool didn't produce $FILE from Resources/AppIcon.icon" >&2
        exit 1
    fi
done

# 4. Write Info.plist. CFBundleVersion is the commit count, since macOS
#    expects digits and dots there; the commit hash goes to PacemarkGitCommit.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BUNDLE_VERSION="$(git rev-list --count HEAD)"
    COMMIT="$(git rev-parse --short HEAD)"
    if [ -n "$(git status --porcelain)" ]; then
        COMMIT="$COMMIT-dirty"
    fi
else
    BUNDLE_VERSION=1
    COMMIT=
fi

plutil -create xml1 "$PLIST"
plutil -insert CFBundleIdentifier -string xyz.chrismetz.pacemark "$PLIST"
plutil -insert CFBundleName -string Pacemark "$PLIST"
plutil -insert CFBundleDisplayName -string Pacemark "$PLIST"
plutil -insert CFBundleExecutable -string Pacemark "$PLIST"
plutil -insert CFBundlePackageType -string APPL "$PLIST"
plutil -insert CFBundleShortVersionString -string 0.1 "$PLIST"
plutil -insert CFBundleVersion -string "$BUNDLE_VERSION" "$PLIST"
if [ -n "$COMMIT" ]; then
    plutil -insert PacemarkGitCommit -string "$COMMIT" "$PLIST"
fi
plutil -insert LSMinimumSystemVersion -string 27.0 "$PLIST"
plutil -insert LSUIElement -bool YES "$PLIST"
plutil -insert CFBundleDevelopmentRegion -string en "$PLIST"
# Add actool's CFBundleIconName and CFBundleIconFile (both AppIcon).
/usr/libexec/PlistBuddy -c "Merge build/partial.plist" "$PLIST"

# 5. Sign with the first Apple Development identity, else ad hoc. No
#    hardened runtime and no notarization: a locally built app isn't
#    quarantined.
IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development/ { print $2; exit }')"
if [ -n "$IDENTITY" ]; then
    echo "Signing with $(security find-identity -v -p codesigning | awk -F'"' '/"Apple Development/ { print $2; exit }')"
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "No Apple Development identity found, signing ad hoc"
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "Built $APP (version 0.1, build $BUNDLE_VERSION${COMMIT:+, commit $COMMIT})"
