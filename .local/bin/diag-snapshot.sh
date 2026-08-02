#!/bin/zsh
# Rolling system-forensics snapshot for after-the-fact freeze/crash debugging.
# See Fieldnotes "macOS Freeze - audiomxd Bluetooth Crash Loop 2026-07-13".
# Appends a compact snapshot every INTERVAL; the last snapshot before a freeze
# tells you what was pegging the machine. No notifications.
#
# ponytail: cheap signals (loadavg, top-CPU, mem, recent crash-report count) run
# every tick — they alone fingered audiomxd (Jul 13) and would flag the radio
# crashes early. The expensive unified-log spammer dump only runs when load is
# already high, so steady state stays cheap.
#
# Runs as a self-looping daemon under launchd with KeepAlive=true, so if it is
# ever killed (e.g. by a JetsamEvent under memory pressure) launchd relaunches
# it. The previous RunAtLoad+StartInterval setup had no KeepAlive: once launchd
# stopped relaunching it (around the 2026-07-16 jetsam) it stayed dead and
# missed the 2026-07-18 freeze. Do not go back to StartInterval-without-KeepAlive.

OUT="$HOME/.local/state/diag-snapshot.log"
MAXLINES=8000                 # rolling trim; ~2min interval => keeps ~half a day
LOAD_TRIGGER=4                # above this 1-min load, also dump log spammers
INTERVAL=120                  # seconds between snapshots
CRASH_DIRS=(/Library/Logs/DiagnosticReports "$HOME/Library/Logs/DiagnosticReports")
mkdir -p "$(dirname "$OUT")"

snapshot() {
  local ts up load mem load1
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  up=$(uptime | sed -E 's/.*up //; s/, [0-9]+ users.*//')
  load=$(sysctl -n vm.loadavg | sed -E 's/[{}]//g; s/^ +//; s/ +$//')
  mem=$(memory_pressure 2>/dev/null | grep -i "System-wide memory free percentage" | tr -s ' ')

  {
    echo "=== $ts | up $up | load $load | ${mem:-mem n/a} ==="
    echo "-- top CPU --"
    ps -Aceo pid,pcpu,pmem,comm -r 2>/dev/null | head -7

    # Radio/combo-controller early warning: both freezes were preceded by a
    # burst of crash reports (bluetoothd, CentauriFirmwareEvent). Cheap: count
    # crash files touched in the last ~5 min and name the newest few.
    local recent
    recent=$(find "${CRASH_DIRS[@]}" -maxdepth 1 -type f \( -name '*.ips' -o -name '*.panic' -o -name '*.diag' \) -mmin -5 2>/dev/null)
    if [ -n "$recent" ]; then
      echo "-- RECENT CRASH REPORTS (last 5m): $(print -r -- "$recent" | grep -c .) --"
      print -r -- "$recent" | xargs -n1 basename 2>/dev/null | sort | tail -6
    fi
  } >> "$OUT"

  # load1 is the first value of vm.loadavg (space-separated originally)
  load1=$(sysctl -n vm.loadavg | awk '{print $2}')
  if [ "${load1%.*}" -ge "$LOAD_TRIGGER" ] 2>/dev/null; then
    {
      echo "-- HIGH LOAD: top log-spamming processes, last 2m --"
      # compact style => field 4 is "proc[pid:tid]"; strip [..] to get the
      # process name. (The old code omitted --style and split the wrong column,
      # which is why the Jul 18 dump showed "Default/Activity/Error" garbage
      # instead of airportd.)
      /usr/bin/log show --last 2m --style compact 2>/dev/null \
        | awk '{print $4}' | sed -E 's/\[[0-9]+:[0-9a-f]+\]$//' \
        | sort | uniq -c | sort -rn | head -8
    } >> "$OUT"
  fi

  # rolling trim (cheap; rewrites only when over cap)
  local lines
  lines=$(wc -l < "$OUT")
  if [ "$lines" -gt "$MAXLINES" ]; then
    local tmp
    tmp=$(mktemp)
    tail -n "$MAXLINES" "$OUT" > "$tmp" && mv "$tmp" "$OUT"
  fi
}

while true; do
  snapshot
  sleep "$INTERVAL"
done
