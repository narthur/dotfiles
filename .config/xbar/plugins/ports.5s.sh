#!/usr/bin/env bash
# ports.5s.sh — xbar plugin. Lists listening localhost servers.
# Dev projects show: <dir> - <type> - <port>; everything else: <proc> - <port>.

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
    label="${cwd/#$HOME/~} - $type"
  else
    label="$proc"
  fi
  echo "$label - $port | href=http://localhost:$port"
done
