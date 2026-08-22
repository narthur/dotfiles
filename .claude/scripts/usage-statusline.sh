#!/usr/bin/env bash
# Claude Code statusLine script: prints daily(5h)/weekly(7d) quota AND caches it
# for tmux to read (tmux has no way to fetch quota itself — only this hook gets it).
# ponytail: field names track CC's rate_limits JSON; shows "?" if absent/old version.
in=$(cat)
fmt() {
  jq -r --arg k "$1" '
    .rate_limits[$k].used_percentage as $p
    | if $p == null then "?" else ($p | floor | tostring) + "%" end' <<<"$in"
}
day=$(fmt five_hour)
week=$(fmt seven_day)
line="daily ${day} · weekly ${week}"
printf '%s' "$line" > "$HOME/.claude/usage-cache"
# Machine-readable copy for skills that pace themselves (pilot). Includes resets_at
# when CC provides it. ponytail: verbatim dump, no schema of our own to keep in sync.
jq -c '.rate_limits // {}' <<<"$in" > "$HOME/.claude/usage-cache.json"
# Print nothing: quota is shown in tmux (via ~/.claude/scripts/tmux-ccusage.sh),
# not in Claude Code's own status line. This hook exists only to refresh the cache.
