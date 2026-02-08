#!/bin/bash
# TODO Scanner Library for Orchestration System
# Scans code for TODO/FIXME/HACK comments and extracts context

set -euo pipefail

# Default TODO patterns (can be overridden per-project)
DEFAULT_TODO_PATTERNS="TODO|FIXME|HACK|XXX|BUG|OPTIMIZE"

# Default file extensions to scan
DEFAULT_EXTENSIONS="ts|js|tsx|jsx|py|rb|go|php|java|c|cpp|h|rs|swift|kt"

# Directories to exclude
EXCLUDE_DIRS="node_modules|vendor|dist|build|target|.git|.next|coverage|__pycache__|.venv"

# Scan project for TODOs
# Usage: todo_scan_project <project_path> [pattern] [extensions]
todo_scan_project() {
    local project_path="$1"
    local pattern="${2:-$DEFAULT_TODO_PATTERNS}"
    local extensions="${3:-$DEFAULT_EXTENSIONS}"

    if [[ ! -d "$project_path" ]]; then
        echo "Error: Project path not found: $project_path" >&2
        return 1
    fi

    # Build grep command with exclusions
    # Use grep to find TODO comments, output with filename and line number
    find "$project_path" -type f -regextype posix-extended \
        -regex ".*\.(${extensions})$" \
        ! -path "*/node_modules/*" \
        ! -path "*/vendor/*" \
        ! -path "*/dist/*" \
        ! -path "*/build/*" \
        ! -path "*/target/*" \
        ! -path "*/.git/*" \
        ! -path "*/.next/*" \
        ! -path "*/coverage/*" \
        ! -path "*/__pycache__/*" \
        ! -path "*/.venv/*" \
        -exec grep -nHE "(${pattern})" {} \; 2>/dev/null || true
}

