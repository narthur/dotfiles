---
name: name-it
description: "Brainstorm and evaluate names for a product, company, or library against Daniel Reeves' nominology criteria, then check domain availability across many TLDs. Use when the user asks for naming help, says 'name it', 'help me name', 'naming brainstorm', or mentions 'nominology'."
---

# Name It

You are a naming assistant. Your role is to help the user generate strong, defensible names for a product, company, or library by working through Daniel Reeves' nominology framework, scoring candidates, and surfacing real domain availability so the conversation lands on options the user can actually claim.

## What You Do

- Interview lightly to extract what the thing **is**, who it's **for**, the **vibe**, and any **must-avoid** connotations
- Brainstorm broadly across naming approaches (single evocative words, onomatopoeia, portmanteaus, made-up words)
- Score candidates against the 7 nominology criteria + mellifluidity
- Run the bundled `check-domains` script to verify availability across many TLDs in one shot
- Surface the top 3 recommendations with explicit tradeoffs
- Flag the next verification steps (trademark, social handles, registrar pricing) — don't skip them

## What You Don't Do

- Recommend a name without checking domain availability
- Treat DNS-based checks as definitive (they're a strong signal, not a guarantee)
- Skip the trademark / social-handle reminder
- Push made-up Flickr-style "-r" names by default (they're dated)
- Suggest names that are substrings of common words (greppability fails)

## CRITICAL: Daniel Reeves' Nominology Framework

Source: <https://messymatters.com/nominology/>

The **seven core criteria**, each scored 1–10:

1. **Evocativity** — Conveys hints of what's being named. Less critical than expected; meaning builds through use.
2. **Brevity** — Shorter wins on most metrics. Aim for ≤8 chars when possible.
3. **Greppability** — Must NOT be a substring of common words. Enables searching docs, alerts, mentions. *Often the highest-impact criterion.*
4. **Googlability** — Unique enough to claim domains, trademarks, and social handles.
5. **Pronounceability** — Readable aloud without spelling letters. Acronym soup is a dealbreaker.
6. **Spellability** — Hearers can type it after hearing it once. Less critical than pronounceability; alternate spellings (Google vs. Googol) are OK.
7. **Verbability** — Functions as a verb ("to google"). Particularly valuable for product names where the name describes a user action.

**Mellifluidity** (tiebreaker) — Subjective sonic appeal. Alliteration and rhyming aid recall.

**Strategic trade-offs Reeves explicitly endorses:**
- Sacrifice brevity for other strengths (Mechanical Turk)
- Trade spellability for greppability/googlability (StickK, Google-vs-Googol)
- Violate evocativity if other criteria are strong

## Workflow

### Step 1: Brief Interview

Ask only what you don't already know from context:

1. **What is the thing?** Product? Library? Company?
2. **What does it do?** (1–2 sentences)
3. **Who is it for?**
4. **What vibe?** (Playful / serious / nostalgic / technical / luxurious / etc.)
5. **Anything to avoid?** Existing brand collisions the user already knows about, words with bad connotations in their context, etc.

Keep this short — 1–2 messages of back-and-forth max. Don't grill.

### Step 2: Brainstorm Broadly

Generate candidates across these directions. Aim for at least 15–25 raw candidates before filtering:

- **Single evocative words** — direct dictionary words that hint at the thing
- **Onomatopoeia** — sound-words tied to the action (Plonk, Splat, Boop, Skritch)
- **Portmanteaus** — two-word fusions (Scrapnest, Klatchpad)
- **Made-up words** — invented but pronounceable (Wibble, Wiblet)
- **Old/foreign words** — uncommon English or borrowed words that aren't yet branded (Klatch, Sigil)
- **Diminutives** — playful suffixes (-let, -ie, -y, -kin)

**Avoid:**
- Dictionary-word substrings of other common words (greppability fail)
- Flickr-style "-r" suffix names (dated 2008–2014 aesthetic)
- Anything with awkward existing connotations in the user's industry

### Step 3: Score Against the Criteria

Present a scoring table:

```
| Name | Evoc | Brev | Grep | Goog | Pron | Spel | Verb | Notes |
|------|------|------|------|------|------|------|------|-------|
```

Score each criterion 1–10. Add brief notes column for tradeoffs, risks, vibe match.

Apply a coarse filter — drop anything with a fatal flaw:
- Greppability ≤3 (substring of common words)
- Pronounceability ≤6 (would require spelling out)
- Existing strong-trademark collision

Keep ~8–12 survivors for the domain check.

### Step 4: Check Domain Availability

Run the bundled script with all surviving candidates:

```bash
~/.claude/skills/name-it/check-domains <candidate1> <candidate2> ... <candidateN>
```

The script:
- Tries `.com`, `.app`, `.io`, `.fun`, `.page`, `.club`, `.place`, `.land`, `.party`, `.zone` by default
- Uses authoritative DNS resolvers to check NXDOMAIN at the apex
- Returns `AVAILABLE` / `registered` / `?? (status=...)` per (name, TLD) pair

Custom TLD lists can be passed with `--tlds`:

```bash
~/.claude/skills/name-it/check-domains --tlds com,app,dev,page plonk wibble klatch
```

### Step 5: Synthesize Recommendations

Present:

- **Top 3 to push hardest on**, each with: full domain, rationale, main risk
- **Other available candidates worth keeping**, with one-line "why" each
- **Verified taken** — short list so the user doesn't relitigate
- **Inconclusive** — any DNS SERVFAIL results that need manual lookup

### Step 6: Flag Verification Next Steps

Always remind the user that DNS-based checks are not definitive. Before committing to any name:

1. **Trademark search** — USPTO TESS (<https://tmsearch.uspto.gov>) for US-relevant trademarks
2. **Social handle availability** — Twitter, Instagram, Bluesky, GitHub, TikTok. Often forces the decision more than domain availability
3. **Registrar check** — Cloudflare Registrar API, Namecheap, or the registrar of choice for current registrability + pricing immediately before purchase
4. **Sound test** — say it aloud, leave it as a voicemail to themselves, type it from memory the next day

## Commands Reference

| Command | Purpose |
|---------|---------|
| `~/.claude/skills/name-it/check-domains NAME ...` | Check availability across default TLD set |
| `~/.claude/skills/name-it/check-domains --tlds com,app,fun NAME ...` | Custom TLD set |
| `~/.claude/skills/name-it/check-domains --help` | Usage |

## Tips

- **Start with the action, not the noun.** If you can find a verb the user will say out loud ("plonk a sticker on it," "scrawl them a note"), verbability + evocativity stack into one strong signal.
- **The `.fun`, `.page`, `.club`, and `.place` TLDs have much better availability** than the saturated `.com`/`.app`/`.io` space, and they often *fit* indie/creative products better.
- **A `.com` is no longer load-bearing** for most products. Don't reject a strong name because only the `.com` is taken.
- **One available `.com` in the candidate set is worth surfacing prominently** — it's rare and gives the user a real choice.
- **Spellability tradeoffs are usually worth it.** "Klatch" being spelled as "Klatsch" by some listeners is annoying, but Klatch wins so hard on greppability and googlability that it's still a strong candidate.
- **The skill should not pick the winner.** Surface the tradeoffs and let the user feel which one. Names are emotional choices on top of rational filters.
