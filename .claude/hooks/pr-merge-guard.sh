#!/usr/bin/env bash
# ponytail: catches PR merges and forces a confirm, so "close" can't silently become "merge".
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Match `gh pr merge` or a REST merge (gh api ... pulls/N/merge). Allow everything else.
if [[ "$command" == *"gh pr merge"* ]] || { [[ "$command" == *"gh api"* ]] && [[ "$command" == *"/merge"* ]]; }; then
  # Pull the PR number out of either form; empty means "current branch", which gh resolves itself.
  pr=$(echo "$command" | grep -oE 'pulls/[0-9]+' | head -1 | tr -dc '0-9')
  [[ -z "$pr" ]] && pr=$(echo "$command" | sed -n 's/.*gh pr merge[[:space:]]*\([0-9]\{1,\}\).*/\1/p')
  desc=$(gh pr view $pr --json number,title -q '"#\(.number): \(.title)"' 2>/dev/null)
  [[ -n "$desc" ]] && desc=" ($desc)"

  jq -n --arg desc "$desc" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: ("This MERGES the PR" + $desc + " (not close). If you meant to close it, use `gh pr close`. Confirm you want to merge.")
    }
  }'
  exit 0
fi

# Not a merge: say nothing. Silence = "no opinion, apply the normal permission
# rules". An explicit "allow" here would auto-approve every other gh command.
exit 0
