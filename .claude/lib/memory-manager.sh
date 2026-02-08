#!/bin/bash
# Memory Management Library for Orchestration System
# Manages persistent learnings and project notes

set -euo pipefail

MEMORY_DIR="${HOME}/.claude/orchestration-memory"

# === Learnings Management ===

# Append learning to learnings.md
# Usage: memory_add_learning <section> <content>
memory_add_learning() {
    local section="$1"
    local content="$2"
    local learnings_file="${MEMORY_DIR}/learnings.md"

    # Ensure file exists
    if [[ ! -f "$learnings_file" ]]; then
        cat > "$learnings_file" <<'EOF'
# Orchestration Learnings

## Successful Patterns

## Failed Approaches

## Project Insights

## Common Bug Patterns

## Effective Implementation Approaches

## Issues to Avoid
EOF
    fi

    # Add content under the specified section
    # Use awk to find the section and append
    awk -v section="## ${section}" -v content="- ${content}" '
        $0 ~ section {
            print
            getline
            print
            print content
            next
        }
        { print }
    ' "$learnings_file" > "${learnings_file}.tmp"
    mv "${learnings_file}.tmp" "$learnings_file"
}

# Read learnings file
# Usage: memory_get_learnings
memory_get_learnings() {
    local learnings_file="${MEMORY_DIR}/learnings.md"
    if [[ -f "$learnings_file" ]]; then
        cat "$learnings_file"
    fi
}

# === Project Notes Management ===

# Get project notes file path
# Usage: memory_get_project_notes_path <project_id>
memory_get_project_notes_path() {
    local project_id="$1"
    echo "${MEMORY_DIR}/project-notes/${project_id}.md"
}

# Read project notes
# Usage: memory_get_project_notes <project_id>
memory_get_project_notes() {
    local project_id="$1"
    local notes_file
    notes_file=$(memory_get_project_notes_path "$project_id")

    if [[ -f "$notes_file" ]]; then
        cat "$notes_file"
    else
        echo ""
    fi
}

# Create project notes template
# Usage: memory_init_project_notes <project_id>
memory_init_project_notes() {
    local project_id="$1"
    local notes_file
    notes_file=$(memory_get_project_notes_path "$project_id")

    if [[ ! -f "$notes_file" ]]; then
        cat > "$notes_file" <<EOF
# ${project_id} Notes

## Architecture

<!-- Project structure and key components -->

## Common Issues

<!-- Recurring issues in this project -->

## Test Patterns

<!-- Testing conventions and patterns -->

## Execution Notes

<!-- Notes about running tests, linting, deployment -->

## Dependencies

<!-- Key dependencies and their quirks -->
EOF
    fi
}

# Update project notes section
# Usage: memory_update_project_notes <project_id> <section> <content>
memory_update_project_notes() {
    local project_id="$1"
    local section="$2"
    local content="$3"
    local notes_file
    notes_file=$(memory_get_project_notes_path "$project_id")

    # Initialize if doesn't exist
    memory_init_project_notes "$project_id"

    # Add content under the specified section
    awk -v section="## ${section}" -v content="- ${content}" '
        $0 ~ section {
            print
            getline
            print
            print content
            next
        }
        { print }
    ' "$notes_file" > "${notes_file}.tmp"
    mv "${notes_file}.tmp" "$notes_file"
}

# === Blocked Issues Management ===

# Check if issue is blocked
# Usage: memory_is_blocked <issue_id>
memory_is_blocked() {
    local issue_id="$1"
    local blocked_file="${MEMORY_DIR}/blocked-issues.json"

    if [[ ! -f "$blocked_file" ]]; then
        return 1
    fi

    jq -e --arg id "$issue_id" 'has($id)' "$blocked_file" > /dev/null
}

# Get blocked issue info
# Usage: memory_get_blocked <issue_id>
memory_get_blocked() {
    local issue_id="$1"
    local blocked_file="${MEMORY_DIR}/blocked-issues.json"

    if [[ ! -f "$blocked_file" ]]; then
        echo "{}"
        return 1
    fi

    jq --arg id "$issue_id" '.[$id] // {}' "$blocked_file"
}

# Mark issue as blocked
# Usage: memory_mark_blocked <issue_id> <reason> [blocked_by_issues...]
memory_mark_blocked() {
    local issue_id="$1"
    local reason="$2"
    shift 2
    local blocked_by=("$@")

    local blocked_file="${MEMORY_DIR}/blocked-issues.json"
    if [[ ! -f "$blocked_file" ]]; then
        echo "{}" > "$blocked_file"
    fi

    local blocked_by_json
    blocked_by_json=$(printf '%s\n' "${blocked_by[@]}" | jq -R . | jq -s .)

    jq --arg id "$issue_id" \
       --arg reason "$reason" \
       --argjson blocked_by "$blocked_by_json" \
       --arg ts "$(date -Iseconds)" \
       '.[$id] = {reason: $reason, blocked_by: $blocked_by, detected_at: $ts}' \
       "$blocked_file" > "${blocked_file}.tmp"
    mv "${blocked_file}.tmp" "$blocked_file"
}

# Unblock issue
# Usage: memory_unblock <issue_id>
memory_unblock() {
    local issue_id="$1"
    local blocked_file="${MEMORY_DIR}/blocked-issues.json"

    if [[ ! -f "$blocked_file" ]]; then
        return 0
    fi

    jq --arg id "$issue_id" 'del(.[$id])' "$blocked_file" > "${blocked_file}.tmp"
    mv "${blocked_file}.tmp" "$blocked_file"
}

# List all blocked issues
# Usage: memory_list_blocked
memory_list_blocked() {
    local blocked_file="${MEMORY_DIR}/blocked-issues.json"

    if [[ ! -f "$blocked_file" ]]; then
        echo "{}"
        return 0
    fi

    cat "$blocked_file"
}

# Export functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f memory_add_learning memory_get_learnings
    export -f memory_get_project_notes_path memory_get_project_notes
    export -f memory_init_project_notes memory_update_project_notes
    export -f memory_is_blocked memory_get_blocked memory_mark_blocked
    export -f memory_unblock memory_list_blocked
fi
