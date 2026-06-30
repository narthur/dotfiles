#!/usr/bin/env bash
# ports.5s.sh — xbar plugin. Lists listening localhost servers.
# Dev projects show: <dir> - <type> - <port>; everything else: <proc> - <port>.

SELF="$HOME/.config/xbar/plugins/ports.5s.sh"

# Cleanup action (clicked from the dropdown): TERM every listener whose parent has
# exited (reparented to launchd, ppid 1) and whose cwd is under ~/code.
# ponytail: kills the listener pid only; orphaned child procs die on next refresh.
if [ "$1" = "cleanup" ]; then
  killed=0
  for pid in $(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $2}' | sort -u); do
    [ "$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')" = "1" ] || continue
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
    case "$cwd" in "$HOME/code"/*) kill "$pid" 2>/dev/null && killed=$((killed+1));; esac
  done
  osascript -e "display notification \"Killed $killed orphaned ~/code server(s)\" with title \"Ports\"" 2>/dev/null
  exit 0
fi

echo "Ports"
echo "---"

# pid, port (last colon-field of name), process name — one row per pid.
# ponytail: sort -u -k1,1 keeps one port per pid; fine for dev servers, lift if a
# multi-port proc needs all of them shown.
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null \
  | awk 'NR>1 {n=split($9,a,":"); print $2, a[n], $1}' \
  | sort -u -k1,1 | while read -r pid port proc; do
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)

  type=""
  if [ -n "$cwd" ]; then
    if   [ -f "$cwd/astro.config.mjs" ] || [ -f "$cwd/astro.config.ts" ]; then type="astro"
    elif [ -f "$cwd/next.config.js" ]  || [ -f "$cwd/next.config.mjs" ];  then type="next"
    elif [ -f "$cwd/vite.config.ts" ]  || [ -f "$cwd/vite.config.js" ];   then type="vite"
    elif [ -f "$cwd/wrangler.toml" ]   || [ -f "$cwd/wrangler.jsonc" ];   then type="workers"
    elif [ -f "$cwd/svelte.config.js" ]; then type="svelte"
    elif [ -f "$cwd/Cargo.toml" ];       then type="rust"
    elif [ -f "$cwd/go.mod" ];           then type="go"
    elif [ -f "$cwd/manage.py" ];        then type="django"
    elif [ -f "$cwd/package.json" ];     then type="node"
    fi
  fi

  if [ -n "$type" ]; then
    # quoted ~ stays literal; ${cwd/#$HOME/~} would tilde-expand back to $HOME in bash 5.
    case "$cwd" in
      "$HOME"/*) label="~${cwd#$HOME} - $type";;
      *)         label="$cwd - $type";;
    esac
  else
    label="$proc"
  fi
  echo "$label - $port | href=http://localhost:$port"
done

echo "---"
echo "🧹 Clean up orphaned ~/code servers | bash=\"$SELF\" param1=cleanup terminal=false refresh=true"
