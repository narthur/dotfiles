#!/usr/bin/env bash

# snooze-feedback.sh - Snooze a PR feedback thread for a duration
# Usage: snooze-feedback.sh <thread-id> <duration>
#   duration: e.g. 1h, 4h, 1d, 3d, 1w
#
# The thread will be hidden from pr-feedback.sh / but-feedback.sh output until:
#   - The duration expires, OR
#   - A new comment (not authored by you) is added to the thread

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SOURCE_DIR/pr-feedback-common.sh"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <id> <duration>" >&2
  echo "  id: thread ID or comment ID (from pr-feedback.sh output)" >&2
  echo "  duration: e.g. 1h, 4h, 1d, 3d, 1w" >&2
  exit 1
fi

ID="$1"
DURATION="$2"

snooze_thread "$ID" "$DURATION"
