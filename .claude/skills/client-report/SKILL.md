---
name: client-report
description: "Generate a summary of GitHub activity for a configured client team. Shows PRs and issues each team member has been involved with. Default is last 7 days; specify a number of days to change the lookback period. Use when asked about team activity, what people have been working on, or to get a status update. Client configs live at ~/.claude/skills/client-report/clients/."
---

You are helping the user get a summary of GitHub activity for a client team.

## What You Do

- Load the appropriate client config from `~/.claude/skills/client-report/clients/`
- Fetch GitHub event data and time tracking data via `fetch-client-data.sh`
- Launch sub-agents to research each authored PR in depth
- Compile the results into a readable summary with per-PR summaries and stage information
- Highlight key activity patterns
- Save an HTML report and a Markdown report to the configured output directory

## Arguments

The user may specify:

- **Client name**: e.g. "acme activity". Match against `name` and `aliases` fields in config files. If not specified and only one config exists (or one is marked `"default": true`), use that one.
- **Number of days**: e.g. "client report for the last 14 days" → 14 days. Default is 7.

## Workflow

### Step 0: Load Client Config

1. List all JSON files in `~/.claude/skills/client-report/clients/`:

   ```bash
   ls ~/.claude/skills/client-report/clients/
   ```

2. Parse the user's request for a client name. Match it against the `name` and `aliases` fields of each config file (case-insensitive).

3. If no client is specified:
   - If only one config file exists, use it.
   - If multiple exist, pick the one with `"default": true`.
   - If none is marked default, ask the user which client they want.

4. Read the matching config file:

   ```bash
   cat ~/.claude/skills/client-report/clients/<name>.json
   ```

5. Extract these values for use throughout the workflow:
   - `CLIENT_NAME` — human-readable name (e.g. "Acme Corp")
   - `GITHUB_ORG` — GitHub org slug (e.g. "acme-corp")
   - `TEAM_MEMBERS` — array of objects, each with `github` (GitHub username) and optional `narthbugz_id`. May also be an array of plain strings (treat each string as a GitHub username with no narthbugz_id).

   **Look up real names — never infer them from usernames.** A username is not a name, and a plausible-looking guess derived from a handle is an invented person. Fetch each member's display name in one batch:

   ```bash
   for u in <github1> <github2>; do gh api users/$u --jq '"\(.login)\t\(.name // "")"'; done
   ```

   Use the returned name as the person's heading, with the username beside it. If `name` comes back empty, use the username alone as the heading — do not guess.
   - `NARTHBUGZ_CLIENT_NAME` — Narthbugz `clientName` to filter time entries (may be absent; skip time tracking if so)
   - `NARTHBUGZ_CLIENT_ID` — Narthbugz numeric client id, required for `tracked+agent` billing (maps to a GitHub org via `/github/orgs`)
   - `BILLING_BASIS` — `"tracked"` (default, explicit entries only) or `"tracked+agent"` (union of tracked entries and agent working time). Absent means `"tracked"`.
   - `OUTPUT_DIR` — local directory path for saving reports
   
### Step 1: Determine Lookback Period

Determine the proposed date range using the following logic, then confirm with the user before proceeding.

1. **If the user specified a number of days** (e.g. "client report for the last 14 days"), use `period_end = now`, `period_start = now - N days`. Skip the auto-detection in step 2.

2. **Otherwise, check for a prior report** in the configured `OUTPUT_DIR`:

   ```bash
   ls -1 <OUTPUT_DIR>/*.html 2>/dev/null | sort | tail -1
   ```

   The filename is an ISO-like timestamp `YYYY-MM-DDTHH-MM-SS.html`. Parse it as the last-generated time.

   - If a prior report exists, propose `period_start = <last report timestamp>` and `period_end = now`. Compute the resulting number of days (rounded to one decimal) for display.
   - If no prior report exists, fall back to the **7-day** default.

