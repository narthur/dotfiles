# Context engineering for Claude 5 generation models

Source: [The new rules of context engineering for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models) (Anthropic). Read the article itself when a judgment call here is ambiguous.

The headline datum: Anthropic removed **~80% of Claude Code's own system prompt** for the Claude 5 generation with no measured performance loss. Scaffolding written for weaker models is now mostly overhead. The governing shift is *trust the model's judgment, give it cleaner interfaces, and load context only when it's needed.*

These six rules apply to writing and auditing skills.

## 1. Constrain less, describe the goal more

Rigid prohibitions were a workaround for models that couldn't weigh context. Claude 5 can.

> **Then:** "Never write multi-paragraph docstrings or comment blocks — one short line max."
> **Now:** "Write code that reads like the surrounding code: match its comment density."

Rewrite mechanical rules into the judgment they were approximating. A rule that restates ordinary good taste ("be concise", "don't add unnecessary abstractions", "write clear names") is pure overhead — delete it.

**The exception that matters most.** This rule is about *replacing rules with judgment the model can exercise*. It does **not** license deleting knowledge the model cannot infer:

- Author-specific preferences ("no em dashes", "never assert what Nathan felt")
- Hard-won correctness lessons, especially ones with a recorded incident behind them
- Safety, security, and destructive-action gates
- Private facts: env vars, org policy, which host is live, which API is deprecated

Those are the opposite of rot. Keep them, and keep the `**CRITICAL**` marker on the ones where violation is expensive. Reserve the marker for exactly those — using it on ordinary guidance trains it to be ignored.

## 2. Design better tools instead of writing usage examples

An expressive interface teaches usage for free. A `status` parameter enumerated as `pending | in_progress | completed` needs no paragraph explaining the lifecycle.

For skills, the "tool" is usually a helper script. Prefer:

- Clear flags and enumerated values over prose describing what to pass
- A `--help` that documents the script, rather than SKILL.md restating it
- A script that returns structured output (labeled sections, one JSON object per line) over instructions telling the model how to parse loose text
- Exit codes with documented meanings over "check whether it worked"

If SKILL.md contains three worked examples of calling your own script, the script's interface is the thing to fix.

## 3. Progressive disclosure

Every line of SKILL.md is loaded on every invocation. Every skill *description* is loaded in every session, whether or not the skill fires.

- **SKILL.md** = the spine: what this is, when each step runs, what gates apply, and pointers. Target under ~150 lines; past ~200, something belongs in `references/`.
- **`references/*.md`** = everything needed only once you're at a given step: full catalogs, rubrics, per-option playbooks, output formats, troubleshooting, worked examples.
- Point at references explicitly and imperatively — **"Read `references/foo.md` before X"** — so it actually happens.
- Verification procedures, evaluation rubrics, and long checklists are reference material almost by default.

Moving a gate into a reference is safe only when the step *cannot* be executed without reading that reference. If the model could plausibly act before opening the file, the gate stays inline.

## 4. Say it once

Don't repeat guidance between CLAUDE.md, the skill description, and the skill body. Pick the layer that owns it:

- **System prompt / CLAUDE.md** — product and repo context: gotchas, non-obvious conventions. Keep lightweight. Not a place to duplicate what a skill already says.
- **Skill `description`** — *when to invoke*, nothing else. Not what the skill does internally, not its architecture, not its agent roster. Trigger phrases and boundaries earn their space; mechanics don't. Aim under ~350 characters.
- **SKILL.md body** — how the skill works.
- **Tool/script docs** — put instructions in the tool definition rather than describing the tool from outside it.

## 5. Lean on auto-memory

Stop hand-maintaining what the harness now captures. Modern Claude records relevant memories automatically. Reserve explicit memory files for structured, shared, or long-lived knowledge (here: Fieldnotes) and let auto-memory carry incidental per-user facts.

## 6. Prefer rich references over descriptions of them

High-fidelity artifacts beat prose about the artifact:

- A test suite or reference implementation over a written spec
- An actual HTML mockup over a description of the layout
- A design rubric a verifying agent can apply over "make it look good"
- A real worked example over an abstract template

When a skill needs to convey a standard, ship the artifact that embodies it.

## Quick audit checklist

- [ ] Description says only when to invoke, and is under ~350 chars
- [ ] SKILL.md under ~150 lines; catalogs, rubrics, and playbooks live in `references/`
- [ ] Every reference is pointed at imperatively from the step that needs it
- [ ] No guidance duplicated across CLAUDE.md, description, and body
- [ ] `**CRITICAL**` appears only on non-inferable or expensive-to-violate rules
- [ ] Rules that merely restate good taste have been deleted
- [ ] Non-inferable knowledge (preferences, incidents, private facts, safety gates) is preserved
- [ ] Repeated command sequences are scripts with expressive interfaces, not prose
