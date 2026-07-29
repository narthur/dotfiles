#!/bin/bash
# Self-heal: ensure a husky repo has the untracked .husky/pre-push delegator that
# hands pre-push control to the global review-gate. Husky's local core.hooksPath
# shadows the global hook, so without this the gate never fires here.
#
# No-op unless this is a husky repo that lacks the delegator. Never modifies an
# existing .husky/pre-push (it may be a tracked, team-owned hook) — just warns.
# Called by review-loop at Step 0.
set -euo pipefail

hp=$(git config --get core.hooksPath 2>/dev/null || true)
case "$hp" in
	*.husky*) ;;      # husky points core.hooksPath into .husky/_
	*) exit 0 ;;      # not a husky repo — the global hook already runs
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
hook="$root/.husky/pre-push"
[ -d "$root/.husky" ] || exit 0

if [ -f "$hook" ]; then
	grep -q 'review-gate.sh' "$hook" && exit 0   # already delegating — done
	echo "review-gate: $root/.husky/pre-push exists without the gate line; add it by hand if you want gating here" >&2
	exit 0
fi

# Create the untracked delegator.
{
	echo '#!/usr/bin/env sh'
	echo '# Personal review-loop gate (local, untracked). Delegates to the global gate;'
	echo '# no-ops if the shared script is absent (e.g. on a teammate machine).'
	echo '[ -x "$HOME/.git-hooks/review-gate.sh" ] && "$HOME/.git-hooks/review-gate.sh" "$@"'
} > "$hook"
chmod +x "$hook"

# Keep it out of git tracking/status via the repo-local exclude.
excl="$root/.git/info/exclude"
mkdir -p "$(dirname "$excl")"
grep -qxF '.husky/pre-push' "$excl" 2>/dev/null || echo '.husky/pre-push' >> "$excl"

echo "review-gate: added untracked .husky/pre-push delegator in $root"
