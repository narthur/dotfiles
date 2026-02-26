---
name: client-report
description: "Generate a summary of GitHub activity for a configured client team. Shows PRs and issues each team member has been involved with. Default is last 7 days; specify a number of days to change the lookback period. Use when asked about team activity, what people have been working on, or to get a status update. Client configs live at ~/.claude/skills/client-report/clients/."
---

You are helping the user get a summary of GitHub activity for a client team.

## What You Do

- Load the appropriate client config from `~/.claude/skills/client-report/clients/`
- Run `user-org-report` for each team member in the config
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
   - `TEAM_MEMBERS` — array of objects, each with `github` (GitHub username) and optional `narthbugz_id`
   - `NARTHBUGZ_CLIENT_NAME` — Narthbugz `clientName` to filter time entries (may be absent; skip time tracking if so)
   - `OUTPUT_DIR` — local directory path for saving reports
   - `SURGE_DOMAIN` — Surge.sh domain for publishing

### Step 1: Determine Lookback Period

Parse the user's request for a number of days. Default to **7 days** if not specified.

### Step 2: Run Reports

Run `user-org-report` for each team member in `TEAM_MEMBERS` in parallel, using the `github` field from each member object:

```bash
user-org-report <member.github> <GITHUB_ORG> --days <N>
```

Where `<N>` is the number of days (default 7).

### Step 2b: Fetch Time Tracking Data

Skip this step if `NARTHBUGZ_CLIENT_NAME` is not set in the config, or if no team members have a `narthbugz_id`.

For each team member who has a `narthbugz_id`, fetch their time entries **in parallel** using the helper script:

```bash
~/.claude/skills/client-report/narthbugz-entries <narthbugz_id> "<NARTHBUGZ_CLIENT_NAME>" <N>
```

Where `<N>` is the lookback period in days (default 7).

The script handles credential loading from `~/.env`, auth header construction, API calls, and date/client filtering. It outputs a JSON array of `{taskName, projectName, clientName, hours, notes, date}` objects, or `[]` if credentials are missing or the call fails.

Store the resulting arrays keyed by GitHub username for use in Steps 4 and 5. If the script returns an empty array for a member, note the absence — do not abort the report.

### Step 3: Research PRs with Sub-agents

From the reports, collect all PRs where any team member has `A` (author) in their `Inv` column. Group these by repo.

For each repo that has authored PRs, launch a **parallel** sub-agent (subagent_type: `general-purpose`) to research all authored PRs in that repo. Give each sub-agent the following prompt, substituting the actual values:

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

Using both the raw report data and the PR research results, present a combined summary organized by person. For each person, include two sections:

**What they've been working on:**
Synthesize their **merged** PRs into a functional narrative. Group related work into themes (e.g. "security hardening", "test infrastructure", "onboarding flow improvements"). For each theme, use the PR summaries from the sub-agents to describe *what changed and why* at a product/engineering level — not just PR titles. Include the PR stage (e.g. "landed in main", "in development branch") where relevant. Aim for 3–5 bullet points per person.

**Important:** PRs that were **closed without merging** are NOT completed work — they represent abandoned, superseded, or deferred efforts. Do NOT include them in "What they've been working on." Instead, briefly note them in a separate **Closed without merging** subsection, explaining why they were closed if the PR body or sub-agent research provides that context (e.g. "superseded by #1234", "approach abandoned"). If there are none, omit this subsection.

**What they still have to do:**
List their open PRs and open issues, grouped by theme where possible. For each open PR, include the sub-agent's summary and note whether it's draft, awaiting review, or blocked. This should read as a to-do list, not a raw data dump.

Also include a brief **Reviewing** note if the person was active as a reviewer on others' work.

**Time tracking context (if available):**
If time entries were fetched in Step 2b, incorporate them into the narrative:
- Calculate each person's **total hours** tracked against this client over the period and note it in their section header (e.g. "32.5h tracked").
- Where a time entry's `notes` or `projectName` clearly maps to a PR or theme (by repo name, PR/issue number mention, or topic match), annotate the relevant theme with hours (e.g. "~6h").
- Do **not** force a match — only annotate when the connection is clear. Unmatched time entries can be listed briefly as "Other tracked work" at the end of the person's section.
- If time data was unavailable for a member, note it briefly (e.g. "Time tracking unavailable").

Keep the summary concise but informative. Highlight any PRs that are blocked, stale, or unexpectedly not in main.

**Important — do not infer stack completeness:**

The reporting window only shows recently-updated PRs. A PR stack may have members that fall outside the window. **Never claim a PR is the "last" or "only remaining" part of a stack** unless the sub-agent's "Stack context" section confirms the full list of stack members and their states. If a PR mentions being "part N of M", report that fact as-is (e.g. "part 8 of a 9-PR stack") and use the stack context to accurately describe how many remain open.

**Important — interpreting the `Inv` column:**

The `Inv` column in each report shows how that specific user was involved:
- `A` = author (they opened the PR)
- `C` = committer
- `R` = reviewer
- `M` = commenter

The same PR can appear in multiple people's reports with different `Inv` flags. When writing the summary or an "Items Needing Attention" table, **always attribute a PR to the person who has `A` in their Inv column**, not the person whose report you happened to read first. Do not infer ownership from report order.

Example: If PR #123 shows `R` for alice and `A C` for bob, the PR is *owned by bob* and *reviewed by alice*.

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
           <a
             href="https://github.com/<GITHUB_ORG>/REPO/pull/2127"
             data-tooltip="Fixed off-by-one error in weekly view boundary calculations."
             >#2127</a
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
         <p class="todo-detail">Part 8 of the GitButler stack.</p>
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
         >) and carol's work (<a
           href="https://github.com/<GITHUB_ORG>/REPO/pull/2240"
           data-tooltip="Updated CSV import to handle bulk uploads."
           >#2240</a
         >,
         <a
           href="https://github.com/<GITHUB_ORG>/REPO/pull/2221"
           data-tooltip="Fixed pagination bug in list view."
           >#2221</a
         >).
       </div>
     </div>
     ```

     Omit subsections that have no content (e.g. skip "Closed without merging" if there are none).
     The **stat-bar** counts should reflect the person's actual totals: merged PRs, open PRs, closed-without-merging PRs, open issues, and hours tracked (omit the time chip if time data is unavailable for that member).
     Each **theme-item** groups related work with the theme name and badge on one line, a narrative summary below, and PR links as clickable chips.
     **closed-item** blocks are visually muted to de-emphasize abandoned work.
     **todo-item** blocks show badge + PR ref on one line with description below, reading as a checklist.
     **issue-list** displays issue references compactly inline, separated by middots.
     **review-note** wraps the reviewing summary in a styled box.

   - For PR references, use `<a href="https://github.com/<GITHUB_ORG>/REPO/pull/NUM" data-tooltip="SUMMARY">#NUM</a>` links, where SUMMARY is the sub-agent's 1–2 sentence summary for that PR. HTML-entity-encode any quotes (`&quot;`), ampersands (`&amp;`), and angle brackets (`&lt;` `&gt;`) inside the attribute value. This powers CSS-only hover tooltips in the report.
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

## Tips

- If a user has no activity, note that briefly rather than omitting them
- Call out any stale PRs or issues that may need attention
- For longer time periods (30+ days), consider grouping by week
- If a PR was closed without merging, check the PR research sub-agent output — the body often explains why (e.g. superseded by another PR)
- Flag any merged PR that is "In development only" as potentially needing attention if it has been there for several days
- After generating the reports, mention the file paths so the user can open the HTML in a browser or share the Markdown
