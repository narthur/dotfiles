#!/bin/bash
input=$(cat)
command=$(echo "$input" | jq -r '.command // empty')

safe_patterns=(
  'apps:info'
  'apps:list'
  'addons:info'
  'addons:list'
  'addons:plans'
  'addons:services'
  'auth:whoami'
  'authorizations:info'
  'authorizations:list'
  'access:list'
  'buildpacks:list'
  'certs:info'
  'certs:list'
  'config:get'
  'config([[:space:]]|$)'
  'container:login'
  'domains:list'
  'domains:info'
  'drains:list'
  'dyno:list'
  'features:info'
  'features:list'
  'git:remote'
  'labs:info'
  'labs:list'
  'local'
  'logs'
  'maintenance([[:space:]]|$)'
  'members:list'
  'notifications'
  'orgs([[:space:]]|$)'
  'orgs:list'
  'pg:info'
  'pg:diagnose'
  'pg:bloat'
  'pg:blocking'
  'pg:cache-hit'
  'pg:calls'
  'pg:credentials:list'
  'pg:index-size'
  'pg:index-usage'
  'pg:links:list'
  'pg:locks'
  'pg:long-running-queries'
  'pg:mandrill'
  'pg:outliers'
  'pg:records-rank'
  'pg:seq-scan'
  'pg:settings'
  'pg:table-indexes-size'
  'pg:table-size'
  'pg:total-index-size'
  'pg:unused-indexes'
  'pg:user-connections'
  'pg:vacuum-stats'
  'pg:wait'
  'pipelines:info'
  'pipelines:list'
  'ps([[:space:]]|$)'
  'ps:list'
  'ps:type'
  'redis:info'
  'redis:list'
  'regions'
  'releases:info'
  'releases([[:space:]]|$)'
  'reviewapps:list'
  'spaces:info'
  'spaces:list'
  'stack([[:space:]]|$)'
  'status'
  'version'
  'webhooks:info'
  'webhooks:list'
  'webhooks:deliveries'
  'help'
  '--help'
  '-h'
)

heroku_invocations=$(echo "$command" | grep -oP 'heroku\s+\S+')

if [[ -z "$heroku_invocations" ]]; then
  echo '{
    "permission": "ask",
    "user_message": "Heroku guard: could not parse heroku subcommand from this command. Review carefully before approving.",
    "agent_message": "A safety hook could not identify the heroku subcommand in this shell command. It may use indirection (variables, eval, xargs, etc.). Wait for the user to approve before proceeding."
  }'
  exit 0
fi

while IFS= read -r invocation; do
  is_safe=false
  for pattern in "${safe_patterns[@]}"; do
    if [[ "$invocation" =~ heroku[[:space:]]+(.*[[:space:]]+)?$pattern ]]; then
      is_safe=true
      break
    fi
  done
  if [[ "$is_safe" == false ]]; then
    echo '{
      "permission": "ask",
      "user_message": "Heroku guard: this command is not on the safe list. Review carefully before approving.",
      "agent_message": "A safety hook flagged this heroku command as potentially destructive. Wait for the user to approve before proceeding."
    }'
    exit 0
  fi
done <<< "$heroku_invocations"

echo '{ "permission": "allow" }'
exit 0
