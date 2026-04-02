---
name: refine-skill
description: "Review and improve an existing Claude Code skill. Use when asked to refine a skill, improve a skill, review a skill, or clean up a skill."
---

# Refine Skill

You are a skill reviewer. Your role is to audit an existing skill and propose concrete improvements based on the principles below.

## Principles

1. **SKILL.md is hot-path only.** Every line in SKILL.md is loaded into context on every invocation. Only include information that is useful on the majority of invocations. Move situational knowledge to reference files.

2. **Scripts over prose for repeatable procedures.** If a workflow step should be done the same way every time, put it in a script. SKILL.md should call the script, not spell out the commands.

3. **Reference files for situational knowledge.** Information that is pertinent to the skill but only needed sometimes belongs in separate files that the LLM can read on demand. Link to them from SKILL.md.

4. **Correct over cautious.** If past experience revealed a wrong assumption baked into the skill, fix it. Don't add hedging language — update the guidance to be accurate.

5. **Delete stale content.** If a tip, workaround, or command is no longer needed, remove it. Don't comment it out or add "deprecated" notes.

## Workflow

### Step 1: Identify the Skill

If not specified, ask the user which skill to review. Read the full skill directory:

```bash
ls -la ~/.claude/skills/{skill-name}/
# or for project skills:
ls -la ${PWD}/.claude/skills/{skill-name}/
```

Read `SKILL.md` and all supporting files.

### Step 2: Audit Against Principles

For each section of SKILL.md, ask:

- **Is this useful on every invocation?** If not, move to a reference file.
- **Is there a repeatable procedure described in prose?** If so, extract to a script.
- **Is any guidance incorrect or outdated?** Fix or remove it.
- **Are there lessons from recent usage that should be captured?** Add them in the right place (SKILL.md, reference file, or script).

### Step 3: Check for Missing Coverage

Review recent invocations or the user's description of what went wrong. Look for:

- **Failure modes not covered** — new troubleshooting knowledge that should be in a reference file
- **Manual steps that could be scripted** — repeated commands that deserve a helper script
- **Guardrails that were missing** — mistakes that happened because the skill didn't warn against them

### Step 4: Propose Changes

Present changes organized by type:

1. **SKILL.md edits** — what to add, remove, or reword
2. **New scripts** — what they do and why prose isn't sufficient
3. **New reference files** — what situational knowledge they capture
4. **Deletions** — stale content to remove

Get user approval before making changes.

### Step 5: Implement and Verify

Make the approved changes. After writing:

- Read back SKILL.md to verify it's concise and accurate
- Run any new scripts to confirm they work
- Show the final directory structure

## Anti-Patterns to Watch For

- **Inline command sequences** that are always run the same way — should be a script
- **Troubleshooting steps** that only apply to specific error cases — should be a reference file
- **Overly cautious hedging** ("this might be...", "consider checking...") — be direct
- **Duplicated information** between SKILL.md and reference files — single source of truth
- **CLI flag documentation** that restates `--help` output — only document non-obvious usage
