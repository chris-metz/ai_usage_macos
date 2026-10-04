#!/bin/sh
# Tests scripts/release-notes.sh against throwaway git repos.
set -eu

NOTES="$(cd "$(dirname "$0")" && pwd)/release-notes.sh"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
FAILURES=0

# Keep the user's git config (signing, hooks, templates) out of the repos.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com

# new_repo: cd into a fresh repo on main with one commit.
new_repo() {
    REPO="$(mktemp -d "$ROOT/repo.XXXXXX")"
    cd "$REPO"
    git init --quiet --initial-branch=main
    git commit --quiet --allow-empty -m "Initial commit"
}

# merge SUBJECT [BODY]: merges a branch with one commit into main.
merge() {
    git switch --quiet -c topic
    git commit --quiet --allow-empty -m "Work on the topic"
    git switch --quiet main
    git merge --quiet --no-ff --no-commit topic >/dev/null 2>&1
    if [ $# -gt 1 ]; then
        git commit --quiet -m "$1" -m "$2"
    else
        git commit --quiet -m "$1"
    fi
    git branch --quiet -D topic
}

# expect NAME EXPECTED ARGS...: runs release-notes.sh ARGS in the current repo.
expect() {
    NAME=$1
    EXPECTED=$2
    shift 2
    ACTUAL="$("$NOTES" "$@" 2>&1)" || true
    if [ "$ACTUAL" = "$EXPECTED" ]; then
        echo "ok - $NAME"
    else
        echo "not ok - $NAME"
        printf '  expected:\n%s\n  actual:\n%s\n' "$EXPECTED" "$ACTUAL"
        FAILURES=$((FAILURES + 1))
    fi
}

new_repo
merge "Merge open at login"
git tag v1.0.0
merge "Merge readable pace text"
expect "a merge since the tag becomes a capitalized bullet" \
    "- Readable pace text" v1.0.0

new_repo
merge "Merge open at login"
expect "without a tag, the notes of the first release" \
    "First release.

Requirements:

- macOS 27
- Claude Code 2.1.283 or later, installed and logged in"

new_repo
git tag v1.0.0
merge "Merge #30: Open at Login"
merge "Merge #29: choose the menu bar limit"
expect "merges with an issue number are listed oldest first" \
    "- Open at Login
- Choose the menu bar limit" v1.0.0

new_repo
git tag v1.0.0
merge "Merge pull request #35 from chris-metz/reset-line" "fix the reset line"
expect "a merge from GitHub's merge button uses the PR title" \
    "- Fix the reset line" v1.0.0

new_repo
git tag v1.0.0
git switch --quiet -c topic
git commit --quiet --allow-empty -m "Work on the topic"
git switch --quiet main
git commit --quiet --allow-empty -m "Fix a typo"
git switch --quiet topic
git merge --quiet --no-ff main -m "Merge branch 'main' into topic"
git switch --quiet main
git merge --quiet --no-ff topic -m "Merge reset line"
expect "direct commits and merges inside a branch stay out" \
    "- Reset line" v1.0.0

[ "$FAILURES" -eq 0 ] || { echo "$FAILURES failed"; exit 1; }
