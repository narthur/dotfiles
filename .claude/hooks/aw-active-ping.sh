#!/bin/bash
# Claude Code hook (PreToolUse / PostToolUse / UserPromptSubmit): record current
# Claude activity for ActivityWatch.
#
# Writes ~/.cache/aw-claude-active.json, whose contents feed a dedicated AW bucket
# and whose mtime doubles as the "Claude is working" freshness sentinel read by
# aw-active-nudge.sh. Must be fast and must never block the tool: exits 0, no stdout.
set -u

STATE="$HOME/.cache/aw-claude-active.json"
input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$cwd" ] && cwd="$PWD"
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Resolve repo + project name from the working directory.
repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$repo_root" ]; then
  project=$(basename "$repo_root")
else
  project=$(basename "$cwd")
fi

# File path, relative to the repo root when the edit is inside it.
file=""
if [ -n "$fp" ]; then
  if [ -n "$repo_root" ] && [ "${fp#"$repo_root"/}" != "$fp" ]; then
    file="${fp#"$repo_root"/}"
  else
    file=$(basename "$fp")
  fi
fi

# Language from file extension.
language=""
case "$file" in
  *.ts|*.tsx)              language="typescript" ;;
  *.js|*.jsx|*.mjs|*.cjs)  language="javascript" ;;
  *.py)                    language="python" ;;
  *.rb)                    language="ruby" ;;
  *.go)                    language="go" ;;
  *.rs)                    language="rust" ;;
  *.php)                   language="php" ;;
  *.java)                  language="java" ;;
  *.kt|*.kts)              language="kotlin" ;;
  *.swift)                 language="swift" ;;
  *.c|*.h)                 language="c" ;;
  *.cpp|*.cc|*.hpp|*.hh)   language="cpp" ;;
  *.cs)                    language="csharp" ;;
  *.sh|*.bash|*.zsh)       language="shell" ;;
  *.css|*.scss|*.sass)     language="css" ;;
  *.html|*.htm)            language="html" ;;
  *.json)                  language="json" ;;
  *.md|*.markdown)         language="markdown" ;;
  *.yml|*.yaml)            language="yaml" ;;
  *.toml)                  language="toml" ;;
  *.sql)                   language="sql" ;;
  *.vue)                   language="vue" ;;
  *)                       language="" ;;
esac

tmp="${STATE}.tmp.$$"
jq -nc \
  --arg project "$project" \
  --arg file "$file" \
  --arg language "$language" \
  --arg tool "$tool" \
  --arg cwd "$cwd" \
  '{project:$project, file:$file, language:$language, tool:$tool, cwd:$cwd}' \
  > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE"

# Fire an immediate heartbeat without blocking the tool.
( "$HOME/.claude/scripts/aw-claude-heartbeat.sh" >/dev/null 2>&1 & )

exit 0
