#!/bin/bash
# Record a commit sha as DELIBERATELY SKIPPED — judged beneath the review loop
# (a tiny comment/doc/config follow-up) and consciously NOT run through it. Clears
# the pre-push review-gate while keeping an honest, auditable record of that call.
#
# This is the honest counterpart to record-reviewed.sh, NOT a substitute for it:
# it writes a DIFFERENT state (skipped, with your reason) on purpose. If a real
# review pass actually ran — even the Step 3b fast path — use record-reviewed.sh.
# Hand-calling record-reviewed.sh on a change no loop looked at records a review
# that never happened; that is the exact dishonesty this tool exists to make
# unnecessary. A reason is required so the record can't be a silent rubber-stamp.
#
#   record-skipped.sh "<reason>" [<sha, default HEAD>]
set -euo pipefail
reason="${1:-}"
if [ -z "$reason" ]; then
	echo "record-skipped: a reason is required — e.g. record-skipped.sh 'comment-only, actionlint green'" >&2
	exit 1
fi
STORE="$HOME/.claude/review-loop/skipped-shas"
mkdir -p "$(dirname "$STORE")"
sha=$(git rev-parse "${2:-HEAD}")
# One line per sha (tab-separated: sha, date, reason); refresh if re-recorded.
if [ -f "$STORE" ]; then
	grep -v "^$sha	" "$STORE" > "$STORE.tmp" 2>/dev/null || true
	mv "$STORE.tmp" "$STORE"
fi
printf '%s\t%s\t%s\n' "$sha" "$(date +%F)" "$reason" >> "$STORE"
# Bound growth — keep the most recent 500.
if [ "$(wc -l < "$STORE" 2>/dev/null || echo 0)" -gt 500 ]; then
	tail -n 500 "$STORE" > "$STORE.tmp" && mv "$STORE.tmp" "$STORE"
fi
echo "review-gate: recorded SKIPPED sha ${sha:0:12} — $reason"
