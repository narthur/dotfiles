#!/bin/bash
# Portfolio Registry Management Library
# Provides utilities for querying and managing project metadata

set -euo pipefail

REGISTRY_FILE="${HOME}/.claude/portfolio-registry.json"

# === Project Queries ===

# Find project by ID
# Usage: registry_get_project <project_id>
registry_get_project() {
    local project_id="$1"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "{}"
        return 1
    fi

    jq --arg id "$project_id" '.projects[] | select(.id == $id)' "$REGISTRY_FILE"
}

# Get project path
# Usage: registry_get_project_path <project_id>
registry_get_project_path() {
    local project_id="$1"
    registry_get_project "$project_id" | jq -r '.path // ""'
}

# List all projects
# Usage: registry_list_projects [enabled_only]
registry_list_projects() {
    local enabled_only="${1:-false}"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "[]"
        return 0
    fi

    if [[ "$enabled_only" == "true" ]]; then
        jq '[.projects[] | select(.orchestration.enabled == true)]' "$REGISTRY_FILE"
    else
        jq '.projects' "$REGISTRY_FILE"
    fi
}

# Count enabled projects
# Usage: registry_count_enabled
registry_count_enabled() {
    registry_list_projects true | jq 'length'
}

# Get projects by family
# Usage: registry_get_family <family_name>
registry_get_family() {
    local family="$1"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "[]"
        return 0
    fi

    jq --arg family "$family" '[.projects[] | select(.family == $family)]' "$REGISTRY_FILE"
}

# Get family info
# Usage: registry_get_family_info <family_name>
registry_get_family_info() {
    local family="$1"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "{}"
        return 1
    fi

    jq --arg family "$family" '.families[$family] // {}' "$REGISTRY_FILE"
}

# === Project Configuration ===

# Enable project for orchestration
# Usage: registry_enable_project <project_id>
registry_enable_project() {
    local project_id="$1"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Error: Registry file not found"
        return 1
    fi

    jq --arg id "$project_id" \
        '(.projects[] | select(.id == $id) | .orchestration.enabled) = true' \
        "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    echo "Enabled orchestration for ${project_id}"
}

# Disable project for orchestration
# Usage: registry_disable_project <project_id> [reason]
registry_disable_project() {
    local project_id="$1"
    local reason="${2:-}"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Error: Registry file not found"
        return 1
    fi

    if [[ -n "$reason" ]]; then
        jq --arg id "$project_id" --arg reason "$reason" \
            '(.projects[] | select(.id == $id) | .orchestration.enabled) = false |
             (.projects[] | select(.id == $id) | .orchestration.reason) = $reason' \
            "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    else
        jq --arg id "$project_id" \
            '(.projects[] | select(.id == $id) | .orchestration.enabled) = false' \
            "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    fi
    mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    echo "Disabled orchestration for ${project_id}"
}

# Set project priority
# Usage: registry_set_priority <project_id> <high|medium|low>
registry_set_priority() {
    local project_id="$1"
    local priority="$2"

    if [[ ! "$priority" =~ ^(high|medium|low)$ ]]; then
        echo "Error: Priority must be high, medium, or low"
        return 1
    fi

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Error: Registry file not found"
        return 1
    fi

    jq --arg id "$project_id" --arg priority "$priority" \
        '(.projects[] | select(.id == $id) | .orchestration.priority) = $priority' \
        "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    echo "Set priority for ${project_id} to ${priority}"
}

# Enable auto-execute for project
# Usage: registry_enable_auto_execute <project_id>
registry_enable_auto_execute() {
    local project_id="$1"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Error: Registry file not found"
        return 1
    fi

    jq --arg id "$project_id" \
        '(.projects[] | select(.id == $id) | .orchestration.auto_execute) = true' \
        "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    echo "Enabled auto-execute for ${project_id}"
}

# Disable auto-execute for project
# Usage: registry_disable_auto_execute <project_id>
registry_disable_auto_execute() {
    local project_id="$1"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Error: Registry file not found"
        return 1
    fi

    jq --arg id "$project_id" \
        '(.projects[] | select(.id == $id) | .orchestration.auto_execute) = false' \
        "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    echo "Disabled auto-execute for ${project_id}"
}

# Bulk enable projects by family
# Usage: registry_enable_family <family_name>
registry_enable_family() {
    local family="$1"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Error: Registry file not found"
        return 1
    fi

    local count
    count=$(jq --arg family "$family" \
        '[.projects[] | select(.family == $family)] | length' \
        "$REGISTRY_FILE")

    jq --arg family "$family" \
        '(.projects[] | select(.family == $family) | .orchestration.enabled) = true' \
        "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    echo "Enabled ${count} projects in ${family} family"
}

# Bulk disable projects by family
# Usage: registry_disable_family <family_name>
registry_disable_family() {
    local family="$1"

    if [[ ! -f "$REGISTRY_FILE" ]]; then
        echo "Error: Registry file not found"
        return 1
    fi

    local count
    count=$(jq --arg family "$family" \
        '[.projects[] | select(.family == $family)] | length' \
        "$REGISTRY_FILE")

    jq --arg family "$family" \
        '(.projects[] | select(.family == $family) | .orchestration.enabled) = false' \
        "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
    mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    echo "Disabled ${count} projects in ${family} family"
}

# Export functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f registry_get_project registry_get_project_path registry_list_projects
    export -f registry_count_enabled registry_get_family registry_get_family_info
    export -f registry_enable_project registry_disable_project registry_set_priority
    export -f registry_enable_auto_execute registry_disable_auto_execute
    export -f registry_enable_family registry_disable_family
fi
