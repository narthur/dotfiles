#!/bin/bash
# Queue Management Library for Orchestration System
# Provides utilities for managing approval queues

set -euo pipefail

QUEUE_DIR="${HOME}/.claude/approval-queue"

# Generate unique ID for queue entries
generate_id() {
    local prefix="${1:-item}"
    echo "${prefix}-$(date +%s)-$(uuidgen | cut -d- -f1)"
}

# Add item to queue
# Usage: queue_add <queue_file> <json_data>
queue_add() {
    local queue_file="$1"
    local json_data="$2"

    if [[ ! -f "$queue_file" ]]; then
        echo "[]" > "$queue_file"
    fi

    # Add timestamp and status if not present
    local enhanced_data
    enhanced_data=$(echo "$json_data" | jq --arg ts "$(date -Iseconds)" \
        'if .timestamp == null then .timestamp = $ts else . end |
         if .status == null then .status = "pending" else . end')

    # Append to queue
    jq --argjson item "$enhanced_data" '. += [$item]' "$queue_file" > "${queue_file}.tmp"
    mv "${queue_file}.tmp" "$queue_file"

    echo "$enhanced_data" | jq -r '.id'
}

# Remove item from queue by ID
# Usage: queue_remove <queue_file> <item_id>
queue_remove() {
    local queue_file="$1"
    local item_id="$2"

    if [[ ! -f "$queue_file" ]]; then
        return 0
    fi

    jq --arg id "$item_id" 'map(select(.id != $id))' "$queue_file" > "${queue_file}.tmp"
    mv "${queue_file}.tmp" "$queue_file"
}

# Mark item as completed
# Usage: queue_complete <queue_file> <item_id>
queue_complete() {
    local queue_file="$1"
    local item_id="$2"

    if [[ ! -f "$queue_file" ]]; then
        return 1
    fi

    jq --arg id "$item_id" --arg ts "$(date -Iseconds)" \
        'map(if .id == $id then .status = "completed" | .completed_at = $ts else . end)' \
        "$queue_file" > "${queue_file}.tmp"
    mv "${queue_file}.tmp" "$queue_file"
}

# Get item by ID
# Usage: queue_get <queue_file> <item_id>
queue_get() {
    local queue_file="$1"
    local item_id="$2"

    if [[ ! -f "$queue_file" ]]; then
        echo "{}"
        return 1
    fi

    jq --arg id "$item_id" '.[] | select(.id == $id)' "$queue_file"
}

# List all items in queue
# Usage: queue_list <queue_file> [status_filter]
queue_list() {
    local queue_file="$1"
    local status_filter="${2:-}"

    if [[ ! -f "$queue_file" ]]; then
        echo "[]"
        return 0
    fi

    if [[ -n "$status_filter" ]]; then
        jq --arg status "$status_filter" 'map(select(.status == $status))' "$queue_file"
    else
        cat "$queue_file"
    fi
}

# Count items in queue
# Usage: queue_count <queue_file> [status_filter]
queue_count() {
    local queue_file="$1"
    local status_filter="${2:-}"

    queue_list "$queue_file" "$status_filter" | jq 'length'
}

# Clear completed items
# Usage: queue_clear_completed <queue_file>
queue_clear_completed() {
    local queue_file="$1"

    if [[ ! -f "$queue_file" ]]; then
        return 0
    fi

    jq 'map(select(.status != "completed"))' "$queue_file" > "${queue_file}.tmp"
    mv "${queue_file}.tmp" "$queue_file"
}

# Get queue statistics
# Usage: queue_stats <queue_file>
queue_stats() {
    local queue_file="$1"

    if [[ ! -f "$queue_file" ]]; then
        echo '{"total": 0, "pending": 0, "completed": 0}'
        return 0
    fi

    jq '{
        total: length,
        pending: map(select(.status == "pending")) | length,
        completed: map(select(.status == "completed")) | length
    }' "$queue_file"
}

# Convenience functions for specific queues
queue_add_issue() {
    queue_add "${QUEUE_DIR}/issues-to-create.json" "$1"
}

queue_add_branch() {
    queue_add "${QUEUE_DIR}/branches-to-push.json" "$1"
}

queue_add_pr() {
    queue_add "${QUEUE_DIR}/prs-to-create.json" "$1"
}

queue_add_issue_update() {
    queue_add "${QUEUE_DIR}/issues-to-update.json" "$1"
}

queue_add_comment() {
    queue_add "${QUEUE_DIR}/comments-to-post.json" "$1"
}

# Export functions for use in other scripts
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f generate_id queue_add queue_remove queue_complete queue_get
    export -f queue_list queue_count queue_clear_completed queue_stats
    export -f queue_add_issue queue_add_branch queue_add_pr queue_add_issue_update queue_add_comment
fi
