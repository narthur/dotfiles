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
#
# Skip it inside the bedtime window (21:30-04:00). Faking not-afk there would feed
# the `abed` do-less goal (bedtime-beemind counts aw-watcher-afk not-afk minutes),
# recording laptop-active time while Claude runs unattended/phone-driven and you're
# off the machine. Daytime tracking, the heartbeat, and caffeinate are unaffected.
hhmm=$((10#$(date +%H%M)))   # 10# so 0930-style leading zeros aren't parsed as octal
in_bedtime=0
{ [ "$hhmm" -ge 2130 ] || [ "$hhmm" -lt 400 ]; } && in_bedtime=1
if [ -x "$CLICLICK" ] && [ "$in_bedtime" -eq 0 ]; then
  "$CLICLICK" kd:cmd ku:cmd >/dev/null 2>&1
fi

# Keepalive heartbeat so the activity event stays continuous through long tools.
"$HOME/.claude/scripts/aw-claude-heartbeat.sh" >/dev/null 2>&1

# Belt-and-suspenders against idle *system* sleep while Claude is working (the
# cliclick tap already keeps the display awake, which normally prevents system
# sleep too). Held in the foreground but for less than the 30s launchd interval, so
# each run finishes before the next is due (no skipped beats) and the assertion
# lapses on its own ~25s after Claude goes idle. System sleep only — display is free
# to dim. No effect on clamshell/lid-closed sleep, and can't wake an asleep Mac.
caffeinate -i -t 25 >/dev/null 2>&1

exit 0
