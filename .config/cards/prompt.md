# Card generator

You are extracting spaced-repetition cards from one of Nathan's Claude Code sessions. The condensed transcript is at `TRANSCRIPT_PATH`. The card corpus is `CORPUS_DIR`.

Your output is markdown files in the corpus. Write nothing else anywhere.

## What earns a card

A **concept**: something that recurs, spans files, other things depend on, or that a new hire would have to be told. Portable specifics count too — the sort of thing an interviewer asks: OAuth grant types, HTTP status semantics, SQL isolation levels, React hook rules, Go channel semantics, what an index does to a query plan.

A **frozen fact about Nathan's own work that an interviewer would ask him to produce**: a policy constant committed in his code and the reason it has that value, a completed measurement, a dated design decision and what it rejected. He is interviewing, and his own numbers are the thing he loses under pressure while the reasoning stays solid — so these earn cards even though they are not portable. Tag them `codebase:<repo>` alongside `interview`. **Put the as-of date in the answer** (e.g. "as of the 2026-08-30 measurement"), so a card that goes stale reads as dated rather than as current.

## What does not

- Local trivia: file paths, helper or variable names in Nathan's repos, flag spellings, version numbers, error strings.
- **Figures that move**: anything re-fetched from a live endpoint, a running total, a point-in-time balance, a count that climbs. Drilling one to automaticity means he states a stale number confidently, which is worse than not knowing it. A completed historical measurement is not this — that is frozen and does earn a card.
- Anything specific to one bug that is now fixed.
- Facts about his tooling setup that a script or `--help` answers faster than memory.
- Cards whose answer is "it depends" with no crisp content.
- Anything in `REJECTED_EXAMPLES` — those are cards he deleted during review. Do not recreate them or their near-duplicates, and infer the pattern: they show what he considers not worth knowing. The exception is one whose reason starts with `leech:` or `answer too long:` — that card was pulled for how it was written, not for what it was about, so the topic is still fair game if you can compose it better.

Most of what a session touches earns nothing. A session with no durable concepts in it should produce no files, and that is a correct outcome — say so and stop.

## Card style

- Two to four cards per concept, not more.
- Question and answer, one fact each. The question must stand alone: a card read in six months with no context still has to be answerable.
- Prefer "why does X exist", "what breaks without X", "when would you choose X over Y", "what does X protect against" over "what is X".
- Answers: one or two sentences, **280 characters at the hard limit**. No hedging, no lists of five things. Anything longer is carrying more than one fact — split it into two cards. The sync enforces this: an over-long answer is kept out of the deck, or pulled from it if it got in, and sent back to be rewritten.
- Cloze only where the sentence itself carries the meaning. Never cloze a code snippet.
- No cards that quiz the wording of Nathan's own notes.

## Before writing

1. `ls CORPUS_DIR` and read any file whose name matches a concept you are considering. If the concept already has a file, add only genuinely new cards to it and leave existing cards untouched (their IDs carry review history).
2. Pick the next free numeric suffix per concept file for new card IDs. IDs are immutable; never renumber an existing card.

## File format

One file per concept, named `<concept-slug>.md`:

```markdown
---
concept: oauth-pkce
tags: [concept, oauth, interview]
sources:
  - 2026-09-12 taskratchet — MCP OAuth work
updated: 2026-09-17
---

One short paragraph explaining the concept in Nathan's own terms. This is a note he may read later, not card text.

## Cards

- What does PKCE protect against? >> Interception of the authorization code by another app on the device; the attacker cannot exchange it without the verifier. <!-- id: oauth-pkce-01 -->
- Why does a native or CLI client need PKCE instead of a client secret? >> It cannot keep a secret — anyone can read the binary — so possession of the verifier stands in for it. <!-- id: oauth-pkce-02 -->
```

Rules for the format:

- `front >> back` on one line, one card per bullet, ID comment at the end.
- `tags`: always `concept`, plus the domain, plus `interview` when it is plausible interview surface, plus `codebase:<repo>` when the knowledge only applies inside one of his repos.
- `sources`: use the session date from the transcript header (`# Date:`), not today's date. Append, don't replace.
- Set `updated` to today.

## Finally

Print one line per file written: `<file> — N new cards`. If you wrote nothing, print `no cards`.
