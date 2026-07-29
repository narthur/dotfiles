#!/bin/bash
# review-gate: block pushing commits YOU authored that review-loop hasn't seen.
#
# Reads pre-push ref lines on stdin: <local_ref> <local_sha> <remote_ref> <remote_sha>
# "Reviewed" = the tip sha was recorded by review-loop's record-reviewed.sh into
# ~/.claude/review-loop/reviewed-shas. A commit added after review changes the tip,
# so it naturally re-triggers the gate.
#
# A tip may also be recorded as "skipped" (with a reason) in skipped-shas by
# record-skipped.sh — the honest path for a change judged beneath the loop. That
# clears the gate too, but keeps a distinct, auditable state: reviewed != skipped.
#
# Only gates commits authored by you (git user.email) that this push would newly
# publish — dependabot/teammate/upstream-merge-only pushes pass untouched.
#
# Bypass a single push:  REVIEW_GATE_BYPASS=1 git push

RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
STORE="$HOME/.claude/review-loop/reviewed-shas"
SKIP_STORE="$HOME/.claude/review-loop/skipped-shas"
MY_EMAIL=$(git config user.email 2>/dev/null | tr '[:upper:]' '[:lower:]')

# Can't attribute authorship without an email — don't gate.
[ -z "$MY_EMAIL" ] && exit 0

while read -r local_ref local_sha remote_ref remote_sha; do
	[ -z "$local_sha" ] && continue
	[ "$local_sha" = "0000000000000000000000000000000000000000" ] && continue  # branch deletion

	# Commits this push would newly publish (not on any remote yet) that I authored.
	mine=$(git rev-list "$local_sha" --not --remotes --author="$MY_EMAIL" 2>/dev/null)
	[ -z "$mine" ] && continue

	# Tip already reviewed? Then this exact state went through review-loop.
	grep -qxF "$local_sha" "$STORE" 2>/dev/null && continue

	# Tip deliberately skipped with a recorded reason? Honest bypass — allow it,
	# but surface the reason so a skipped push never looks like a reviewed one.
	if grep -q "^${local_sha}[[:space:]]" "$SKIP_STORE" 2>/dev/null; then
		reason=$(grep "^${local_sha}[[:space:]]" "$SKIP_STORE" | head -1 | cut -f3-)
		echo -e "${YELLOW}review-gate: tip ${local_sha:0:12} recorded as skipped (not reviewed) — ${reason}${NC}" >&2
		continue
	fi

	if [ "$REVIEW_GATE_BYPASS" = "1" ]; then
		echo -e "${YELLOW}review-gate: bypassed (REVIEW_GATE_BYPASS=1)${NC}" >&2
		continue
	fi

	branch=$(echo "${remote_ref:-$local_ref}" | sed 's|refs/heads/||')
	echo -e "\n${RED}${BOLD}!! PUSH BLOCKED — commits not reviewed by review-loop !!${NC}" >&2
	echo -e "  Branch: ${YELLOW}${branch}${NC}" >&2
	echo -e "  Tip ${YELLOW}${local_sha:0:12}${NC} isn't in the reviewed set, and you authored unpushed commit(s) under it." >&2
	echo -e "  Run ${BOLD}review-loop${NC} first. If this is genuinely beneath the loop, record that" >&2
	echo -e "  honestly: ${BOLD}record-skipped.sh \"<reason>\"${NC} — do NOT hand-call record-reviewed.sh." >&2
	echo -e "  Or bypass this one push without recording: ${BOLD}REVIEW_GATE_BYPASS=1 git push${NC}\n" >&2
	exit 1
done

exit 0
