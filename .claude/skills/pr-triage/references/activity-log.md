# Autonomous-mode activity log

### Activity log

Keep a durable, reviewable trail of everything autonomous mode does. Log to a per-repo file:

```
${XDG_CACHE_HOME:-$HOME/.cache}/pr-triage-worktrees/<owner>-<repo>/triage-activity.log
```

Append one timestamped line per meaningful action — don't overwrite. At the start of a run write a header, then log each action as you take it (not in a batch at the end, so the trail survives an interruption):

```bash
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/pr-triage-worktrees/$(gh repo view --json nameWithOwner -q .nameWithOwner | tr / -)/triage-activity.log"
mkdir -p "$(dirname "$LOG")"
log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"; }

log "=== autonomous run start: $(gh repo view --json nameWithOwner -q .nameWithOwner) ==="
log "PR #780: rebased onto origin/main, resolved 2 conflicts in shared.ts, pushed (abc1234)"
log "PR #780: applied bot feedback (assert issues field), tests 14/14, pushed (def5678)"
log "PR #601: web-audit failing on repo-wide vitest CVE — deferred to user"
log "=== run end: 3 ready to merge, 1 needs input ==="
```

Log at minimum: run start/end, each conflict resolution / CI fix / feedback application (with the pushed commit SHA), each gated item deferred, and each thing deferred to the user with the reason. Tell the user where the log lives in your final report.

