#!/bin/bash
# Record a commit sha as reviewed, so the pre-push review-gate recognizes it.
# Called by review-loop on a clean loop exit (Step 14), before the auto-push decision.
#   record-reviewed.sh [<sha, default HEAD>]
set -euo pipefail
STORE="$HOME/.claude/review-loop/reviewed-shas"
mkdir -p "$(dirname "$STORE")"
sha=$(git rev-parse "${1:-HEAD}")
grep -qxF "$sha" "$STORE" 2>/dev/null || printf '%s\n' "$sha" >> "$STORE"
# Bound growth — keep the most recent 500.
if [ "$(wc -l < "$STORE" 2>/dev/null || echo 0)" -gt 500 ]; then
	tail -n 500 "$STORE" > "$STORE.tmp" && mv "$STORE.tmp" "$STORE"
fi
echo "review-gate: recorded reviewed sha ${sha:0:12}"
