#!/usr/bin/env bash

# wait-for-review.sh - Passively wait for CodeRabbit's INITIAL review to land.
#
# Usage:
#   wait-for-review.sh [--workspace-type gitbutler|standard]
#
# Context: the working policy is ONE CodeRabbit review per PR — the automatic
# one posted when the PR is opened (or marked ready). (PinePeakDigital repos
# enforce this via auto_incremental_review: false; other orgs may still have
# incremental reviews on, but the policy here is the same.) This script only
# ever waits for that single initial review to complete. It NEVER posts
# `@coderabbitai review` to request or re-request a review, and it does NOT
# sleep out rate-limit reset windows chasing one. The local `review-loop` skill
# is the iterative reviewer; CodeRabbit is a one-shot second opinion.
#
# Behaviour:
#   1. Sleeps a short settle period to let CodeRabbit register the PR.
#   2. Draft PRs: CodeRabbit doesn't auto-review drafts and we won't request
#      one — there's nothing to wait for, so exit immediately (code 0).
#   3. Polls (read-only) for the initial review to complete (up to ~20 min).
#   4. If CodeRabbit is rate-limited or its review times out, we do NOT chase
#      it — we simply report and exit 1 once the budget is exhausted.
#
# Exit codes:
#   0 = Initial review completed (new feedback may be available), OR draft PR
#       (nothing to wait for)
#   1 = The initial review did not land within the budget (timed out or
#       rate-limited). Not blocking — proceed; the local review-loop is the gate.
#   2 = Error (e.g. no PR found)

set -euo pipefail

# Load ~/.env (if present) so an opt-out flag set there is honoured even though
# this runs in a non-interactive shell that wouldn't otherwise read it.
if [[ -f "$HOME/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; . "$HOME/.env" 2>/dev/null || true; set +a
fi

# Opt out of the CodeRabbit wait entirely (e.g. no active CodeRabbit
# subscription). Set CODERABBIT_WAITER_DISABLED=1 in your environment or ~/.env.
# Exits 0 — same as a draft PR: there's simply nothing to wait for, so the
# caller (drive-pr) proceeds straight to CI/feedback without blocking.
# Lowercase via tr for portability (macOS ships bash 3.2, which lacks ${v,,}).
_crw_disabled="${CODERABBIT_WAITER_DISABLED:-}"
_crw_lc=$(printf '%s' "$_crw_disabled" | tr '[:upper:]' '[:lower:]')
if [[ -n "$_crw_disabled" && "$_crw_lc" != "0" && "$_crw_lc" != "false" && "$_crw_lc" != "no" ]]; then
  echo "[wait-for-review] CODERABBIT_WAITER_DISABLED set — skipping the CodeRabbit wait." >&2
  exit 0
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# coderabbit-status.sh lives in the sibling `coderabbit-status` skill, which
# owns CodeRabbit status detection. Resolve it relative to this script.
CODERABBIT_STATUS_SH="$SOURCE_DIR/../coderabbit-status/coderabbit-status.sh"

WORKSPACE_TYPE=""
SETTLE_SECONDS=30
FIRST_POLL_SECONDS=30   # 30s after settle = ~1 min total
POLL_INTERVAL_SECONDS=30  # 30s between subsequent polls
MAX_TOTAL_SECONDS=1200  # 20 min total from start — fixed budget, never extended

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-type)
      WORKSPACE_TYPE="$2"; shift 2;;
    -h|--help)
      cat <<EOF
Usage: $0 [--workspace-type gitbutler|standard]

Passively waits for CodeRabbit's single initial review to complete. Does NOT
request or re-request reviews, and does NOT sleep out rate limits.

Options:
  --workspace-type TYPE   Set workspace type (gitbutler or standard).
                          Auto-detects from git branch if not specified.
  -h, --help              Show this help

