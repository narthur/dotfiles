#!/bin/bash
# Orchestration Cycle Script
# Runs the complete autonomous workflow: capture → groom → execute

set -euo pipefail

# Source required libraries
source "${HOME}/.claude/lib/queue-manager.sh"
source "${HOME}/.claude/lib/state-manager.sh"
source "${HOME}/.claude/lib/portfolio-registry.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Log file
LOG_FILE="${HOME}/.claude/logs/orchestration-cycle-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

# Logging functions
log() {
    echo "$@" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${BOLD}${BLUE}=== $@ ===${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${BLUE}→${NC} $@" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $@" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}!${NC} $@" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC} $@" | tee -a "$LOG_FILE"
}

# Initialize cycle tracking
CYCLE_ID="cycle-$(date +%s)"
CYCLE_START=$(date -Iseconds)

# Statistics
STATS_PROJECTS_PROCESSED=0
STATS_TODOS_CAPTURED=0
STATS_ISSUES_GROOMED=0
STATS_ISSUES_EXECUTED=0
STATS_ERRORS=0

# Get enabled projects
get_enabled_projects() {
    registry_list_projects true | jq -r '.[].id'
}

# Count enabled projects
count_enabled_projects() {
    registry_count_enabled
}

# Run capture phase
run_capture_phase() {
    log_section "Phase 1: TODO Capture"

    local enabled_count
    enabled_count=$(count_enabled_projects)

    if [[ $enabled_count -eq 0 ]]; then
        log_warning "No projects enabled for orchestration"
        log_warning "Enable projects with: /orchestrate-config enable <project-id>"
        return 0
    fi

    log_step "Scanning $enabled_count enabled project(s) for TODOs..."

    # Get initial queue count
    local initial_count
    initial_count=$(queue_count "${HOME}/.claude/approval-queue/issues-to-create.json" "pending")

    # Run capture for all enabled projects
    local projects
    projects=$(get_enabled_projects)

    while IFS= read -r project_id; do
        log_step "Scanning: $project_id"

        # Get project path and check auto_capture setting
        local project_data
        project_data=$(registry_get_project "$project_id")
        local auto_capture
        auto_capture=$(echo "$project_data" | jq -r '.orchestration.auto_capture_todos')
        local project_path
        project_path=$(echo "$project_data" | jq -r '.path')

        if [[ "$auto_capture" != "true" ]]; then
            log "  → TODO capture not enabled (skipping)"
            continue
        fi

        if [[ -z "$project_path" ]] || [[ ! -d "$project_path" ]]; then
            log_error "Project path not found or invalid: $project_path"
            STATS_ERRORS=$((STATS_ERRORS + 1))
            continue
        fi

        # Run capture in project directory for proper token attribution
        if (cd "$project_path" && "${HOME}/.claude/skills/capture/execute.sh" scan "$project_id") >> "$LOG_FILE" 2>&1; then
            STATS_PROJECTS_PROCESSED=$((STATS_PROJECTS_PROCESSED + 1))
        else
            log_error "Failed to scan $project_id"
            STATS_ERRORS=$((STATS_ERRORS + 1))
        fi
    done <<< "$projects"

    # Calculate TODOs captured
    local final_count
    final_count=$(queue_count "${HOME}/.claude/approval-queue/issues-to-create.json" "pending")
    STATS_TODOS_CAPTURED=$((final_count - initial_count))

    log_success "Capture phase complete"
    log "  → Projects scanned: $STATS_PROJECTS_PROCESSED"
    log "  → TODOs captured: $STATS_TODOS_CAPTURED"
}

# Run groom phase
run_groom_phase() {
    log_section "Phase 2: Issue Grooming"

    local enabled_count
    enabled_count=$(count_enabled_projects)

    if [[ $enabled_count -eq 0 ]]; then
        log_warning "No projects enabled for orchestration"
        return 0
    fi

    log_step "Grooming issues in $enabled_count enabled project(s)..."

    # Get initial queue count
    local initial_count
    initial_count=$(queue_count "${HOME}/.claude/approval-queue/issues-to-update.json" "pending")

    # Run groom for all enabled projects
    if "${HOME}/.claude/skills/groom/execute.sh" auto >> "$LOG_FILE" 2>&1; then
        log_success "Grooming phase complete"
    else
        log_error "Grooming encountered errors"
        STATS_ERRORS=$((STATS_ERRORS + 1))
    fi

    # Calculate issues groomed
    local final_count
    final_count=$(queue_count "${HOME}/.claude/approval-queue/issues-to-update.json" "pending")
    STATS_ISSUES_GROOMED=$((final_count - initial_count))

    log "  → Label updates queued: $STATS_ISSUES_GROOMED"
}

