# Learnings file format & write rules (SKILL Step 11)

The learnings file is loaded into every future cycle's agent prompts, so its size and quality directly affect downstream cost and signal. Treat it as a curated index, not an append-only log. Do the actual file edits with `learn.py` (SKILL Step 11) — this file is the judgment behind those edits.

## File

`.git/info/review-loop-learnings.md`. `learn.py add` creates it with this structure if it doesn't exist:

```markdown
# Review Loop Learnings

## Dismissed
<!-- Patterns the user has chosen to skip. Skill won't auto-flag matches. -->

## Accepted patterns
<!-- Patterns the user has explicitly confirmed matter here. Skill weights matches higher. -->
```

## Writing rules

**Entry shape** — one line, ~150 chars max. Lead with the date and either the literal token `PATTERN:` (for a broad, reusable rule) or a concrete one-off. PATTERN entries are the goal — they survive over time; one-off entries are pruned first.

**Before adding a new entry, dedup.** Read the file. If a similar entry already exists:

- **Same topic, same direction** (e.g. "don't flag X in this repo" already covers what you'd write) → don't add a duplicate, but **do bump the existing entry's date to today** (`learn.py bump`). This is the freshness signal the Step 2a sweep's 90-day horizon depends on: an entry that keeps matching stays fresh and survives; one that never re-matches ages out and gets evicted. Skipping the bump would let live entries look stale.
- **Same topic, narrower scope** (your new entry is a specific instance of an existing PATTERN) → don't add it. The PATTERN already covers it.
- **Same topic, broader scope** (your new entry generalises 2+ existing entries) → replace the narrower entries with one PATTERN entry. Note the consolidation date.
- **Different topic** → add a new entry.

**Promote on repetition.** If you've added three or more narrow entries that share a theme, replace them with one PATTERN entry that captures the rule. Don't let the file accumulate near-duplicates.

**Cap at ~50 entries.** The primary maintenance mechanism is the **Step 2a staleness sweep** — relevance-based eviction (dead paths, unused one-offs) triggered automatically at ≥40 entries, which normally keeps the file well under the cap. This age-based cap is the **fallback** for the rare case the file still exceeds ~50 (e.g. the sweep couldn't run); `learn.py prune` enforces it, evicting in this order:
1. Oldest non-PATTERN dismissed entries (the specific one-off skips).
2. Oldest non-PATTERN accepted entries.
3. PATTERN entries last, and only if redundant with a newer one.

**If the file passes ~75 entries even after pruning**, that's a signal the repo's review tastes are heterogeneous enough to need topic splits. At that point (not before), split into a `.git/info/review-loop-learnings/` directory with topic files (`comments.md`, `tests.md`, `refactor.md`, …) and concatenate them when loading. Don't pre-split — single file is simpler when the volume is small.

## What to write for each Step 8b outcome

- "Skip" → Dismissed entry: `- <date>: <finding description> (file: <path>, fix declined)`
- "Skip and remember as a dismissal pattern" → Dismissed entry: `- <date>: PATTERN: <user-worded pattern>`
- "Apply fix" → Accepted entry: `- <date>: <finding description> (accepted)`

Auto-applied low-risk 50-79 findings (from Step 8a) do NOT write to learnings — they're tactical and would just be noise.

When in doubt about whether an entry is worth writing, err on the side of NOT writing. The file's value is in being scannable, not exhaustive.
