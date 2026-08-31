# Security review (replaces Agent #5)

Read this at Step 5 before spawning the security review.

## Provenance — why this is not ours

<!-- upstream: claude-code 2.1.251 sha256:83af94c8777cf13eb31b900a8b8c026df44804925d0eb8b956c007f3f7829104 -->

**Staying current.** The upstream prompt is compiled into the Claude Code binary, so it updates
silently whenever Claude Code does; this vendored copy does not. `upstream-check.py` (run at
Step 2a) extracts the installed version's prompt, hashes it, and compares it to the stamp above.
Drift is not automatically a problem — upstream may have changed something we deliberately depart
from — it is a prompt to run `python3 upstream-check.py --extract`, diff it against this file, and
decide. After adopting an upstream change, refresh the stamp with `--stamp`.

The finder prompt and the false-positive filter below are Anthropic's `/security-review`, adopted
near-verbatim. The exclusion list and precedents were derived from production false positives
across a large number of repos. We could not have written them; we would have rediscovered them
one dismissal at a time.

Two deliberate departures, both additive:

1. **The threat model is injected** rather than re-derived. Anthropic's Phase 1 says *"understand
   the project's security model and threat model"* — from scratch, every run, then discarded.
   Ours is persisted (`references/threat-model.md`), so repo-specific facts survive.
2. **Findings route into the loop** (score → auto-fix / ask / report) instead of terminating in a
   markdown report.

Everything else — the categories, the exclusions, the precedents, the two-stage architecture —
is theirs. **Do not "improve" the exclusion list from first principles.** Amend it only via the
threat model's per-repo override, which is evidence-backed by definition.

## Architecture: fan out on verification, not discovery

**One** finder agent, then **one filter subagent per finding**, in parallel. Not a roster of
per-class specialists — the finder covers the classes, and the expensive, parallel, adversarial
step is *verification*. Usually 0–3 filter agents; on a clean diff, zero.

Both stages pin to `model: sonnet` per `references/model-choice.md`.

## Gating

Runs on **every cycle** except Step 3b's fast path (where the merged reviewer covers it). It is
one agent; it does not need the conditional-agent gating that #7/#8 need.

**Cycles 2+:** re-run only if a security fix was applied in the previous cycle, scoped to the
applied hunks. Rationale: authorization fixes are always-ask, which makes the user the sole
reviewer of a fix they cannot audit, and nothing else re-reads it. SecLLMHolmes also found LLM
vulnerability reasoning is non-deterministic and sensitive to variable naming, so the re-run
doubles as a second sample of a noisy detector.

---

## Stage 1 — the finder

Give the agent: this cycle's diff, the changed files, the threat model file contents, and
everything from here to the stage divider.

> You are a senior security engineer conducting a focused security review of the changes on this
> branch.
>
> **OBJECTIVE:** Perform a security-focused code review to identify HIGH-CONFIDENCE security
> vulnerabilities that could have real exploitation potential. This is not a general code review —
> focus ONLY on security implications newly added by these changes. Do not comment on existing
> security concerns.
>
> **CRITICAL INSTRUCTIONS:**
> 1. MINIMIZE FALSE POSITIVES: Only flag issues where you're >80% confident of actual exploitability
> 2. AVOID NOISE: Skip theoretical issues, style concerns, or low-impact findings
> 3. FOCUS ON IMPACT: Prioritize vulnerabilities that could lead to unauthorized access, data
>    breaches, or system compromise
> 4. EXCLUSIONS: Do NOT report Denial of Service, rate limiting, or resource exhaustion issues.
>
> **SECURITY CATEGORIES TO EXAMINE:**
>
> *Input Validation:* SQL injection via unsanitized input; command injection in system calls or
> subprocesses; XXE in XML parsing; template injection; NoSQL injection; path traversal in file
> operations.
>
> *Authentication & Authorization:* authentication bypass logic; privilege escalation paths;
> session management flaws; JWT token vulnerabilities; authorization logic bypasses; insecure
> direct object reference (acting on an id without checking the caller owns it).
>
> *Crypto & Secrets:* hardcoded API keys, passwords or tokens; weak cryptographic algorithms or
> implementations; improper key storage; cryptographic randomness issues; certificate validation
> bypasses.
>
> *Injection & Code Execution:* RCE via deserialization; pickle injection; YAML deserialization;
> eval injection; XSS (reflected, stored, DOM-based).
>
> *Data Exposure:* sensitive data logging or storage; PII handling violations; API endpoint data
> leakage; debug information exposure.
>
> Even if something is only exploitable from the local network, it can still be HIGH severity.
>
> **ANALYSIS METHODOLOGY:**
>
> *Phase 1 — Repository context.* You have been given this repository's threat model. **Treat its
> OBSERVED claims (which carry `[file:line @ commit]` citations) as verified fact. Treat its
> INFERRED claims (uncited) as hypotheses to check against the code, not as ground truth.** Beyond
> that: identify the security frameworks and libraries in use, the established sanitization and
> validation patterns, and the existing secure-coding conventions.
>
> *Phase 2 — Comparative analysis.* Compare the new code against those existing patterns. Identify
> deviations from established secure practice, inconsistent security implementations, and code that
> introduces new attack surface.
>
> *Phase 3 — Vulnerability assessment.* Examine each modified file for security implications. Trace
> data flow from user inputs to sensitive operations. Look for privilege boundaries crossed
> unsafely. Identify injection points and unsafe deserialization.
>
> **SEVERITY:** HIGH = directly exploitable, leading to RCE, data breach, or auth bypass. MEDIUM =
> requires specific conditions but has significant impact. LOW = defense-in-depth or lower impact.
> Report HIGH and MEDIUM only. Better to miss a theoretical issue than to flood the report. Each
> finding should be something a security engineer would confidently raise in a PR review.
>
> **OUTPUT:** a list of `{file, line_range, severity, category, description, exploit_scenario,
> suggested_fix, reasoning}`. `category` is a slug such as `sql_injection`, `idor`, `xss`.
> `exploit_scenario` must be concrete: the attacker's actual input and what they get.

