#!/bin/bash
# Issue Grooming Library
# Algorithms for triaging, labeling, and prioritizing GitHub issues

set -euo pipefail

# Suggest labels for an issue based on content analysis
# Usage: suggest_labels <issue_json>
# Returns: JSON array of suggested labels
suggest_labels() {
    local issue_json="$1"

    local title
    title=$(echo "$issue_json" | jq -r '.title')
    local body
    body=$(echo "$issue_json" | jq -r '.body // ""')
    local combined="$title $body"

    local labels=()

    # Bug detection
    if echo "$combined" | grep -qiE "\b(bug|error|crash|fail|broken|issue|problem|fix)\b"; then
        labels+=("bug")
    fi

    # Enhancement/Feature detection
    if echo "$combined" | grep -qiE "\b(add|feature|enhance|improve|new|implement|support)\b"; then
        labels+=("enhancement")
    fi

    # Documentation
    if echo "$combined" | grep -qiE "\b(doc|readme|comment|documentation|guide|explain)\b"; then
        labels+=("documentation")
    fi

    # Tech debt/Refactoring
    if echo "$combined" | grep -qiE "\b(refactor|cleanup|tech debt|technical debt|improve code|restructure)\b"; then
        labels+=("tech-debt")
    fi

    # Performance
    if echo "$combined" | grep -qiE "\b(performance|slow|optimize|speed|faster|efficiency)\b"; then
        labels+=("performance")
    fi

    # Security
    if echo "$combined" | grep -qiE "\b(security|vulnerability|xss|sql injection|auth|authentication|authorization)\b"; then
        labels+=("security")
    fi

    # Testing
    if echo "$combined" | grep -qiE "\b(test|testing|coverage|unit test|integration test)\b"; then
        labels+=("testing")
    fi

    # UI/UX
    if echo "$combined" | grep -qiE "\b(ui|ux|interface|design|layout|style|css|visual)\b"; then
        labels+=("ui")
    fi

    # Dependencies
    if echo "$combined" | grep -qiE "\b(dependency|dependencies|package|upgrade|update.*version)\b"; then
        labels+=("dependencies")
    fi

    # Good first issue (simple keywords)
    if echo "$combined" | grep -qiE "\b(typo|simple|easy|beginner|first)\b"; then
        labels+=("good first issue")
    fi

    # Default to enhancement if no other labels
    if [[ ${#labels[@]} -eq 0 ]]; then
        labels+=("enhancement")
    fi

    # Convert to JSON array
    printf '%s\n' "${labels[@]}" | jq -R . | jq -s 'unique'
}

# Calculate priority score for an issue
# Usage: calculate_priority <issue_json>
# Returns: JSON object with priority level and score
calculate_priority() {
    local issue_json="$1"

    local title
    title=$(echo "$issue_json" | jq -r '.title')
    local body
    body=$(echo "$issue_json" | jq -r '.body // ""')
    local created_at
    created_at=$(echo "$issue_json" | jq -r '.createdAt // .created_at // ""')
    local comments
    comments=$(echo "$issue_json" | jq -r '.comments // 0')

    local score=5  # Default medium priority

    # Keyword-based priority adjustments
    if echo "$title $body" | grep -qiE "\b(critical|urgent|blocker|breaking|production)\b"; then
        score=$((score + 3))
    fi

    if echo "$title $body" | grep -qiE "\b(security|vulnerability|exploit)\b"; then
        score=$((score + 3))
    fi

    if echo "$title $body" | grep -qiE "\b(bug|error|crash|broken)\b"; then
        score=$((score + 2))
    fi

    if echo "$title $body" | grep -qiE "\b(enhancement|feature|improve)\b"; then
        score=$((score + 1))
    fi

    if echo "$title $body" | grep -qiE "\b(nice to have|someday|future|low priority)\b"; then
        score=$((score - 2))
    fi

    # Age-based adjustment (older = higher priority)
    if [[ -n "$created_at" ]]; then
        local now
        now=$(date +%s)
        local created_ts
        created_ts=$(date -d "$created_at" +%s 2>/dev/null || echo "$now")
        local age_days=$(( (now - created_ts) / 86400 ))

        if [[ $age_days -gt 90 ]]; then
            score=$((score + 2))
        elif [[ $age_days -gt 30 ]]; then
            score=$((score + 1))
        fi
    fi

    # Activity-based adjustment (more comments = higher priority)
    if [[ $comments -gt 10 ]]; then
        score=$((score + 2))
    elif [[ $comments -gt 5 ]]; then
        score=$((score + 1))
    fi

    # Determine priority level
    local priority="medium"
    if [[ $score -ge 10 ]]; then
        priority="critical"
    elif [[ $score -ge 8 ]]; then
        priority="high"
    elif [[ $score -ge 5 ]]; then
        priority="medium"
    else
        priority="low"
    fi

    jq -n \
        --arg priority "$priority" \
        --arg score "$score" \
        '{
            priority: $priority,
            score: ($score | tonumber)
        }'
}

# Detect if issue should be broken down into smaller issues
# Usage: should_break_down <issue_json>
# Returns: JSON object with breakdown recommendation and reasons
should_break_down() {
    local issue_json="$1"

    local title
    title=$(echo "$issue_json" | jq -r '.title')
    local body
    body=$(echo "$issue_json" | jq -r '.body // ""')

    local should_break=false
    local reasons=()

    # Check body length (very long descriptions often need breakdown)
    if [[ ${#body} -gt 2000 ]]; then
        should_break=true
        reasons+=("Very long description (${#body} chars)")
    fi

    # Check for multiple "and" conjunctions in title
    local and_count
    and_count=$(echo "$title" | grep -o " and " | wc -l)
    if [[ $and_count -ge 2 ]]; then
        should_break=true
        reasons+=("Multiple tasks in title ($and_count 'and' conjunctions)")
    fi

    # Check for bullet lists (often indicates multiple subtasks)
    local bullet_count
    bullet_count=$(echo "$body" | grep -cE "^[*-] " || echo "0")
    if [[ $bullet_count -ge 5 ]]; then
        should_break=true
        reasons+=("Many subtasks listed ($bullet_count items)")
    fi

    # Check for numbered lists
    local numbered_count
    numbered_count=$(echo "$body" | grep -cE "^[0-9]+\. " || echo "0")
    if [[ $numbered_count -ge 5 ]]; then
        should_break=true
        reasons+=("Many numbered steps ($numbered_count steps)")
    fi

    # Check for phase/stage keywords
    if echo "$body" | grep -qiE "(phase [0-9]|stage [0-9]|step [0-9]|part [0-9])"; then
        should_break=true
        reasons+=("Contains multiple phases/stages")
    fi

    # Check for epic-style keywords
    if echo "$title $body" | grep -qiE "\b(epic|initiative|project|roadmap)\b"; then
        should_break=true
        reasons+=("Marked as epic or large initiative")
    fi

    # Convert reasons to JSON array
    local reasons_json
    if [[ ${#reasons[@]} -gt 0 ]]; then
        reasons_json=$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s '.')
    else
        reasons_json="[]"
    fi

    jq -n \
        --argjson should "$([[ "$should_break" == "true" ]] && echo "true" || echo "false")" \
        --argjson reasons "$reasons_json" \
        '{
            should_break_down: $should,
            reasons: $reasons
        }'
}

# Generate suggested sub-issues from a large issue
# Usage: suggest_sub_issues <issue_json>
# Returns: JSON array of suggested sub-issue titles
suggest_sub_issues() {
    local issue_json="$1"

    local title
    title=$(echo "$issue_json" | jq -r '.title')
    local body
    body=$(echo "$issue_json" | jq -r '.body // ""')

    local sub_issues=()

    # Extract bullet points as potential sub-issues
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            # Clean up the bullet point
            local clean_line
            clean_line=$(echo "$line" | sed 's/^[*-] //' | sed 's/^[0-9]*\. //')
            if [[ ${#clean_line} -gt 10 ]] && [[ ${#clean_line} -lt 100 ]]; then
                sub_issues+=("$clean_line")
            fi
        fi
    done < <(echo "$body" | grep -E "^[*-] |^[0-9]+\. " || true)

    # If no bullet points found, try to split by sentences/paragraphs
    if [[ ${#sub_issues[@]} -eq 0 ]]; then
        # Extract first few action items from body
        while IFS= read -r line; do
            if [[ -n "$line" ]] && echo "$line" | grep -qiE "\b(add|fix|update|remove|implement|create)\b"; then
                if [[ ${#line} -gt 20 ]] && [[ ${#line} -lt 150 ]]; then
                    sub_issues+=("$line")
                fi
            fi
        done < <(echo "$body" | grep -v "^#" | grep -v "^>" | head -10)
    fi

    # Limit to first 10 suggestions
    if [[ ${#sub_issues[@]} -gt 10 ]]; then
        sub_issues=("${sub_issues[@]:0:10}")
    fi

    # Convert to JSON array
    printf '%s\n' "${sub_issues[@]}" | jq -R . | jq -s '.'
}

# Generate grooming summary for an issue
# Usage: groom_issue <issue_json>
# Returns: Complete grooming analysis as JSON
groom_issue() {
    local issue_json="$1"

    local suggested_labels
    suggested_labels=$(suggest_labels "$issue_json")

    local priority_analysis
    priority_analysis=$(calculate_priority "$issue_json")

    local breakdown_analysis
    breakdown_analysis=$(should_break_down "$issue_json")

    local complexity_analysis
    complexity_analysis=$(analyze_issue_complexity "$issue_json" 2>/dev/null || echo '{}')

    # Combine all analyses
    jq -n \
        --argjson labels "$suggested_labels" \
        --argjson priority "$priority_analysis" \
        --argjson breakdown "$breakdown_analysis" \
        --argjson complexity "$complexity_analysis" \
        '{
            suggested_labels: $labels,
            priority: $priority,
            breakdown: $breakdown,
            complexity: $complexity,
            groomed_at: (now | todate)
        }'
}

# Export functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f suggest_labels calculate_priority should_break_down
    export -f suggest_sub_issues groom_issue
fi
