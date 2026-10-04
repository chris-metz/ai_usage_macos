#!/bin/sh
# Builds Pacemark, replaces /Applications/Pacemark.app and launches it.
# It always goes to /Applications, because the login item remembers the
# location. It doesn't run the tests.
set -eu

cd "$(dirname "$0")/.."

scripts/bundle.sh

# Quit a running Pacemark and wait until it's gone. Killing it is safe:
# there is nothing to save on quit.
pkill -x Pacemark || true
while pgrep -x Pacemark >/dev/null; do
    sleep 0.1
done

rm -rf /Applications/Pacemark.app
ditto build/Pacemark.app /Applications/Pacemark.app

open /Applications/Pacemark.app
echo "Installed and launched /Applications/Pacemark.app"

# Homebrew still counts a release it installed as its own and would bring it
# back over this build.
if command -v brew >/dev/null && brew list --cask pacemark >/dev/null 2>&1; then
    echo "Warning: Homebrew lists the cask pacemark, so the next brew upgrade replaces" >&2
    echo "this local build with the release. To end that, run brew uninstall --cask" >&2
    echo "pacemark, which also removes this build, then scripts/install.sh again." >&2
fi
