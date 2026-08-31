#!/bin/bash
# Self-check for ensure-husky-gate.sh: creates delegator in a husky repo, is
# idempotent, no-ops in non-husky repos, and won't clobber an existing hook.
set -euo pipefail
# Absolute: the tests cd into temp repos, so a $0-relative path breaks after the first cd.
script="$(cd "$(dirname "$0")" && pwd)/ensure-husky-gate.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- husky repo missing the delegator → creates it, adds to exclude ---
hr="$tmp/husky"; mkdir -p "$hr"; cd "$hr"
git init -q
mkdir -p .husky/_
git config core.hooksPath .husky/_
"$script" >/dev/null
[ -f .husky/pre-push ] || { echo "FAIL: delegator not created"; exit 1; }
grep -q 'review-gate.sh' .husky/pre-push || { echo "FAIL: delegator missing gate call"; exit 1; }
grep -qxF '.husky/pre-push' .git/info/exclude || { echo "FAIL: not excluded"; exit 1; }
[ -x .husky/pre-push ] || { echo "FAIL: not executable"; exit 1; }

# --- idempotent: second run adds no duplicate exclude line, no change ---
before=$(md5 -q .husky/pre-push 2>/dev/null || md5sum .husky/pre-push)
"$script" >/dev/null
after=$(md5 -q .husky/pre-push 2>/dev/null || md5sum .husky/pre-push)
[ "$before" = "$after" ] || { echo "FAIL: not idempotent (hook changed)"; exit 1; }
[ "$(grep -cxF '.husky/pre-push' .git/info/exclude)" = "1" ] || { echo "FAIL: duplicate exclude line"; exit 1; }

# --- non-husky repo → no-op ---
nr="$tmp/plain"; mkdir -p "$nr"; cd "$nr"
git init -q
"$script" >/dev/null
[ -e .husky/pre-push ] || true  # nothing to create
[ ! -d .husky ] || { echo "FAIL: touched non-husky repo"; exit 1; }

# --- husky repo with a pre-existing custom hook → left untouched ---
er="$tmp/existing"; mkdir -p "$er/.husky"; cd "$er"
git init -q; git config core.hooksPath .husky/_; mkdir -p .husky/_
printf '#!/bin/sh\necho custom\n' > .husky/pre-push
"$script" 2>/dev/null || true
grep -q 'review-gate.sh' .husky/pre-push && { echo "FAIL: clobbered existing hook"; exit 1; }
grep -q custom .husky/pre-push || { echo "FAIL: lost existing hook content"; exit 1; }

echo "ok"
