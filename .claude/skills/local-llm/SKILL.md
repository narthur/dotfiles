---
name: local-llm
description: "Leverage local Ollama models (qwen2.5-coder) for the current task. Invoke when you want Claude Code to offload cheap, recoverable subtasks — bulk filtering/extraction/classification, or redacting secrets/PII before sending text externally — to a local model instead of doing them in-context."
---

# Local LLM (Ollama)

This skill loads the rules for using the local Ollama models on this Mac. The user invokes it when they want local-model leverage for the current task. Apply the scoping below strictly — the point of the skill is *when* to use these models, not just *how*.

## CRITICAL: only delegate cheap, RECOVERABLE work

The local models here are small (7B/14B) — far weaker than you. Delegating to them is safe ONLY when an error is cheap and self-correcting.

- ✅ **Use for:** bulk filtering, extraction, or classification of low-stakes text; redacting secrets/PII before sending text to an external service; first-pass triage where you or the user verify the result. The local model acts as a **filter/router** that narrows or labels — something recoverable if it's wrong.
- ❌ **Never use to summarize or pre-digest source that you then reason about for correctness.** Putting a weak model upstream of your reasoning produces confident wrong answers that are hard to debug — for code especially, the dropped detail (a flag, an edge case, an off-by-one) is the one that matters. When in doubt, read the content yourself.
- Treat all local-model output as **best-effort, never a guarantee** — especially `redact`, where the small model has been observed to miss PII (e.g. email addresses). Verify anything that matters; never rely on it as a security control.

**Rule of thumb:** delegate work whose errors are cheap and recoverable; never delegate work that becomes the foundation of expensive reasoning.

## Available setup

- **Ollama** running on `http://127.0.0.1:11434` (OpenAI-compatible API).
- **Models pulled:** `qwen2.5-coder:14b` (better quality) and `qwen2.5-coder:7b` (faster, lighter).
- **`llm-local`** (on PATH, `~/bin/llm-local`) — the preferred entry point. Reads input from **stdin**. Modes:
  - `filter <goal>` — return only the input lines/items relevant to the goal, verbatim
  - `extract <what>` — pull out the requested items (TODOs, env vars, URLs, …), one per line
  - `redact` — replace secrets/PII with `[REDACTED]`, echo the rest unchanged (defaults to the 14B for reliability)
  - `classify <categories>` — label each input line with one of the given categories
  - `run <instruction>` — raw escape hatch (same caveats apply)
  - Override the model with `LLM_LOCAL_MODEL` (e.g. `LLM_LOCAL_MODEL=qwen2.5-coder:14b`).
- **Direct access** if a mode doesn't fit: `llm -m qwen2.5-coder:7b "<prompt>"` (piped stdin is prepended) or `ollama run qwen2.5-coder:7b "<prompt>"`.

## Examples

```bash
cat app.log        | llm-local filter "errors related to auth"
cat .env.example   | llm-local extract "the env var names"
pbpaste            | llm-local redact | pbcopy
cat tickets.txt    | llm-local classify "bug, feature, question"
```

## Memory awareness (24GB Mac)

- Models **load on demand and unload after ~5 min idle** (default `keep_alive`); they are not resident otherwise. Pulled-but-unused models cost disk, not RAM.
- Loaded footprint: **7B ≈ 4.8GB, 14B ≈ 9.3GB**. Running both leaves ~14GB resident, which is tight alongside the user's working set — **prefer one model at a time** for a given task.
- Inspect / manage: `ollama ps` (what's currently loaded), `ollama stop <model>` (unload now).

## Commands Reference

| Command | Purpose |
|---|---|
| `llm-local <mode> [instruction]` | Scoped local-model subtask (input via stdin) |
| `llm -m qwen2.5-coder:7b "<prompt>"` | Direct one-off via the `llm` CLI |
| `ollama run <model> "<prompt>"` | Direct one-off via Ollama |
| `ollama ps` | Show models currently loaded in memory |
| `ollama stop <model>` | Unload a model now |

## Rationale

See the Obsidian Fieldnote **"Local LLM Setup on Mac (Apple Silicon)"** for the full reasoning: why the setup exists, the backend/model decisions (Ollama + qwen2.5-coder 14B/7B on a 24GB M5 Air, for offline/fallback use), and why local-model delegation is scoped to recoverable tasks (the *router/filter, not compressor of ground truth* principle). Also note: inside a flat-rate Claude subscription, offloading saves rate-limit budget, not dollars — so don't reach for local models just to "save tokens" on work you'd do better yourself.
