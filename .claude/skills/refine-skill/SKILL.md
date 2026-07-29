---
name: refine-skill
description: "Review and improve an existing Claude Code skill. Use when asked to refine a skill, improve a skill, review a skill, or clean up a skill."
---

# Refine Skill

You are a skill reviewer. Your role is to audit an existing skill and propose concrete improvements based on the principles below.

**Read `~/.claude/skills/create-skill/references/context-engineering.md` before auditing.** It holds the current rules for writing for Claude 5 generation models, from [Anthropic's context-engineering guidance](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models), and ends with an audit checklist to run the skill against. Principles 1–5 below predate it and remain correct; 6–8 come from it.

## Principles

1. **SKILL.md is hot-path only.** Every line in SKILL.md is loaded into context on every invocation. Only include information that is useful on the majority of invocations. Move situational knowledge to reference files. Concretely: under ~150 lines; past ~200, something belongs in `references/`.

2. **Scripts over prose for repeatable procedures.** If a workflow step should be done the same way every time, put it in a script. SKILL.md should call the script, not spell out the commands.

3. **Reference files for situational knowledge.** Information that is pertinent to the skill but only needed sometimes belongs in separate files that the LLM can read on demand. Link to them from SKILL.md **imperatively** — "Read `references/<name>.md` before doing X" — so the read actually happens.

4. **Correct over cautious.** If past experience revealed a wrong assumption baked into the skill, fix it. Don't add hedging language — update the guidance to be accurate.

5. **Delete stale content.** If a tip, workaround, or command is no longer needed, remove it. Don't comment it out or add "deprecated" notes.

6. **The description is a routing signal, not a summary.** It loads in every session whether or not the skill fires. It should say only *when to invoke* — trigger phrases and boundaries — never how the skill works internally. Over ~350 characters means it is describing mechanics; cut those.

7. **Replace constraints with judgment, but not knowledge.** Rules written to compensate for weaker models are now overhead: a prohibition that restates ordinary good taste should become the judgment it was approximating, or be deleted. This does **not** extend to what the model cannot infer — author preferences, lessons with a real incident behind them, private facts, and safety or destructive-action gates all stay, and keep their `**CRITICAL**` marker. Deleting those is how hard-won correctness gets lost.

8. **Fix the interface instead of documenting around it.** If SKILL.md needs worked examples to explain the skill's own helper script, the script's flags, enumerated values, structured output, or exit codes are the thing to improve. Put usage in the script's `--help`, not in the hot path.

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
- **Guidance repeated across layers** — the same instruction in CLAUDE.md, the description, and the body. Pick the layer that owns it and delete the rest
- **A description that explains the architecture** — agent rosters, scoring, delegation topology. Move to the body
- **`**CRITICAL**` on ordinary guidance** — inflation trains the marker to be ignored; reserve it for expensive-to-violate, non-inferable rules
- **Scaffolding around a limitation the model no longer has** — subagent fan-out to work around context limits, chunking long inputs, re-reading to compensate for attention. Check before keeping
