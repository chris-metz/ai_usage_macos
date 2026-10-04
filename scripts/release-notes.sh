#!/bin/sh
# Prints the release notes for the merges into the current branch since TAG:
# one bullet per first-parent merge commit, by its title. Without TAG (the
# first release), "First release." and the requirements from the README.
# Runs in the current directory's repo.
# Usage: scripts/release-notes.sh [TAG]
set -eu

TAG=${1:-}

if [ -z "$TAG" ]; then
    cat <<'EOF'
First release.

Requirements:

- macOS 27
- Claude Code 2.1.283 or later, installed and logged in
EOF
    exit
fi

for COMMIT in $(git rev-list --first-parent --merges --reverse "$TAG..HEAD"); do
    TITLE="$(git log -1 --format=%s "$COMMIT")"
    case $TITLE in
        # GitHub's merge button puts the PR title in the body's first line.
        "Merge pull request #"*) TITLE="$(git log -1 --format=%b "$COMMIT" | awk 'NF { print; exit }')" ;;
        *) TITLE="$(printf '%s\n' "$TITLE" | sed -E 's/^Merge (#[0-9]+: )?//')" ;;
    esac
    printf '%s\n' "$TITLE" | awk '{ print "- " toupper(substr($0, 1, 1)) substr($0, 2) }'
done