3. **Confirm the range with the user** using `AskUserQuestion` before fetching any data:

   Question: `"Generate report covering <PERIOD_START> → <PERIOD_END> (<N> days since last report)?"` (adjust wording if no prior report: "Generate report covering the last 7 days (<start> → <end>)?")
   Header: `"Date range"`
   Options:
   - **Use this range** — Proceed with the proposed window.
   - **Use 7-day default** — Override to a 7-day lookback ending now. (Omit this option if the proposed range is already 7 days.)
   - **Custom** — User will specify a different range or number of days; ask a follow-up to collect it.

   Once confirmed, use the agreed `period_start` / `period_end` for the rest of the workflow. When calling `fetch-client-data.sh`, pass `--days <N>` where N is the integer number of days in the window (round up so no activity is missed).

### Step 2: Fetch Activity Data

Run the fetch script for all team members. Build the `--member` arguments from `TEAM_MEMBERS`: for each member object, pass `<github>[:<narthbugz_id>]` (omit the colon-suffix if no `narthbugz_id`). If `NARTHBUGZ_CLIENT_NAME` is set, pass it via `--client-name`.

```bash
~/.claude/skills/client-report/fetch-client-data.sh <GITHUB_ORG> \
  --days <N> \
  --member <github1>[:<narthbugz_id1>] \
  [--member <github2>[:<narthbugz_id2>]] \
  [--client-name "<NARTHBUGZ_CLIENT_NAME>"]
```

Use a 3-minute timeout since the script fetches many repos in parallel and the Narthbugz API can be slow on cold starts.

The script outputs labeled sections to stdout:
- `=== META ===` — JSON: `period_start`, `period_end`, `days`
- `=== <user> GITHUB EVENTS ===` — one JSON object per line, each representing an action the user actually performed in the org during the period (from the repo Events API)
- `=== <user> OPEN PRS ===` — one JSON object per line (open PRs authored by user in the org)
- `=== <user> MERGED PRS ===` — one JSON object per line (PRs merged within the period)
- `=== <user> ASSIGNED ISSUES ===` — one JSON object per line (open issues assigned to user)
- `=== <user> ISSUE EDITS ===` — one JSON object per line (issues whose body was edited by the user during the period, detected via GraphQL `userContentEdits`). Each object has `{repo, number, title, url, lastEditedAt, edits: [{editedAt, editor}]}`.
- `=== <user> TIME ===` — JSON array of `{taskName, projectName, clientName, hours, notes, date}` objects, or `[]`

**Interpreting event types** (same logic as daily-standup):
- `PullRequestEvent` + `action: "opened"` → user opened a PR
- `PullRequestEvent` + `action: "closed"` → user closed/merged a PR
- `PullRequestReviewEvent` → user reviewed a PR
- `PullRequestReviewCommentEvent` → user left a review comment
- `IssuesEvent` + `action: "opened"` → user filed an issue
- `IssuesEvent` + `action: "closed"` → user closed an issue
- `IssuesEvent` + `action: "labeled"` / `"assigned"` / `"unlabeled"` → triage activity
- `IssueCommentEvent` → user commented on an issue or PR

**Note:** Issue body/title edits do NOT appear in the Events API. Instead, the fetch script detects them separately via GraphQL `userContentEdits` and outputs them in the `ISSUE EDITS` section. Use that section (not events) to identify issue-editing work.
- `PushEvent` → user pushed commits (see `commits[]` for messages, `ref` for branch)
- `CreateEvent` → user created a branch or tag

Only `PullRequestEvent`/`PullRequestReviewEvent` events (and items in OPEN/MERGED PRS sections) represent actual code work. `IssuesEvent` and `IssueCommentEvent` represent issue triage and discussion.

**Note on Events API coverage:** The Events API only returns the last ~300 events per repo, so coverage may be incomplete for repos with very high activity or for periods longer than a few days. Cross-reference with the MERGED PRS section (which uses the Search API) to ensure merged PRs within the window are not missed.

### Step 3: Research PRs with Sub-agents

From the MERGED PRS and OPEN PRS sections, collect all PR numbers attributed to each team member. Group these by repo (extract repo from `repository_url`).

For each repo that has PRs to research, launch a **parallel** sub-agent (subagent_type: `general-purpose`) to research all PRs in that repo. Give each sub-agent the following prompt, substituting the actual values:

