#!/usr/bin/env bash
# SessionStart hook: in a tmux dev session, keep the watcher panes on this
# session's cwd. Silent everywhere else, so non-dev Claude sessions (and this
# one) never see it.
#
# The pane-following is now fully deterministic across three hooks — this one
# (session start, incl. resuming straight into a worktree via `claude --continue`),
# worktree-seed-on-enter.sh (EnterWorktree → immediate reconcile), and
# devpanes-follow.sh (each UserPromptSubmit). So this hook RECONCILES rather than
# asking the model to move panes by hand — no model-compliance dependency, no
# race with the deterministic reconciles. The short note that follows only tells
# Claude the two things automation can't do for it.
#
# Docs: Obsidian Fieldnotes → "Tmux Dev Environment & Worktree Automation".
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.asdf/shims:$PATH"

input="$(cat 2>/dev/null || true)"

"$HOME/bin/devpanes" --gate 2>/dev/null || exit 0

# Prefer the session cwd from the hook payload; fall back to $PWD.
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
"$HOME/bin/devpanes" --reconcile "$cwd" >/dev/null 2>&1 || true

cat <<'EOF'
[dev-panes] Your watcher panes (dev/test) are kept on your cwd automatically —
on session start, on worktree enter, and on every message. You do NOT inspect or
move them by hand. Only two things are yours to get right:
- Create worktrees with the EnterWorktree tool (it moves your cwd in-place), NOT
  `git worktree add` + cd — the follow only works if your harness cwd moves.
- If you LEAVE a worktree mid-session and want the panes moved back immediately,
  run `devpanes --reconcile` (otherwise they catch up on your next message).
EOF
