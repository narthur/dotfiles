#!/usr/bin/env bash
# SessionStart hook: in a tmux dev session, hand Claude ownership of the watcher
# panes and the rule that keeps them on its own cwd. Silent everywhere else, so
# non-dev Claude sessions (and this one) never see it.
#
# The full procedure lives here rather than in CLAUDE.md on purpose: injected at
# session start it stays in context all session (covering the mid-session
# worktree case too), without taxing every unrelated Claude session with a
# tmux-specific rule. ponytail: gate first, instruction second.
#
# Docs: Obsidian Fieldnotes → "Tmux Dev Environment & Worktree Automation".

"$HOME/bin/devpanes" --gate 2>/dev/null || exit 0

cat <<'EOF'
[dev-panes] The launcher started this session's watcher panes; YOU keep them on
your cwd. INVARIANT: each pane that carries an @cmd runs that command in YOUR
current working directory.

- Inspect panes with `devpanes`: SELF|<your-cwd>|<your-pane> then, per sibling,
  PANE|<pane_id>|<role>|<cmd>|<cwd>|<current_command>. <cmd> is the stashed @cmd
  (may be empty).
- For each pane with a non-empty <cmd>: ensure it is running <cmd> in YOUR cwd.
  - <cwd> differs from yours, or the pane is idle (a bare shell) -> send C-c,
    then `tmux send-keys -t <pane_id> 'cd <your-cwd> && <cmd>' C-m`.
  - already running <cmd> in your cwd -> leave it alone.
- Panes with an empty <cmd> are yours to leave alone (claude + scratch terminals).
- Do this immediately after you enter or leave a worktree (your cwd just moved),
  and once now in case you started already inside a worktree.
- On ENTERING a worktree, first run `worktree-seed` (no args) — it copies the
  gitignored runtime state watchers need (env files, wrangler local D1 state)
  from the main checkout and installs deps if node_modules is missing. THEN
  relaunch the watcher panes.
- CRITICAL: create worktrees with the EnterWorktree tool (it moves your cwd
  in-place), NOT `git worktree add` + cd. The invariant only holds if your
  harness cwd actually moves into the worktree.
EOF
