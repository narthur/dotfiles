# Manual-testing evidence gate — procedure (SKILL Step 13)

SKILL Step 13 holds the trigger and skip conditions. This file is the 13a→13b→13c procedure, run only when the gate is active.

## 13a: Check the PR for existing evidence

Read the PR body and comments:

```bash
gh pr view --json body,comments
```

**Sufficient evidence** = artifacts demonstrating this PR's changed functionality actually working: screenshots/recordings of the changed UI states, command transcripts with real output (curl against a dev server, CLI invocations), or test-session notes with concrete inputs and observed outputs. A bare claim ("tested locally ✅") is **not** sufficient, and evidence must cover the *changes in this PR*, not the app generally. Evidence found → gate passes; go to Step 14.

## 13b: Do the manual testing yourself

No sufficient evidence → produce it:

1. Stand up whatever the changes need locally, per repo convention (check CLAUDE.md / package.json scripts — e.g. `pnpm dev`; seed env/data as the repo's docs describe).
2. Exercise **each functional change the PR makes** — not a generic smoke test:
   - UI changes → the **playwright** skill: drive the changed flows and `playwright-cli screenshot` at the states that prove the new behavior.
   - API/CLI changes → real requests/invocations; capture the command and the actual response verbatim.
3. Save evidence as you go — screenshots to the scratchpad, transcripts verbatim.

## 13c: Outcome

**Everything works** → publish the evidence to the PR:

1. Images → public URLs via the **surge-image-upload** skill: `~/.claude/skills/surge-image-upload/upload.sh <files>`.
2. Post one PR comment (`gh pr comment`) with a `## Manual testing evidence` section: what was tested and how, embedded screenshots, transcripts in fenced blocks, and the environment (local dev, commit SHA tested).
3. Gate passes → Step 14.

**Testing finds a real issue** (broken behavior, error, regression):

1. **Stop the review immediately** — post no evidence, push nothing.
2. Fix the issue and commit it (`fix(<scope>): <description>`).
3. **Restart the loop from Step 4, cycle 1** — the fix is new, unreviewed code and goes through the full review before the gate runs again.
4. Cap gate-triggered restarts at **2 per invocation**. At the cap, stop, report the unresolved issues, and don't auto-push.

**Can't test** (required secret/service unavailable, dev environment broken) → don't fake or hand-wave it: treat the gate as **not passed**, skip the auto-push, and report exactly what was attempted, what blocked it, and what the user needs to provide.
