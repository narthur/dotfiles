#!/usr/bin/env bash
# PostToolUse hook for the EnterWorktree tool: seed the freshly-entered worktree
# with the gitignored runtime state + deps it needs (env files, wrangler local
# D1/KV/R2 state, node_modules) via ~/bin/worktree-seed.
#
# Deliberately tmux-INDEPENDENT so it also fires in detached background jobs,
# unlike the SessionStart devpanes-reconcile guidance, which gates on $TMUX and
# no-ops in a background job (where TMUX is unset because the process isn't a
# child of a pane). Synchronous so deps are in place before Claude touches the
# tree — a missing node_modules is what makes husky/lint-staged abort on commit.
#
# worktree-seed is idempotent (never overwrites, only installs when node_modules
# is missing) and no-ops on the main checkout, so double-firing is harmless.
#
# Docs: Obsidian Fieldnotes → "Tmux Dev Environment & Worktree Automation".
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.asdf/shims:$PATH"

input="$(cat)"

[ "$(printf '%s' "$input" | jq -r '.tool_name // empty')" = "EnterWorktree" ] || exit 0

# Absolute worktree path from the tool result ("... worktree at <path> ..."),
# falling back to the cwd the hook was invoked with.
wt="$(printf '%s' "$input" | jq -r '.tool_response // empty' \
  | grep -oE '/[^[:space:]]+/\.claude/worktrees/[^[:space:]]+' | head -n1)"
[ -n "$wt" ] || wt="$(printf '%s' "$input" | jq -r '.cwd // empty')"
[ -n "$wt" ] && [ -d "$wt" ] || exit 0

"$HOME/bin/worktree-seed" "$wt" 2>&1 | sed 's/^/[worktree-seed] /'

# Then move this repo's watcher panes onto the just-entered worktree NOW, so a
# mid-session switch is reflected immediately instead of waiting for the next
# UserPromptSubmit (devpanes-follow.sh still covers switching sessions between
# messages). devpanes --reconcile is git-located and tmux-independent, no-ops
# when there's no dev session / no stamped panes, and only moves panes whose cwd
# actually differs — so firing here as well as on the next message is harmless.
"$HOME/bin/devpanes" --reconcile "$wt" 2>&1 | sed 's/^/[devpanes] /' || true
exit 0
