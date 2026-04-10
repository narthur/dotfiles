#!/bin/bash
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

heroku-guard-check "$command"
rc=$?

if [[ $rc -eq 0 ]]; then
  exit 0
elif [[ $rc -eq 2 ]]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Heroku guard: could not parse heroku subcommand. Command may use indirection (variables, eval, xargs, etc.)."
    }
  }'
else
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Heroku guard: this command is not on the safe list."
    }
  }'
fi
