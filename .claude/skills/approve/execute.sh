#!/bin/bash
# approve skill executor
# Batch approve and execute queued orchestration actions

set -euo pipefail

# Source queue manager
source "${HOME}/.claude/lib/queue-manager.sh"

QUEUE_DIR="${HOME}/.claude/approval-queue"
LOG_FILE="${HOME}/.claude/logs/approve-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$(dirname "$LOG_FILE")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$@" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $@" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $@" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}→${NC} $@" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}!${NC} $@" | tee -a "$LOG_FILE"
}

# Count total pending items
count_pending() {
    local total=0
    for queue_file in "${QUEUE_DIR}"/*.json; do
        if [[ -f "$queue_file" ]]; then
            count=$(queue_count "$queue_file" "pending")
            total=$((total + count))
        fi
    done
    echo "$total"
}

# Display queue summary
show_summary() {
    echo ""
    echo "=== APPROVAL QUEUE SUMMARY ==="
    echo ""

    local issues_count=$(queue_count "${QUEUE_DIR}/issues-to-create.json" "pending")
    local branches_count=$(queue_count "${QUEUE_DIR}/branches-to-push.json" "pending")
    local prs_count=$(queue_count "${QUEUE_DIR}/prs-to-create.json" "pending")
    local updates_count=$(queue_count "${QUEUE_DIR}/issues-to-update.json" "pending")
    local comments_count=$(queue_count "${QUEUE_DIR}/comments-to-post.json" "pending")

    local total=$((issues_count + branches_count + prs_count + updates_count + comments_count))

    if [[ $total -eq 0 ]]; then
        echo "No pending actions in queue."
        echo ""
        echo "Run /orchestrate-cycle to capture, groom, and execute issues."
        return 1
    fi

    echo "Total pending actions: $total"
    echo ""
    echo "  Issues to Create:    $issues_count"
    echo "  Branches to Push:    $branches_count"
    echo "  PRs to Create:       $prs_count"
    echo "  Issue Updates:       $updates_count"
    echo "  Comments to Post:    $comments_count"
    echo ""
}

# Display category details
show_category() {
    local category="$1"
    local queue_file="$2"

    echo ""
    echo -e "${BLUE}=== $category ===${NC}"
    echo ""

    local items
    items=$(queue_list "$queue_file" "pending")
    local count
    count=$(echo "$items" | jq 'length')

    if [[ $count -eq 0 ]]; then
        echo "  (none)"
        return 0
    fi

    # Display each item
    echo "$items" | jq -r 'to_entries[] | "  \(.key + 1). [\(.value.project // "unknown")] \(.value.data.title // .value.type)"'
    echo ""
}

# Execute issue creation
execute_create_issue() {
    local item="$1"
    local id
    id=$(echo "$item" | jq -r '.id')
    local project
    project=$(echo "$item" | jq -r '.project')
    local title
    title=$(echo "$item" | jq -r '.data.title')
    local body
    body=$(echo "$item" | jq -r '.data.body')
    local labels
    labels=$(echo "$item" | jq -r '.data.labels | join(",")')

    log_info "Creating issue in $project: $title"

    # Get GitHub repo from registry
    source "${HOME}/.claude/lib/portfolio-registry.sh"
    local repo
    repo=$(registry_get_project "$project" | jq -r '.github_repo')

    if [[ -z "$repo" ]] || [[ "$repo" == "null" ]]; then
        log_error "No GitHub repo found for project: $project"
        return 1
    fi

    # Create issue using gh CLI
    local issue_url
    if [[ -n "$labels" ]]; then
        issue_url=$(gh issue create --repo "$repo" --title "$title" --body "$body" --label "$labels" 2>&1)
    else
        issue_url=$(gh issue create --repo "$repo" --title "$title" --body "$body" 2>&1)
    fi

    if [[ $? -eq 0 ]]; then
        log_success "Created issue: $issue_url"
        queue_complete "${QUEUE_DIR}/issues-to-create.json" "$id"
        return 0
    else
        log_error "Failed to create issue: $issue_url"
        return 1
    fi
}

# Execute branch push
execute_push_branch() {
    local item="$1"
    local id
    id=$(echo "$item" | jq -r '.id')
    local project
    project=$(echo "$item" | jq -r '.project')
    local branch
    branch=$(echo "$item" | jq -r '.data.branch')

    log_info "Pushing branch in $project: $branch"

    # Get project path
    source "${HOME}/.claude/lib/portfolio-registry.sh"
    local project_path
    project_path=$(registry_get_project_path "$project")

    if [[ ! -d "$project_path" ]]; then
        log_error "Project path not found: $project_path"
        return 1
    fi

    # Push branch using GitButler
    cd "$project_path"
    if but push "$branch" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Pushed branch: $branch"
        queue_complete "${QUEUE_DIR}/branches-to-push.json" "$id"
        return 0
    else
        log_error "Failed to push branch: $branch"
        return 1
    fi
}

# Execute PR creation
execute_create_pr() {
    local item="$1"
    local id
    id=$(echo "$item" | jq -r '.id')
    local project
    project=$(echo "$item" | jq -r '.project')
    local title
    title=$(echo "$item" | jq -r '.data.title')
    local body
    body=$(echo "$item" | jq -r '.data.body')
    local branch
    branch=$(echo "$item" | jq -r '.data.branch')
    local base
    base=$(echo "$item" | jq -r '.data.base // "main"')

    log_info "Creating PR in $project: $title"

    # Get GitHub repo and project path
    source "${HOME}/.claude/lib/portfolio-registry.sh"
    local repo
    repo=$(registry_get_project "$project" | jq -r '.github_repo')
    local project_path
    project_path=$(registry_get_project_path "$project")

    if [[ -z "$repo" ]] || [[ "$repo" == "null" ]]; then
        log_error "No GitHub repo found for project: $project"
        return 1
    fi

    # Create PR using gh CLI
    cd "$project_path"
    local pr_url
    pr_url=$(gh pr create --repo "$repo" --title "$title" --body "$body" --base "$base" --head "$branch" 2>&1)

    if [[ $? -eq 0 ]]; then
        log_success "Created PR: $pr_url"
        queue_complete "${QUEUE_DIR}/prs-to-create.json" "$id"
        return 0
    else
        log_error "Failed to create PR: $pr_url"
        return 1
    fi
}

# Execute issue update
execute_update_issue() {
    local item="$1"
    local id
    id=$(echo "$item" | jq -r '.id')
    local project
    project=$(echo "$item" | jq -r '.project')
    local issue_number
    issue_number=$(echo "$item" | jq -r '.data.issue_number')
    local action
    action=$(echo "$item" | jq -r '.data.action')

    log_info "Updating issue #$issue_number in $project: $action"

    # Get GitHub repo
    source "${HOME}/.claude/lib/portfolio-registry.sh"
    local repo
    repo=$(registry_get_project "$project" | jq -r '.github_repo')

    if [[ -z "$repo" ]] || [[ "$repo" == "null" ]]; then
        log_error "No GitHub repo found for project: $project"
        return 1
    fi

    case "$action" in
        add-labels)
            local labels
            labels=$(echo "$item" | jq -r '.data.labels | join(",")')
            if gh issue edit "$issue_number" --repo "$repo" --add-label "$labels" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Added labels to issue #$issue_number"
                queue_complete "${QUEUE_DIR}/issues-to-update.json" "$id"
                return 0
            fi
            ;;
        close)
            if gh issue close "$issue_number" --repo "$repo" 2>&1 | tee -a "$LOG_FILE"; then
                log_success "Closed issue #$issue_number"
                queue_complete "${QUEUE_DIR}/issues-to-update.json" "$id"
                return 0
            fi
            ;;
        *)
            log_error "Unknown action: $action"
            return 1
            ;;
    esac

    log_error "Failed to update issue #$issue_number"
    return 1
}

# Execute comment post
execute_post_comment() {
    local item="$1"
    local id
    id=$(echo "$item" | jq -r '.id')
    local project
    project=$(echo "$item" | jq -r '.project')
    local issue_number
    issue_number=$(echo "$item" | jq -r '.data.issue_number')
    local comment
    comment=$(echo "$item" | jq -r '.data.comment')

    log_info "Posting comment on #$issue_number in $project"

    # Get GitHub repo
    source "${HOME}/.claude/lib/portfolio-registry.sh"
    local repo
    repo=$(registry_get_project "$project" | jq -r '.github_repo')

    if [[ -z "$repo" ]] || [[ "$repo" == "null" ]]; then
        log_error "No GitHub repo found for project: $project"
        return 1
    fi

    if gh issue comment "$issue_number" --repo "$repo" --body "$comment" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Posted comment on issue #$issue_number"
        queue_complete "${QUEUE_DIR}/comments-to-post.json" "$id"
        return 0
    else
        log_error "Failed to post comment"
        return 1
    fi
}

# Process a queue category
process_category() {
    local category="$1"
    local queue_file="$2"
    local executor="$3"

    local items
    items=$(queue_list "$queue_file" "pending")
    local count
    count=$(echo "$items" | jq 'length')

    if [[ $count -eq 0 ]]; then
        return 0
    fi

    show_category "$category" "$queue_file"

    echo -n "Process this category? [a]ccept all / [r]eview individually / [s]kip: "
    read -r choice

    case "$choice" in
        a|A)
            log "Processing all items in $category..."
            echo "$items" | jq -c '.[]' | while read -r item; do
                $executor "$item" || true
            done
            ;;
        r|R)
            echo "$items" | jq -c '.[]' | while read -r item; do
                local title
                title=$(echo "$item" | jq -r '.data.title // .type')
                echo ""
                echo "Item: $title"
                echo -n "Approve this item? [y/n]: "
                read -r approve
                if [[ "$approve" =~ ^[Yy]$ ]]; then
                    $executor "$item" || true
                else
                    log_info "Skipped: $title"
                fi
            done
            ;;
        s|S)
            log_info "Skipped category: $category"
            ;;
        *)
            log_warning "Invalid choice, skipping category"
            ;;
    esac
}

# Main execution
main() {
    local mode="${1:-interactive}"

    log "=== Approval Session Started at $(date) ==="
    log ""

    # Show summary
    if ! show_summary; then
        exit 0
    fi

    # Auto-approve mode
    if [[ "$mode" == "--all" ]]; then
        log_warning "AUTO-APPROVE MODE: Processing all items without review!"
        echo -n "Are you sure? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi

        # Process all categories without prompting
        queue_list "${QUEUE_DIR}/issues-to-create.json" "pending" | jq -c '.[]' | while read -r item; do
            execute_create_issue "$item" || true
        done

        queue_list "${QUEUE_DIR}/branches-to-push.json" "pending" | jq -c '.[]' | while read -r item; do
            execute_push_branch "$item" || true
        done

        queue_list "${QUEUE_DIR}/prs-to-create.json" "pending" | jq -c '.[]' | while read -r item; do
            execute_create_pr "$item" || true
        done

        queue_list "${QUEUE_DIR}/issues-to-update.json" "pending" | jq -c '.[]' | while read -r item; do
            execute_update_issue "$item" || true
        done

        queue_list "${QUEUE_DIR}/comments-to-post.json" "pending" | jq -c '.[]' | while read -r item; do
            execute_post_comment "$item" || true
        done

    # Category-specific mode
    elif [[ "$mode" =~ ^(issues|branches|prs|updates|comments)$ ]]; then
        case "$mode" in
            issues)
                process_category "Issues to Create" "${QUEUE_DIR}/issues-to-create.json" execute_create_issue
                ;;
            branches)
                process_category "Branches to Push" "${QUEUE_DIR}/branches-to-push.json" execute_push_branch
                ;;
            prs)
                process_category "PRs to Create" "${QUEUE_DIR}/prs-to-create.json" execute_create_pr
                ;;
            updates)
                process_category "Issue Updates" "${QUEUE_DIR}/issues-to-update.json" execute_update_issue
                ;;
            comments)
                process_category "Comments to Post" "${QUEUE_DIR}/comments-to-post.json" execute_post_comment
                ;;
        esac

    # Interactive mode (default)
    else
        process_category "Issues to Create" "${QUEUE_DIR}/issues-to-create.json" execute_create_issue
        process_category "Branches to Push" "${QUEUE_DIR}/branches-to-push.json" execute_push_branch
        process_category "PRs to Create" "${QUEUE_DIR}/prs-to-create.json" execute_create_pr
        process_category "Issue Updates" "${QUEUE_DIR}/issues-to-update.json" execute_update_issue
        process_category "Comments to Post" "${QUEUE_DIR}/comments-to-post.json" execute_post_comment
    fi

    echo ""
    log "=== Approval Session Complete ==="
    log "Log file: $LOG_FILE"

    # Clean up completed items
    for queue_file in "${QUEUE_DIR}"/*.json; do
        if [[ -f "$queue_file" ]]; then
            queue_clear_completed "$queue_file"
        fi
    done
}

# Run main with arguments
main "$@"