Environment:
  CODERABBIT_WAITER_DISABLED  If set (and not 0/false/no), skip the wait
                              entirely and exit 0. Read from the environment or
                              ~/.env. Use when you have no CodeRabbit subscription.

Exit codes:
  0  Initial review completed (check for feedback), or draft PR (nothing to wait for)
  1  Initial review did not land within ~20 min (timed out / rate-limited). Not blocking.
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

get_status() {
  "$CODERABBIT_STATUS_SH" "$@"
}

get_status_json() {
  "$CODERABBIT_STATUS_SH" --json
}

# ── Step 1: Settle period ───────────────────────────────────────────

log "Waiting ${SETTLE_SECONDS}s for CodeRabbit to register the PR..."
sleep "$SETTLE_SECONDS"

start_time=$SECONDS

# ── Step 2: Draft PRs have no auto-review to wait for ───────────────

is_draft=$(gh pr view --json isDraft -q '.isDraft' 2>/dev/null) || {
  log "Error: Could not determine PR draft status"
  exit 2
}

if [[ "$is_draft" == "true" ]]; then
  # CodeRabbit doesn't auto-review drafts, and per policy we never request a
  # review. The single review will happen when the PR is marked ready — that's
  # the user's call. Nothing to wait for here.
  log "PR is a draft — CodeRabbit won't auto-review until it's marked ready, and we don't request reviews. Nothing to wait for."
  exit 0
fi

# ── Step 3: Polling loop (read-only) ────────────────────────────────

log "Waiting ${FIRST_POLL_SECONDS}s before first status check..."
sleep "$FIRST_POLL_SECONDS"

poll_count=0
# Tracks whether we've observed CodeRabbit actively reviewing this run, used
# to distinguish a fresh `completed` from a stale one (see the completed case).
seen_active=false

while true; do
  poll_count=$((poll_count + 1))
  elapsed=$((SECONDS - start_time + SETTLE_SECONDS))

  log "Poll #${poll_count} (${elapsed}s elapsed)..."

  status_json=$(get_status_json)
  status=$(echo "$status_json" | jq -r '.status')
  check_state=$(echo "$status_json" | jq -r '.check_state')

  log "CodeRabbit status: $status"

  case "$status" in
    completed)
      # Accept completion once we've either seen the review go active this run,
      # or the check itself has concluded on the current head. Right after a PR
      # opens there can be a brief window where a prior/stale walkthrough shows
      # completed before the real review registers; keep polling through it.
      if [[ "$seen_active" == true || "$check_state" == "completed" ]]; then
        log "CodeRabbit's initial review completed"
        exit 0
      fi
      log "Status is 'completed' but the initial review hasn't registered yet (check_state=$check_state) — continuing to poll"
      ;;
    in_progress|starting_up)
      # The initial review is actively running — record it so a later
      # `completed` is trusted as fresh.
      seen_active=true
      ;;
    rate_limited|timed_out)
      # Per the one-review-per-PR policy we do NOT chase this: no re-request,
      # no sleeping out the reset window. Just keep polling within the fixed
      # budget in case it clears on its own; otherwise we time out below.
      log "CodeRabbit is $status — not chasing it (policy: one review per PR). Will give up at the budget if it doesn't clear."
      ;;
    not_started|paused)
      # No auto-review has landed. We don't request one. Keep polling within
      # budget in case it's just slow to register.
      log "CodeRabbit status is '$status' — waiting (we don't request reviews)."
      ;;
  esac

  # Check timeout — fixed budget, never extended.
  elapsed=$((SECONDS - start_time + SETTLE_SECONDS))
  if [[ "$elapsed" -ge "$MAX_TOTAL_SECONDS" ]]; then
    log "Initial review did not land within ~${elapsed}s — giving up (not blocking; the review-loop is the gate)"
    exit 1
  fi

  log "Waiting ${POLL_INTERVAL_SECONDS}s before next poll..."
  sleep "$POLL_INTERVAL_SECONDS"
done