# Run execute phase
run_execute_phase() {
    log_section "Phase 3: Autonomous Execution"

    local max_issues="${1:-3}"

    log_step "Executing up to $max_issues issue(s)..."

    # Get initial queue counts
    local initial_branches
    initial_branches=$(queue_count "${HOME}/.claude/approval-queue/branches-to-push.json" "pending")
    local initial_prs
    initial_prs=$(queue_count "${HOME}/.claude/approval-queue/prs-to-create.json" "pending")

    # Run execute
    if "${HOME}/.claude/skills/execute/execute.sh" auto --max "$max_issues" >> "$LOG_FILE" 2>&1; then
        log_success "Execution phase complete"
    else
        log_error "Execution encountered errors"
        STATS_ERRORS=$((STATS_ERRORS + 1))
    fi

    # Calculate issues executed
    local final_branches
    final_branches=$(queue_count "${HOME}/.claude/approval-queue/branches-to-push.json" "pending")
    STATS_ISSUES_EXECUTED=$((final_branches - initial_branches))

    log "  → Issues executed: $STATS_ISSUES_EXECUTED"
}

# Generate cycle summary
generate_summary() {
    log_section "Orchestration Cycle Summary"

    log "Cycle ID: $CYCLE_ID"
    log "Started: $CYCLE_START"
    log "Completed: $(date -Iseconds)"
    log ""
    log "Statistics:"
    log "  Projects processed: $STATS_PROJECTS_PROCESSED"
    log "  TODOs captured: $STATS_TODOS_CAPTURED"
    log "  Issues groomed: $STATS_ISSUES_GROOMED"
    log "  Issues executed: $STATS_ISSUES_EXECUTED"
    log "  Errors: $STATS_ERRORS"
    log ""

    # Queue summary
    local issues_queued
    issues_queued=$(queue_count "${HOME}/.claude/approval-queue/issues-to-create.json" "pending")
    local branches_queued
    branches_queued=$(queue_count "${HOME}/.claude/approval-queue/branches-to-push.json" "pending")
    local prs_queued
    prs_queued=$(queue_count "${HOME}/.claude/approval-queue/prs-to-create.json" "pending")
    local updates_queued
    updates_queued=$(queue_count "${HOME}/.claude/approval-queue/issues-to-update.json" "pending")
    local comments_queued
    comments_queued=$(queue_count "${HOME}/.claude/approval-queue/comments-to-post.json" "pending")

    local total_queued=$((issues_queued + branches_queued + prs_queued + updates_queued + comments_queued))

    log "Approval Queue:"
    log "  Issues to create: $issues_queued"
    log "  Branches to push: $branches_queued"
    log "  PRs to create: $prs_queued"
    log "  Issue updates: $updates_queued"
    log "  Comments to post: $comments_queued"
    log "  ${BOLD}Total pending: $total_queued${NC}"
    log ""

    if [[ $total_queued -gt 0 ]]; then
        log -e "${GREEN}${BOLD}Ready for approval!${NC}"
        log ""
        log "Review and approve queued actions:"
        log "  ${BOLD}/approve${NC}"
    else
        log "No actions queued. All work is complete!"
    fi

    log ""
    log "Full log: $LOG_FILE"
}

# Record cycle in history
record_cycle() {
    local cycle_data
    cycle_data=$(jq -n \
        --arg cycle_id "$CYCLE_ID" \
        --arg started_at "$CYCLE_START" \
        --arg completed_at "$(date -Iseconds)" \
        --arg projects "$STATS_PROJECTS_PROCESSED" \
        --arg todos "$STATS_TODOS_CAPTURED" \
        --arg groomed "$STATS_ISSUES_GROOMED" \
        --arg executed "$STATS_ISSUES_EXECUTED" \
        --arg errors "$STATS_ERRORS" \
        '{
            cycle_id: $cycle_id,
            started_at: $started_at,
            completed_at: $completed_at,
            stats: {
                projects_processed: ($projects | tonumber),
                todos_captured: ($todos | tonumber),
                issues_groomed: ($groomed | tonumber),
                issues_executed: ($executed | tonumber),
                errors: ($errors | tonumber)
            }
        }')

    cycle_record "$cycle_data"
}

# Main execution
main() {
    local max_execute="${1:-3}"

    log_section "Orchestration Cycle"
    log "Started at $(date)"
    log ""

    # Check if any projects are enabled
    local enabled_count
    enabled_count=$(count_enabled_projects)

    if [[ $enabled_count -eq 0 ]]; then
        log_error "No projects enabled for orchestration!"
        log ""
        log "Enable projects with:"
        log "  /orchestrate-config enable <project-id>"
        log "  /orchestrate-config enable-family <family-name>"
        log ""
        log "Example:"
        log "  /orchestrate-config enable example-api"
        log "  /orchestrate-config auto-execute example-api on"
        exit 1
    fi

    log "Processing $enabled_count enabled project(s)"
    log ""

    # Run phases
    run_capture_phase

    run_groom_phase

    run_execute_phase "$max_execute"

    # Generate summary
    generate_summary

    # Record cycle
    record_cycle

    log ""
    log -e "${GREEN}${BOLD}Orchestration cycle complete!${NC}"
}

# Run with arguments
main "$@"
