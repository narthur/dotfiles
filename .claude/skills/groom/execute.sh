#!/bin/bash
# groom skill executor
# Automatically triage and label GitHub issues

set -euo pipefail

# Source required libraries
source "${HOME}/.claude/lib/issue-grooming.sh"
source "${HOME}/.claude/lib/issue-analyzer.sh"
source "${HOME}/.claude/lib/queue-manager.sh"
source "${HOME}/.claude/lib/state-manager.sh"
source "${HOME}/.claude/lib/memory-manager.sh"
source "${HOME}/.claude/lib/portfolio-registry.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Fetch issues to groom
fetch_issues_to_groom() {
    local project_id="$1"
    local unlabeled_only="${2:-false}"

    echo -e "${BLUE}→${NC} Fetching issues from $project_id..."

    # Get GitHub repo
    local repo
    repo=$(registry_get_project "$project_id" | jq -r '.github_repo')

    if [[ -z "$repo" ]] || [[ "$repo" == "null" ]]; then
        echo "  No GitHub repo configured"
        echo "[]"
        return 0
    fi

    # Fetch issues
    local issues
    if [[ "$unlabeled_only" == "true" ]]; then
        issues=$(gh issue list --repo "$repo" --state open --json number,title,body,labels,createdAt,comments --label "" --limit 50 2>/dev/null || echo "[]")
    else
        issues=$(gh issue list --repo "$repo" --state open --json number,title,body,labels,createdAt,comments --limit 50 2>/dev/null || echo "[]")
    fi

    echo "$issues"
}

# Groom a single issue
groom_single_issue() {
    local project_id="$1"
    local issue_json="$2"

    local issue_number
    issue_number=$(echo "$issue_json" | jq -r '.number')
    local title
    title=$(echo "$issue_json" | jq -r '.title')

    echo ""
    echo "  Issue #$issue_number: $title"

    # Check if recently analyzed
    if issue_analysis_is_fresh "issue-${issue_number}"; then
        echo "    (Using cached analysis)"
    fi

    # Perform grooming analysis
    local grooming
    grooming=$(groom_issue "$issue_json")

    local suggested_labels
    suggested_labels=$(echo "$grooming" | jq -r '.suggested_labels | join(", ")')
    local priority
    priority=$(echo "$grooming" | jq -r '.priority.priority')
    local priority_score
    priority_score=$(echo "$grooming" | jq -r '.priority.score')
    local complexity
    complexity=$(echo "$grooming" | jq -r '.complexity.complexity // "unknown"')
    local should_break
    should_break=$(echo "$grooming" | jq -r '.breakdown.should_break_down')

    echo "    Labels: $suggested_labels"
    echo "    Priority: $priority (score: $priority_score)"
    echo "    Complexity: $complexity"

    # Check if executable
    local project
    project=$(registry_get_project "$project_id")
    local executable
    executable=$(is_issue_executable "$issue_json" "$project" 2>/dev/null || echo "false")

    if [[ "$executable" == "true" ]]; then
        echo -e "    ${GREEN}✓${NC} Ready for auto-execution"
    else
        if [[ "$complexity" == "high" ]]; then
            echo -e "    ${YELLOW}⚠${NC} Too complex for auto-execution"
        fi
    fi

    # Check breakdown
    if [[ "$should_break" == "true" ]]; then
        local reasons
        reasons=$(echo "$grooming" | jq -r '.breakdown.reasons | join(", ")')
        echo -e "    ${YELLOW}⚠${NC} Should be broken down ($reasons)"

        # Generate sub-issue suggestions
        local sub_issues
        sub_issues=$(suggest_sub_issues "$issue_json")
        local sub_count
        sub_count=$(echo "$sub_issues" | jq 'length')

        if [[ $sub_count -gt 0 ]]; then
            echo "    Suggested sub-issues:"
            echo "$sub_issues" | jq -r '.[] | "      - \(.)"' | head -5
        fi

        # Queue comment with breakdown suggestion
        local comment="## Breakdown Suggestion

This issue appears to be quite large and might benefit from being broken down into smaller, focused issues.

**Reasons:**
$(echo "$grooming" | jq -r '.breakdown.reasons[] | "- \(.)"')

**Suggested sub-issues:**
$(echo "$sub_issues" | jq -r 'to_entries | .[] | "\(.key + 1). \(.value)"')

This will make the work easier to track and execute incrementally."

        local comment_entry
        comment_entry=$(jq -n \
            --arg id "$(generate_id 'comment')" \
            --arg project "$project_id" \
            --arg issue "$issue_number" \
            --arg comment "$comment" \
            '{
                id: $id,
                project: $project,
                data: {
                    issue_number: $issue,
                    comment: $comment
                }
            }')

        queue_add_comment "$comment_entry" >/dev/null
    fi

    # Get current labels
    local current_labels
    current_labels=$(echo "$issue_json" | jq -r '[.labels[]?.name] | join(",")')

    # Get new labels to add (only those not already present)
    local labels_to_add
    labels_to_add=$(echo "$grooming" | jq -r --arg current "$current_labels" \
        '.suggested_labels | map(select((("," + $current + ",") | contains("," + . + ",")) | not)) | join(",")')

    # Add priority label
    if [[ "$priority" != "medium" ]]; then
        if [[ -n "$labels_to_add" ]]; then
            labels_to_add="${labels_to_add},priority:${priority}"
        else
            labels_to_add="priority:${priority}"
        fi
    fi

    # Queue label updates if there are new labels
    if [[ -n "$labels_to_add" ]]; then
        local update_entry
        update_entry=$(jq -n \
            --arg id "$(generate_id 'update')" \
            --arg project "$project_id" \
            --arg issue "$issue_number" \
            --arg labels "$labels_to_add" \
            '{
                id: $id,
                project: $project,
                data: {
                    issue_number: $issue,
                    action: "add-labels",
                    labels: ($labels | split(","))
                }
            }')

        queue_add_issue_update "$update_entry" >/dev/null
        echo "    → Queued: add labels [$labels_to_add]"
    fi

    # Save analysis to state for /execute to use
    issue_save_analysis "issue-${issue_number}" "$grooming"

    # Update project notes with patterns
    if [[ "$should_break" == "true" ]]; then
        memory_update_project_notes "$project_id" "Common Issues" "Issue #${issue_number} needed breakdown - ${reasons}"
    fi
}

