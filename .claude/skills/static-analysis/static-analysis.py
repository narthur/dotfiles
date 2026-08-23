#!/usr/bin/env python3
"""One static-analysis runner to rule them all.

Detects languages + configs in a repo, maps them to a curated registry of
analyzers, runs the applicable ones (installed or ephemerally via
npx/uvx/etc.), and writes .static-analysis/{summary.json,report.md,raw/}.

Pure stdlib. See registry.toml for the tool set and SKILL.md for the contract.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REGISTRY = HERE / "registry.toml"
OUTDIR = ".static-analysis"
STYLE_EXTS = {"css", "scss", "sass", "less"}
MD_EXTS = {"md", "markdown"}
SKIP_DIRS = {".git", "node_modules", "vendor", "dist", "build", ".next",
             ".venv", "venv", "__pycache__", ".mypy_cache", ".ruff_cache",
             "coverage", ".static-analysis"}


# --------------------------------------------------------------------------- #
# repo inspection
# --------------------------------------------------------------------------- #
def run(cmd, cwd=None, timeout=600):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                          timeout=timeout)


def is_git(root: Path) -> bool:
    return (root / ".git").exists() or subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"],
        capture_output=True).returncode == 0


def git_ignored(root: Path, paths: list[str]) -> set[str]:
    """Subset of paths that .gitignore excludes — deliberately outside VCS
    (local env files, exports, build output), so never report-worthy."""
    if not paths or not is_git(root):
        return set()
    p = subprocess.run(["git", "-C", str(root), "check-ignore", "--stdin"],
                       input="\n".join(paths), capture_output=True, text=True)
    return set(p.stdout.splitlines())


def list_files(root: Path) -> list[str]:
    """Repo-relative file paths, respecting .gitignore when possible."""
    if is_git(root):
        tracked = run(["git", "-C", str(root), "ls-files"]).stdout.splitlines()
        others = run(["git", "-C", str(root), "ls-files", "--others",
                      "--exclude-standard"]).stdout.splitlines()
        return [f for f in tracked + others if f]
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for f in filenames:
            out.append(str(Path(dirpath, f).relative_to(root)))
    return out


def changed_files(root: Path, staged: bool) -> list[str]:
    if not is_git(root):
        return []
    if staged:
        return [f for f in run(["git", "-C", str(root), "diff",
                                "--name-only", "--cached"]).stdout.splitlines() if f]
    base = detect_base(root)
    files = set()
    if base:
        files.update(run(["git", "-C", str(root), "diff", "--name-only",
                          f"{base}...HEAD"]).stdout.splitlines())
    files.update(run(["git", "-C", str(root), "diff", "--name-only"]).stdout.splitlines())
    files.update(run(["git", "-C", str(root), "ls-files", "--others",
                      "--exclude-standard"]).stdout.splitlines())
    return [f for f in files if f]


def detect_base(root: Path):
    ref = run(["git", "-C", str(root), "symbolic-ref", "refs/remotes/origin/HEAD"]).stdout.strip()
    if ref:
        return ref.replace("refs/remotes/", "")
    for b in ("origin/main", "origin/master", "main", "master"):
        if run(["git", "-C", str(root), "rev-parse", "--verify", b]).returncode == 0:
            return b
    return None


def ext_of(path: str) -> str:
    return Path(path).suffix.lstrip(".").lower()


# --------------------------------------------------------------------------- #
# runner resolution
# --------------------------------------------------------------------------- #
def resolve_runner(runners: list[str]) -> list[str] | None:
    """First runner spec whose base command exists -> argv prefix."""
    for spec in runners:
        kind, _, payload = spec.partition(":")
        if kind == "path":
            payload = os.path.expanduser(payload)
            if shutil.which(payload):
                return [payload]
        if kind == "npx" and shutil.which("npx"):
            return ["npx", "--yes", payload]
        if kind == "bunx" and shutil.which("bunx"):
            return ["bunx", payload]
        if kind == "uvx" and shutil.which("uvx"):
            return ["uvx", payload]
        if kind == "pipx" and shutil.which("pipx"):
            return ["pipx", "run", payload]
        if kind == "go" and shutil.which("go"):
            return ["go", "run", payload]
    return None


# --------------------------------------------------------------------------- #
# tool selection
# --------------------------------------------------------------------------- #
def basename_matches(files: list[str], patterns: list[str]) -> bool:
    import fnmatch
    bases = {Path(f).name for f in files}
    parts = {p for f in files for p in Path(f).parts}  # dir names too (.github)
    for pat in patterns:
        if pat in parts:
            return True
        if any(fnmatch.fnmatch(b, pat) for b in bases):
            return True
    return False


def select_tools(reg: dict, files: list[str], want_sql: bool) -> list[str]:
    exts = {ext_of(f) for f in files}
    gemfile = next((f for f in files if Path(f).name == "Gemfile"), None)
    has_rails = False
    if gemfile:
        try:
            has_rails = "rails" in Path(gemfile).read_text(errors="ignore").lower()
        except OSError:
            pass

    applicable = []
    for name, t in reg.items():
        t_exts = set(t.get("exts", []))
        ext_hit = bool(t_exts & exts) or "*" in t_exts
        cfg_hit = basename_matches(files, t.get("configs", []))
        if not (ext_hit or cfg_hit):
            continue
        if t.get("needs") == "rails" and not has_rails:
            continue
        if t.get("needs_config") and not cfg_hit:
            continue
        if t.get("ondemand") and not (cfg_hit or want_sql):
            continue
        applicable.append(name)

    # overlap groups: keep one winner
    groups: dict[str, list[str]] = {}
    solo = []
    for name in applicable:
        g = reg[name].get("group")
        if g:
            groups.setdefault(g, []).append(name)
        else:
            solo.append(name)

    winners = list(solo)
    for g, members in groups.items():
        configured = [m for m in members if basename_matches(files, reg[m].get("configs", []))]
        pool = configured or [m for m in members if reg[m].get("default")]
        if not pool:
            continue
        winners.append(max(pool, key=lambda m: reg[m].get("priority", 0)))
    return winners


# --------------------------------------------------------------------------- #
# target expansion
# --------------------------------------------------------------------------- #
def expand_target(t: dict, root: Path, files: list[str], scoped: list[str] | None) -> list[str]:
    """Return the list of path args to substitute for {target}."""
    kind = t.get("target", "dir")
    if kind == "none":
        return []
    if kind == "dir":
        if scoped is not None:
            return scoped or []
        return ["."]
    pool = scoped if scoped is not None else files
    if kind == "files":
        te = set(t.get("exts", []))
        return [f for f in pool if ext_of(f) in te]
    if kind == "styleglob":
        return [f for f in pool if ext_of(f) in STYLE_EXTS]
    if kind == "mdglob":
        return [f for f in pool if ext_of(f) in MD_EXTS]
    if kind == "dockerfiles":
        return [f for f in pool if Path(f).name.startswith("Dockerfile")]
    return ["."]


# --------------------------------------------------------------------------- #
# count parsers  (key -> (n_findings, [finding strings]))
# --------------------------------------------------------------------------- #
def _load(text):
    try:
        return json.loads(text)
    except (json.JSONDecodeError, ValueError):
        return None


def c_eslint(o, e):
    d = _load(o) or []
    fnd = [f"{r['filePath']}:{m.get('line','?')} {m.get('ruleId','')} {m.get('message','')}"
           for r in d for m in r.get("messages", [])]
    return len(fnd), fnd


def c_ruff(o, e):
    d = _load(o) or []
    fnd = [f"{r.get('filename')}:{r.get('location',{}).get('row','?')} "
           f"{r.get('code','')} {r.get('message','')}" for r in d]
    return len(fnd), fnd


def c_rubocop(o, e):
    d = _load(o) or {}
    fnd = [f"{fl.get('path')}:{of.get('location',{}).get('line','?')} "
           f"{of.get('cop_name','')} {of.get('message','')}"
           for fl in d.get("files", []) for of in fl.get("offenses", [])]
    return len(fnd), fnd


def c_stylelint(o, e):
    d = _load(o) or []
    fnd = [f"{r.get('source')}:{w.get('line','?')} {w.get('rule','')} {w.get('text','')}"
           for r in d for w in r.get("warnings", [])]
    return len(fnd), fnd


def c_biome(o, e):
    d = _load(o)
    if isinstance(d, dict):
        diags = d.get("diagnostics", [])
        fnd = [f"{x.get('location',{}).get('path',{}).get('file','?')} "
               f"{x.get('category','')} {x.get('description','')}" for x in diags]
        return len(fnd), fnd
    return _fallback(o, e)


def c_oxlint(o, e):
    d = _load(o)
    if isinstance(d, dict):
        diags = d.get("diagnostics", [])
        fnd = [f"{x.get('filename','?')} {x.get('code','')} {x.get('message','')}" for x in diags]
        return len(fnd), fnd
    return _fallback(o, e)


def c_semgrep(o, e):
    d = _load(o) or {}
    res = d.get("results", [])
    fnd = [f"{r.get('path')}:{r.get('start',{}).get('line','?')} "
           f"{r.get('check_id','')}" for r in res]
    return len(fnd), fnd


def c_golangci(o, e):
    d = _load(o) or {}
    iss = d.get("Issues") or []
    fnd = [f"{i.get('Pos',{}).get('Filename')}:{i.get('Pos',{}).get('Line','?')} "
           f"{i.get('FromLinter','')} {i.get('Text','')}" for i in iss]
    return len(fnd), fnd


def c_govulncheck(o, e):
    # streaming JSON objects; count distinct vuln OSV ids
    ids = set()
    for line in o.splitlines():
        obj = _load(line)
        if isinstance(obj, dict) and "finding" in obj:
            osv = obj["finding"].get("osv")
            if osv:
                ids.add(osv)
    return len(ids), sorted(ids)


def c_zizmor(o, e):
    d = _load(o)
    if isinstance(d, list):
        return len(d), [x.get("ident", "finding") for x in d]
    return _fallback(o, e)


def c_sqlfluff(o, e):
    d = _load(o) or []
    fnd = [f"{r.get('filepath')}:{v.get('line_no','?')} {v.get('code','')} {v.get('description','')}"
           for r in d for v in r.get("violations", [])]
    return len(fnd), fnd


def c_brakeman(o, e):
    d = _load(o) or {}
    w = d.get("warnings", [])
    fnd = [f"{x.get('file')}:{x.get('line','?')} {x.get('warning_type','')} {x.get('message','')}"
           for x in w]
    return len(fnd), fnd


def c_fallow(o, e):
    d = _load(o)
    if not isinstance(d, dict):
        return _fallback(o, e)
    chk = d.get("check") or {}
    hlt = d.get("health") or {}
    dup = d.get("dupes") or {}
    fnd = []
    for kind, items in chk.items():
        if not isinstance(items, list):
            continue
        for x in items:
            if not isinstance(x, dict):
                fnd.append(f"{kind} {x}")
                continue
            path = x.get("path") or (x.get("files") or ["?"])[0]
            name = x.get("export_name") or x.get("name") or ""
            fnd.append(f"{path}:{x.get('line','?')} {kind} {name}".rstrip())
    for h in hlt.get("findings", []):
        fnd.append(f"{h.get('path')}:{h.get('line','?')} complexity "
                   f"{h.get('name','')} ({h.get('severity','')})")
    for g in dup.get("clone_groups", []):
        i = (g.get("instances") or [{}])[0]
        fnd.append(f"{i.get('file','?')}:{i.get('start_line','?')} duplicate "
                   f"({len(g.get('instances', []))} copies)")
    return len(fnd), fnd


def c_generic_json(o, e):
    d = _load(o)
    if isinstance(d, list):
        return len(d), [json.dumps(x)[:200] for x in d[:50]]
    return _fallback(o, e)


def c_gitleaks(o, e, report=None, root=None, scoped=None):
    if report and Path(report).exists():
        d = _load(Path(report).read_text()) or []
        # Drop gitignored files (expected local secrets, not leaks); in diff
        # scope, only report files the change actually touches.
        skip = git_ignored(root, sorted({x.get("File", "") for x in d})) if root else set()
        keep = [x for x in d if x.get("File") not in skip
                and (scoped is None or x.get("File") in set(scoped))]
        fnd = [f"{x.get('File')}:{x.get('StartLine','?')} {x.get('RuleID','')}" for x in keep]
        return len(fnd), fnd
    return _fallback(o, e)


def _fallback(o, e):
    lines = [l for l in (o or "").splitlines() if l.strip()]
    return len(lines), lines[:50]


COUNTERS = {
    "eslint": c_eslint, "ruff": c_ruff, "rubocop": c_rubocop,
    "stylelint": c_stylelint, "biome": c_biome, "oxlint": c_oxlint,
    "semgrep": c_semgrep, "golangci": c_golangci, "govulncheck": c_govulncheck,
    "zizmor": c_zizmor, "sqlfluff": c_sqlfluff, "brakeman": c_brakeman,
    "generic_json": c_generic_json, "gitleaks": c_gitleaks, "fallow": c_fallow,
}


# --------------------------------------------------------------------------- #
# execution
# --------------------------------------------------------------------------- #
def build_argv(base, args, target_paths, report_path):
    argv = list(base)
    for a in args:
        if a == "{target}":
            argv.extend(target_paths or ["."])
        elif a == "{report}":
            argv.append(str(report_path))
        else:
            argv.append(os.path.expanduser(a))
    return argv


def run_tool(name, t, root, files, scoped, do_fix, rawdir):
    base = resolve_runner(t["runners"])
    if base is None:
        return {"tool": name, "status": "skipped",
                "reason": "not installed / no ephemeral runner",
                "install_hint": t.get("install_hint", "")}

    target = expand_target(t, root, files, scoped)
    if t.get("target") in ("files", "styleglob", "mdglob", "dockerfiles") and not target:
        return {"tool": name, "status": "skipped", "reason": "no matching files in scope"}

    # Repo-wide tools with a diff_gate prefix only run in diff/staged scope
    # when the change actually touches that domain (e.g. .github/ workflows).
    gate = t.get("diff_gate")
    if scoped is not None and gate and not any(f.startswith(gate) for f in scoped):
        return {"tool": name, "status": "skipped",
                "reason": f"no {gate} files in scope"}

    report_path = rawdir / f"{name}.gitleaks.json"

    if do_fix and t.get("fix"):
        try:
            run(build_argv(base, t["fix"], target, report_path), cwd=root)
        except (subprocess.TimeoutExpired, OSError):
            pass

    argv = build_argv(base, t["cmd"], target, report_path)
    try:
        p = run(argv, cwd=root)
    except subprocess.TimeoutExpired:
        return {"tool": name, "status": "error", "reason": "timeout", "cmd": " ".join(argv)}
    except OSError as ex:
        return {"tool": name, "status": "error", "reason": str(ex), "cmd": " ".join(argv)}

    counter = COUNTERS.get(t.get("count", ""))
    if counter is c_gitleaks:
        n, fnd = c_gitleaks(p.stdout, p.stderr, report=report_path,
                            root=root, scoped=scoped)
    elif counter:
        n, fnd = counter(p.stdout, p.stderr)
    else:
        n, fnd = _fallback(p.stdout, p.stderr)

    raw = (p.stdout or "") + (("\n[stderr]\n" + p.stderr) if p.stderr.strip() else "")
    (rawdir / f"{name}.txt").write_text(raw)

    return {"tool": name, "status": "ran", "exit": p.returncode,
            "findings": n, "sample": fnd[:25], "cmd": " ".join(argv)}


# --------------------------------------------------------------------------- #
# reporting
# --------------------------------------------------------------------------- #
def write_report(outdir: Path, summary: dict):
    (outdir / "summary.json").write_text(json.dumps(summary, indent=2))

    L = ["# Static analysis report", ""]
    L.append(f"- scope: **{summary['scope']}**  ·  target: `{summary['target']}`")
    L.append(f"- total findings: **{summary['total_findings']}**")
    ran = [r for r in summary["results"] if r["status"] == "ran"]
    skipped = [r for r in summary["results"] if r["status"] == "skipped"]
    errored = [r for r in summary["results"] if r["status"] == "error"]
    L += ["", "## Tools", "", "| tool | findings | exit |", "|---|---|---|"]
    for r in sorted(ran, key=lambda r: -r["findings"]):
        L.append(f"| {r['tool']} | {r['findings']} | {r['exit']} |")
    if skipped:
        L += ["", "## Skipped", ""]
        for r in skipped:
            hint = f" — install: `{r['install_hint']}`" if r.get("install_hint") else ""
            L.append(f"- **{r['tool']}**: {r['reason']}{hint}")
    if errored:
        L += ["", "## Errors", ""]
        for r in errored:
            L.append(f"- **{r['tool']}**: {r['reason']}")
    for r in sorted(ran, key=lambda r: -r["findings"]):
        if r["findings"]:
            L += ["", f"### {r['tool']} ({r['findings']})", "```"]
            L += r["sample"]
            if r["findings"] > len(r["sample"]):
                L.append(f"... +{r['findings'] - len(r['sample'])} more (see raw/{r['tool']}.txt)")
            L.append("```")
    (outdir / "report.md").write_text("\n".join(L) + "\n")


# --------------------------------------------------------------------------- #
# main
# --------------------------------------------------------------------------- #
def main() -> int:
    ap = argparse.ArgumentParser(description="Run curated static analyzers.")
    ap.add_argument("path", nargs="?", default=".", help="repo/dir to analyze")
    ap.add_argument("--diff", action="store_true", help="only files changed vs base branch")
    ap.add_argument("--staged", action="store_true", help="only staged files")
    ap.add_argument("--fix", action="store_true", help="run safe autofixers first")
    ap.add_argument("--sql", action="store_true", help="include SQLFluff (on-demand)")
    ap.add_argument("--exit-zero", action="store_true", help="always exit 0")
    ap.add_argument("--jobs", type=int, default=min(8, (os.cpu_count() or 4)))
    args = ap.parse_args()

    root = Path(args.path).resolve()
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2

    reg = tomllib.loads(REGISTRY.read_text())
    all_files = list_files(root)
    if not all_files:
        print("error: no files found", file=sys.stderr)
        return 2

    if args.diff or args.staged:
        scoped = changed_files(root, staged=args.staged)
        scope = "staged" if args.staged else "diff"
        if not scoped:
            print(f"no {scope} files; nothing to analyze")
            return 0
    else:
        scoped = None
        scope = "whole-repo"

    tools = select_tools(reg, all_files, want_sql=args.sql)
    if not tools:
        print("no applicable tools for this repo")
        return 0

    outdir = root / OUTDIR
    rawdir = outdir / "raw"
    rawdir.mkdir(parents=True, exist_ok=True)
    for old in rawdir.glob("*"):
        old.unlink()

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(run_tool, n, reg[n], root, all_files, scoped, args.fix, rawdir): n
                for n in tools}
        for fut in concurrent.futures.as_completed(futs):
            results.append(fut.result())

    total = sum(r.get("findings", 0) for r in results if r["status"] == "ran")
    summary = {
        "scope": scope,
        "target": str(root),
        "total_findings": total,
        "tools_run": sorted(r["tool"] for r in results if r["status"] == "ran"),
        "tools_skipped": sorted(r["tool"] for r in results if r["status"] == "skipped"),
        "results": sorted(results, key=lambda r: r["tool"]),
    }
    write_report(outdir, summary)

    print(f"static-analysis: {total} findings across {len(summary['tools_run'])} tools "
          f"({len(summary['tools_skipped'])} skipped) -> {OUTDIR}/report.md")

    if args.exit_zero:
        return 0
    if any(r["status"] == "error" for r in results):
        return 2
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
