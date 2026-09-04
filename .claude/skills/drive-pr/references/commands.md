# Command reference and git operations by workspace type

## Commands Reference

| Command | Purpose |
| --- | --- |
| `gh pr view --json mergeable,mergeStateStatus,baseRefName` | Check conflicts / how far behind the base |
| `gh pr checks` | Check CI status on the pushed commit |
| `gh run rerun <run-id> --failed` | Re-run a genuinely-transient failed check |

**Feedback commands** (retrieve / resolve / dismiss / reply / snooze) live in the **`resolve-feedback`** skill (`~/.claude/skills/resolve-feedback/`), which this skill delegates to in Step 1 — don't call them directly here.


