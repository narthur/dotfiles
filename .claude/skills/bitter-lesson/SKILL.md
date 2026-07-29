---
name: bitter-lesson
description: >-
  Audit my Claude Code skills for staleness and over-engineering against current model and
  harness capabilities, then propose deletions, simplifications, and fixes. Use when asked to
  run a bitter-lesson pass, audit my skills, find over-engineered or stale scaffolding, check
  what the harness now does natively, or do a periodic scaffolding upgrade.
---

# Bitter-Lesson Audit

You are a scaffolding auditor. Your job is to find where Nathan's personal Claude Code
**skills** have rotted — because the model and harness got smarter while the skills stayed the
same — and propose what to **delete, simplify, fix, or merge**.

The governing principle: scaffolding is a depreciating asset, so the default verdict is
suspicion and the bias is toward removal. But scaffolding that encodes private, non-inferable
knowledge or hard-won correctness is the opposite of rot and must be kept. Read
`references/audit-criteria.md` before judging anything — it defines the verdicts and the
KEEP guardrails (some skills must never be deleted without explicit confirmation).

This skill is the **triage layer above `refine-skill`**: it audits the whole library and
prioritizes; `refine-skill` does the deep rework on a single skill. Don't duplicate that
work here — hand SIMPLIFY/FIX items to `refine-skill`.

## Scope: skill *content*, not config health

`/doctor` (a full setup checkup since Claude Code 2.1.214; `/checkup` is an alias) now owns
two dimensions this audit used to cover:

- **Hooks, `settings.json`, permissions, auth, install health** — it diagnoses *and fixes* these.
- **Checked-in `CLAUDE.md` bloat** — since 2.1.206 it proposes trimming content Claude could
  derive from the codebase.

**Don't re-derive either.** Step 1 asks Nathan to run `/doctor` and folds its output in. This
audit's remaining job — the part nothing native does — is judging **skill content**: whether a
skill is over-engineered, stale against current model capability, duplicated, or should exist
at all.

Hooks and settings still appear in the Step 2 inventory, but as *context* for judging skills
(e.g. a skill that reimplements what a hook already does), not as things to health-check.

## CRITICAL constraints

- **Never delete or rewrite anything without explicit user approval.** Produce the report,
  then act on what they approve.
- **Never touch the protected set** (review-loop, egress-guard hook, documented correctness
  learnings) without the user explicitly confirming that specific item.
- **Vendor plugin bundles are out of scope** — the `render-*` and `cloudflare*` skills are an
  installed plugin set, not Nathan's scaffolding. Don't propose changes to them.
- This is a **read-then-recommend** workflow. The expensive, valuable output is the judgment,
  not the file edits.

## Workflow

### Step 1: Establish the capability baseline

What can the harness/model do *now* that scaffolding might be reimplementing?

1. Get the installed version: `claude --version`.
2. **Ask Nathan to run `/doctor`** and paste or summarize what it flags. You can't invoke it —
   it's a slash command, not a skill. Its findings are the config/hooks/settings/CLAUDE.md
   half of the picture; take them as given and don't re-derive them. Note anything it reports
   that a *skill* is also trying to handle — that's a DELETE lead.
3. Read `references/native-capabilities.md` for the last-known baseline.
4. Fetch the current Claude Code changelog and read entries newer than the last audit:
   `WebFetch https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`
   (also check the last audit's recorded version in the Fieldnotes log, Step 5).
5. **Update `references/native-capabilities.md`** with any new capabilities that could
   obsolete scaffolding. This ledger is the point — keep it current so future audits are fast.
6. Read `~/.claude/skills/create-skill/references/context-engineering.md` — the current rules
   for writing for this model generation, plus the audit checklist. Its guardrail section is
   the authority on what must *not* be simplified away.

### Step 2: Inventory the scaffolding

Run the inventory script and read its output:

```bash
~/.claude/skills/bitter-lesson/inventory-scaffolding
```

It emits, as labeled sections of one-JSON-per-line: installed version; every personal (and
project) skill with description, SKILL.md line count, file count, whether it has scripts, and
last-modified date; all configured hooks; and a settings summary. Use `skill_md_lines` and
`last_modified` as first-pass signals (large + old = prime suspect), but read the actual
SKILL.md before assigning any non-KEEP verdict.

### Step 3: Gather friction signal

Scaffolding that annoys or misfires is a strong audit lead. Pull from:

- **Auto-memory feedback** — read `~/.claude/projects/-Users-narthur/memory/MEMORY.md` and any
  `type: feedback` entries; these often record "X misfires" or "stop doing Y".
- **Fieldnotes** — grep `$OBSIDIAN_VAULT/Fieldnotes` for outage/issue/bug notes that implicate
  a skill or hook.
- **Ask Nathan directly**, once, concisely: which skills feel annoying, fire at the wrong
  time, or that he avoids using? Human friction signal beats inference here.

### Step 4: Triage

For each skill (excluding the out-of-scope vendor bundles), assign a verdict
(DELETE / SIMPLIFY / FIX / MERGE / KEEP) with a one-line rationale and confidence, per
`references/audit-criteria.md`. Lead with the highest-confidence, highest-leverage findings.
Be honest about uncertainty and about any category you sampled rather than fully reviewed.

Hooks and settings are triaged only where a *skill* overlaps them; their health is `/doctor`'s
job (see Scope). Pass through anything `/doctor` flagged that you're not acting on, so the
report is still a complete picture.

### Step 5: Write the report to Fieldnotes (tracks progress across sessions)

Append a dated section to `$OBSIDIAN_VAULT/Fieldnotes/Bitter-Lesson Audit Log.md` (create it
if missing). Record:

- Date and the capability baseline (Claude Code version + notable new features this round).
- A table of findings: skill/hook · verdict · rationale · confidence.
- A short "recommended actions, in order" list.
- What was deferred or not reviewed.

This log is how the next run knows the last baseline and avoids re-litigating settled items.
Also update the parent note `Fieldnotes/AI Infrastructure Upgrades.md` if this audit resolves
or informs item #3 or #7.

### Step 6: Act on approval

Present the report and ask which actions to take. Then:

- **DELETE** — remove the skill directory (and unregister if needed) after confirming it's not
  protected. For dotfiles-tracked skills, mention that `dotfiles-sync` should commit the removal.
- **SIMPLIFY / FIX** — invoke the `refine-skill` skill on each, one at a time.
- **MERGE** — fold per the plan, then refine the survivor.
- Record confirmed deletions/merges in `references/native-capabilities.md`
  ("Superseded-in-this-setup") so they're not re-proposed.

### Step 7: Close out

Summarize what changed. Suggest a cadence: Miessler runs his equivalent every couple of weeks
(he used to run it every couple days). A `/schedule` routine or a periodic reminder is a
reasonable way to keep this from going stale — offer it, don't impose it.

## Tips

- The whole-library scan is parallelizable — for a thorough pass, dispatch `Explore`/`Agent`
  readers across batches of skills and have each return verdicts, rather than reading 100
  SKILL.md files inline.
- Weight recent friction heavily. A skill Nathan complained about last week is a better lead
  than one that's merely long.
- Resist the urge to delete correctness guardrails just because the model "could" do it — that
  reasoning is exactly how hard-won lessons get lost. When in doubt, KEEP and flag for the user.
