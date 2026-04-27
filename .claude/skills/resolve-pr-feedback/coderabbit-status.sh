#!/usr/bin/env bash

# coderabbit-status.sh - Determine CodeRabbit's current review status
# Usage:
#   coderabbit-status.sh [--json]
#
# Consults both the CodeRabbit check status and CodeRabbit's first PR
# comment to produce a single combined status. CodeRabbit's first comment
# is a living status document edited in-place as it moves through states
# (reviewing, paused, rate limited, completed, etc.). Later comments are
# review-specific replies. These two signals (check + first comment) can
# disagree, so both are needed.
#
# Statuses (stdout):
#   not_started   - No check and no comment from CodeRabbit
#   starting_up   - Check is pending but no comment yet
#   in_progress   - CodeRabbit is actively reviewing
#   completed     - Review finished
#   timed_out     - CodeRabbit timed out
#   paused        - Auto-reviews disabled; manual review request needed
#   rate_limited  - CodeRabbit hit a rate limit
#
# With --json, outputs a JSON object with fields:
#   status, check_state, comment_state, wait_seconds (for rate_limited)
#
# Exit codes: 0 = success, 1 = error (e.g. no PR found)

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/pr-feedback-common.sh"

JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUTPUT=true; shift;;
    -h|--help)
      cat <<EOF
Usage: $0 [--json]

