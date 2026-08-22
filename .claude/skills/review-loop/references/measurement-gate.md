# Impact measurement gate — procedure (SKILL Step 13.5)

SKILL Step 13.5 holds the trigger and skip conditions. This file is the 13.5a → 13.5b → 13.5c procedure, run only when the gate is active.

Step 13 asks "does it work?". This gate asks **"when this is live, how will we know whether it helped?"** — and it is the last moment that question can still be answered, because the fix for a wrong answer is *code in this PR*. Instrumentation added after merge cannot produce a pre-ship baseline, and a threshold picked after seeing the data is not a threshold.

## 13.5a: State the measurement plan

Start from the Step 4b intent statement (the change's goal in user terms). If Step 4b gated off, derive the goal from the issue / commit messages the same way. Then write the plan — five lines, no more:

- **Expected effect** — a directional claim about users, not a description of the code: "fewer people abandon the import flow at the mapping step", not "adds retry to the import".
- **Metric** — the one number that moves, named **as it exists in this repo's telemetry**: the event name, metric key, or a query against a real table. If naming it requires inventing something that doesn't exist yet, that's a 13.5b blocker, not a naming problem.
- **Baseline** — the current value, or the exact query that reads it. Read it *now* if you can and put the number in the plan; post-merge there may be nothing to compare against.
- **Window and threshold** — how long to wait, and what counts as worked / didn't / inconclusive. Decide the threshold before the data exists, or it will be chosen to fit whatever arrives.
- **Guardrail** — the metric that must not get *worse*: error rate, latency, or the conversion this change could cannibalise.

Keep it to what the change's stakes justify. A copy tweak gets one metric and one guardrail; a pricing or onboarding change earns segmentation and a real window.

## 13.5b: Verify the instrumentation actually exists

For each metric and guardrail named above, check the **code**, not your assumption. All four must hold:

1. **Emitted on the changed path** — the event/metric fires on the code path this diff touches, including its failure and early-return branches, not merely somewhere in the same feature.
2. **Segmentable** — the payload carries enough (user/account id, variant, cohort, or version) to isolate the affected population. A global counter you can't split by "did this user hit the new path" measures nothing.
3. **Both arms covered** — if the change is behind a flag, rollout, or A/B split, the metric fires identically on both sides. One-armed instrumentation produces a before/after with a confound baked in.
4. **Baseline readable now** — you can query the pre-change value today. If the metric only starts existing when this ships, there is no baseline and the experiment is already broken.

Anything failing is a **gap**, and gaps block — see below.

## 13.5c: Outcome

**Plan complete, instrumentation verified** → publish it and pass:

1. Add an `## Impact measurement` section to the PR description with the five lines (Step 14 reconciles the body anyway — fold it in there), or post it as a PR comment if the description is the author's and you'd be rewriting it.
2. Gate passes → continue to Step 14.

**Instrumentation gap** → **stop; do not push.**

1. Add the missing instrumentation **in this PR** — the event, the property, the flag-aware emission, whatever 13.5b found missing. This is not scope creep: shipping the change without it forfeits the measurement permanently.
2. Commit it (`feat(telemetry): <what it measures>` or the repo's convention).
3. **Restart the loop from Step 4, cycle 1** — new code, unreviewed.
4. Restarts share the Step 13 budget: **2 gate-triggered restarts per invocation across both gates.** At the cap, stop, report the gap, and don't auto-push.

**Genuinely unmeasurable** → **waive it, out loud.** The waiver requires a stated reason, always visible in the report and the PR — never silent.

- Legitimate: no user-visible surface (internal tooling with a handful of users); traffic too low for any effect to separate from noise inside a useful window; the measurement would cost more than the change is worth; the effect is definitionally unobservable (a fix for a failure mode that has never fired).
- Not legitimate: "we'll add analytics later", "hard to measure", "obviously an improvement". Those are 13.5b gaps wearing a disguise — instrument them.

A waiver passes the gate and reports as `waived — <reason>`.