---

**Sub-agent prompt template:**

````
Research the following pull requests in the <GITHUB_ORG>/<REPO> GitHub repository and return a structured markdown report.

PRs to research: <comma-separated list of PR numbers, e.g. #2129, #2198, #2207>

For each PR, do the following steps using `gh` CLI:

**Step 1: Fetch PR details**
```bash
gh pr view <NUM> --repo <GITHUB_ORG>/<REPO> --json number,title,body,state,mergedAt,baseRefName,mergeCommit
````

**Step 2: Determine stage**

First resolve the repo's actual default branch — never assume `main`. It may be `master`, `main`, `trunk`, or anything else, and it varies from repo to repo within one org:

```bash
DEFAULT=$(gh repo view <GITHUB_ORG>/<REPO> --json defaultBranchRef --jq .defaultBranchRef.name)
```

Then:

- If state is OPEN → stage is "Open"
- If state is CLOSED (not merged, mergedAt is null) → stage is "Closed (not merged)"
- If state is MERGED:
  - Note the baseRefName (the branch it merged into)
  - If baseRefName equals `$DEFAULT` → stage is "In $DEFAULT"
  - Otherwise (e.g. "development", "dev") → check if the merge commit reached the default branch:

    ```bash
    gh api repos/<GITHUB_ORG>/<REPO>/compare/$DEFAULT...<mergeCommit.oid> --jq '{status:.status,ahead:.ahead_by}'
    ```

    - If `ahead == 0` → stage is "In $DEFAULT (via <baseRefName>)"
    - If `ahead > 0` → stage is "In <baseRefName> only (not yet in $DEFAULT)"

Report the branch name you resolved, so the summarizer never has to guess it.

**Step 3: Check for reverts**

```bash
gh pr list --repo <GITHUB_ORG>/<REPO> --state all --search 'Revert in:title' --json number,title,state,body
```

Scan the results: if any PR title matches `Revert "<original PR title>"` or the body references the original PR number, note it as reverted and include the revert PR number. If the revert was itself reverted (re-applied), note that too.

**Step 4: Detect and look up PR stacks**
If any PR's title, body, or CodeRabbit summary mentions being part of a stack (e.g. "Part 3 of 9", "GitButler stack", "stacked on #1234"), look up the **other PRs in that stack** that are NOT already in the research list. For each sibling PR found, fetch its number, title, and state:

```bash
gh pr view <NUM> --repo <GITHUB_ORG>/<REPO> --json number,title,state
```

Include a "Stack context" note at the end of your report listing all stack members and their states, so the summarizer has full visibility into which parts are open, merged, or closed — even if those PRs fall outside the reporting window.

**Return format:**
For each PR return a row in this markdown table:

| PR  | Title | Summary | Stage | Reverted? |
| --- | ----- | ------- | ----- | --------- |

- **Summary**: 1–2 sentences describing the purpose and key changes, written at a product/engineering level. Use the PR body (and CodeRabbit summary if present) to inform this — do not just copy the title. Keep summaries under ~200 characters for tooltip readability.
- **Stage**: one of: Open, Closed (not merged), In main, In main (via development), In development only, etc.
- **Reverted?**: "Yes — #<num>" if reverted, otherwise "No"

Then, if any stacks were detected, append a section like:

**Stack context:**

- Stack "<name>": #1234 (merged), #1235 (merged), #1236 (open), #1237 (open)

Process all PRs in the list before returning.

````
---

Launch all repo sub-agents in parallel. Wait for all to return before proceeding.

### Step 4: Summarize Results

Using the event data, PR/issue lists, PR research results, and time entries, present a combined summary organized by person.

#### 4a: Correlate data into work activities

Look across all data sources and identify distinct pieces of work:

- **Events are the primary source of truth** for what the user actually did. Use `type` and `action` to understand each action (see Step 2 for the mapping).
- Cross-reference MERGED PRS with events — a merged PR may not have a `PullRequestEvent` in the window if it was opened earlier.
- Cross-reference ASSIGNED ISSUES with events — if the member commented or closed an assigned issue, note it.
- Cross-reference ISSUE EDITS with time entries — if the user edited issue bodies on the same date as a time entry, those edits are likely what the time entry describes. Group bulk edits to the same repo (e.g. 45 issues in `integrations` edited on one day) into a single theme.
- **Split time entry notes first.** Before correlating, split each time entry's `notes` field on semicolons and commas into individual sub-activities. Treat each sub-activity as its own work item to cross-reference independently against PRs, issues, and events.
- Match each sub-activity (and whole-entry `projectName`) to GitHub repos, PR numbers, or issue titles where the connection is clear. Do **not** force matches.
- Group related PRs into themes (e.g. "auth hardening", "onboarding improvements").
- **Every sub-activity must appear in the report.** If a sub-activity matches a PR or event, include it in the relevant theme. If it does not match anything, it must appear as a standalone item — either in "Other tracked work" or (if it warrants a dedicated theme) as its own theme. Do not silently absorb unmatched sub-activities into an adjacent theme.

#### 4b: Look up missing PR/issue titles

Before writing the summary, ensure every PR and issue referenced has a title. Titles may be `null` in event data. For anything still missing after checking OPEN/MERGED PRS and ASSIGNED ISSUES:

```bash
gh pr view {number} --repo {org}/{repo} --json title -q .title
gh issue view {number} --repo {org}/{repo} --json title -q .title
```

Run these lookups in parallel where possible.

#### 4b.ii: Enrich vague time entries using issue edits, events, and GitHub search

For any time entry whose `notes` field contains **no explicit PR or issue number** (i.e., no `#NNN`) and does **not** clearly match an already-fetched PR title or issue title:

**Step 1 — check ISSUE EDITS first.** Look through the `ISSUE EDITS` section for edits on the same date as the time entry. If found, the time entry likely describes that editing work. For bulk edits (many issues in the same repo on the same day), summarize as a single theme (e.g. "Edited 45 integration issues in beeminder/integrations — added spoiler formatting").

**Step 2 — scan already-fetched events.** Look through the `GITHUB EVENTS` data for events on the same date. An `IssueCommentEvent`, `PushEvent`, `IssuesEvent`, or `PullRequestReviewEvent` on that date is likely what the person was doing. Use the event's `title`, `html_url`, and `number` to annotate the time entry.

**Step 3 — fall back to GitHub search only if neither resolves it.** Extract meaningful keywords from the note (skip generic words like "fix", "work on", "update", "programming") and search:
```bash
gh api search/issues -X GET \
  -f q="<keywords> org:<GITHUB_ORG>" \
  -f per_page=5 \
  --jq '.items[] | {number, title, html_url, state, repository_url}'
```
If a clear match is found (result title substantially overlaps with note text), annotate with the issue/PR link and title.

**Step 4 — if still unresolved**, report the note as-is. Do not fabricate a description.

Run all searches in parallel where there are multiple vague entries.

#### 4c: Organize the report by outcome, not by person

The report is **organized by what the reader does with each part**, not by who did the work. One person's name appearing five times is not structure; "this needs your decision" versus "this shipped" is. Contributors are named once in the masthead.

Sections, in this order:

1. **Waiting on a decision** — the asks that survived 4d. The only visually loud part of the page. Omit the section entirely when nothing survives.
2. **Shipped** — merged PRs, grouped into themes rather than listed one per PR. One line of prose per theme; anything longer goes in a `<details class="more">` disclosure.
3. **In flight** — open PRs, each with a status chip (`Your call` / `Ready for review` / `Draft · blocked`) and one line saying what it is waiting on.
4. **Worth a look** — observations that are not asks. Things the user owes, conventions awaiting someone else, anything odd. Say plainly when an item is the user's own to do.
5. **Time** — see the billing-basis rules above.

**Closed without merging** is not a section. Fold those into Worth a look with one line each, or omit them; abandoned work rarely earns a heading.

**Every visible line is one sentence.** If a theme needs three sentences, the first goes on the page and the rest go in a disclosure. The old per-person format failed because it put every sentence on the page at once.