# Parse TODO line into structured data
# Usage: todo_parse_line <grep_output_line>
# Input format: /path/to/file.ts:123:  // TODO: Fix this bug
# Output: JSON with file, line, text, type
todo_parse_line() {
    local line="$1"

    # Extract file path, line number, and content
    if [[ "$line" =~ ^([^:]+):([0-9]+):(.*)$ ]]; then
        local file="${BASH_REMATCH[1]}"
        local line_num="${BASH_REMATCH[2]}"
        local content="${BASH_REMATCH[3]}"

        # Determine TODO type
        local todo_type="TODO"
        if [[ "$content" =~ FIXME ]]; then
            todo_type="FIXME"
        elif [[ "$content" =~ HACK ]]; then
            todo_type="HACK"
        elif [[ "$content" =~ BUG ]]; then
            todo_type="BUG"
        elif [[ "$content" =~ XXX ]]; then
            todo_type="XXX"
        elif [[ "$content" =~ OPTIMIZE ]]; then
            todo_type="OPTIMIZE"
        fi

        # Extract the actual TODO text (remove comment markers and TODO keyword)
        local todo_text
        todo_text=$(echo "$content" | sed -E 's@^\s*[/*#-]+\s*(TODO|FIXME|HACK|XXX|BUG|OPTIMIZE):?\s*@@' | sed 's@\*/$@@g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Truncate if too long to avoid argument length issues
        if [[ ${#todo_text} -gt 500 ]]; then
            todo_text="${todo_text:0:497}..."
        fi

        # Output as JSON (use temp file for large content)
        local temp_content
        temp_content=$(mktemp)
        echo "$content" > "$temp_content"

        local result
        result=$(jq -n \
            --arg file "$file" \
            --arg line "$line_num" \
            --arg text "$todo_text" \
            --arg type "$todo_type" \
            --rawfile content "$temp_content" \
            '{
                file: $file,
                line: ($line | tonumber),
                text: $text,
                type: $type,
                original: $content
            }')
        rm -f "$temp_content"

        echo "$result"
    fi
}

# Get surrounding context for a TODO
# Usage: todo_get_context <file> <line_number> [context_lines]
todo_get_context() {
    local file="$1"
    local line_num="$2"
    local context_lines="${3:-5}"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    # Get context before and after the TODO
    local start=$((line_num - context_lines))
    [[ $start -lt 1 ]] && start=1

    local end=$((line_num + context_lines))

    sed -n "${start},${end}p" "$file"
}

# Try to extract author from git blame
# Usage: todo_get_author <file> <line_number>
todo_get_author() {
    local file="$1"
    local line_num="$2"

    if [[ ! -f "$file" ]]; then
        echo "unknown"
        return 1
    fi

    # Check if file is in a git repo
    if ! git -C "$(dirname "$file")" rev-parse --git-dir >/dev/null 2>&1; then
        echo "unknown"
        return 1
    fi

    # Get author from git blame
    local author
    author=$(git -C "$(dirname "$file")" blame -L "${line_num},${line_num}" --porcelain "$file" 2>/dev/null | grep "^author " | sed 's/^author //' || echo "unknown")
    echo "$author"
}

# Generate issue title from TODO
# Usage: todo_generate_title <todo_type> <todo_text> <file>
todo_generate_title() {
    local todo_type="$1"
    local todo_text="$2"
    local file="$3"

    local filename
    filename=$(basename "$file")

    # Truncate todo_text if too long
    local short_text="$todo_text"
    if [[ ${#short_text} -gt 60 ]]; then
        short_text="${short_text:0:57}..."
    fi

    case "$todo_type" in
        FIXME|BUG)
            echo "Fix: $short_text"
            ;;
        HACK)
            echo "Refactor: $short_text"
            ;;
        OPTIMIZE)
            echo "Optimize: $short_text"
            ;;
        *)
            echo "TODO: $short_text"
            ;;
    esac
}

# Generate issue body from TODO with context
# Usage: todo_generate_body <todo_json> <project_path>
todo_generate_body() {
    local todo_json="$1"
    local project_path="$2"

    local file
    file=$(echo "$todo_json" | jq -r '.file')
    local line
    line=$(echo "$todo_json" | jq -r '.line')
    local text
    text=$(echo "$todo_json" | jq -r '.text')
    local todo_type
    todo_type=$(echo "$todo_json" | jq -r '.type')

    # Get relative path from project root
    local rel_path="${file#$project_path/}"

    # Get context
    local context
    context=$(todo_get_context "$file" "$line" 5)

    # Get author
    local author
    author=$(todo_get_author "$file" "$line")

    # Build body
    cat <<EOF
## Description

$text

## Location

- **File**: \`$rel_path\`
- **Line**: $line
- **Type**: $todo_type
- **Author**: $author

## Code Context

\`\`\`
$context
\`\`\`

---

*Auto-captured from TODO comment by orchestration system*
EOF
}

# Determine labels for TODO type
# Usage: todo_get_labels <todo_type>
todo_get_labels() {
    local todo_type="$1"

    case "$todo_type" in
        FIXME|BUG)
            echo '["bug", "auto-captured"]'
            ;;
        HACK)
            echo '["refactoring", "tech-debt", "auto-captured"]'
            ;;
        OPTIMIZE)
            echo '["enhancement", "performance", "auto-captured"]'
            ;;
        *)
            echo '["enhancement", "auto-captured"]'
            ;;
    esac
}

# Scan project and generate issue data for all TODOs
# Usage: todo_scan_and_generate <project_id> <project_path>
# Output: JSON array of issue data ready for queuing
todo_scan_and_generate() {
    local project_id="$1"
    local project_path="$2"

    # Source state manager to check for already-captured TODOs
    source "${HOME}/.claude/lib/state-manager.sh"

    # Use temp file to collect issues (avoids arg length limits)
    local issues_file
    issues_file=$(mktemp)

    # Scan for TODOs
    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            continue
        fi

        # Parse the TODO
        local todo_json
        todo_json=$(todo_parse_line "$line")

        if [[ -z "$todo_json" ]] || [[ "$todo_json" == "null" ]]; then
            continue
        fi

        local file
        file=$(echo "$todo_json" | jq -r '.file')
        local line_num
        line_num=$(echo "$todo_json" | jq -r '.line')

        # Check if already captured
        if todo_is_captured "$file" "$line_num"; then
            continue
        fi

        local text
        text=$(echo "$todo_json" | jq -r '.text')
        local todo_type
        todo_type=$(echo "$todo_json" | jq -r '.type')

        # Generate title and body
        local title
        title=$(todo_generate_title "$todo_type" "$text" "$file")
        local body
        body=$(todo_generate_body "$todo_json" "$project_path")
        local labels
        labels=$(todo_get_labels "$todo_type")

        # Get relative path for source reference
        local rel_path="${file#$project_path/}"

        # Build issue data (use temp file to avoid arg length limits)
        local issue_data
        local temp_body
        temp_body=$(mktemp)
        echo "$body" > "$temp_body"
        issue_data=$(jq -n \
            --arg title "$title" \
            --rawfile body "$temp_body" \
            --argjson labels "$labels" \
            --arg source "todo-scan" \
            --arg source_file "${rel_path}:${line_num}" \
            '{
                title: $title,
                body: $body,
                labels: $labels,
                source: $source,
                source_file: $source_file
            }')
        rm -f "$temp_body"

        # Write issue to temp file (one per line - ndjson format)
        echo "$issue_data" >> "$issues_file"

    done < <(todo_scan_project "$project_path")

    # Convert ndjson to JSON array
    local issues
    if [[ -s "$issues_file" ]]; then
        issues=$(jq -s '.' "$issues_file")
    else
        issues="[]"
    fi
    rm -f "$issues_file"

    echo "$issues"
}

# Export functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f todo_scan_project todo_parse_line todo_get_context
    export -f todo_get_author todo_generate_title todo_generate_body
    export -f todo_get_labels todo_scan_and_generate
fi
