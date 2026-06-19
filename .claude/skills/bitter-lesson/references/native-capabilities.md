# Native Capabilities Ledger

Running list of things **Claude Code (the harness) and Claude (the model) now do natively**,
so the audit can spot scaffolding that has been superseded. This is the institutional memory
that makes each audit faster — **update it every run** from the changelog diff (Step 1).

Format: capability — what it obsoletes — first noted (version/date).

## Harness capabilities (Claude Code)

_Baseline captured at first audit; v2.1.183, 2026-06-18. Confirm/extend from the changelog each run._
_First full audit run 2026-06-19 on v2.1.183 (same version as baseline). Changelog entries below extracted this run._

### New since baseline (extracted from CHANGELOG 2026-06-19, v2.1.139–183)

- **Agent Teams** (v2.1.178) — spawn teammates directly with implicit team support. Plus **nested
  subagents** to 5 levels (v2.1.172) and **Agent View** (v2.1.139, one list of all sessions). →
  obsoletes hand-rolled "spawn background agents in worktrees" orchestration (e.g. `issue-blitz`).
- **Dynamic Workflows** (v2.1.154) — orchestrate tens–hundreds of agents in the background. → same.
- **/goal** (v2.1.139) — set a completion condition; Claude keeps working across turns. → obsoletes
  manual "keep going until done" loop prose.
- **Native /code-review + /simplify** (v2.1.154) — correctness review at chosen effort, cleanup-only
  review. → bears on the review-skill cluster (review-loop stays protected; cross-check overlap).
- **/cd** (v2.1.169), **worktree isolation** "none" setting (v2.1.143), **EnterWorktree** mid-session
  (v2.1.157) — native worktree management. → obsoletes bespoke worktree-juggling scaffolding.
- **/config key=value** + **/config --help** (v2.1.183) — set any setting from the prompt. → bears on
  `update-config`-style scaffolding.
- **Marketplace search UI + Suggested Plugins** (v2.1.154, 2.1.181) — search bar when browsing
  plugins; relevance-pinned suggestions. NOTE: this is a browse/search *UI*, NOT a `/find-skills`
  slash command — `find-skills` is only *partially* superseded.
- **/reload-skills** (v2.1.152), **claude plugin init** (v2.1.157), nested `.claude/skills` loading
  (v2.1.178) — native skill/plugin scaffolding + reload. → bears on `create-skill`.
- **Hook additions**: Stop/SubagentStop can return `additionalContext` to continue the turn (v2.1.152);
  **MessageDisplay** hook transforms/hides displayed assistant text (v2.1.152); **SessionStart** can set
  session title (v2.1.152); hooks can emit desktop notifications/bells/titles (v2.1.141).
- **Tool-parameter permission rules** `Tool(param:value)` (v2.1.178) — finer-grained allow/deny.
- **Auto-mode safety**: destructive git blocked unless asked (v2.1.183); improved exfil classifier
  (v2.1.152); MCP auth-stub tools no longer exposed (v2.1.181). → complements (does NOT replace) the
  egress-guard / sensitive-file guards, which are local deterministic controls.
- **/insights, /usage per-category, /stats** (v2.1.149–181) — native usage/cost analytics per
  skill/agent/plugin/MCP.

- **Skills system** with auto-discovery from `~/.claude/skills` and `./.claude/skills` —
  obsoletes any manual "skill registry" bookkeeping.
- **Agent tool / subagents** with custom agent types (Explore, Plan, general-purpose, etc.)
  and parallel dispatch — obsoletes bespoke fan-out/parallel-search scaffolding.
- **Workflow tool** for deterministic multi-agent orchestration (pipeline/parallel, schemas,
  budgets) — obsoletes hand-rolled multi-stage agent scripts.
- **Plan mode** (EnterPlanMode/ExitPlanMode) — obsoletes manual "first make a plan, then ask
  approval" rituals written into skills.
- **WebSearch / WebFetch** tools — obsolete custom search-API wrappers for general lookups
  (a dedicated search skill only earns its keep if it adds private indexing or a specific
  ranked source).
- **Hooks** (PreToolUse, PostToolUse, UserPromptSubmit, Stop, SessionEnd, …) — the supported
  way to enforce automated behavior; prefer over prose instructions that ask the model to
  "always remember to…".
- **`/loop` and `/schedule`** (recurring + cloud cron agents), **ScheduleWakeup**, background
  tasks (`run_in_background`) — obsolete bespoke polling/scheduling scaffolding.
- **AskUserQuestion** structured prompts — obsolete ad-hoc "present a numbered menu" prose.
- **MCP** servers + `ToolSearch` deferred-tool loading — native integration path for external
  tools; prefer over custom CLI-wrapper skills where an MCP server exists.
- **Memory** (auto-memory files + `MEMORY.md` index) and **Fieldnotes** convention —
  the durable-knowledge stores; skills shouldn't reinvent note persistence.

## Model capabilities (Claude, current generation)

- Strong unprompted ability at: reading stack traces, writing idiomatic code/commits,
  summarizing, classification, following multi-step instructions without a spelled-out script.
  → Skills that *only* encode generic best practice for these are bitter-lesson candidates.
- Reliable structured output / tool-calling → skills don't need to hand-hold JSON formatting.
- Large context windows → aggressive pre-summarization scaffolding is often unnecessary now;
  keep the raw (see Fieldnotes "AI Infrastructure Upgrades" item #4).

## Superseded-in-this-setup (confirmed deletions/merges from past audits)

_Append as the audit confirms them, so we don't re-litigate. Date each entry._

- **`coderabbit-review-loop`** — DELETED 2026-06-19. Self-documented fallback to `review-loop` (the default Claude-driven local review); the CodeRabbit-CLI iterative loop was dead weight. One-shot CodeRabbit needs are met by a manual `@coderabbitai review` or native `/code-review`. Don't re-propose creating it.
