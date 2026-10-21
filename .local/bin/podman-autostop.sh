#!/bin/sh
# ponytail: stops the Podman VM when no containers run, so an idle VM stops eating RAM.
# ceiling: "idle" = zero running containers for 2 consecutive checks (~30 min at the 15-min agent schedule).
PODMAN=/opt/homebrew/bin/podman
STATE=/tmp/podman-idle-strikes

# not running -> nothing to do
[ "$("$PODMAN" machine inspect --format '{{.State}}' 2>/dev/null)" = running ] || { rm -f "$STATE"; exit 0; }

# containers running -> leave it alone, reset the strike count
if [ -n "$("$PODMAN" ps -q 2>/dev/null)" ]; then
  rm -f "$STATE"
  exit 0
fi

# idle: require two consecutive idle checks before stopping (avoids yanking a just-started VM)
strikes=$(cat "$STATE" 2>/dev/null || echo 0)
strikes=$((strikes + 1))
if [ "$strikes" -ge 2 ]; then
  rm -f "$STATE"
  "$PODMAN" machine stop
else
  echo "$strikes" > "$STATE"
fi
