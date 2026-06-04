#!/bin/bash
# launchd job (every 30s): keep this Mac counted as active in ActivityWatch while
# Claude Code is working — including when driven remotely from the phone app,
# which produces no local keyboard/mouse input.
#
# If Claude was active within the last $FRESH seconds (per the sentinel written by
# aw-active-ping.sh), inject one harmless synthetic keypress so the real
# aw-watcher-afk registers not-afk, and send a keepalive activity heartbeat to
# bridge long single tool calls. When Claude goes idle the sentinel goes stale,
# nudging stops, and the Mac falls back to AFK ~180s later (aw-watcher-afk's
# default timeout). Worst-case "active" tail after work ends is ~FRESH+180s.
set -u

STATE="$HOME/.cache/aw-claude-active.json"
FRESH=150                         # seconds since last Claude activity to still count as working
CLICLICK="/opt/homebrew/bin/cliclick"

[ -f "$STATE" ] || exit 0

mtime=$(stat -f %m "$STATE" 2>/dev/null) || exit 0
now=$(date +%s)
age=$(( now - mtime ))
[ "$age" -gt "$FRESH" ] && exit 0

# Synthetic input: a lone Command tap. Resets the HID idle timer aw-watcher-afk
# reads, but is a no-op in virtually every app. Requires Accessibility permission
# (System Settings > Privacy & Security > Accessibility); silently no-ops without it.
if [ -x "$CLICLICK" ]; then
  "$CLICLICK" kd:cmd ku:cmd >/dev/null 2>&1
fi

# Keepalive heartbeat so the activity event stays continuous through long tools.
"$HOME/.claude/scripts/aw-claude-heartbeat.sh" >/dev/null 2>&1

exit 0
