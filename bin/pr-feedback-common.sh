#!/usr/bin/env bash

# pr-feedback-common.sh - Shared functions for PR feedback tools

print_pr_tools_help() {
  local color_reset=$'\033[0m'
  local color_header=$'\033[1;36m'  # Bold Cyan
  local color_cmd=$'\033[1;33m'     # Bold Yellow
  local color_desc=$'\033[90m'      # Gray
  
  cat <<EOF

${color_header}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_reset}
${color_header}PR Feedback Tools${color_reset}
${color_header}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_reset}

${color_cmd}pr-feedback${color_reset} [--json] [--all] [--limit N]
  ${color_desc}List review comments on the current PR${color_reset}
  ${color_desc}--json: Output as JSON${color_reset}
  ${color_desc}--all: Show resolved comments too${color_reset}
  ${color_desc}--limit N: Limit number of results${color_reset}

${color_cmd}pr-comment${color_reset} <thread-id> [comment-text]
  ${color_desc}Reply to a review comment thread${color_reset}
  ${color_desc}Omit comment-text to open \$EDITOR${color_reset}

${color_cmd}resolve-feedback${color_reset} <thread-id> [--unresolve]
  ${color_desc}Mark a review thread as resolved${color_reset}
  ${color_desc}--unresolve: Mark as unresolved instead${color_reset}

${color_header}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_reset}
EOF
}
