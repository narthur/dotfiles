# Learnings staleness sweep (SKILL Step 2a)

The learnings file is re-shipped to every review agent on every cycle, so its size is a direct, recurring token cost — and left alone it only grows and goes stale (entries for code that's since been deleted, one-offs no one has hit in months). Age-based pruning (Step 11) doesn't fix this: it evicts *old* entries, not *irrelevant* ones. This sweep evicts by **relevance** and runs automatically when the file gets big enough to be worth it.

**Trigger:** run this sweep only when Step 0's `learnings_compaction_due` is `true` (the file has ≥40 entries — below that, the cost isn't worth a subagent). It runs **once, at load time**, before the review agents, so the entire run uses the slimmed file. Skip it entirely otherwise.

**How:** spawn **one** compaction subagent (`model: sonnet` — bounded editing task). Give it the learnings file contents, `today` (from Step 0), and the repo's tracked file list (`git ls-files`). Instruct it to rewrite the file, evicting in this order and reporting counts:

1. **Dead-path eviction** — drop any non-PATTERN entry that cites `(file: <path>)` where `<path>` is not in `git ls-files`. The code it was about is gone; the note is dead weight. (PATTERN entries are path-agnostic rules — never dead-path-evict them.)
2. **Stale one-off eviction** — drop non-PATTERN entries whose date is more than **90 days** before `today`. A one-off that hasn't been re-confirmed in a quarter (active entries get their date bumped when they actually match — see Step 11) has aged out of relevance. PATTERN entries are exempt; they're the durable rules that justify the file's existence.
3. **Dedup + promote** — apply Step 11's dedup and "promote 3+ near-duplicates into one PATTERN" rules across the whole file, not just against the newest entry.

Then it rewrites the file (same two-section structure) and returns a one-line summary: `dropped N (D dead-path, S stale), promoted P, now E entries`. Surface that line in the final report (Step 14). If the sweep can't run (subagent unavailable), fall back to Step 11's age-based cap — don't block the review.
