#!/bin/bash
# Issue Complexity Analyzer
# Analyzes GitHub issues to determine execution feasibility and complexity

set -euo pipefail

# Analyze issue complexity
# Usage: analyze_issue_complexity <issue_json>
# Returns: JSON with complexity score and analysis
analyze_issue_complexity() {
    local issue_json="$1"

    local title
    title=$(echo "$issue_json" | jq -r '.title')
    local body
    body=$(echo "$issue_json" | jq -r '.body // ""')
    local labels
    labels=$(echo "$issue_json" | jq -r '.labels[]?.name // empty' | tr '\n' ',' || echo "")

    # Calculate complexity based on various factors
    local complexity="low"
    local score=0
    local blockers=()
    local reasons=()

    # Check title and body length
    local combined_length=$((${#title} + ${#body}))
    if [[ $combined_length -gt 1000 ]]; then
        score=$((score + 2))
        reasons+=("Long description suggests complex issue")
    fi

    # Check for architectural keywords
    if echo "$title $body" | grep -qiE "(architect|refactor|redesign|migration|database schema|breaking change)"; then
        score=$((score + 3))
        complexity="high"
        reasons+=("Involves architectural changes")
    fi

    # Check for multi-file indicators
    if echo "$body" | grep -qE "multiple files|several files|across.*files"; then
        score=$((score + 2))
        reasons+=("Affects multiple files")
    fi

    # Check for blocked status
    if echo "$labels" | grep -qiE "blocked|on-hold|waiting"; then
        blockers+=("Issue is blocked or on hold")
    fi

    if echo "$title $body" | grep -qiE "blocked by|depends on|waiting for"; then
        blockers+=("Has dependencies")
    fi

    # Check for discussion/design labels
    if echo "$labels" | grep -qiE "discussion|design|help wanted|question"; then
        blockers+=("Requires discussion or design")
    fi

    # Check for unclear requirements
    if echo "$body" | grep -qE "\?$" | head -3 | grep -q "?"; then
        score=$((score + 1))
        reasons+=("Contains questions")
    fi

    if [[ ${#body} -lt 50 ]] && [[ ! "$body" =~ (TODO|FIXME|typo|fix|update) ]]; then
        score=$((score + 2))
        reasons+=("Description too vague")
        blockers+=("Needs clarification")
    fi

    # Check for specific, simple patterns (reduce complexity)
    if echo "$title" | grep -qiE "^(fix|update|add|remove):?\s+(typo|comment|log|test|documentation)"; then
        score=$((score - 2))
        reasons+=("Simple, well-defined change")
    fi

    # Check for TODO-sourced issues (usually simple)
    if echo "$labels" | grep -q "auto-captured"; then
        score=$((score - 1))
        reasons+=("Auto-captured from TODO (usually simple)")
    fi

    # Calculate final complexity
    if [[ $score -le 1 ]]; then
        complexity="low"
    elif [[ $score -le 4 ]]; then
        complexity="medium"
    else
        complexity="high"
    fi

    # Determine if executable
    local executable="true"
    if [[ ${#blockers[@]} -gt 0 ]]; then
        executable="false"
    fi

    # Build result JSON
    local blockers_json
    blockers_json=$(printf '%s\n' "${blockers[@]}" | jq -R . | jq -s '.')
    local reasons_json
    reasons_json=$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s '.')

    jq -n \
        --arg complexity "$complexity" \
        --arg score "$score" \
        --arg executable "$executable" \
        --argjson blockers "$blockers_json" \
        --argjson reasons "$reasons_json" \
        '{
            complexity: $complexity,
            score: ($score | tonumber),
            executable: ($executable == "true"),
            blockers: $blockers,
            reasons: $reasons
        }'
}

# Check if issue meets execution criteria
# Usage: is_issue_executable <issue_json> <project_settings_json>
is_issue_executable() {
    local issue_json="$1"
    local project_settings="$2"

    # Get analysis
    local analysis
    analysis=$(analyze_issue_complexity "$issue_json")

    local executable
    executable=$(echo "$analysis" | jq -r '.executable')
    local complexity
    complexity=$(echo "$analysis" | jq -r '.complexity')

    # Check if blocked
    if [[ "$executable" != "true" ]]; then
        echo "false"
        return 0
    fi

    # Check project's max complexity setting
    local max_complexity
    max_complexity=$(echo "$project_settings" | jq -r '.orchestration.auto_execute_max_complexity // "medium"')

    case "$max_complexity" in
        low)
            if [[ "$complexity" == "low" ]]; then
                echo "true"
            else
                echo "false"
            fi
            ;;
        medium)
            if [[ "$complexity" == "low" ]] || [[ "$complexity" == "medium" ]]; then
                echo "true"
            else
                echo "false"
            fi
            ;;
        high)
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

# Estimate lines of code to change
# Usage: estimate_loc <issue_json>
estimate_loc() {
    local issue_json="$1"

    local title
    title=$(echo "$issue_json" | jq -r '.title')
    local body
    body=$(echo "$issue_json" | jq -r '.body // ""')

    # Simple heuristics
    if echo "$title" | grep -qiE "typo|comment|log"; then
        echo "5"
    elif echo "$title" | grep -qiE "add.*test|update.*test"; then
        echo "50"
    elif echo "$title $body" | grep -qiE "refactor|redesign"; then
        echo "200"
    elif echo "$title $body" | grep -qiE "new feature|implement"; then
        echo "150"
    else
        echo "30"
    fi
}

# Get relevant files for issue
# Usage: get_relevant_files <issue_json> <project_path>
# Returns: Array of file paths mentioned in issue
get_relevant_files() {
    local issue_json="$1"
    local project_path="$2"

    local body
    body=$(echo "$issue_json" | jq -r '.body // ""')

    # Extract file paths from markdown code blocks and mentions
    local files=()

    # Look for file paths in body (e.g., `src/file.ts`)
    while IFS= read -r line; do
        if [[ -n "$line" ]] && [[ -f "${project_path}/${line}" ]]; then
            files+=("$line")
        fi
    done < <(echo "$body" | grep -oE '`[^`]+\.(ts|js|py|rb|go|php|java|rs|swift|kt|c|cpp|h)`' | tr -d '`' || true)

    # Look for File: markers (from our TODO captures)
    while IFS= read -r line; do
        if [[ -n "$line" ]] && [[ -f "${project_path}/${line}" ]]; then
            files+=("$line")
        fi
    done < <(echo "$body" | grep -oE '\*\*File\*\*: `[^`]+`' | sed 's/\*\*File\*\*: `//;s/`//' || true)

    # Output as JSON array
    printf '%s\n' "${files[@]}" | jq -R . | jq -s '.' || echo "[]"
}

# Export functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f analyze_issue_complexity is_issue_executable
    export -f estimate_loc get_relevant_files
fi
