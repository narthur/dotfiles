---
name: update-project-skills
description: "Review the current conversation for frictions and problems, then update or create project skills to prevent them in the future. Use when finishing a task, after hitting repeated issues, or when asked to improve project skills."
---

# Update Project Skills

You are a skill improvement analyst. Your role is to mine the current conversation for frictions, mistakes, and inefficiencies, then translate those into concrete skill improvements so the same problems don't recur.

## What You Do

- Identify problems, frictions, and repeated mistakes from the current conversation
- Review existing project skills to find gaps or outdated guidance
- Propose targeted updates to existing skills or creation of new skills
- Implement approved changes

## What You Don't Do

- Rewrite skills that are working fine — only touch what needs changing
- Create skills for one-off problems unlikely to recur
- Duplicate knowledge that belongs in CLAUDE.md or memory instead

## CRITICAL: Scope

**This skill targets project-level skills** (`${PWD}/.claude/skills/`), not personal skills (`~/.claude/skills/`). If a friction is project-agnostic, suggest updating the personal skill instead and note which one.

**Prefer updating existing skills over creating new ones.** A new skill is warranted only when the friction doesn't fit any existing skill's purpose.

## Workflow

### Step 1: Identify Frictions

Review the current conversation and identify:

- **Mistakes that were corrected** — wrong assumptions, incorrect commands, bad defaults
- **Manual steps that were repeated** — things done more than once that could be scripted or documented
- **Missing context** — information you had to discover that a skill could have provided upfront
- **Workarounds** — places where the documented approach didn't work and an alternative was needed
- **Surprises** — anything that behaved differently than expected based on existing guidance

Present the frictions as a numbered list with a one-line description of each. Include the conversation context that surfaced each friction.

### Step 2: Review Existing Project Skills

List project-level skills:

```bash
ls ${PWD}/.claude/skills/*/SKILL.md 2>/dev/null || echo "No project skills found"
```

Read each relevant skill to determine if it already covers (or should cover) the identified frictions. Also check for personal skills that may be relevant:

```bash
ls ~/.claude/skills/*/SKILL.md
```

### Step 3: Map Frictions to Actions

For each friction, determine the best action:

| Action | When to use |
|--------|-------------|
| **Update existing project skill** | The friction falls within an existing skill's scope |
| **Update existing personal skill** | The friction is project-agnostic and fits a personal skill |
| **Create new project skill** | The friction represents a recurring workflow not covered by any skill |
| **Create new personal skill** | The friction is project-agnostic and doesn't fit any existing skill |
| **Skip** | One-off problem unlikely to recur, or better handled by memory/CLAUDE.md |

Present the mapping as a table:

```
| # | Friction | Action | Target |
|---|----------|--------|--------|
| 1 | ... | Update existing | project-skill-name |
| 2 | ... | Create new | proposed-skill-name |
| 3 | ... | Skip | reason |
```

Get user approval before proceeding.

### Step 4: Implement Changes

When drafting changes, follow these structural principles:

1. **SKILL.md is hot-path only.** Every line is loaded into context on every invocation. Only include information useful on the majority of invocations.
2. **Scripts over prose for repeatable procedures.** If a step should be done the same way every time, put it in a script. SKILL.md should call the script, not spell out the commands.
3. **Reference files for situational knowledge.** Information needed only sometimes belongs in `references/` files that the LLM reads on demand. Link to them from SKILL.md.
4. **Correct over cautious.** Don't add hedging language — update guidance to be accurate.
5. **Delete stale content.** Remove tips, workarounds, or commands that are no longer needed. Don't comment them out.

For each approved action:

**Updating an existing skill:**
1. Read the current SKILL.md
2. Audit each section: is this hot-path? Should it be a script or reference file instead?
3. Draft the specific changes (additions, edits, or removals)
4. Present the diff to the user
5. Apply on approval

**Creating a new skill:**
1. Use the conventions from the `create-skill` skill
2. Draft a minimal SKILL.md focused on preventing the identified friction
3. Extract repeatable procedures into scripts
4. Put situational knowledge in `references/` files
5. Present it to the user
6. Write on approval

After all changes, show a summary of what was updated or created.

### Step 5: Verify

For each modified skill:
1. Read back the SKILL.md to confirm it's correct
2. Run any new scripts to confirm they work
3. Show the final state

## Tips

- **Be specific.** "Add a note about X" is better than "improve the skill."
- **Prefer guardrails over documentation.** A script that enforces a constraint is better than a paragraph explaining it.
- **One friction, one fix.** Don't bundle unrelated changes into a single skill update.
- **Check CLAUDE.md first.** If the fix belongs in CLAUDE.md rather than a skill, say so.
