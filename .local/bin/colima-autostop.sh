#!/bin/sh
# ponytail: stops the Colima VM when no containers run, so an idle Docker VM stops eating RAM.
# ceiling: "idle" = zero running containers for 2 consecutive checks (~30 min at the 900s agent interval).
#          if you keep colima up for non-container use, raise the threshold or gate on `colima ssh`.
COLIMA=/opt/homebrew/bin/colima
DOCKER=/opt/homebrew/bin/docker
STATE=/tmp/colima-idle-strikes

# not running -> nothing to do
"$COLIMA" status >/dev/null 2>&1 || { rm -f "$STATE"; exit 0; }

# containers running -> leave it alone, reset the strike count
if [ -n "$("$DOCKER" ps -q 2>/dev/null)" ]; then
  rm -f "$STATE"
  exit 0
fi

# idle: require two consecutive idle checks before stopping (avoids yanking a just-started VM)
strikes=$(cat "$STATE" 2>/dev/null || echo 0)
strikes=$((strikes + 1))
if [ "$strikes" -ge 2 ]; then
  rm -f "$STATE"
  "$COLIMA" stop
else
  echo "$strikes" > "$STATE"
fi