**Two things to add to that prompt from the loop's own context:**

- The `## Not an issue here` and `## Watch this spot` sections of the threat model, with:
  *"A 'Not an issue here' entry means do not raise that finding on this repo. A 'Watch this spot'
  entry means report anything touching that location even if a general rule would exclude it."*
- The learnings file, with the standard: *"If a finding matches anything in the Dismissed list, do
  not flag it."*

**Do not** duplicate what Step 4a's tools already own. Skip hardcoded-secret findings (gitleaks),
known-vulnerable dependencies (govulncheck / Dependabot), and CI workflow permissions (zizmor) —
those arrive as pre-verified ≥80 findings from the static-analysis pass and do not need a second
opinion.

---

## Stage 2 — the false-positive filter

**One subagent per finding, spawned in parallel.** Each receives one finding, the relevant code,
and the threat model. This replaces Haiku scoring for security findings — do not also run a Haiku
scorer over them.

> You do not need to run commands to reproduce the vulnerability, just read the code to determine
> if it is a real vulnerability. Do not use the bash tool or write to any files.
>
> **HARD EXCLUSIONS — automatically exclude findings matching these patterns:**
> 1. Denial of Service (DOS) vulnerabilities or resource exhaustion attacks.
> 2. Secrets or credentials stored on disk if they are otherwise secured.
> 3. Rate limiting concerns or service overload scenarios.
> 4. Memory consumption or CPU exhaustion issues.
> 5. Lack of input validation on non-security-critical fields without proven security impact.
> 6. Input sanitization concerns for GitHub Action workflows unless they are clearly triggerable
>    via untrusted input.
> 7. A lack of hardening measures. Code is not expected to implement all security best practices,
>    only flag concrete vulnerabilities.
> 8. Race conditions or timing attacks that are theoretical rather than practical issues. Only
>    report a race condition if it is concretely problematic.
> 9. Vulnerabilities related to outdated third-party libraries. These are managed separately and
>    should not be reported here.
> 10. Memory safety issues such as buffer overflows or use-after-free are impossible in Rust. Do
>     not report memory safety issues in Rust or any other memory-safe language.
> 11. Files that are only unit tests or only used as part of running tests.
> 12. Log spoofing concerns. Outputting un-sanitized user input to logs is not a vulnerability.
> 13. SSRF vulnerabilities that only control the path. SSRF is only a concern if it can control the
>     host or protocol.
> 14. Including user-controlled content in AI system prompts is not a vulnerability.
> 15. Regex injection. Injecting untrusted content into a regex is not a vulnerability.
> 16. Regex DOS concerns.
> 17. Insecure documentation. Do not report any findings in documentation files such as markdown
>     files.
> 18. A lack of audit logs is not a vulnerability.
>
> **PRECEDENTS:**
> 1. Logging high value secrets in plaintext is a vulnerability. Logging URLs is assumed to be safe.
> 2. UUIDs can be assumed to be unguessable and do not need to be validated.
> 3. Environment variables and CLI flags are trusted values. Attackers are generally not able to
>    modify them in a secure environment. Any attack that relies on controlling an environment
>    variable is invalid.
> 4. Resource management issues such as memory or file descriptor leaks are not valid.
> 5. Subtle or low impact web vulnerabilities such as tabnabbing, XS-Leaks, prototype pollution, and
>    open redirects should not be reported unless they are extremely high confidence.
> 6. React and Angular are generally secure against XSS. These frameworks do not need to sanitize or
>    escape user input unless it is using `dangerouslySetInnerHTML`, `bypassSecurityTrustHtml`, or
>    similar methods. Do not report XSS vulnerabilities in React or Angular components or tsx files
>    unless they are using unsafe methods.
> 7. Most vulnerabilities in GitHub Action workflows are not exploitable in practice. Before
>    validating one ensure it is concrete and has a very specific attack path.
> 8. A lack of permission checking or authentication in client-side JS/TS code is not a
>    vulnerability. Client-side code is not trusted and does not need to implement these checks,
>    they are handled server-side. The same applies to all flows that send untrusted data to the
>    backend; the backend is responsible for validating and sanitizing all inputs.
> 9. Only include MEDIUM findings if they are obvious and concrete issues.
> 10. Most vulnerabilities in IPython notebooks (`*.ipynb`) are not exploitable in practice. Before
>     validating one ensure it is concrete and has a very specific attack path where untrusted input
>     can trigger it.
> 11. Logging non-PII data is not a vulnerability even if the data may be sensitive. Only report
>     logging vulnerabilities if they expose sensitive information such as secrets, passwords, or
>     personally identifiable information (PII).
> 12. Command injection vulnerabilities in shell scripts are generally not exploitable in practice
>     since shell scripts generally do not run with untrusted user input. Only report them if they
>     are concrete and have a very specific attack path for untrusted input.
>
> **REPO-SPECIFIC OVERRIDE (this beats the lists above, in both directions):**
> - If the finding's location appears under `## Watch this spot` in the threat model, do NOT drop it
>   under a hard exclusion or precedent. That location has a recorded, evidence-backed reason to be
>   treated as sensitive here. Score it on its merits.
> - If the finding matches an entry under `## Not an issue here`, score it 1.
>
> **SIGNAL QUALITY — for remaining findings, assess:**
> 1. Is there a concrete, exploitable vulnerability with a clear attack path?
> 2. Does this represent a real security risk vs theoretical best practice?
> 3. Are there specific code locations and reproduction steps?
> 4. Would this finding be actionable for a security team?
>
> **Assign a confidence score from 1-10:**
> - 1-3: Low confidence, likely false positive or noise
> - 4-6: Medium confidence, needs investigation
> - 7-10: High confidence, likely true vulnerability
>
> Return the confidence integer and one sentence of justification.

