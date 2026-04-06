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
   - `NARTHBUGZ_CLIENT_NAME` — Narthbugz `clientName` to filter time entries (may be absent; skip time tracking if so)
   - `OUTPUT_DIR` — local directory path for saving reports
   - `SURGE_DOMAIN` — Surge.sh domain for publishing

### Step 1: Determine Lookback Period

Parse the user's request for a number of days. Default to **7 days** if not specified.

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
Use this logic:

- If state is OPEN → stage is "Open"
- If state is CLOSED (not merged, mergedAt is null) → stage is "Closed (not merged)"
- If state is MERGED:
  - Note the baseRefName (the branch it merged into)
  - If baseRefName is "main" → stage is "In main"
  - Otherwise (e.g. "development", "dev") → check if the merge commit reached main:

    ```bash
    gh api repos/<GITHUB_ORG>/<REPO>/compare/main...<mergeCommit.oid> --jq '{status:.status,ahead:.ahead_by}'
    ```

    - If `ahead == 0` → stage is "In main (via <baseRefName>)"
    - If `ahead > 0` → stage is "In <baseRefName> only (not yet in main)"

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

#### 4c: Write the per-person summary

For each person, include these sections:

**What they've been working on:**
Synthesize their **merged** PRs and completed work (from events) into a functional narrative. Group related work into themes. For each theme, use the PR summaries from the sub-agents to describe *what changed and why* at a product/engineering level. Include the PR stage where relevant. Aim for 3–5 bullet points per person.

**Important:** PRs that were **closed without merging** are NOT completed work. Do NOT include them here. Instead, briefly note them in a separate **Closed without merging** subsection (explain why if the PR body provides context). Omit if none.

**What they still have to do:**
List their open PRs and assigned issues, grouped by theme where possible. For each open PR, include the sub-agent's summary and note whether it's draft, awaiting review, or blocked. Read as a to-do list.

**Reviewing:**
If the person has `PullRequestReviewEvent` or `PullRequestReviewCommentEvent` events on PRs they didn't author, include a brief note about what they reviewed.

**Time tracking context (if available):**
- Calculate total hours tracked for this client in the period and note in the section header (e.g. "12.5h tracked").
- Annotate themes with hours where the match is clear.
- List unmatched sub-activities (and whole entries with no match) briefly as "Other tracked work." Every tracked sub-activity must appear somewhere in the report — never drop one silently.
- If time data was unavailable, note it (e.g. "Time tracking unavailable").

**Important — do not infer stack completeness:**

