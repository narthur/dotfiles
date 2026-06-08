#!/usr/bin/env bash

# wait-for-review.sh - Wait for CodeRabbit to finish reviewing after a push
# Usage:
#   wait-for-review.sh [--workspace-type gitbutler|standard]
#
# Handles the full post-push flow:
#   1. Sleeps 1 minute to let CodeRabbit register the push
#   2. Checks CodeRabbit status; requests a review if paused or if draft PR needs one
#   3. Polls for review completion (up to ~20 minutes total)
#   4. Handles rate limits and timeouts with automatic retry
#
# Exit codes:
#   0 = Review completed (new feedback may be available)
#   1 = Timed out waiting for review (no review after ~20 minutes)
#   2 = Error (e.g. no PR found)

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/pr-feedback-common.sh"

# coderabbit-status.sh now lives in the sibling `coderabbit-status` skill,
# which owns CodeRabbit status detection. Resolve it relative to this script.
CODERABBIT_STATUS_SH="$SOURCE_DIR/../coderabbit-status/coderabbit-status.sh"

WORKSPACE_TYPE=""
SETTLE_SECONDS=30
FIRST_POLL_SECONDS=30   # 30s after settle = ~1 min total
POLL_INTERVAL_SECONDS=30  # 30s between subsequent polls
MAX_TOTAL_SECONDS=1200  # 20 min total from start

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-type)
      WORKSPACE_TYPE="$2"; shift 2;;
    -h|--help)
      cat <<EOF
Usage: $0 [--workspace-type gitbutler|standard]

Waits for CodeRabbit to complete its review after pushing commits.
Handles draft PR review requests, polling, and rate limit retries.

Options:
  --workspace-type TYPE   Set workspace type (gitbutler or standard).
                          Auto-detects from git branch if not specified.
  -h, --help              Show this help

Exit codes:
  0  Review completed (check for new feedback)
  1  Timed out (~20 min with no completed review)
  2  Error
EOF
      exit 0
      ;;
    *)
      echo "Error: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── Auto-detect workspace type ──────────────────────────────────────

if [[ -z "$WORKSPACE_TYPE" ]]; then
  current_branch=$(git branch --show-current 2>/dev/null) || true
  if [[ "$current_branch" == "gitbutler/workspace" ]]; then
    WORKSPACE_TYPE="gitbutler"
  else
    WORKSPACE_TYPE="standard"
  fi
fi

# ── Helpers ─────────────────────────────────────────────────────────

log() {
  echo "[wait-for-review] $*" >&2
}

request_coderabbit_review() {
  log "Requesting CodeRabbit review via PR comment..."
  gh pr comment --body "@coderabbitai review" >/dev/null 2>&1 || {
    log "Warning: Failed to post review request comment"
  }
}

check_for_new_feedback() {
  local count
  if [[ "$WORKSPACE_TYPE" == "gitbutler" ]]; then
    count=$("$SOURCE_DIR/but-feedback.sh" --limit 1 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -c '^\[Thread:\|^\[Review:\|^\[Comment:') || true
  else
    count=$("$SOURCE_DIR/pr-feedback.sh" --limit 1 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -c '^\[Thread:\|^\[Review:\|^\[Comment:') || true
  fi
  [[ "$count" -gt 0 ]]
}

get_status() {
  "$CODERABBIT_STATUS_SH" "$@"
}

get_status_json() {
  "$CODERABBIT_STATUS_SH" --json
}

# ── Step 1: Settle period ───────────────────────────────────────────

log "Waiting ${SETTLE_SECONDS}s for CodeRabbit to register the push..."
sleep "$SETTLE_SECONDS"

start_time=$SECONDS

# ── Step 2: Check if CodeRabbit needs a review request ──────────────

is_draft=$(gh pr view --json isDraft -q '.isDraft' 2>/dev/null) || {
  log "Error: Could not determine PR draft status"
  exit 2
}

