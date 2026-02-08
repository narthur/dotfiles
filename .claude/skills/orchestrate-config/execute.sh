#!/bin/bash
# orchestrate-config skill executor
# Manages project orchestration settings

set -euo pipefail

# Source the portfolio registry library
source "${HOME}/.claude/lib/portfolio-registry.sh"

REGISTRY_FILE="${HOME}/.claude/portfolio-registry.json"

# Parse command and arguments
COMMAND="${1:-}"
shift || true

case "$COMMAND" in
    enable)
        PROJECT_ID="${1:-}"
        if [[ -z "$PROJECT_ID" ]]; then
            echo "Error: Project ID required"
            echo "Usage: /orchestrate-config enable <project-id>"
            exit 1
        fi
        registry_enable_project "$PROJECT_ID"
        # Also enable TODO capture by default
        jq --arg id "$PROJECT_ID" \
            '(.projects[] | select(.id == $id) | .orchestration.auto_capture_todos) = true' \
            "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp"
        mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"
        ;;

    disable)
        PROJECT_ID="${1:-}"
        REASON="${2:-}"
        if [[ -z "$PROJECT_ID" ]]; then
            echo "Error: Project ID required"
            echo "Usage: /orchestrate-config disable <project-id> [reason]"
            exit 1
        fi
        registry_disable_project "$PROJECT_ID" "$REASON"
        ;;

    priority)
        PROJECT_ID="${1:-}"
        PRIORITY="${2:-}"
        if [[ -z "$PROJECT_ID" ]] || [[ -z "$PRIORITY" ]]; then
            echo "Error: Project ID and priority required"
            echo "Usage: /orchestrate-config priority <project-id> <high|medium|low>"
            exit 1
        fi
        registry_set_priority "$PROJECT_ID" "$PRIORITY"
        ;;

    auto-execute)
        PROJECT_ID="${1:-}"
        STATE="${2:-}"
        if [[ -z "$PROJECT_ID" ]] || [[ -z "$STATE" ]]; then
            echo "Error: Project ID and state required"
            echo "Usage: /orchestrate-config auto-execute <project-id> <on|off>"
            exit 1
        fi
        if [[ "$STATE" == "on" ]]; then
            registry_enable_auto_execute "$PROJECT_ID"
        elif [[ "$STATE" == "off" ]]; then
            registry_disable_auto_execute "$PROJECT_ID"
        else
            echo "Error: State must be 'on' or 'off'"
            exit 1
        fi
        ;;

    enable-family)
        FAMILY="${1:-}"
        if [[ -z "$FAMILY" ]]; then
            echo "Error: Family name required"
            echo "Usage: /orchestrate-config enable-family <family-name>"
            exit 1
        fi
        registry_enable_family "$FAMILY"
        ;;

    disable-family)
        FAMILY="${1:-}"
        if [[ -z "$FAMILY" ]]; then
            echo "Error: Family name required"
            echo "Usage: /orchestrate-config disable-family <family-name>"
            exit 1
        fi
        registry_disable_family "$FAMILY"
        ;;

    list)
        ENABLED_ONLY="false"
        if [[ "${1:-}" == "--enabled-only" ]]; then
            ENABLED_ONLY="true"
        fi

        echo "=== Project Portfolio ==="
        echo ""

        projects=$(registry_list_projects "$ENABLED_ONLY")
        count=$(echo "$projects" | jq 'length')

        if [[ "$ENABLED_ONLY" == "true" ]]; then
            echo "Enabled Projects: $count"
        else
            enabled_count=$(registry_count_enabled)
            echo "Total Projects: $count"
            echo "Enabled: $enabled_count"
            echo "Disabled: $((count - enabled_count))"
        fi
        echo ""

        # Group by family
        for family in "ProjectA" "ProjectB" "ProjectE" "ProjectC" "ProjectD" "Other"; do
            if [[ "$family" == "Other" ]]; then
                family_projects=$(echo "$projects" | jq '[.[] | select(.family == "")]')
            else
                family_projects=$(echo "$projects" | jq --arg family "$family" '[.[] | select(.family == $family)]')
            fi

            family_count=$(echo "$family_projects" | jq 'length')
            if [[ $family_count -gt 0 ]]; then
                echo "## $family ($family_count projects)"
                echo "$family_projects" | jq -r '.[] | "  - \(.id) [\(.orchestration.priority)] " +
                    (if .orchestration.enabled then "✓" else "✗" end) +
                    (if .orchestration.auto_execute then " [auto-exec]" else "" end)'
                echo ""
            fi
        done
        ;;

    show)
        PROJECT_ID="${1:-}"
        if [[ -z "$PROJECT_ID" ]]; then
            echo "Error: Project ID required"
            echo "Usage: /orchestrate-config show <project-id>"
            exit 1
        fi

        project=$(registry_get_project "$PROJECT_ID")
        if [[ "$project" == "{}" ]]; then
            echo "Error: Project not found: $PROJECT_ID"
            exit 1
        fi

        echo "=== Project: $PROJECT_ID ==="
        echo ""
        echo "Path: $(echo "$project" | jq -r '.path')"
        echo "Family: $(echo "$project" | jq -r '.family // "None"')"
        echo "GitHub: $(echo "$project" | jq -r '.github_repo // "Unknown"')"
        echo "Tech Stack: $(echo "$project" | jq -r '.tech_stack | join(", ")')"
        echo ""
        echo "Orchestration Settings:"
        echo "  Enabled: $(echo "$project" | jq -r '.orchestration.enabled')"
        echo "  Priority: $(echo "$project" | jq -r '.orchestration.priority')"
        echo "  Auto-capture TODOs: $(echo "$project" | jq -r '.orchestration.auto_capture_todos')"
        echo "  Auto-execute: $(echo "$project" | jq -r '.orchestration.auto_execute')"
        echo "  Max complexity: $(echo "$project" | jq -r '.orchestration.auto_execute_max_complexity')"
        echo "  Require tests: $(echo "$project" | jq -r '.orchestration.require_tests')"

        reason=$(echo "$project" | jq -r '.orchestration.reason // ""')
        if [[ -n "$reason" ]]; then
            echo "  Reason: $reason"
        fi
        ;;

    count)
        enabled_count=$(registry_count_enabled)
        total_count=$(jq '.projects | length' "$REGISTRY_FILE")
        echo "Enabled projects: ${enabled_count} / ${total_count}"
        ;;

    *)
        echo "Usage: /orchestrate-config <command> [args]"
        echo ""
        echo "Commands:"
        echo "  enable <project-id>                    Enable project for orchestration"
        echo "  disable <project-id> [reason]          Disable project"
        echo "  priority <project-id> <high|med|low>   Set project priority"
        echo "  auto-execute <project-id> <on|off>     Enable/disable auto-execution"
        echo "  enable-family <family>                 Enable all projects in family"
        echo "  disable-family <family>                Disable all projects in family"
        echo "  list [--enabled-only]                  List all projects"
        echo "  show <project-id>                      Show project details"
        echo "  count                                  Count enabled projects"
        exit 1
        ;;
esac
