#!/usr/bin/env bash

# pr-feedback-common.sh - Shared functions for PR feedback tools

# ──────────────────────────────────────────────
# Snooze state management for PR feedback threads
# ──────────────────────────────────────────────

SNOOZE_STATE_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/pr-feedback-snooze/state.json"

# Parse a duration string (e.g. 1h, 4h, 1d, 3d, 1w) into seconds.
parse_snooze_duration() {
  local dur="$1"
  local num="${dur%[hHdDwW]}"
  local unit="${dur##*[0-9]}"
  if [[ -z "$num" ]] || ! [[ "$num" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid duration '$dur'. Use e.g. 1h, 4h, 1d, 3d, 1w." >&2
    return 1
  fi
  case "$unit" in
    h|H) echo $((num * 3600)) ;;
    d|D) echo $((num * 86400)) ;;
    w|W) echo $((num * 604800)) ;;
    *) echo "Error: Unknown unit in '$dur'. Use h (hours), d (days), or w (weeks)." >&2; return 1 ;;
  esac
}

# Read and return snooze state as JSON object.
read_snooze_state() {
  if [[ ! -f "$SNOOZE_STATE_FILE" ]]; then
    echo '{}'
    return
  fi
  cat "$SNOOZE_STATE_FILE" 2>/dev/null || echo '{}'
}

# Snooze a thread by ID for a duration string.
snooze_thread() {
  local thread_id="$1"
  local duration="$2"
  local seconds
  seconds=$(parse_snooze_duration "$duration") || return 1
  local now_epoch
  now_epoch=$(date +%s)
  local until_epoch=$((now_epoch + seconds))
  local until_iso snoozed_at_iso
  until_iso=$(date -u -d "@$until_epoch" "+%Y-%m-%dT%H:%M:%SZ")
  snoozed_at_iso=$(date -u -d "@$now_epoch" "+%Y-%m-%dT%H:%M:%SZ")

  mkdir -p "$(dirname "$SNOOZE_STATE_FILE")"
  local existing updated
  existing=$(read_snooze_state)
  updated=$(echo "$existing" | jq \
    --arg id "$thread_id" \
    --arg until "$until_iso" \
    --arg at "$snoozed_at_iso" \
    '.[$id] = {until: $until, snoozedAt: $at}')
  echo "$updated" > "$SNOOZE_STATE_FILE"

  local until_fmt
  until_fmt=$(date -d "$until_iso" "+%b %d %H:%M" 2>/dev/null || echo "$until_iso")
  echo "💤 Snoozed feedback thread until $until_fmt"
}

# Remove a thread from snooze state.
unsnooze_thread() {
  local thread_id="$1"
  [[ ! -f "$SNOOZE_STATE_FILE" ]] && return
  local existing updated
  existing=$(read_snooze_state)
  updated=$(echo "$existing" | jq --arg id "$thread_id" 'del(.[$id])')
  echo "$updated" > "$SNOOZE_STATE_FILE"
}

# Check if a thread should be skipped due to active snooze.
# Also auto-unsnoozes if snooze expired or new non-me comments are found.
# Args: thread_id, thread_json (full thread JSON from GraphQL), me (current user login)
# Returns: 0 = skip (still snoozed), 1 = include (not snoozed or just unsnooze'd)
check_thread_snoozed() {
  local thread_id="$1"
  local thread_json="$2"
  local me="$3"

  local state snooze_entry
  state=$(read_snooze_state)
  snooze_entry=$(echo "$state" | jq -c --arg id "$thread_id" '.[$id] // empty')
  [[ -z "$snooze_entry" ]] && return 1  # Not snoozed

  local snooze_until snooze_at
  snooze_until=$(echo "$snooze_entry" | jq -r '.until')
  snooze_at=$(echo "$snooze_entry" | jq -r '.snoozedAt')

  local now_epoch until_epoch
  now_epoch=$(date +%s)
  until_epoch=$(date -d "$snooze_until" +%s 2>/dev/null || echo 0)

  if [[ "$until_epoch" -le "$now_epoch" ]]; then
    unsnooze_thread "$thread_id"
    return 1  # Expired, include
  fi

  # Check for new non-me comments added after the snooze was set
  local has_new
  has_new=$(echo "$thread_json" | jq -r \
    --arg me "$me" --arg at "$snooze_at" \
    '[.comments.nodes[] | select(.author.login != $me and .createdAt > $at)] | length' \
    2>/dev/null || echo 0)

  if [[ "$has_new" -gt 0 ]]; then
    unsnooze_thread "$thread_id"
    return 1  # New activity from others, include
  fi

  return 0  # Still snoozed, skip
}

# Check if a generic PR comment should be skipped due to active snooze.
# Simpler than check_thread_snoozed — only checks expiry, no new-activity detection.
# Returns: 0 = skip (still snoozed), 1 = include (not snoozed or expired)
check_comment_snoozed() {
  local comment_id="$1"

  local state snooze_entry
  state=$(read_snooze_state)
  snooze_entry=$(echo "$state" | jq -c --arg id "$comment_id" '.[$id] // empty')
  [[ -z "$snooze_entry" ]] && return 1  # Not snoozed

  local snooze_until
  snooze_until=$(echo "$snooze_entry" | jq -r '.until')

  local now_epoch until_epoch
  now_epoch=$(date +%s)
  until_epoch=$(date -d "$snooze_until" +%s 2>/dev/null || echo 0)

  if [[ "$until_epoch" -le "$now_epoch" ]]; then
    unsnooze_thread "$comment_id"
    return 1  # Expired, include
  fi

  return 0  # Still snoozed, skip
}

