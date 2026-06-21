#!/usr/bin/env bash
# Claude Code status line — renders a single line at the bottom of every CC session.
#
# Claude Code pipes a JSON blob about the current session to this script on stdin.
# We print ONE line to stdout; that line becomes the status bar. ANSI colors are OK;
# keep it to a single line (no trailing newline needed, CC handles it).
#
# Inspect the full input shape anytime with:
#   echo '<paste a captured stdin blob>' | jq .
# or temporarily add:  cat > /tmp/cc-statusline-input.json  near the top.

set -euo pipefail

input="$(cat)"

# --- helpers ---------------------------------------------------------------
jqr() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

# ANSI colors (dim/cyan/yellow/green/red). \033 keeps it portable.
DIM=$'\033[2m'; CYAN=$'\033[36m'; YEL=$'\033[33m'; GRN=$'\033[32m'; RED=$'\033[31m'; BLU=$'\033[34m'; RST=$'\033[0m'
SEP=" ${DIM}·${RST} "

# --- core fields -----------------------------------------------------------
model="$(jqr '.model.display_name // empty')"
cwd="$(jqr '.workspace.current_dir // .cwd // empty')"
[ -z "$cwd" ] && cwd="$PWD"
dir_name="$(basename "$cwd")"

# --- git context -----------------------------------------------------------
git_part=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)"
  dirty=""
  if ! git -C "$cwd" diff --quiet 2>/dev/null || ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
    dirty="${YEL}*${RST}"
  fi
  git_part="${GRN}${branch}${RST}${dirty}"
fi

# --- PR url (cached; `gh pr view` is a network call, too slow to run per render)
# Show the cached value immediately; refresh in the background, throttled to
# every 2 min via the cache file's mtime (touch first to avoid a refresh stampede).
pr_part=""
if [ -n "${git_part:-}" ]; then
  pr_cache_dir="${HOME}/.claude/status-cache/pr"
  mkdir -p "$pr_cache_dir" 2>/dev/null || true
  pr_key="$(printf '%s' "${cwd}#${branch}" | shasum | cut -c1-16)"
  pr_cache="${pr_cache_dir}/${pr_key}"
  if [ ! -f "$pr_cache" ] || [ -n "$(find "$pr_cache" -mmin +2 2>/dev/null)" ]; then
    touch "$pr_cache" 2>/dev/null || true
    # Always mv the tmp into place (even on no-PR/empty) so the empty result is
    # cached and throttled, and no .tmp is orphaned when `gh` exits non-zero.
    ( cd "$cwd" 2>/dev/null || exit 0
      gh pr view --json url -q .url 2>/dev/null > "${pr_cache}.tmp"
      mv "${pr_cache}.tmp" "$pr_cache" 2>/dev/null ) >/dev/null 2>&1 &
  fi
  pr_url="$(cat "$pr_cache" 2>/dev/null || true)"
  if [ -n "$pr_url" ]; then
    # Short, clickable label instead of the full URL (which runs off the edge).
    # OSC 8 hyperlink: terminals that support it make "pr #N" clickable; the
    # rest just show the text. (Markdown links don't render in a status line.)
    pr_num="${pr_url##*/}"
    osc8_open=$'\033]8;;'"${pr_url}"$'\033\\'
    osc8_close=$'\033]8;;\033\\'
    pr_part="${BLU}${osc8_open}pr #${pr_num}${osc8_close}${RST}"
  fi
fi

# --- context-window pressure (best-effort; field exists only in some versions)
ctx_part=""
if [ "$(jqr '.exceeds_200k_tokens // false')" = "true" ]; then
  ctx_part="${RED}>200k${RST}"
fi

# ===========================================================================
# CUSTOM METRICS — add your always-visible numbers here.
# Each block should set a colored string and get appended to `parts` below.
# Keep these FAST (statusline runs on every render). Cache slow data to a file
# via a separate cron/hook and just read the cached file here.
#
# Example — show a cached number written elsewhere:
#   custom=""
#   if [ -f ~/.claude/status-cache/beeminder.txt ]; then
#     custom="${CYAN}bm:$(cat ~/.claude/status-cache/beeminder.txt)${RST}"
#   fi
# ===========================================================================
custom=""

# --- assemble --------------------------------------------------------------
parts=()
[ -n "$model" ]    && parts+=("${CYAN}${model}${RST}")
[ -n "$pr_part" ]  && parts+=("$pr_part")
[ -n "$dir_name" ] && parts+=("${dir_name}")
[ -n "$git_part" ] && parts+=("$git_part")
[ -n "$ctx_part" ] && parts+=("$ctx_part")
[ -n "$custom" ]   && parts+=("$custom")

# join with separator
out=""
for p in "${parts[@]}"; do
  [ -n "$out" ] && out="${out}${SEP}"
  out="${out}${p}"
done

printf '%s' "$out"
