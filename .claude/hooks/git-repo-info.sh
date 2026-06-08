#!/usr/bin/env bash
# Stop hook: as a systemMessage, show (when in a git repo) owner/repo,
# branch, and the associated PR URL.

# JSONL debug log; one object per invocation. Cross-reference entries with
# Claude Code history via session_id / transcript_path.
LOG_DIR="${HOME}/.claude/hooks/logs"
LOG_FILE="${LOG_DIR}/git-repo-info.jsonl"

# Capture stdin (the Stop hook payload) for the debug log.
payload=$(cat)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty')
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty')
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Git context (silent when not in a repo).
repo=""; branch=""; pr=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git branch --show-current 2>/dev/null)
  remote=$(git remote get-url origin 2>/dev/null)
  repo=$(printf '%s' "$remote" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')
  if command -v gh >/dev/null 2>&1; then
    pr=$(gh pr view --json url -q .url 2>/dev/null)
  fi
fi

# Append a structured debug record (best-effort; never blocks output).
mkdir -p "$LOG_DIR" 2>/dev/null && \
jq -nc \
  --arg ts "$started_at" \
  --arg session_id "$session_id" \
  --arg transcript "$transcript" \
  --arg cwd "$cwd" \
  --arg repo "$repo" --arg branch "$branch" --arg pr "$pr" \
  '{ts: $ts, session_id: $session_id, transcript: $transcript, cwd: $cwd,
    repo: $repo, branch: $branch, pr: $pr}' \
  >> "$LOG_FILE" 2>/dev/null

jq -n --arg repo "$repo" --arg branch "$branch" --arg pr "$pr" '
  [ (if $repo   == "" then empty else "Repo: "    + $repo   end),
    (if $branch == "" then empty else "Branch: "  + $branch end),
    (if $pr     == "" then empty else "PR: "      + $pr     end) ]
  | select(length > 0)
  | {systemMessage: ("\n\n" + join("\n\n"))}'