# ──────────────────────────────────────────────
# Dismissed state management for generic PR comments
# ──────────────────────────────────────────────

DISMISSED_STATE_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/pr-feedback-snooze/dismissed.json"

# Read and return dismissed state as JSON object.
read_dismissed_state() {
  if [[ ! -f "$DISMISSED_STATE_FILE" ]]; then
    echo '{}'
    return
  fi
  cat "$DISMISSED_STATE_FILE" 2>/dev/null || echo '{}'
}

# Dismiss a comment by node ID.
dismiss_comment_state() {
  local comment_id="$1"
  local now_iso
  now_iso=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

  mkdir -p "$(dirname "$DISMISSED_STATE_FILE")"
  local existing updated
  existing=$(read_dismissed_state)
  updated=$(echo "$existing" | jq \
    --arg id "$comment_id" \
    --arg at "$now_iso" \
    '.[$id] = {dismissedAt: $at}')
  echo "$updated" > "$DISMISSED_STATE_FILE"
  echo "✓ Dismissed comment: $comment_id"
}

# Undismiss a comment by node ID.
undismiss_comment_state() {
  local comment_id="$1"
  [[ ! -f "$DISMISSED_STATE_FILE" ]] && return
  local existing updated
  existing=$(read_dismissed_state)
  updated=$(echo "$existing" | jq --arg id "$comment_id" 'del(.[$id])')
  echo "$updated" > "$DISMISSED_STATE_FILE"
}

# Check if a comment is dismissed.
# Returns: 0 = dismissed (skip), 1 = not dismissed (include)
is_comment_dismissed() {
  local comment_id="$1"
  local state entry
  state=$(read_dismissed_state)
  entry=$(echo "$state" | jq -c --arg id "$comment_id" '.[$id] // empty')
  [[ -n "$entry" ]] && return 0 || return 1
}

# ──────────────────────────────────────────────
# Bot command detection for auto-skipping
# ──────────────────────────────────────────────

BOT_COMMAND_PATTERNS=(
  '^@coderabbitai\b'
  '^@dependabot\b'
  '^@github-actions\b'
  '^@copilot\b'
  '^\s*<!-- This is an auto-generated (reply|comment) by CodeRabbit -->'
)

# Check if a comment body is a bot command (not actionable feedback).
# Returns: 0 = bot command (skip), 1 = real feedback (include)
is_bot_command() {
  local body="$1"
  local trimmed
  trimmed=$(echo "$body" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')

  for pattern in "${BOT_COMMAND_PATTERNS[@]}"; do
    # -E (POSIX extended), not -P (PCRE): macOS/BSD grep has no -P and errors
    # out on it (exit 2), which would make every pattern silently fail to match
    # and let bot-command comments through as if they were real feedback.
    if echo "$trimmed" | grep -qiE "$pattern"; then
      return 0
    fi
  done

  return 1
}

print_pr_tools_help() {
  local color_reset=$'\033[0m'
  local color_header=$'\033[1;36m'  # Bold Cyan
  local color_cmd=$'\033[1;33m'     # Bold Yellow
  local color_desc=$'\033[90m'      # Gray
  
  cat <<EOF

${color_header}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_reset}
${color_header}PR Feedback Tools${color_reset}
${color_header}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_reset}

${color_cmd}pr-feedback.sh${color_reset} [--json] [--all] [--limit N]
  ${color_desc}List review comments on the current PR${color_reset}
  ${color_desc}--json: Output as JSON${color_reset}
  ${color_desc}--all: Show resolved comments too${color_reset}
  ${color_desc}--limit N: Limit number of results${color_reset}

${color_cmd}pr-comment.sh${color_reset} <thread-id> [comment-text]
  ${color_desc}Reply to a review comment thread${color_reset}
  ${color_desc}Omit comment-text to open \$EDITOR${color_reset}

${color_cmd}resolve-feedback.sh${color_reset} <thread-id> [--unresolve]
  ${color_desc}Mark a review thread as resolved${color_reset}
  ${color_desc}--unresolve: Mark as unresolved instead${color_reset}

${color_cmd}snooze-feedback.sh${color_reset} <thread-id> <duration>
  ${color_desc}Snooze a feedback thread (hide until duration expires or new comments appear)${color_reset}
  ${color_desc}duration: e.g. 1h, 4h, 1d, 3d, 1w${color_reset}

${color_cmd}dismiss-comment.sh${color_reset} <comment-id> [--undismiss]
  ${color_desc}Dismiss a generic PR comment (mark as addressed locally)${color_reset}
  ${color_desc}--undismiss: Undo dismissal${color_reset}

${color_cmd}../drive-pr/wait-for-review.sh${color_reset} [--workspace-type TYPE]
  ${color_desc}Wait for CodeRabbit review after pushing (handles settle, draft, polling, rate limits)${color_reset}
  ${color_desc}Lives in the sibling 'drive-pr' skill, which owns PR orchestration${color_reset}

${color_cmd}../coderabbit-status/coderabbit-status.sh${color_reset} [--json]
  ${color_desc}Check CodeRabbit's current review status (combines check + comment signals)${color_reset}
  ${color_desc}Lives in the sibling 'coderabbit-status' skill, which owns status detection${color_reset}

${color_header}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_reset}
EOF
}
