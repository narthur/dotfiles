#!/bin/bash
input=$(cat)
command=$(echo "$input" | jq -r '.command // empty')

heroku-guard-check "$command"
rc=$?

if [[ $rc -eq 0 ]]; then
  echo '{ "permission": "allow" }'
elif [[ $rc -eq 2 ]]; then
  echo '{
    "permission": "ask",
    "user_message": "Heroku guard: could not parse heroku subcommand from this command. Review carefully before approving.",
    "agent_message": "A safety hook could not identify the heroku subcommand in this shell command. It may use indirection (variables, eval, xargs, etc.). Wait for the user to approve before proceeding."
  }'
else
  echo '{
    "permission": "ask",
    "user_message": "Heroku guard: this command is not on the safe list. Review carefully before approving.",
    "agent_message": "A safety hook flagged this heroku command as potentially destructive. Wait for the user to approve before proceeding."
  }'
fi
