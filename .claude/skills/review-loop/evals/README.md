# review-loop evals

A recall harness for the review-loop skill. It replays real past review findings
(human + bot) through the review agent that *owns* each finding and measures
whether the agent independently surfaces it. Use it as a regression guard when
editing agent prompts, model pins, or the learnings flow.

Fixtures are per-repo and may contain private code details, so they are **not**
committed here — this directory ships only the harness. Point `--repo` at a local
checkout and `--fixtures` at your own curated set (format below).

## What it measures (and what it doesn't)

- **Recall** on substantive, *accepted-and-fixed* findings — the core signal.
  A drop here after a skill edit means an agent got worse.
- **Blind spots** — findings no current agent truly owns. Reported separately: a
  miss is a prompt-for-a-new-lens signal, not a regression.
- **Dismissed** findings (author replied "won't fix, because…"). v1 only records
  whether the agent *surfaced* them. Surfacing is fine; the real requirement is
  that they route to the ASK bucket, not auto-fix, and ideally get suppressed by
  the learnings Dismissed list. That routing/suppression axis is **not yet
  measured** — see "Not yet built".

It does **not** measure precision (the agents' false-positive rate on top of the
gold set). Recall-against-history alone will happily reward a noisier reviewer;
pair conclusions with a precision check before acting on them.

## Fidelity

Each finding is replayed at its **review-time commit** in a throwaway `git
worktree`, so the agent sees the code the reviewer saw — not the already-fixed
tip. `base_sha`/`review_sha` are frozen in the fixture (the merge-base and the
commit the comment was left on).

**Scope = the fixture file's diff, plus the worktree.** The agent gets the diff
for the file the finding lives in, and — sitting in a checkout at review state —
can open sibling files itself for context. We deliberately do **not** feed the
whole-PR diff per fixture: measured, it *tanked* recall, because whole-PR diffs
drag in generated/lock files that swamp the signal, and per-fixture it conflates
recall with how the agent *prioritises* among many findings on a big PR. The
focused diff is a cleaner, lower-variance probe.

**Recall is noisy at n=1.** The deep agents run on a non-deterministic model; a
borderline finding flips hit/miss run to run. Use `--repeat N` for a stable
per-fixture hit-rate before trusting a number or calling a regression — a single
run can't tell a real drop from variance.

## Usage

```bash
# recall + blind-spot buckets
python3 replay.py --repo ~/code/yourrepo --fixtures /path/to/fixtures.jsonl

# STABLE baseline: 3 runs per fixture, production tier for the deep agents
python3 replay.py --repo ~/code/yourrepo --repeat 3 --agent-model opus

# include the dismissed fixtures too
python3 replay.py --repo ~/code/yourrepo --include-optional

# one fixture, focused iteration
python3 replay.py --repo ~/code/yourrepo --only <fixture-id> --agent-model opus

python3 replay.py --selftest      # parsing self-check, no API calls
```

Requires the `claude` CLI on PATH and a local checkout of the source repo. Runs
serially; ~2 `claude` calls per fixture per repeat. Default models are `sonnet`
for cost — bump `--agent-model` to `opus` to match how the skill actually runs
the deep agents (#2 bugs, #5 security, #7 structural).

Every run writes `last-run.jsonl` (each agent's findings + the judge verdict) next
to the fixtures — read it to see *what* an agent found, not just hit/miss. It's a
run artifact and is gitignored.

## Fixture format (JSONL, one JSON object per line)

| field | meaning |
|-------|---------|
| `id` | stable slug |
| `pr`, `url` | provenance — the PR and the exact review comment |
| `file`, `line` | where the finding lives |
| `base_sha`, `review_sha` | frozen replay range (merge-base … review commit) |
| `agent` | which review-loop agent owns it: `2-bugs`, `5-security`, `7-structural` |
| `category` | correctness / security / data-integrity / performance / contract / maintainability |
| `severity` | the reviewer's severity tag (major/minor/trivial) |
| `resolution` | `accepted-fixed` or `dismissed` (from the author's reply) |
| `expect` | `surface` (should catch) or `optional` (dismissed) |
| `blind_spot` | true → no agent truly owns it; a miss is diagnostic |
| `gold` | the independent claim the agent must produce |
| `notes` | rationale, esp. why a dismissed finding was declined |

## Curating fixtures

Pull candidates with `gh api repos/<owner>/<repo>/pulls/<n>/comments` — filter to
substantive findings (drop nits/style), read the author's reply to label
`resolution`, and freeze the SHAs with `git merge-base <review_sha> <default-branch>`.
Keep it small and hand-checked; 10–20 good fixtures beat hundreds of raw comments.

## Not yet built (add when the manual signal proves useful)

- Auto-pull candidate findings from the GitHub API.
- A **precision** pass (classify each agent's *extra* findings as real/noise).
- Measuring dismissed-finding **routing** (ask vs auto-fix) and **learnings
  suppression**, not just whether they were surfaced.
- CI gating / parallel execution.
