#!/bin/bash
# Self-check for review-gate.sh: block unreviewed, pass when recorded, honor bypass.
set -euo pipefail
gate="$(dirname "$0")/review-gate.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"

mkdir -p "$tmp/repo"; cd "$tmp/repo"
git init -q
git config user.email me@example.com
git config user.name Me
git commit -q --allow-empty -m init
sha=$(git rev-parse HEAD)
zero=0000000000000000000000000000000000000000
line="refs/heads/main $sha refs/heads/main $zero"

# 1. Unreviewed commit I authored → blocked (exit 1).
if printf '%s\n' "$line" | "$gate" 2>/dev/null; then
	echo "FAIL: expected block on unreviewed commit"; exit 1
fi

# 2. Recorded as reviewed → passes.
mkdir -p "$HOME/.claude/review-loop"
echo "$sha" > "$HOME/.claude/review-loop/reviewed-shas"
if ! printf '%s\n' "$line" | "$gate" 2>/dev/null; then
	echo "FAIL: expected pass after recording sha"; exit 1
fi

# 3. Bypass env → passes even when unreviewed.
rm "$HOME/.claude/review-loop/reviewed-shas"
if ! printf '%s\n' "$line" | REVIEW_GATE_BYPASS=1 "$gate" 2>/dev/null; then
	echo "FAIL: expected pass with REVIEW_GATE_BYPASS=1"; exit 1
fi

# 4. Push that introduces only a foreign-authored commit → not gated (passes).
# Needs a real remote so my already-pushed commit is excluded by --not --remotes.
rm -f "$HOME/.claude/review-loop/reviewed-shas"
git init -q --bare "$tmp/remote.git"
git remote add origin "$tmp/remote.git"
git push -q origin HEAD:refs/heads/main   # my commit (sha) is now on the remote
GIT_COMMITTER_EMAIL=other@example.com GIT_AUTHOR_EMAIL=other@example.com \
	git commit -q --allow-empty -m other
sha2=$(git rev-parse HEAD)
# Only new commit vs the remote is other's → my authored set is empty → pass.
if ! printf '%s\n' "refs/heads/main $sha2 refs/heads/main $sha" | "$gate" 2>/dev/null; then
	echo "FAIL: push of only a foreign commit should not be gated"; exit 1
fi

echo "ok"
