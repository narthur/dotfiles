---
name: prod-uvis
description: "Find user-visible improvements (UVIs) deployed to production in the current git repo that are not hidden behind a feature flag. Use when asked to find recent improvements, list what's been deployed to prod, or review what's visible to users."
---

# Prod UVIs

You are reviewing recent production deployments to identify user-visible improvements (UVIs) — changes that are live and visible to all users, not hidden behind a feature flag.

## What You Do

- Inspect recent commits on the production branch
- Filter for potentially user-visible changes (feat, fix commit types)
- Check each change for feature flag gating
- Identify which GitHub users contributed to each change
- Report only improvements that are live and accessible to all users

## What You Don't Do

- Report chore, refactor, test, docs, or ci commits — these are not user-visible
- Report changes that are behind a disabled feature flag
- Guess — if you can't determine flag status, say so and investigate

---

## Workflow

### Step 1: Determine the Range

If the user specified a `--since` ref (date, commit hash, or tag), use that. Otherwise default to the last 30 commits on the production branch.

Identify the production branch — typically `origin/main` or `origin/master`. Check with:

```bash
git remote show origin | grep 'HEAD branch'
```

### Step 2: Fetch Commits

Get recent commits, filtering for user-visible types:

```bash
git fetch origin
git log origin/main --oneline -50
```

Focus on commits with types: `feat`, `fix`. Skip: `chore`, `refactor`, `test`, `docs`, `ci`, `build`, `perf` (unless perf is user-noticeable).

If commits are squash-merged PRs, look at the PR titles/merge commits for the full picture.

For each qualifying commit or PR, collect the GitHub author(s):

```bash
# Get author of a commit
git log --format="%an <%ae>" <commit-hash> -1

# For a PR, get all authors of commits in the PR
gh pr view <number> --json author,commits --jq '{author: .author.login, commits: [.commits[].authors[].login]}'
```

If the repo uses squash merges, the commit author is typically the PR author. For multi-author PRs, use the `gh pr view` approach to find all contributors.

### Step 3: Load Feature Flag State

Check if a feature flag config exists:

```bash
# Common locations:
cat config/feature_flags.json 2>/dev/null
cat config/features.yml 2>/dev/null
```

Note which flags are `false` (disabled) — any feature gated behind these is NOT visible to users.

### Step 4: Check Each Candidate for Feature Flag Gating

For each `feat`/`fix` commit, identify the files it changed:

```bash
git show --name-only <commit-hash> | grep -v '^$' | tail -n +2
```

Then check if those files use a feature flag:

```bash
# Frontend pattern (React/TypeScript):
grep -l "useIsFeatureEnabled" <file1> <file2> ...

# Rails backend pattern:
grep -r "feature_enabled\|feature_flag\|flipper" <file1> <file2> ...
```

If the feature is gated, cross-reference the flag name against the feature flag config to see if it's enabled or disabled.

### Step 5: Present Results

Group findings into two sections:

**Visible to all users** — improvements with no flag, or with an enabled flag. Include:
- Brief description of what changed
- Which PR or commit introduced it
- Why it's user-visible
- GitHub username(s) who contributed

**Behind feature flags** — improvements gated by a disabled flag. List briefly.

---

## Tips

- Merge commits (e.g. `Merge pull request #N`) are often the best entry point — they group all the commits for a feature together
- When in parallel refactor + feat work exists, the refactor commits often set up a feat — check the PR they belong to
- A `fix` is user-visible if it corrects something the user could observe (UI bug, wrong data, broken flow) — not if it fixes a test or internal logic
- If a component uses `useIsFeatureEnabled` but the flag is `true` in config, the feature IS live
- When in doubt about a change's visibility, look at the component it touches and ask: would a user see this in the UI or notice the behavior change?