# Groom all issues in a project
groom_project() {
    local project_id="$1"
    local unlabeled_only="${2:-false}"

    echo -e "${BLUE}→${NC} Grooming project: $project_id"

    # Fetch issues
    local issues
    issues=$(fetch_issues_to_groom "$project_id" "$unlabeled_only")

    local count
    count=$(echo "$issues" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "  No issues to groom"
        return 0
    fi

    echo "  Found $count issue(s) to groom"

    # Groom each issue
    local groomed=0
    echo "$issues" | jq -c '.[]' | while read -r issue; do
        groom_single_issue "$project_id" "$issue"
        groomed=$((groomed + 1))
    done

    echo -e "  ${GREEN}✓${NC} Groomed $count issue(s)"
}

# Auto-groom all enabled projects
auto_groom() {
    local unlabeled_only="${1:-false}"

    echo "=== Issue Grooming ==="
    echo ""

    # Get enabled projects
    local projects
    projects=$(registry_list_projects true)

    local project_count
    project_count=$(echo "$projects" | jq 'length')

    if [[ $project_count -eq 0 ]]; then
        echo "No projects enabled for orchestration."
        echo ""
        echo "Enable a project:"
        echo "  /orchestrate-config enable <project-id>"
        return 0
    fi

    echo "Processing $project_count project(s)"
    echo ""

    echo "$projects" | jq -c '.[]' | while read -r project_json; do
        local project_id
        project_id=$(echo "$project_json" | jq -r '.id')
        local project_path
        project_path=$(echo "$project_json" | jq -r '.path')

        # Run in project directory for proper token attribution
        if [[ -n "$project_path" ]] && [[ -d "$project_path" ]]; then
            (cd "$project_path" && groom_project "$project_id" "$unlabeled_only")
        else
            groom_project "$project_id" "$unlabeled_only"
        fi
        echo ""
    done

    echo "=== Grooming Complete ==="
    echo ""

    # Show queue summary
    local updates_count
    updates_count=$(queue_count "${HOME}/.claude/approval-queue/issues-to-update.json" "pending")
    local comments_count
    comments_count=$(queue_count "${HOME}/.claude/approval-queue/comments-to-post.json" "pending")

    echo "Queued actions:"
    echo "  Label updates: $updates_count"
    echo "  Breakdown comments: $comments_count"
    echo ""
    echo "Review and approve updates:"
    echo "  /approve updates"
}

# Analyze a specific issue without queueing
analyze_issue() {
    local issue_number="$1"
    local project_id="$2"

    echo "=== Issue Analysis ==="
    echo ""

    # Get repo
    local repo
    repo=$(registry_get_project "$project_id" | jq -r '.github_repo')

    if [[ -z "$repo" ]] || [[ "$repo" == "null" ]]; then
        echo "Error: No GitHub repo configured for $project_id"
        return 1
    fi

    # Fetch issue
    local issue
    issue=$(gh issue view "$issue_number" --repo "$repo" --json number,title,body,labels,createdAt,comments 2>/dev/null || echo "{}")

    if [[ "$issue" == "{}" ]]; then
        echo "Error: Issue #$issue_number not found"
        return 1
    fi

    # Perform analysis
    local grooming
    grooming=$(groom_issue "$issue")

    local title
    title=$(echo "$issue" | jq -r '.title')

    echo "Issue #$issue_number: $title"
    echo ""
    echo "Suggested Labels:"
    echo "$grooming" | jq -r '.suggested_labels[] | "  - \(.)"'
    echo ""
    echo "Priority: $(echo "$grooming" | jq -r '.priority.priority') (score: $(echo "$grooming" | jq -r '.priority.score'))"
    echo ""
    echo "Complexity: $(echo "$grooming" | jq -r '.complexity.complexity // "unknown"')"
    echo ""

    local should_break
    should_break=$(echo "$grooming" | jq -r '.breakdown.should_break_down')

    if [[ "$should_break" == "true" ]]; then
        echo "Breakdown Recommendation: YES"
        echo "Reasons:"
        echo "$grooming" | jq -r '.breakdown.reasons[] | "  - \(.)"'
        echo ""
        echo "Suggested sub-issues:"
        suggest_sub_issues "$issue" | jq -r '.[] | "  - \(.)"'
    else
        echo "Breakdown Recommendation: NO"
    fi
}

# Main execution
main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        auto)
            local unlabeled_only="false"

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --unlabeled-only)
                        unlabeled_only="true"
                        shift
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            auto_groom "$unlabeled_only"
            ;;

        project)
            local project_id="${1:-}"
            if [[ -z "$project_id" ]]; then
                echo "Error: Project ID required"
                echo "Usage: /groom project <project-id>"
                exit 1
            fi

            # Get project path for token attribution
            local project_path
            project_path=$(registry_get_project "$project_id" | jq -r '.path')

            # Run in project directory if available
            if [[ -n "$project_path" ]] && [[ -d "$project_path" ]]; then
                (cd "$project_path" && groom_project "$project_id" "false")
            else
                groom_project "$project_id" "false"
            fi
            ;;

        issue)
            local issue_number="${1:-}"
            local project_id=""

            shift || true
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project)
                        project_id="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            if [[ -z "$issue_number" ]] || [[ -z "$project_id" ]]; then
                echo "Error: Issue number and project required"
                echo "Usage: /groom issue <number> --project <project-id>"
                exit 1
            fi

            echo "Direct issue grooming not yet fully implemented"
            echo "Use: /groom project <project-id>"
            ;;

        analyze)
            local issue_number="${1:-}"
            local project_id=""

            shift || true
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --project)
                        project_id="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            if [[ -z "$issue_number" ]] || [[ -z "$project_id" ]]; then
                echo "Error: Issue number and project required"
                echo "Usage: /groom analyze <number> --project <project-id>"
                exit 1
            fi

            analyze_issue "$issue_number" "$project_id"
            ;;

        *)
            echo "Usage: /groom <command> [options]"
            echo ""
            echo "Commands:"
            echo "  auto [--unlabeled-only]                Groom all enabled projects"
            echo "  project <id>                           Groom specific project"
            echo "  issue <number> --project <id>          Groom specific issue"
            echo "  analyze <number> --project <id>        Analyze without queueing"
            echo ""
            echo "Examples:"
            echo "  /groom auto"
            echo "  /groom auto --unlabeled-only"
            echo "  /groom project example-api"
            echo "  /groom analyze 42 --project example-api"
            echo ""
            echo "After grooming, approve with:"
            echo "  /approve updates"
            exit 1
            ;;
    esac
}

# Run main with arguments
main "$@"
