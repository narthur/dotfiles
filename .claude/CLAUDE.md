# Fieldnotes

There is an Obsidian folder called Fieldnotes at `$OBSIDIAN_VAULT/Fieldnotes` (inside the main Obsidian vault; `$OBSIDIAN_VAULT` is an env var, falling back to `~/vaults/Main` if unset) that supplements the auto-memory system. Use it for structured knowledge and project information.

Fieldnotes is read and edited directly by the user, in contrast to auto-memory (`~/.claude/projects/.../memory/`), which is agent-only. Treat Fieldnotes as a shared workspace; treat auto-memory as your private notes.

## What belongs in Fieldnotes

- **Project information** — goals, scope, constraints, current status, stakeholders, open questions, decisions and their rationale, for projects the user is working on.
- **Structured knowledge** — notes that build up understanding of a domain, system, codebase, or workflow over time; things the user might want to revisit, share, or hand to a teammate.
- **Anything the user might want to read or modify themselves** that doesn't fit in code, docs, or git.

## What does not belong in Fieldnotes

- Ephemeral task state or scratch work for the current conversation — use tasks/plans.
- Personal preferences, feedback rules, durable facts about the user — those go in auto-memory.
- Information already authoritative elsewhere (codebase, git history, GitHub, Linear, etc.) — link to it instead of duplicating.

## How to use it

Do all of the following proactively, without waiting to be asked:

- **No prescribed structure.** Organize however the content suggests; let conventions emerge. Read what's already there before adding new files, and prefer extending existing notes over creating parallel ones.
- **Read first.** When starting work on a project or topic, check Fieldnotes for relevant notes before doing anything else.
- **Create when missing.** If there is no Fieldnote for a project or topic you're working on, create one.
- **Update as you learn.** When something changes — a constraint, a decision, a deadline, new context — update the relevant note rather than letting it go stale.
- **Update after completing work.** At the end of a task, review relevant Fieldnotes and bring them up to date with what changed.
- **Write for a human reader.** Use clear prose and Markdown that renders well in Obsidian. Avoid agent-only shorthand.
