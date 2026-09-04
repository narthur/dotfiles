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

### New since baseline (v2.1.183 → v2.1.219, noted 2026-07-24)

- **`/doctor` is a full setup checkup that diagnoses *and fixes* issues** (v2.1.214; `/checkup`
  is an alias). Obsoletes hand-rolled config/hook/permission health checking.
  → **This audit should delegate the hooks + `settings.json` health dimension to `/doctor`**
  rather than re-deriving it. Run `/doctor` first, then audit what it doesn't cover.
- **`/doctor` proposes trimming checked-in `CLAUDE.md` files** by cutting content Claude could
  derive from the codebase (v2.1.206). Obsoletes the CLAUDE.md-bloat dimension of this audit.
  → Hand CLAUDE.md trimming to `/doctor`. Keep bitter-lesson focused on what it does *not* do:
  skill **content** quality, over-engineering, and staleness against model capability.
- **Startup warning for `Write(path)` / `NotebookEdit(path)` / `Glob(path)` permission rules**
  (v2.1.210) — prefer `Edit(path)` / `Read(path)`. Settings-hygiene now self-reporting.

### New since 2.1.219 → 2.1.258 (noted 2026-09-02)

- **`/review` is now just an alias of `/code-review`** (v2.1.223). `/code-review [level] [pr#|branch|path]`
  reviews the current diff *or* a PR, remembers the last effort level, takes **`--comment`** (posts inline
  findings to a GitHub PR — and, since v2.1.257, GitLab MRs via `glab mr note`) and **`--fix`** (applies
  findings to the working tree). **`/code-review ultra`** runs a deep multi-agent review in the cloud, with
  `--post` to publish the result to the PR. Claude may now start `/code-review` on its own (v2.1.246).
  → This is the biggest supersession pressure on the PR/review skill cluster. `review-loop` stays protected,
  but anything that merely walks a diff and reports findings is now duplicating a native command.
- **`/claude-api prompt-audit`** (v2.1.221) — audits prompts and tool descriptions for patterns written for
  older models. Overlaps the description-hygiene dimension of `refine-skill` / `create-skill`.
- **`/claude-api upgrade`** (v2.1.239) and **`/claude-api cost-optimize`** (v2.1.247).
- **Built-in "Concise" output style** (v2.1.237) — leads with results, skips preamble/narration. Partial
  overlap with `caveman` — which Nathan chose to DELETE on 2026-09-02 on that basis.
- **`SendFeedback` tool** (v2.1.247) — Claude drafts a feedback report for `/feedback`. Adjacent to, but not
  a replacement for, the private `~/.claude/friction.md` log (that one feeds *this* audit, not Anthropic).
- **Cross-session messaging** (v2.1.224): `SendMessage` / `ListAgents` between sessions on the same machine,
  plus `notify_when_idle` (v2.1.236, one-shot idle notice, no polling). → obsoletes bespoke session-coordination
  and polling scaffolding.
- **`--restricted` / `CLAUDE_CODE_RESTRICTED=1`** (v2.1.248) — strips command-running tools and WebFetch.
- **Auto-mode Containment Escape rule** (v2.1.257) — cloud metadata-credential fetches, egress evasion, and
  cross-tenant reach are no longer auto-approved. Plus `permissions.blockReadsOutsideWorkingDirectories`
  (v2.1.257). → *Complements* `egress-guard.sh`; does not replace it (that hook is a local deterministic
  control and stays protected), but the overlap is now real enough to re-check the hook's scope.
- **Auto mode tab in `/permissions`** (v2.1.246) for viewing/editing classifier rules.
- **`/usage` Loops breakdown** (v2.1.243) — per-loop run count/tokens/last-run; **per-session prompt-cache line
  in `/cost`** (v2.1.251). → native observability for `/loop` sprawl.
- **`PreModelSwitch` / `PostModelSwitch` hooks** (v2.1.251); **`DirectoryAdded` hook** (v2.1.219).
- **`promptCacheTtl` / `subagentPromptCacheTtl`** settings (v2.1.243); `experimental.cacheTtl` per agent (v2.1.248).
- **Workflow tool prompt footprint cut** 5.7k → ~1k tokens, script reference moved into the bundled
  `workflow-authoring` skill (v2.1.248).
- **Bundled first-party skills now include**: `design` (multi-artboard visual canvas — UI mockups, wireframes,
  landing pages, posters), `artifact-design`, `artifact-diagramming`, `artifact-capabilities`, `dataviz`,
  `claude-in-chrome`, `security-review`, `simplify`, `code-review`, `run`, `init`, `update-config`,
  `keybindings-help`, `fewer-permission-prompts`, `claude-api`, `workflow-authoring`, `loop`, `schedule`.
  → Check personal skills against this list before keeping any of them.
- **`/doctor` gained**: stale sandbox-mask warning (v2.1.257), server-managed-settings load diagnostics
  (v2.1.248), wildcard-Bash-allow-rule startup warning (v2.1.246).
- **Write tool** no longer requires a prior Read for newer models (v2.1.228).

## Model capabilities (Claude, current generation)

- Strong unprompted ability at: reading stack traces, writing idiomatic code/commits,
  summarizing, classification, following multi-step instructions without a spelled-out script.
  → Skills that *only* encode generic best practice for these are bitter-lesson candidates.
- Reliable structured output / tool-calling → skills don't need to hand-hold JSON formatting.
- Large context windows → aggressive pre-summarization scaffolding is often unnecessary now;
  keep the raw (see Fieldnotes "AI Infrastructure Upgrades" item #4).
- **Claude 5 generation needs materially less instruction** — Anthropic cut ~80% of Claude Code's
  own system prompt with no measured performance loss
  ([context-engineering guidance](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models),
  noted 2026-07-24). → Rigid prohibitions that restate ordinary good taste are now pure overhead,
  as is scaffolding that works around old context limits (subagent fan-out for long inputs,
  chunking, re-reading for attention). The rules and an audit checklist live in
  `~/.claude/skills/create-skill/references/context-engineering.md`; `refine-skill` reads it too.
  **Guardrail:** this does *not* license deleting non-inferable knowledge — author preferences,
  lessons with a real incident behind them, private facts, safety gates.

## Superseded-in-this-setup (confirmed deletions/merges from past audits)

_Append as the audit confirms them, so we don't re-litigate. Date each entry._

- **`caveman`** — DELETED 2026-09-02 (Nathan's explicit call). The built-in "Concise" output style
  (v2.1.237) covers the intent; zero invocations by either route in the preceding six weeks. Don't
  re-propose creating it. The `ponytail` plugin still references pairing with it — that's a vendor
  bundle, left alone.
- **`coderabbit-review-loop`** — DELETED 2026-06-19. Self-documented fallback to `review-loop` (the default Claude-driven local review); the CodeRabbit-CLI iterative loop was dead weight. One-shot CodeRabbit needs are met by a manual `@coderabbitai review` or native `/code-review`. Don't re-propose creating it.
