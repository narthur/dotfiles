# Fieldnotes

There is an Obsidian folder called Fieldnotes at `$OBSIDIAN_VAULT/Fieldnotes` that supplements the auto-memory system. Use it for structured knowledge and project information shared between you and the user.

See the `/fieldnotes` skill for full conventions on what belongs there and how to use it. Always read relevant Fieldnotes before starting work on a project or topic, and update them after completing work.

Maintaining Fieldnotes is proactive and does not require permission. Read, create, and update notes on your own initiative as part of doing the work — don't ask whether to record something or wait to be told. (This covers Fieldnotes upkeep only; it is not blanket authorization for unrelated outward-facing actions.)

# Skill friction log

When a skill misfires — wrong output, missing step, stale instruction, or you had to work around it — append one line to `~/.claude/friction.md`: `YYYY-MM-DD | skill-name | what broke | the fix or workaround`. Create the file if absent. Do this on your own initiative, no permission needed; keep it to one line. Don't edit the skill in place mid-run — the log is reviewed in batches (e.g. via `bitter-lesson`) so fixes are deliberate, not silent drift.
