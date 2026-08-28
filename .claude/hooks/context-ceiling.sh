#!/usr/bin/env bash
# PostToolUse hook: backstop against the ~1M context ceiling on long autonomous runs.
#
# Background: the auto-compact soft threshold (CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60)
# is honored inconsistently — during long uninterrupted runs context can climb
# gradually past 60% to the ~1M hard ceiling before a forced compaction, the most
# expensive way to burn Opus budget.
# See Fieldnotes: "Claude Code Auto-Compact Override Behavior 2026-06-19".
#
# BACKSTOP ONLY. It sits well above the auto-compact threshold so auto-compact
# gets first crack, and fires only when auto-compact demonstrably failed. Halting
# *at* the auto-compact threshold (what this did until 2026-08-27) preempts
# auto-compact 100% of the time and turns every automatic recovery into a manual
# interruption — measured: zero `auto` compactions in the whole install window.
# Hooks cannot trigger /compact themselves; the halt hands control back to you
# (a turn boundary) where you run /compact and resume.

input=$(cat)
t=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$t" ] && [ -f "$t" ] || exit 0

# True main-thread context = usage of the most recent NON-sidechain assistant
# message (input + cache_creation + cache_read). Sidechain (subagent) messages
# carry their own, much smaller usage and would understate the real figure.
ctx=$(grep '"type":"assistant"' "$t" 2>/dev/null \
  | grep -v '"isSidechain":true' \
  | grep -o '"input_tokens":[0-9]*,"cache_creation_input_tokens":[0-9]*,"cache_read_input_tokens":[0-9]*' \
  | tail -1 | awk -F'[:,]' '{print $2+$4+$6}')
ctx=${ctx:-0}
[ "$ctx" -gt 0 ] 2>/dev/null || exit 0

WINDOW=1000000   # 1M Opus variant (opus[1m]); inert on smaller-window models
BACKSTOP_PCT=85  # deliberately above CLAUDE_AUTOCOMPACT_PCT_OVERRIDE (60) — auto-compact owns that

HALT=$((WINDOW*BACKSTOP_PCT/100))
pct=$((ctx*100/WINDOW))

if [ "$ctx" -ge "$HALT" ]; then
  jq -n --arg r "🛑 Context at ${pct}% (${ctx} tokens) — past the ${BACKSTOP_PCT}% backstop, so auto-compact did not fire. Halting; run /compact, then resume." \
    '{continue:false, stopReason:$r}'
fi
exit 0
