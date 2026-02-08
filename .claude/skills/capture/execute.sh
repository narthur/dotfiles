#!/bin/bash
# capture skill executor
# Scan code for TODOs and queue issue creation

set -euo pipefail

# Source required libraries
source "${HOME}/.claude/lib/todo-scanner.sh"
source "${HOME}/.claude/lib/queue-manager.sh"
source "${HOME}/.claude/lib/state-manager.sh"
source "${HOME}/.claude/lib/portfolio-registry.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Capture TODOs from a single project
capture_project() {
    local project_id="$1"

    echo -e "${BLUE}→${NC} Scanning project: $project_id"

    # Get project info from registry
    local project
    project=$(registry_get_project "$project_id")

    if [[ "$project" == "{}" ]]; then
        echo "  Error: Project not found in registry"
        return 1
    fi

    local project_path
    project_path=$(echo "$project" | jq -r '.path')

    if [[ ! -d "$project_path" ]]; then
        echo "  Error: Project path not found: $project_path"
        return 1
    fi

    # Check if TODO capture is enabled
    local auto_capture
    auto_capture=$(echo "$project" | jq -r '.orchestration.auto_capture_todos')

    if [[ "$auto_capture" != "true" ]]; then
        echo "  Skipped: TODO capture not enabled for this project"
        echo "  Enable with: /orchestrate-config enable $project_id"
        return 0
    fi

    # Scan and generate issues
    local issues
    issues=$(todo_scan_and_generate "$project_id" "$project_path")

    local count
    count=$(echo "$issues" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "  No new TODOs found"
        return 0
    fi

    echo -e "  ${GREEN}✓${NC} Found $count new TODO(s)"

    # Queue each issue
    echo "$issues" | jq -c '.[]' | while read -r issue_data; do
        local id
        id=$(generate_id "capture")

        # Use temp file to avoid argument length limits
        local temp_data
        temp_data=$(mktemp)
        echo "$issue_data" > "$temp_data"

        local queue_entry
        queue_entry=$(jq -n \
            --arg id "$id" \
            --arg project "$project_id" \
            --arg type "create-issue" \
            --slurpfile data "$temp_data" \
            '{
                id: $id,
                project: $project,
                type: $type,
                data: $data[0]
            }')
        rm -f "$temp_data"

        queue_add_issue "$queue_entry" >/dev/null

        # Mark as captured (will be marked when approved, but we'll track the queue intent)
        local source_file
        source_file=$(echo "$issue_data" | jq -r '.source_file')
        echo "    - Queued: $source_file"
    done

    echo -e "  ${GREEN}✓${NC} Queued $count issue(s) for approval"
}

# Scan all projects
scan_all() {
    local enabled_only="${1:-false}"

    echo "=== TODO Capture Scan ==="
    echo ""

    local projects
    if [[ "$enabled_only" == "true" ]]; then
        echo "Scanning only enabled projects..."
        projects=$(registry_list_projects true)
    else
        echo "Scanning all projects with TODO capture enabled..."
        projects=$(registry_list_projects false | jq '[.[] | select(.orchestration.auto_capture_todos == true)]')
    fi

    local count
    count=$(echo "$projects" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "No projects configured for TODO capture."
        echo ""
        echo "Enable a project:"
        echo "  /orchestrate-config enable <project-id>"
        return 0
    fi

    echo "Found $count project(s) to scan"
    echo ""

    local total_queued=0

    echo "$projects" | jq -r '.[].id' | while read -r project_id; do
        if capture_project "$project_id"; then
            # Count queued items (this is approximate since it runs in subshell)
            :
        fi
        echo ""
    done

    echo "=== Scan Complete ==="
    echo ""
    echo "Review and approve queued issues:"
    echo "  /approve issues"
}

# Show statistics without capturing
show_stats() {
    echo "=== TODO Statistics ==="
    echo ""

    local projects
    projects=$(registry_list_projects false | jq '[.[] | select(.orchestration.auto_capture_todos == true)]')

    local count
    count=$(echo "$projects" | jq 'length')

    echo "Projects with TODO capture enabled: $count"
    echo ""

    local total_todos=0
    local total_captured=0

    echo "$projects" | jq -r '.[].id' | while read -r project_id; do
        local project
        project=$(registry_get_project "$project_id")
        local project_path
        project_path=$(echo "$project" | jq -r '.path')

        if [[ ! -d "$project_path" ]]; then
            continue
        fi

        # Count TODOs
        local todo_count
        todo_count=$(todo_scan_project "$project_path" | wc -l)

        if [[ $todo_count -gt 0 ]]; then
            echo "  $project_id: $todo_count TODO(s)"
            total_todos=$((total_todos + todo_count))
        fi
    done

    # Count already captured
    if [[ -f "${HOME}/.claude/orchestration-state/todos-captured.json" ]]; then
        total_captured=$(jq 'length' "${HOME}/.claude/orchestration-state/todos-captured.json")
    fi

    echo ""
    echo "Total TODOs found: $total_todos"
    echo "Already captured: $total_captured"
    echo "New TODOs: $((total_todos - total_captured))"
}

# Clear captured state for a file
clear_file() {
    local file_path="$1"

    if [[ -z "$file_path" ]]; then
        echo "Error: File path required"
        echo "Usage: /capture clear-file <file-path>"
        return 1
    fi

    todo_clear_file "$file_path"
    echo "Cleared captured TODOs for: $file_path"
    echo "Next scan will recapture TODOs from this file."
}

# Main execution
main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        scan-all)
            local enabled_only="false"
            if [[ "${1:-}" == "--enabled-only" ]]; then
                enabled_only="true"
            fi
            scan_all "$enabled_only"
            ;;

        scan)
            local project_id="${1:-}"
            if [[ -z "$project_id" ]]; then
                echo "Error: Project ID required"
                echo "Usage: /capture scan <project-id>"
                exit 1
            fi
            capture_project "$project_id"
            ;;

        stats)
            show_stats
            ;;

        clear-file)
            clear_file "${1:-}"
            ;;

        *)
            echo "Usage: /capture <command> [options]"
            echo ""
            echo "Commands:"
            echo "  scan-all [--enabled-only]   Scan all projects for TODOs"
            echo "  scan <project-id>           Scan specific project"
            echo "  stats                       Show TODO statistics"
            echo "  clear-file <path>           Clear captured state for file"
            echo ""
            echo "Examples:"
            echo "  /capture scan-all --enabled-only"
            echo "  /capture scan example-api"
            echo "  /capture stats"
            echo ""
            echo "After capturing, review with:"
            echo "  /approve issues"
            exit 1
            ;;
    esac
}

# Run main with arguments
main "$@"