Determines CodeRabbit's current review status by combining the check
status from \`gh pr checks\` with CodeRabbit's first PR comment (a living
status document that CodeRabbit edits in-place).

Options:
  --json    Output a JSON object instead of a single status word
  -h        Show this help

Possible statuses:
  not_started   No check and no comment from CodeRabbit
  starting_up   Check is pending but no comment yet
  in_progress   CodeRabbit is actively reviewing
  completed     Review finished
  timed_out     CodeRabbit timed out
  paused        Auto-reviews disabled; manual review request needed
  rate_limited  CodeRabbit hit a rate limit (wait_seconds may be set)
EOF
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── Gather check status ─────────────────────────────────────────────

check_state="not_present"

checks_output=$(gh pr checks 2>/dev/null) || true

if [[ -n "$checks_output" ]]; then
  # Look for a line containing "CodeRabbit" (case-insensitive)
  cr_line=$(echo "$checks_output" | grep -i 'coderabbit' | head -1) || true

  if [[ -n "$cr_line" ]]; then
    # gh pr checks columns: NAME\tSTATUS\t...
    # Status keywords: pass, fail, pending, *
    if echo "$cr_line" | grep -qiw 'pass'; then
      check_state="completed"
    elif echo "$cr_line" | grep -qiw 'fail'; then
      check_state="completed"
    elif echo "$cr_line" | grep -qiw 'pending'; then
      check_state="pending"
    else
      check_state="pending"
    fi
  fi
fi

# ── Gather comment status ───────────────────────────────────────────

comment_state="not_present"
wait_seconds=0

RATE_LIMIT_PATTERNS='rate limit|rate-limit|too many requests|please try again|will review once|API rate limit exceeded'
TIMEOUT_PATTERNS='timed out|timeout|timed-out'
PAUSED_PATTERNS='paused|review paused|reviews are paused|auto-reviews are disabled|auto-review is disabled|reviews are disabled'
REVIEWING_PATTERNS='<!-- This is an auto-generated comment: summarize by coderabbit.ai -->|Walkthrough|<!-- This is an auto-generated comment: review status by coderabbit.ai -->|<!-- This is an auto-generated comment: raw summary by coderabbit.ai -->'

# CodeRabbit's first comment on a PR is a living status document that it
# edits in-place as it moves through states (reviewing, paused, completed,
# rate limited, etc.). Later comments are review-specific replies (e.g.
# "Review triggered"). We read the first comment to get the current status.
pr_json=$(gh pr view --json 'comments' 2>/dev/null) || {
  echo "Error: Could not fetch PR data. Is there a PR for this branch?" >&2
  exit 1
}

cr_body=$(echo "$pr_json" | jq -r '
  [.comments[]? | select(.author.login == "coderabbitai" or .author.login == "coderabbitai[bot]")]
  | sort_by(.createdAt) | first // empty
  | .body // empty
')

# The first comment has two sections: a status header (paused/reviewing/etc.)
# followed by a walkthrough describing code changes. The walkthrough can
# contain arbitrary text (e.g. "10s timeout") that would cause false matches,
# so we only classify the status header section.
cr_status_section="${cr_body%%<!-- walkthrough_start -->*}"

if [[ -n "$cr_body" ]]; then
  # Classify the status section of the comment
  if echo "$cr_status_section" | grep -qiP "$RATE_LIMIT_PATTERNS"; then
    comment_state="rate_limited"
    # Extract wait time from messages like "wait 45 minutes and 9 seconds"
    wait_min=$(echo "$cr_status_section" | grep -oiP '(\d+)\s*minutes?' | grep -oP '\d+' | head -1) || true
    wait_sec=$(echo "$cr_status_section" | grep -oiP '(\d+)\s*seconds?' | grep -oP '\d+' | head -1) || true
    if [[ -n "$wait_min" || -n "$wait_sec" ]]; then
      wait_seconds=$(( ${wait_min:-0} * 60 + ${wait_sec:-0} ))
    else
      wait_seconds=180  # default 3 minutes
    fi
  elif echo "$cr_status_section" | grep -qiP "$TIMEOUT_PATTERNS"; then
    comment_state="timed_out"
  elif echo "$cr_status_section" | grep -qiP "$PAUSED_PATTERNS"; then
    comment_state="paused"
  elif echo "$cr_status_section" | grep -qiP "$REVIEWING_PATTERNS"; then
    # Check if this is a completed review (has actionable items or approval)
    # vs still in progress (walkthrough posted but review threads may still be coming)
    # A completed review will have "Actionable comments" or review thread markers
    if echo "$cr_status_section" | grep -qiP 'Actionable comments|no issues found|no actionable comments|Changes approved|LGTM'; then
      comment_state="completed"
    else
      comment_state="reviewing"
    fi
  else
    # Has content but doesn't match known patterns — treat as completed
    comment_state="completed"
  fi
fi

# ── Combine signals into a single status ────────────────────────────

status=""

case "${check_state}:${comment_state}" in
  pending:not_present)     status="starting_up" ;;
  pending:reviewing)       status="in_progress" ;;
  pending:completed)       status="in_progress" ;;   # re-reviewing
  pending:rate_limited)    status="rate_limited" ;;
  pending:timed_out)       status="timed_out" ;;
  pending:paused)           status="paused" ;;
  completed:not_present)   status="completed" ;;
  completed:reviewing)     status="in_progress" ;;   # check finished early
  completed:completed)     status="completed" ;;
  completed:rate_limited)  status="rate_limited" ;;
  completed:timed_out)     status="timed_out" ;;
  completed:paused)         status="paused" ;;
  not_present:not_present) status="not_started" ;;
  not_present:reviewing)   status="in_progress" ;;
  not_present:completed)   status="completed" ;;
  not_present:rate_limited) status="rate_limited" ;;
  not_present:timed_out)   status="timed_out" ;;
  not_present:paused)       status="paused" ;;
  *)                       status="not_started" ;;
esac

# ── Output ──────────────────────────────────────────────────────────

if [[ "$JSON_OUTPUT" == true ]]; then
  jq -n \
    --arg status "$status" \
    --arg check_state "$check_state" \
    --arg comment_state "$comment_state" \
    --argjson wait_seconds "$wait_seconds" \
    '{status: $status, check_state: $check_state, comment_state: $comment_state, wait_seconds: $wait_seconds}'
else
  echo "$status"
fi
