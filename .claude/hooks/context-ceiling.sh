#!/usr/bin/env bash
# PostToolUse hook: enforce the auto-compact threshold during long autonomous runs.
#
# Background: the auto-compact soft threshold (CLAUDE_AUTOCOMPACT_PCT_OVERRIDE)
# is not reliably enforced mid-run — context can climb to the ~1M hard ceiling
# before a forced compaction, the most expensive way to burn Opus budget.
# See Fieldnotes: "Claude Code Auto-Compact Override Behavior 2026-06-19".
#
# This hook reads the live transcript after each tool call, computes the true
# current context size (the most recent assistant message's usage), and HALTS
# the loop immediately (continue:false) the moment context reaches the SAME
# percentage you configured in settings.json — no grace period, no warning.
# Hooks cannot trigger /compact themselves; the halt hands control back to you
# (a turn boundary) where you run /compact and resume.

input=$(cat)
t=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$t" ] && [ -f "$t" ] || exit 0

# True current context = usage of the most recent assistant message
# (input + cache_creation + cache_read input tokens).
ctx=$(grep '"type":"assistant"' "$t" 2>/dev/null \
  | grep -o '"input_tokens":[0-9]*,"cache_creation_input_tokens":[0-9]*,"cache_read_input_tokens":[0-9]*' \
  | tail -1 | awk -F'[:,]' '{print $2+$4+$6}')
ctx=${ctx:-0}
[ "$ctx" -gt 0 ] 2>/dev/null || exit 0

WINDOW=1000000  # 1M Opus variant (opus[1m])

# Threshold = the auto-compact percentage you set in settings.json, so this hook
# enforces the same number. Fall back to the env var, then to 60.
SETTINGS="$HOME/.claude/settings.json"
pct_thresh=$(jq -r '.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE // empty' "$SETTINGS" 2>/dev/null)
[ -n "$pct_thresh" ] || pct_thresh="${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-60}"
case "$pct_thresh" in *[!0-9]*|'') pct_thresh=60 ;; esac

HALT=$((WINDOW*pct_thresh/100))
pct=$((ctx*100/WINDOW))

if [ "$ctx" -ge "$HALT" ]; then
  jq -n --arg r "🛑 Context at ${pct}% (${ctx} tokens) — at/over your ${pct_thresh}% auto-compact threshold. Halting; run /compact, then resume." \
    '{continue:false, stopReason:$r}'
fi
exit 0
