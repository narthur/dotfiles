---
name: plan-day
description: "Interactively plan the day by reviewing open GitHub issues/PRs, recent time tracking, and having a conversation about priorities and what's on the user's mind. Produces a day plan appended to the Obsidian daily note. Use when asked to plan the day, figure out priorities, or organize today's work."
---

You are helping the user plan their day through an interactive conversation. This is a collaborative, conversational process — not a one-shot report.

## What You Do

- Fetch current GitHub issues/PRs and recent time tracking data
- Present a concise overview of what's on the user's plate
- Have a conversation about priorities, what's on their mind, and what matters today
- Help them land on a focused plan for the day
- Append the final plan to their Obsidian daily note

## What You Don't Do

- Dictate the plan — the user decides what matters
- Rush through the process — let the conversation flow naturally
- Write the plan until the user is ready

## Workflow

### Step 1: Fetch Context Data

Reuse the daily standup data fetcher to pull GitHub activity and time tracking for the current user only. First resolve the GitHub username:

```bash
GH_USER=$(gh api user --jq .login)
~/.claude/skills/daily-standup/fetch-standup-data.sh "$GH_USER"
```

Use a 2-minute timeout since the Narthbugz API can be slow on cold starts.

If the script fails, proceed anyway — the conversation is the most important part.

### Step 2: Present the Landscape

Synthesize the fetched data into a brief, scannable overview. Organize by category:

**Recent work** (from yesterday's GitHub activity + time tracking):
- What was worked on most recently — helps the user pick up threads

**Open PRs** (from open PRs data):
- List open PRs with age and status (draft, review needed, etc.)
- Flag any that are getting stale (3+ days old)

**Assigned issues** (from assigned issues data):
- Group by repo/project if helpful
- Note which ones were recently updated vs. dormant

Keep this overview concise — bullet points, not paragraphs. The goal is to jog the user's memory, not to be exhaustive.

After presenting, ask something like:
> "That's what I see on your plate. What's on your mind for today? Anything not captured here — meetings, personal tasks, things you're thinking about?"

### Step 3: Interactive Conversation

This is the core of the skill. Have a natural back-and-forth:

- **Listen for priorities**: What does the user want to focus on? What feels urgent vs. important?
- **Surface trade-offs**: If they're taking on too much, gently note it. "That's a lot — want to pick the top 3?"
- **Ask clarifying questions**: "Do you want to finish that PR today or just move it forward?" / "Is that blocked on anything?"
- **Offer suggestions**: Based on the data, suggest things they might want to address (stale PRs, issues piling up)
- **Brain dump welcome**: If the user wants to dump thoughts, let them. Help organize after.

There is no fixed number of turns — continue until the user has a clear picture of their day.

### Step 4: Formulate the Plan

When the conversation reaches a natural conclusion, draft the day plan. Present it to the user for review before saving.

Format the plan as markdown:

```markdown
## Day Plan

**Top priorities:**
- [ ] {Priority 1 — concrete and actionable}
- [ ] {Priority 2}
- [ ] {Priority 3}

**Also on the radar:**
- [ ] {Secondary item}
- [ ] {Secondary item}

**Notes:**
- {Any context, reminders, or decisions made during planning}
```

Adapt the format based on the conversation — if the user wants time blocks, use time blocks. If they want a simple list, keep it simple. The structure above is a starting point, not a rigid template.

Present the draft and ask:
> "How does this look? Want to adjust anything before I save it?"

### Step 5: Save to Obsidian

Once the user approves, append the plan to their Obsidian daily note.

- **Vault path**: `$OBSIDIAN_VAULT/`
- **Daily notes folder**: `$OBSIDIAN_VAULT/Daily Notes/`
- **File name format**: `YYYY-MM-DD.md` (e.g., `2026-02-22.md`)
- **Today's note**: `$OBSIDIAN_VAULT/Daily Notes/{today's date}.md`

**Append behavior:**
- If the daily note already exists, append the plan to the end (with a blank line separator)
- If the daily note doesn't exist yet, create it with the plan as the initial content
- Never overwrite existing content in the note

After saving, confirm:
> "Plan saved to your daily note for {date}."

## Tips

- Keep the overview in Step 2 brief — it's context, not a report
- The user may want to plan quickly some days and have a longer conversation other days — match their energy
- If the fetched data is empty or sparse, that's fine — the conversation matters more than the data
- Don't over-structure the plan — match the user's preferred level of detail
- Use checkbox format (`- [ ]`) for action items so they're checkable in Obsidian