Never claim a PR is the "last" or "only remaining" part of a stack unless the sub-agent's "Stack context" section confirms the full list. Report stacks as-is (e.g. "part 4 of a 9-PR stack").

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
   - Replace `{{REPORT_TITLE}}` with "<CLIENT_NAME> Team Activity Report"
   - Replace `{{PERIOD_START}}` and `{{PERIOD_END}}` with the date range boundaries
   - Replace `{{DAYS}}` with the lookback period in days
   - Replace `{{GENERATED_AT}}` and `{{FOOTER_TIMESTAMP}}` with a human-readable timestamp
   - Replace `{{PERSON_SECTIONS}}` with HTML blocks for each person, using this structure:

     ```html
     <div class="person-card">
       <h2>Person Name</h2>
       <div class="stat-bar">
         <span class="stat stat-merged">14 merged</span>
         <span class="stat stat-open">1 open</span>
         <span class="stat stat-closed">3 closed</span>
         <span class="stat stat-issues">8 issues</span>
         <span class="stat stat-time">32.5h tracked</span>
       </div>

       <h3>What they've been working on</h3>
       <div class="theme-item">
         <div class="theme-header">
           <span class="theme-name">Calendar/State Management Refactoring</span>
           <span class="badge badge-in-main">In main</span>
         </div>
         <p class="theme-summary">
           Completed parts 3-8 of a GitButler stack overhauling frontend
           calendar state — testability, null safety, and edge case fixes.
         </p>
         <div class="theme-prs">
           <a
             href="https://github.com/<GITHUB_ORG>/REPO/pull/2124"
             data-tooltip="Refactored calendar state into a testable store, removing tight coupling to UI components."
             >#2124</a
           >
           <a
             href="https://github.com/<GITHUB_ORG>/REPO/pull/2126"
             data-tooltip="Added null-safety guards to calendar date ranges to fix edge-case crashes."
             >#2126</a
           >
         </div>
       </div>
       <!-- Repeat .theme-item for each theme -->

       <h3>Closed without merging</h3>
       <div class="closed-item">
         <a
           href="https://github.com/<GITHUB_ORG>/REPO/pull/2023"
           data-tooltip="Migrated component styles from global CSS to CSS Modules for better encapsulation."
           >#2023</a
         >
         — CSS Modules migration. Likely superseded or deferred.
       </div>

       <h3>What they still have to do</h3>
       <div class="todo-item">
         <div class="todo-header">
           <span class="badge badge-open">Open PR</span>
           <a
             href="https://github.com/<GITHUB_ORG>/REPO/pull/2131"
             data-tooltip="Extracts CalendarToggleTracker into a standalone helper for reuse across views."
             >#2131</a
           >
           — Extract CalendarToggleTracker into helper
         </div>
         <p class="todo-detail">Awaiting review.</p>
       </div>
       <!-- Repeat .todo-item for each open PR -->
       <h4>Open Issues</h4>
       <div class="issue-list">
         <a href="https://github.com/<GITHUB_ORG>/REPO/issues/2241">#2241</a>
         Display user email &middot;
         <a href="https://github.com/<GITHUB_ORG>/REPO/issues/2216">#2216</a>
         Flaky Test Tracker
       </div>

       <h3>Reviewing</h3>
       <div class="review-note">
         Reviewed bob's dark mode feature PR (<a
           href="https://github.com/<GITHUB_ORG>/REPO/pull/2198"
           data-tooltip="Adds dark mode support across all dashboard views."
           >#2198</a
         >) and carol's CSV import (<a
           href="https://github.com/<GITHUB_ORG>/REPO/pull/2240"
           data-tooltip="Updated CSV import to handle bulk uploads."
           >#2240</a
         >).
       </div>
     </div>
     ```

     Omit subsections that have no content.
     The **stat-bar** counts should reflect the person's actual totals: merged PRs, open PRs, closed-without-merging PRs, open issues, and hours tracked (omit the time chip if time data is unavailable).
     Each **theme-item** groups related work with the theme name and badge on one line, a narrative summary below, and PR links as clickable chips.
     **closed-item** blocks are visually muted to de-emphasize abandoned work.
     **todo-item** blocks show badge + PR ref on one line with description below, reading as a checklist.
     **issue-list** displays issue references compactly inline, separated by middots.
     **review-note** wraps the reviewing summary in a styled box.

   - For PR references, use `<a href="https://github.com/<GITHUB_ORG>/REPO/pull/NUM" data-tooltip="SUMMARY">#NUM</a>` links, where SUMMARY is the sub-agent's 1–2 sentence summary. HTML-entity-encode quotes (`&quot;`), ampersands (`&amp;`), and angle brackets (`&lt;` `&gt;`) inside the attribute value.
   - For issue references, use `<a href="https://github.com/<GITHUB_ORG>/REPO/issues/NUM">#NUM</a>` links. Do **not** add `data-tooltip` to issue links.
   - For stage badges, use `<span class="badge badge-open">Open</span>`, `<span class="badge badge-merged">Merged</span>`, `<span class="badge badge-in-main">In main</span>`, `<span class="badge badge-closed">Closed</span>`, or `<span class="badge badge-dev-only">In dev only</span>` as appropriate.
   - Replace `{{ATTENTION_SECTION}}` with items needing attention inside the `.attention-section` div, or remove it if there are none.

5. Write the populated HTML to `<OUTPUT_DIR>/<timestamp>.html`.

6. Write a Markdown version of the report to `<OUTPUT_DIR>/<timestamp>.md` (same timestamp as the HTML file). The Markdown report should contain the same content as the HTML report but in plain Markdown format:
   - Use `#` for the report title, `##` for person names, `###` for subsection headings
   - Use `- ` bullet lists for the narrative sections
   - Use `[#NUM](https://github.com/<GITHUB_ORG>/REPO/pull/NUM)` for PR links
   - Use markdown tables for the "Items Needing Attention" section
   - Include the date range, lookback period, and generation timestamp at the top

7. Deploy the reports directory to Surge:

   ```bash
   npx surge <OUTPUT_DIR> <SURGE_DOMAIN>
   ```

8. Tell the user the full file paths of both generated reports, and provide the public URL to the HTML report:
   ```
   https://<SURGE_DOMAIN>/<timestamp>.html
   ```

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
  "output_dir": "/path/to/reports",
  "surge_domain": "acme-report.surge.sh",
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