The override paragraph is ours, and it is the reason the threat model exists. Anthropic's
precedent 11 would otherwise suppress the Postgres `Failing row contains (…)` class of finding —
user-authored content reaching an error sink — which is among the most valuable this repo set has
produced.

---

## Routing into the loop

Security findings **do not go through Haiku scoring** (Step 6). Stage 2 is their scorer. Convert
and route:

| Filter confidence | Score | Routing |
| --- | --- | --- |
| 8–10 | 80–100 | Actioned. Step 7 auto-fix, or Step 8a risk profile. |
| 1–7 | 10–70 | **Not actioned. Listed in the Step 14 report**, one line each. |

The floor is deliberately higher than the loop's general 50-79 ask band: Anthropic's threshold is
8, and honoring it is most of what buys the low false-positive rate. Nothing between 4 and 7 is
worth an interruption.

**But nothing below 8 is silently dropped either.** A wrongly-dropped security finding is
invisible to a non-expert forever, and the Step 14 report is the only place it can surface. One
line each: `file:line — category — one-clause description (confidence N/10)`.

**Authorization findings are always-ask.** Pass `agent: "5-security-authz"` to `bucket.py` for any
finding whose category is authorization-shaped (`idor`, `authz_bypass`, `auth_bypass`,
`privilege_escalation`, `missing_authz`, `broken_access_control`); everything else uses
`agent: "5-security"`. By Step 8a's own dimensions, adding or tightening an authorization check is
high-blast-radius *by construction* — the failure mode is locking legitimate users out of
production, and it is the one class where an auto-applied wrong fix looks exactly like a right one.
Injection fixes (parameterize a query) and data-exposure fixes (drop a field from a log payload)
are mechanical and subtractive; those take the normal risk profile.

When asking, Step 8b's non-expert framing applies with full force. Lead with the concrete
`exploit_scenario` — what an attacker types and what they get — not the category name.
