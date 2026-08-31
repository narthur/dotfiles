# The per-repo threat model (Step 2b)

Read this at Step 2b. It defines the file format, the bootstrap brief, and the update brief.

## What this file is for

`~/.claude/skills/review-loop/references/security-review.md` carries Anthropic's security-review
prompt, whose exclusion list and precedents were tuned on production false positives across many
repos. That list is *generic* — it cannot know that grove's `/s/*` routes are deliberately
cookie-less, or that TaskRatchet's `normalizeDepth: 3` is load-bearing PII containment rather than
a tuning knob.

**The threat model is the per-repo override channel for that generic list.** It is the only thing
in this skill that carries repo-specific security context between runs. Everything else about the
security review is Anthropic's, deliberately.

It is **not** an OWASP threat model. No data-flow diagrams, no asset-ID tables, no trust-level
cross-reference matrices. That ceremony exists for human review boards. This file exists to prime
one LLM.

Location: `<git-common-dir>/info/review-loop-threat-model.md`. Resolve with
`git rev-parse --git-common-dir`, **never `--git-dir`** — in a worktree the latter returns
`.git/worktrees/<name>/`, which has no `info/`, and the file silently reads as empty.

## Format

Every claim is **OBSERVED** or **INFERRED**.

- **OBSERVED** — verified by reading the code. Carries a citation: `[path:line @ sha]`,
  `[path:start-end @ sha]`, or `[path @ sha]` for a whole-file claim. The sha is the commit the
  claim was verified at (`git rev-parse --short HEAD`).
- **INFERRED** — a reasonable belief that was not verified. No citation. Consumers treat it as a
  hypothesis to check, not a fact to rely on.

This split is load-bearing. The user is not a security expert and **cannot audit this file**. A
bootstrap agent will happily write "all `/api/v2` routes authenticate at the router level" after a
skim, and that claim would then prime every security review indefinitely. With the split, a wrong
inference costs a redundant check instead of a missed vulnerability. **When in doubt, write
INFERRED** — the cost of under-claiming is one extra check.

Never write an OBSERVED claim you did not verify by reading the cited lines.

```markdown
# Threat model — <repo>
<!-- Maintained by review-loop Step 2b. OBSERVED claims are cited and pinned; INFERRED are not. -->

## Architecture
- OBSERVED: All `/api/v2/*` routes authenticate via Clerk JWT in shared middleware; handlers do
  not re-check. [packages/api/src/hono/app.ts:42 @ a1b2c3d]
- INFERRED: Task text is user-authored, so any path that renders or logs it handles untrusted data.

## Entry points
- OBSERVED: HTTP routes registered in [packages/api/src/hono/routes/index.ts @ a1b2c3d]
- OBSERVED: Cron/queue consumers in [packages/api/src/jobs/ @ a1b2c3d]

## Trust boundaries
- OBSERVED: `/s/*` is a distinct surface — bearer-token authorized, no cookies, no session.
  [src/routes/s.ts:1-40 @ a1b2c3d]

## Sensitive data
- OBSERVED: Stripe customer, payment-method and billing data reach the error path via
  `logger.error({...errorInfo, error})`. [packages/api/src/lib/charge/authorize.ts:88 @ a1b2c3d]

## Not an issue here
<!-- Written by Step 11 when the user dismisses a security finding. Overrides the generic
     exclusion list in either direction. Date every entry. -->
- 2026-08-02: Do not propose CSRF tokens, sign-in, or cookie sessions on `/s/*`. Deliberately
  cookie-less and bearer-token-authorized. [src/routes/s.ts @ abc1234]

## Watch this spot
<!-- Written by Step 12 ("remember X"), or by the review when it surfaces a risk it should not
     fix. These OVERRIDE the generic exclusions — see below. -->
- 2026-08-09: `normalizeDepth` is unset (defaults to 3) and that default is the only thing keeping
  Stripe cardholder data and Postgres "Failing row contains (…)" out of Sentry. Raising it is a PII
  decision, not a tuning knob. [lib/sentryOptions.ts:12 @ def5678]
```

## Overriding the generic exclusions

Anthropic's list is tuned for a false-positive-averse, high-volume setting, and some of it is wrong
for a given repo. The clearest example: precedent 11 says *"Logging non-PII data is not a
vulnerability even if the data may be sensitive"* — which would suppress the Postgres
`Failing row contains (…)` finding, one of the most valuable catches this repo set has produced.

Rule: **a "Watch this spot" entry beats a generic exclusion.** If a finding lands on a watched
location, it is reported even when an exclusion or precedent would otherwise drop it. Conversely a
"Not an issue here" entry beats a generic *inclusion* — that is the grove case.

Both directions are per-repo and evidence-backed. Neither is a licence to relax the exclusions in
general.

## Bootstrap brief (first run only, when the file does not exist)

One agent, `model: sonnet`. **Hard caps: read at most ~30 files, write at most ~60 lines.** The
point is priming, not documentation, and an unbounded "build a threat model of this app" prompt on
a monorepo eats a session.

Answer exactly four questions and stop:

1. **What is the auth mechanism?** Per route family if they differ. Cookie/session, bearer token,
   signed request, none. Where is it enforced — middleware, per handler, edge?
2. **Where is the entry-point surface?** The files where HTTP routes, jobs, queue consumers,
   webhooks, and CLI entry points are registered.
3. **Where are the trust boundaries?** Points where data or control crosses a privilege level —
   client→server, server→DB, first-party→third-party API, authenticated→public surface.
4. **What is the sensitive-data inventory?** What in this system would matter if it leaked, and
   which paths carry it.

Prefer breadth over depth: a cited one-liner per route family beats an exhaustive treatment of one.
Write INFERRED freely; the update pass promotes claims to OBSERVED as it verifies them.

Skip the bootstrap entirely on a repo with no attacker-reachable surface (a static blog, a
personal script collection). Write the file with a single line saying so and why, so the next run
does not retry.

## Update brief (every subsequent run)

Input: `python3 ~/.claude/skills/review-loop/threat-model.py` output plus this cycle's diff.

1. **Re-verify the stale claims.** Each entry in `stale[]` has a cited file that changed since its
   pin. Read the current code. Then either re-pin at `HEAD` (still true), rewrite (changed), or
   delete (no longer true). Do not re-pin without re-reading — a blind re-pin is how a stale claim
   becomes permanent.
2. **Add new surface from the diff.** New route, new job, new external integration, new sensitive
   field, new trust boundary → a new claim.
3. **Demote what you could not verify.** An OBSERVED claim you could not confirm becomes INFERRED
   with its citation dropped. `uncited` in the script output counts OBSERVED claims that are
   already missing citations — fix or demote those.
4. **Leave "Not an issue here" and "Watch this spot" alone** unless the diff directly invalidates
   one. Those are the user's entries, written at Step 11/12.

Keep the file under ~120 lines. Past that, cut the weakest INFERRED claims — a long file dilutes
the priming it exists to provide.
