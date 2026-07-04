#!/usr/bin/env bash
# UserPromptSubmit hook: relocate this repo's tmux dev-session watcher panes onto
# the cwd of the session you just messaged — approximating "the session I'm
# working in now" with "the session that last got a user message".
#
# Runs from ANY session (foreground in-pane OR background/child) because it
# resolves the target tmux session from git, not from $TMUX / pane membership,
# and drives tmux over the default socket. Idempotent: panes only move when the
# active session's cwd actually differs from where they are, so re-messaging the
# same session is a no-op. Registered async so it never delays the turn.
#
# Docs: Obsidian Fieldnotes → "Tmux Dev Environment & Worktree Automation".
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.asdf/shims:$PATH"

# The session cwd is provided in the hook payload; fall back to $PWD.
cwd="$(cat | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
[ -d "$cwd" ] || exit 0

"$HOME/bin/devpanes" --reconcile "$cwd" >/dev/null 2>&1 || true
exit 0
