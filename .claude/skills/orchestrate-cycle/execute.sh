#!/bin/bash
# orchestrate-cycle skill executor
# Runs the complete orchestration workflow

set -euo pipefail

# Main execution
main() {
    local max_execute=3

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max|--max-execute)
                max_execute="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Run the orchestration cycle script
    "${HOME}/.claude/scripts/orchestration-cycle.sh" "$max_execute"
}

# Run with arguments
main "$@"
