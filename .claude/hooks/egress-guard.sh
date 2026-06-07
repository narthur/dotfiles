#!/bin/bash
# PreToolUse(Bash) hook: re-inserts a human approval step on any command that
# can send data off this machine, even when Claude Code runs in auto/bypass
# permission mode. This is the control that breaks the "lethal trifecta"
# (private data + untrusted content + outbound channel) on local autonomous runs.
#
# Pairs with ~/bin/egress-guard-check (the detector). This wrapper only maps
# the detector's exit code to a Claude Code permission decision:
#   no egress  -> stay silent (exit 0): normal permission flow continues
#   egress     -> permissionDecision "ask": forces a confirmation prompt
#
# "ask" (not "deny") is intentional: legitimate pushes/uploads still work with
# one keystroke; the goal is a checkpoint, not a wall.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Nothing to inspect -> defer to normal flow.
[[ -z "$command" ]] && exit 0

reason=$(egress-guard-check "$command")
rc=$?

if [[ $rc -eq 0 ]]; then
  # No egress channel detected; say nothing and let normal permissions apply.
  exit 0
fi

jq -n --arg reason "$command can reach the network: $reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("Egress guard — confirm this outbound action.\n" + $reason)
  }
}'
exit 0
