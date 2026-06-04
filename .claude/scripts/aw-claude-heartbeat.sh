#!/bin/bash
# Send an ActivityWatch heartbeat describing current Claude Code activity.
#
# Reads ~/.cache/aw-claude-active.json (written by aw-active-ping.sh) and posts a
# heartbeat to a dedicated bucket aw-watcher-claude_<host>. ActivityWatch merges
# consecutive heartbeats with identical {project,file,language} within pulsetime
# into one continuous event, so this yields clean per-project / per-file
# durations. Best-effort, silent, fast — never errors out loud.
set -u

AW_URL="http://localhost:5600"
STATE="$HOME/.cache/aw-claude-active.json"
HOST_CACHE="$HOME/.cache/aw-claude-host"
PULSETIME=180

[ -f "$STATE" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# Resolve the hostname the LIVE afk watcher is using, so our bucket lines up with
# the rest of AW's timeline. AW caches its hostname at launch, which can differ
# from `hostname` (e.g. after a network/DHCP rename), so we read it from the most
# recently updated aw-watcher-afk_* bucket. Cache the resolved value for a day;
# never cache the bare-hostname fallback (it may be wrong once AW is reachable).
host=""
if [ -f "$HOST_CACHE" ]; then
  if [ -n "$(find "$HOST_CACHE" -mmin +1440 2>/dev/null)" ]; then
    rm -f "$HOST_CACHE"
  else
    host=$(cat "$HOST_CACHE" 2>/dev/null)
  fi
fi
if [ -z "$host" ]; then
  afk_host=$(curl -s --max-time 1 "$AW_URL/api/0/buckets/" 2>/dev/null \
    | jq -r 'to_entries
        | map(select(.key | startswith("aw-watcher-afk_")))
        | sort_by(.value.last_updated) | last | .key
        | sub("aw-watcher-afk_"; "")' 2>/dev/null)
  if [ -n "$afk_host" ] && [ "$afk_host" != "null" ]; then
    host="$afk_host"
    printf '%s' "$host" > "$HOST_CACHE" 2>/dev/null
  else
    host=$(hostname)
  fi
fi
[ -z "$host" ] && exit 0

bucket="aw-watcher-claude_${host}"

# Ensure the bucket exists (idempotent; the server returns 304 if it already does).
curl -s --max-time 1 -o /dev/null -X POST "$AW_URL/api/0/buckets/$bucket" \
  -H 'Content-Type: application/json' \
  -d "{\"client\":\"aw-watcher-claude\",\"type\":\"claudecode.activity\",\"hostname\":\"$host\"}" 2>/dev/null

# Only project/file/language go into the event data — keeping it stable is what
# lets heartbeats merge into continuous events. (tool/cwd live in the state file
# for debugging but are intentionally not part of the bucket data.)
data=$(jq -c '{project: (.project // ""), file: (.file // ""), language: (.language // "")}' "$STATE" 2>/dev/null)
[ -z "$data" ] && exit 0

ts=$(date -u +%Y-%m-%dT%H:%M:%S.000000+00:00)
curl -s --max-time 1 -o /dev/null -X POST \
  "$AW_URL/api/0/buckets/$bucket/heartbeat?pulsetime=$PULSETIME" \
  -H 'Content-Type: application/json' \
  -d "{\"timestamp\":\"$ts\",\"duration\":0,\"data\":$data}" 2>/dev/null

exit 0
