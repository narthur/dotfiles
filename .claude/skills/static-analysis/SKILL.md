---
name: static-analysis
description: Run every applicable static-analysis tool on a repo — detect languages/configs, run the curated CodeRabbit-weighted analyzer set (installed or ephemerally via npx/uvx), and write results to .static-analysis/. Use when asked to run static analysis, lint the whole repo, run all linters/analyzers, do a code-quality/security scan, or check a repo before pushing. Report-only by default; --fix opts into safe autofixers. Subagent-safe (never blocks).
---

# static-analysis

One runner that detects what a repo is written in, picks the right analyzers
(one per concern — no overlap), runs them, and writes machine- + human-readable
results. All detection/dispatch/execution lives in the script; your job is thin.

## Run it

```bash
python3 ~/.claude/skills/static-analysis/static-analysis.py [PATH] [flags]
```

- `PATH` — repo/dir to analyze (default: current directory).
- `--diff` — only files changed vs the base branch (pre-push scope).
- `--staged` — only staged files.
- `--fix` — run safe autofixers (eslint --fix, ruff --fix, rubocop -a, …) first, then report residue.
- `--sql` — include SQLFluff (otherwise on-demand: only runs if the repo has a sqlfluff config).
- `--exit-zero` — always exit 0 (for callers that don't want the gate).

**Exit codes:** `0` clean or only skips · `1` findings present · `2` script error.

## Output (git-ignored, latest overwrites)

```
.static-analysis/
  summary.json   # machine-readable: tools run/skipped, finding counts, exit codes
  report.md      # human-readable, rendered by the script
  raw/<tool>.txt # each tool's raw output
```

## What you do after it runs (thin relay)

1. Relay the one-line result: per-tool finding counts, what was skipped, exit status. Point to `.static-analysis/report.md` for detail.
2. **Do not** re-read every finding and re-analyze — the tools already did that. (Deep triage is review-loop's job, not this skill's.)
3. **Install offer — only if you can actually prompt the user** (you are the main interactive agent, not a headless subagent): if `summary.json` lists skipped-but-installable tools, offer to install them (use each entry's `install_hint`) and re-run. In a subagent, skip this step — just report the skips upward and return `summary.json`.

## Adding a tool

Edit `registry.toml` — one table per tool (fields documented at the top of that
file). Add a count parser in `static-analysis.py` (`COUNTERS`) only if the tool
emits clean JSON; otherwise it falls back to exit-code + line count automatically.

## Scope

Registry covers the languages actually in use here (TS/JS, Ruby/Rails, Python,
Go, CSS/SCSS, Markdown, HTML, YAML/GitHub Actions, SQL, Shell, Docker) plus
all-files secret (gitleaks) and SAST (semgrep) scanning. Overlapping tools are
pruned to one per concern; the JS/TS linter is chosen by the repo's own config
(biome.json → Biome, eslint config → ESLint, else oxlint).

**fallow** (TS/JS dead code, import cycles, duplication, complexity) is
whole-repo only, so it runs only in repos that opted in with a `.fallowrc.json`
/ `fallow.toml` (`npx fallow init`). Its `fix` command deletes "unused" code, so
it is deliberately not wired to `--fix`; run `npx fallow fix` by hand. For
change-scoped output use `npx fallow audit --base <ref>` directly.