**Contributors line.** Name people once, in the masthead: who was active, then, in muted text, who had no activity. Someone with nothing to report gets a name in a list, never a section or a card of their own.

#### 4d: Grill the user on every ask before it goes in the report

The report's decision section (`{{DECISIONS_SECTION}}`) is the only part that demands something of the client. It is worth nothing if it cries wolf — a list that reads as urgent every month trains the client to skip it. So no candidate ask goes into the report until the user has defended it.

**First, filter without asking.** Kill or demote these yourself; do not spend a question on them.

- **Not actually blocked on the client.** If the user can move it without them, it is his to-do, not an ask. This is the most common false positive: "needs review" is usually a scheduling fact, not a decision.
- **Answerable from GitHub.** If the PR body, issue thread, review state, or CI already says what is blocked and on whom, go read it. Never ask the user what the data can tell you.
- **Already answered.** Check the previous report in `<OUTPUT_DIR>` (`ls -1 <OUTPUT_DIR>/*.md | sort | tail -1`) and grep its ask section. If the same ask appeared and has since moved, drop it.
- **Better asked in person.** A permission grant, an access request, a favour, anything whose natural home is a message or a conversation — put it in Taskwarrior for the user to raise directly, not in the report. A report ask has to survive being read cold with no one to answer a follow-up question, which is exactly what makes small interpersonal asks read as vague. Load the `taskwarrior` skill and add the task rather than printing the ask.
- **Nothing changes if they don't decide.** An ask needs a cost to waiting. No cost, no ask — move it to "worth a look".

**Then grill what survives, one ask at a time**, using `AskUserQuestion`. Never batch them; the point is that the user considers each ask on its own.

For each, state in the question: the ask as it would be printed, precisely what is blocked behind it, and what it costs to keep waiting. Then offer:

- **Keep** — goes in as written.
- **Reword** — the ask is real but the framing overstates it; collect the user's wording.
- **Demote** — real but not blocking; moves to "worth a look".
- **Drop** — not an ask.

Give a recommendation with each question, as the first option and marked `(Recommended)`.

**Push back where the data does.** This is a grilling, not a survey. If the user keeps an ask the evidence does not support — a PR nobody is actually waiting on, a decision he could make himself, a "blocker" whose cost he cannot name — say so once, plainly, with the evidence, then take his answer and move on. He has context the GitHub data does not.

**Enforce scarcity.** More than three surviving asks is itself the wolf-crying signal. If more than three survive, ask which single one matters most this period and demote the rest; a client who reads one ask and acts is worth more than one who reads six and does nothing.

**Flag repeats explicitly.** If an ask also appeared in the previous report, say so in the question ("this is the 3rd report carrying this ask"). A repeat means either the client is not reading the section or the ask is not really important — both are worth naming in the report itself rather than silently restating it.

**If the user is not present** (the skill is running unattended), do not invent approval. Write the ask section with only the asks that pass the filter above, and note at the top of the section that it has not been reviewed.

### Step 5: Generate HTML Report

