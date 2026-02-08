#!/bin/bash
# State Management Library for Orchestration System
# Manages persistent state for TODO tracking, issue analysis, and execution history

set -euo pipefail

STATE_DIR="${HOME}/.claude/orchestration-state"

# === TODO Capture State ===

# Check if TODO has been captured
# Usage: todo_is_captured <file> <line>
todo_is_captured() {
    local file="$1"
    local line="$2"
    local key="${file}:${line}"

    local state_file="${STATE_DIR}/todos-captured.json"
    if [[ ! -f "$state_file" ]]; then
        return 1
    fi

    jq -e --arg key "$key" 'has($key)' "$state_file" > /dev/null
}

# Mark TODO as captured
# Usage: todo_mark_captured <file> <line> <issue_id>
todo_mark_captured() {
    local file="$1"
    local line="$2"
    local issue_id="$3"
    local key="${file}:${line}"

    local state_file="${STATE_DIR}/todos-captured.json"
    if [[ ! -f "$state_file" ]]; then
        echo "{}" > "$state_file"
    fi

    jq --arg key "$key" \
       --arg issue "$issue_id" \
       --arg ts "$(date -Iseconds)" \
       '.[$key] = {captured_at: $ts, issue_id: $issue}' \
       "$state_file" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
}

# Clear TODO capture state (when file is modified)
# Usage: todo_clear_file <file>
todo_clear_file() {
    local file="$1"
    local pattern="${file}:"

    local state_file="${STATE_DIR}/todos-captured.json"
    if [[ ! -f "$state_file" ]]; then
        return 0
    fi

    jq --arg pattern "$pattern" \
       'to_entries | map(select(.key | startswith($pattern) | not)) | from_entries' \
       "$state_file" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
}

# === Issue Analysis State ===

# Get issue analysis
# Usage: issue_get_analysis <issue_id>
issue_get_analysis() {
    local issue_id="$1"
    local state_file="${STATE_DIR}/issues-analyzed.json"

    if [[ ! -f "$state_file" ]]; then
        echo "{}"
        return 1
    fi

    jq --arg id "$issue_id" '.[$id] // {}' "$state_file"
}

# Check if issue analysis is fresh (less than 24 hours old)
# Usage: issue_analysis_is_fresh <issue_id>
issue_analysis_is_fresh() {
    local issue_id="$1"
    local analysis
    analysis=$(issue_get_analysis "$issue_id")

    local analyzed_at
    analyzed_at=$(echo "$analysis" | jq -r '.analyzed_at // ""')

    if [[ -z "$analyzed_at" ]]; then
        return 1
    fi

    # Check if less than 24 hours old
    local now
    now=$(date +%s)
    local analyzed_ts
    analyzed_ts=$(date -d "$analyzed_at" +%s)
    local diff=$((now - analyzed_ts))

    [[ $diff -lt 86400 ]]
}

# Save issue analysis
# Usage: issue_save_analysis <issue_id> <analysis_json>
issue_save_analysis() {
    local issue_id="$1"
    local analysis="$2"

    local state_file="${STATE_DIR}/issues-analyzed.json"
    if [[ ! -f "$state_file" ]]; then
        echo "{}" > "$state_file"
    fi

    # Add analyzed_at timestamp
    local enhanced_analysis
    enhanced_analysis=$(echo "$analysis" | jq --arg ts "$(date -Iseconds)" \
        '.analyzed_at = $ts')

    jq --arg id "$issue_id" \
       --argjson analysis "$enhanced_analysis" \
       '.[$id] = $analysis' \
       "$state_file" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
}

# === Execution Attempts State ===

# Get execution attempts for issue
# Usage: execution_get_attempts <issue_id>
execution_get_attempts() {
    local issue_id="$1"
    local state_file="${STATE_DIR}/execution-attempts.json"

    if [[ ! -f "$state_file" ]]; then
        echo "[]"
        return 0
    fi

    jq --arg id "$issue_id" '.[$id] // []' "$state_file"
}

# Count recent failed attempts (last 7 days)
# Usage: execution_count_recent_failures <issue_id>
execution_count_recent_failures() {
    local issue_id="$1"
    local attempts
    attempts=$(execution_get_attempts "$issue_id")

    local cutoff
    cutoff=$(date -d "7 days ago" -Iseconds)

    echo "$attempts" | jq --arg cutoff "$cutoff" \
        'map(select(.attempted_at > $cutoff and .status == "failed")) | length'
}

# Record execution attempt
# Usage: execution_record_attempt <issue_id> <status> <reason>
execution_record_attempt() {
    local issue_id="$1"
    local status="$2"
    local reason="$3"

    local state_file="${STATE_DIR}/execution-attempts.json"
    if [[ ! -f "$state_file" ]]; then
        echo "{}" > "$state_file"
    fi

    local attempt
    attempt=$(jq -n \
        --arg ts "$(date -Iseconds)" \
        --arg status "$status" \
        --arg reason "$reason" \
        '{attempted_at: $ts, status: $status, reason: $reason}')

    jq --arg id "$issue_id" \
       --argjson attempt "$attempt" \
       '.[$id] = (.[$id] // []) + [$attempt]' \
       "$state_file" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
}

# Prune old execution attempts (older than 30 days)
# Usage: execution_prune_old
execution_prune_old() {
    local state_file="${STATE_DIR}/execution-attempts.json"
    if [[ ! -f "$state_file" ]]; then
        return 0
    fi

    local cutoff
    cutoff=$(date -d "30 days ago" -Iseconds)

    jq --arg cutoff "$cutoff" \
        'map_values(map(select(.attempted_at > $cutoff)))' \
        "$state_file" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
}

# === Cycle History ===

# Record cycle execution
# Usage: cycle_record <cycle_data_json>
cycle_record() {
    local cycle_data="$1"
    local state_file="${STATE_DIR}/cycle-history.json"

    if [[ ! -f "$state_file" ]]; then
        echo "[]" > "$state_file"
    fi

    # Add cycle_id and timestamp if not present
    local enhanced_data
    enhanced_data=$(echo "$cycle_data" | jq \
        --arg id "cycle-$(date +%s)" \
        --arg ts "$(date -Iseconds)" \
        'if .cycle_id == null then .cycle_id = $id else . end |
         if .started_at == null then .started_at = $ts else . end')

    jq --argjson cycle "$enhanced_data" '. += [$cycle]' "$state_file" > "${state_file}.tmp"
    mv "${state_file}.tmp" "$state_file"
}

# Get recent cycles
# Usage: cycle_get_recent [count]
cycle_get_recent() {
    local count="${1:-10}"
    local state_file="${STATE_DIR}/cycle-history.json"

    if [[ ! -f "$state_file" ]]; then
        echo "[]"
        return 0
    fi

    jq --arg count "$count" '.[-($count | tonumber):]' "$state_file"
}

# Export functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f todo_is_captured todo_mark_captured todo_clear_file
    export -f issue_get_analysis issue_analysis_is_fresh issue_save_analysis
    export -f execution_get_attempts execution_count_recent_failures execution_record_attempt execution_prune_old
    export -f cycle_record cycle_get_recent
fi
