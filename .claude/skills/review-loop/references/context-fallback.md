# Context fallback (workspace detection + Steps 1–3)

`context.sh` (SKILL Step 0) automates all of this and emits it as JSON. This file
is the **fallback** — consult it only if the script errors or returns `null` for
a field you need. Don't run this bash by hand when the JSON already has the answer.

## Detecting Workspace Type

## Step 1: Determine Base Branch

Try these in order; use the first that returns a value:

```bash
# 1. PR base (if a PR exists for this branch)
base_branch=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null)

# 2. Repo default branch via gh
[ -z "$base_branch" ] && base_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)

# 3. origin/HEAD symbolic ref
[ -z "$base_branch" ] && base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
```

If all three fail, ask the user to specify a base branch (e.g. `main` or `master`).

Then fetch the latest from origin so the review compares against current remote state:

```bash
git fetch origin "$base_branch"
```

The scope of the review is everything on the current branch that isn't on `origin/<base_branch>` — i.e. committed changes only. If the user has uncommitted work they want reviewed, tell them to commit it first before re-invoking.

## Step 2: Load Per-Repo Learnings

```bash
learnings_file=".git/info/review-loop-learnings.md"
[ -f "$learnings_file" ] && cat "$learnings_file"
```

If the file exists, hold its contents in mind for the entire session — pass them to every review agent in Step 5. The file has two sections:

- **Dismissed**: findings the user has explicitly said are not worth flagging in this repo
- **Accepted patterns**: types of issues the user has explicitly confirmed matter in this repo

If the file does not exist, that's fine — start with no learnings.

## Step 3: Detect Test & Lint Commands

The broad analyzer set (linters, security, secrets) is handled deterministically by the static-analysis pass (Step 4a) — you don't need to detect per-tool commands for it. What you're detecting here is the **test** command and any **project-specific** lint/format/typecheck script (Prettier, `tsc`, a custom `npm run lint`) that static-analysis doesn't replicate and that runs alongside it.

Search for project-standard test and lint commands. Check (in this order):

1. Root `CLAUDE.md` — look for explicit "test command" / "lint command" instructions
2. `package.json` `scripts` — `test`, `lint` (note if `lint` supports `--fix` or a `lint:fix` script exists)
3. `Makefile` — `test`, `lint` targets
4. Language-specific configs: `pytest.ini` / `pyproject.toml` → `pytest`; `ruff.toml` / `.ruff.toml` → `ruff check --fix`; `.eslintrc*` → `eslint --fix`; `.rubocop.yml` → `rubocop -A`; `Cargo.toml` → `cargo clippy --fix` and `cargo test`
5. CI config (`.github/workflows/*.yml`) as a last-resort hint

Record what you found. If no test command can be detected, warn the user once at the start: "No test command detected — fix-induced regressions won't be caught between cycles." Same for lint.