1. Create the output directory:
   ```bash
   mkdir -p <OUTPUT_DIR>
````

2. Get a timestamp for the filename:

   ```bash
   date +"%Y-%m-%dT%H-%M-%S"
   ```

3. Read the HTML template at `~/.claude/skills/client-report/report-template.html`.

4. Populate the template placeholders with the report data gathered in Steps 2–4:
   - Replace `{{REPORT_TITLE}}` with "<CLIENT_NAME> Activity, <Mon>&ndash;<Mon YYYY>" (e.g. "Acme Activity, Aug&ndash;Sep 2026") so each report is identifiable in the artifact gallery
   - Replace `{{PERIOD_START}}` and `{{PERIOD_END}}` with the date range boundaries
   - Replace `{{DAYS}}` with the lookback period in days
   - Replace `{{FOOTER_TIMESTAMP}}` with a human-readable date, and `{{CLIENT_NAME}}` with the client's display name
   - `{{SCOREBOARD}}` — one `<div class="score">` per figure: shipped, in flight, decisions (add `is-decision` to the div so the number takes the accent), and the hours figure. Use the billing basis's headline number: billable for `tracked+agent`, tracked for `tracked`.
   - `{{CONTRIBUTORS}}` — a `<span>` naming who was active, then `<span class="quiet">` spans for who was not, and any single-line counts worth keeping (e.g. assigned-issue totals).
   - `{{DECISIONS_SECTION}}` — a `<section>` of `<div class="decision">` blocks, each with `.ask` (the decision as a question or imperative), a `.ref` link, and `.why` giving what is blocked and what waiting costs. Omit the whole section when 4d leaves nothing.
   - `{{SHIPPED_SECTION}}` / `{{INFLIGHT_SECTION}}` — `<section>` wrapping `.rows` of `.row` blocks: `.repo` on the left, then `.line` (chip + `.what` + `.ref` links) and one `.sub` sentence. Extra depth goes in `<details class="more">`.
   - `{{WATCH_SECTION}}` — a `<ul class="watch">`; add `class="hot"` to at most one item.
   - `{{TIME_SECTION}}` — the `.split` equation, the tracked entries, and a disclosure deriving the figure.
   - Section note slots take a count only — see the rule above.
   - For PR references use `<a class="ref" href="...">#NUM</a>`. Chips: `chip-ship`, `chip-review`, `chip-decision`, `chip-stalled`.

5. Write the populated HTML to `<OUTPUT_DIR>/<timestamp>.html`.

6. Write a Markdown version to `<OUTPUT_DIR>/<timestamp>.md` (same timestamp), carrying the same content and the same section order:
   - `#` title, then period / generated lines, the one-line stat row, and the contributors line
   - `##` per section: Waiting on a decision, Shipped, In flight, Worth a look, Time
   - Bold lead-in per item, then its sentence; disclosure content becomes a trailing italic sentence or a nested bullet
   - `[#NUM](https://github.com/<GITHUB_ORG>/REPO/pull/NUM)` for PR links
   - No tables — the sections are lists, and a table of asks reads as a bug tracker

7. **Publish the HTML report as an Artifact.**

   Call the `Artifact` tool with `file_path` set to the HTML report written in step 5. Artifacts are private to the user by default, so no consent prompt is needed.

   - Do **not** pass `url`. Each report gets its own artifact and its own link, mirroring the old per-timestamp URLs. The files under `<OUTPUT_DIR>` remain the archive; the artifact is the shareable view.
   - Leave `title` off — the template's `<title>` already carries the client and period.
   - `description`: one sentence naming the client and the period covered.
   - `favicon`: one emoji, chosen per client and reused for that client's later reports so they are recognizable in the gallery.

   To let someone outside share the link, the user shares it from the artifact page's own share menu.

8. Tell the user the artifact URL and the full paths of both generated report files.

## Client Config Format

Each client config JSON file supports these fields:

```json
{
  "name": "Acme Corp",
  "aliases": ["acme", "ac"],
  "github_org": "acme-corp",
  "team_members": [
    { "github": "alice", "narthbugz_id": 3 },
    { "github": "bob" }
  ],
  "narthbugz_client_name": "Acme Corp",
  "billing_basis": "tracked",
  "narthbugz_client_id": 42,
  "output_dir": "/path/to/reports",
  "default": false
}
```

`team_members` may also be a plain array of strings (treated as GitHub usernames with no narthbugz_id). Time tracking is skipped unless both `narthbugz_client_name` is set and at least one member has a `narthbugz_id`.

## Tips

- If a user has no activity at all, note that briefly rather than omitting them
- Call out any stale PRs or issues that may need attention
- For longer time periods (30+ days), consider grouping by week
- If a PR was closed without merging, check the PR research sub-agent output — the body often explains why
- Flag any merged PR that is "In development only" as potentially needing attention if it has been there for several days
- The Events API covers the last ~300 events per repo; for low-activity repos or short windows this is fine, but always cross-reference with MERGED PRS (Search API) to catch PRs merged in the window that predate the event window
- After generating the reports, mention the file paths so the user can open the HTML in a browser or share the Markdown
