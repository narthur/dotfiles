#!/usr/bin/env bash

# dismiss-comment.sh - Mark a generic PR comment as addressed (local tracking)
# Usage:
#   dismiss-comment.sh <comment-id> [--undismiss]

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/pr-feedback-common.sh"

UNDISMISS=false
COMMENT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --undismiss|-u) UNDISMISS=true; shift;;
    -h|--help)
      cat <<EOF
Usage: $0 <comment-id> [options]

Marks a generic PR comment as addressed (tracked locally).
Unlike review threads, generic PR comments cannot be "resolved" on GitHub,
so this command tracks dismissal in local state.

Arguments:
  <comment-id>           The comment node ID (from pr-feedback.sh output)

Options:
  --undismiss|-u         Undo dismissal
  -h, --help             Show this help

Examples:
  $0 IC_kwDOABCDEF4ABCDEFG
  $0 IC_kwDOABCDEF4ABCDEFG --undismiss
EOF
      exit 0
      ;;
    *)
      if [[ -z "$COMMENT_ID" ]]; then
        COMMENT_ID="$1"
      else
        echo "Error: Unknown argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$COMMENT_ID" ]]; then
  echo "Error: Comment ID is required." >&2
  echo "Run 'pr-feedback.sh' to see available comment IDs." >&2
  exit 1
fi

if [[ "$UNDISMISS" == true ]]; then
  undismiss_comment_state "$COMMENT_ID"
  echo "✓ Undismissed comment: $COMMENT_ID"
else
  dismiss_comment_state "$COMMENT_ID"
fi