log "Checking CodeRabbit status..."
status=$(get_status)

# "paused" is a permanent state meaning auto-reviews are disabled for this PR.
# CodeRabbit's first comment stays "paused" even after a manually-requested
# review completes. We request once and then just wait for feedback/completion.
review_requested=false

# Draft PRs are not auto-reviewed by CodeRabbit. After every push to a draft,
# we must explicitly request a review so the new commits get covered. We do
# this regardless of the current status: a `completed` state reflects the
# previous review (now stale), and even an `in_progress` state likely refers
# to a review of an older commit that won't pick up the new push.
if [[ "$is_draft" == "true" ]]; then
  log "PR is a draft (CodeRabbit doesn't auto-review drafts) — requesting review for the new push"
  request_coderabbit_review
  review_requested=true
else
  case "$status" in
    paused)
      log "CodeRabbit auto-reviews are paused — requesting manual review"
      request_coderabbit_review
      review_requested=true
      ;;
    in_progress|starting_up)
      log "CodeRabbit is already reviewing — no request needed"
      ;;
    rate_limited|timed_out)
      log "CodeRabbit is $status — will handle during polling"
      ;;
  esac
fi

# ── Step 3: Polling loop ────────────────────────────────────────────

log "Waiting ${FIRST_POLL_SECONDS}s before first status check..."
sleep "$FIRST_POLL_SECONDS"

poll_count=0

while true; do
  poll_count=$((poll_count + 1))
  elapsed=$((SECONDS - start_time + SETTLE_SECONDS))

  log "Poll #${poll_count} (${elapsed}s elapsed since push)..."

  # Check if there's new feedback available
  if check_for_new_feedback; then
    log "New feedback detected — review complete"
    exit 0
  fi

  # Check CodeRabbit status
  status_json=$(get_status_json)
  status=$(echo "$status_json" | jq -r '.status')
  wait_seconds=$(echo "$status_json" | jq -r '.wait_seconds')

  log "CodeRabbit status: $status"

  case "$status" in
    completed)
      log "CodeRabbit review completed (no new feedback found)"
      exit 0
      ;;
    rate_limited|timed_out)
      actual_wait=${wait_seconds:-180}
      if [[ "$actual_wait" -le 0 ]]; then
        actual_wait=180
      fi
      # Extend the max timeout to accommodate the rate limit wait
      rate_limit_end=$((SECONDS - start_time + SETTLE_SECONDS + actual_wait + 600))
      if [[ "$rate_limit_end" -gt "$MAX_TOTAL_SECONDS" ]]; then
        log "Extending timeout from ${MAX_TOTAL_SECONDS}s to ${rate_limit_end}s to accommodate rate limit"
        MAX_TOTAL_SECONDS=$rate_limit_end
      fi
      log "Rate limited — waiting ${actual_wait}s before retrying..."
      sleep "$actual_wait"
      request_coderabbit_review
      review_requested=true
      ;;
    in_progress|starting_up)
      # Still working — continue polling
      ;;
    paused)
      if [[ "$review_requested" == false ]]; then
        log "CodeRabbit auto-reviews are paused — requesting manual review"
        request_coderabbit_review
        review_requested=true
      else
        log "CodeRabbit still paused (expected — auto-reviews disabled). Waiting for review to complete..."
      fi
      ;;
    not_started)
      if [[ "$is_draft" == "true" ]]; then
        log "CodeRabbit still not started on draft PR — re-requesting review"
        request_coderabbit_review
      fi
      ;;
  esac

  # Check timeout
  elapsed=$((SECONDS - start_time + SETTLE_SECONDS))
  if [[ "$elapsed" -ge "$MAX_TOTAL_SECONDS" ]]; then
    log "Timed out after ~${elapsed}s — giving up"
    exit 1
  fi

  log "Waiting ${POLL_INTERVAL_SECONDS}s before next poll..."
  sleep "$POLL_INTERVAL_SECONDS"
done
