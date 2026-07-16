#!/usr/bin/env bash
# review-loop context gatherer. Emits one JSON blob with everything the
# orchestrator needs to start a run — workspace type, base branch (fetched),
# learnings, test/lint commands, diff size, fast-path eligibility.
# Replaces the per-step bash round-trips of SKILL Steps 1-3 + 3b-sizing.
# ponytail: one deterministic call instead of six reasoned steps.
set -uo pipefail

workspace=standard
[ "$(git branch --show-current 2>/dev/null)" = "gitbutler/workspace" ] && workspace=gitbutler

# base branch: PR base -> repo default -> origin/HEAD symbolic ref
base_branch=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null || true)
[ -z "$base_branch" ] && base_branch=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
[ -z "$base_branch" ] && base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || true)

[ -n "$base_branch" ] && git fetch origin "$base_branch" >/dev/null 2>&1 || true

learnings=""
lf=".git/info/review-loop-learnings.md"
[ -f "$lf" ] && learnings=$(cat "$lf")

diffstat=""
changed_lines=0
if [ -n "$base_branch" ]; then
  diffstat=$(git diff --stat "origin/$base_branch...HEAD" 2>/dev/null || true)
  changed_lines=$(git diff --numstat "origin/$base_branch...HEAD" 2>/dev/null \
    | awk '{a+=$1; d+=$2} END {print a+d+0}' || echo 0)
fi

BASE_BRANCH="$base_branch" WORKSPACE="$workspace" LEARNINGS="$learnings" \
DIFFSTAT="$diffstat" CHANGED_LINES="$changed_lines" python3 - <<'PY'
import json, os, re, pathlib

def pkg_scripts():
    p = pathlib.Path("package.json")
    if not p.exists():
        return {}
    try:
        return json.loads(p.read_text()).get("scripts", {}) or {}
    except Exception:
        return {}

scripts = pkg_scripts()
test_cmd = lint_cmd = None
lint_fix = False

# test command
if "test" in scripts:
    test_cmd = "npm test"
elif pathlib.Path("pyproject.toml").exists() or pathlib.Path("pytest.ini").exists():
    test_cmd = "pytest"
elif pathlib.Path("Cargo.toml").exists():
    test_cmd = "cargo test"
elif pathlib.Path("Makefile").exists() and re.search(r'^test:', pathlib.Path("Makefile").read_text(), re.M):
    test_cmd = "make test"

# lint command (+ whether it can autofix)
if "lint:fix" in scripts:
    lint_cmd, lint_fix = "npm run lint:fix", True
elif "lint" in scripts:
    lint_cmd = "npm run lint"
    lint_fix = "--fix" in scripts["lint"]
elif pathlib.Path("ruff.toml").exists() or pathlib.Path(".ruff.toml").exists():
    lint_cmd, lint_fix = "ruff check --fix", True
elif list(pathlib.Path(".").glob(".eslintrc*")):
    lint_cmd, lint_fix = "eslint --fix", True
elif pathlib.Path(".rubocop.yml").exists():
    lint_cmd, lint_fix = "rubocop -A", True

changed = int(os.environ.get("CHANGED_LINES") or 0)
print(json.dumps({
    "workspace": os.environ["WORKSPACE"],
    "base_branch": os.environ["BASE_BRANCH"] or None,
    "test_cmd": test_cmd,
    "lint_cmd": lint_cmd,
    "lint_fix": lint_fix,
    "learnings": os.environ.get("LEARNINGS") or None,
    "diff_stat": os.environ.get("DIFFSTAT") or None,
    "changed_lines": changed,
    "fast_path_eligible_by_size": 0 < changed < 30,
}, indent=2))
PY
