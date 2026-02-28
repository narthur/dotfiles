---
name: playwright
description: "Browser automation using playwright-cli. Use when asked to open a browser, navigate to a URL, click elements, fill forms, take screenshots, scrape web content, or automate browser interactions."
---

# Playwright Browser Automation

You are a browser automation agent. Use `playwright-cli` to control web browsers for the user.

`playwright-cli` is installed as a pinned wrapper at `~/.local/bin/playwright-cli` and works from any directory regardless of the project's node version.

## CRITICAL: Session Management

Always use **named sessions** (`-s=name`) so the user can observe the browser with `playwright-cli show`. Choose short, descriptive session names (e.g., `-s=main`, `-s=login`, `-s=scrape`).

## Workflow

### Step 1: Open a browser session

Always open the session first, then navigate. `goto` will fail if the session isn't open yet.

```bash
playwright-cli open -s=main
playwright-cli goto https://example.com -s=main
```

### Step 2: Interact with the page

After each command, playwright-cli returns a **snapshot** of the page. Read the snapshot to understand the current state before issuing the next command.

```bash
# Click an element (use ref from snapshot, e.g. ref=e12)
playwright-cli click ref=e12 -s=main

# Type text into focused element
playwright-cli type "hello world" -s=main

# Fill a form field by ref
playwright-cli fill ref=e5 "my@email.com" -s=main

# Select a dropdown option
playwright-cli select ref=e8 "Option Label" -s=main

# Press a key
playwright-cli press Enter -s=main

# Scroll the page
playwright-cli scroll down -s=main
```

### Step 3: Capture page state

```bash
# Take a screenshot (returns image path)
playwright-cli screenshot -s=main

# Get a full DOM snapshot
playwright-cli snapshot -s=main

# Export page as PDF
playwright-cli pdf -s=main
```

### Step 4: Manage sessions

```bash
# List active sessions
playwright-cli list

# Open the visual dashboard to watch the browser
playwright-cli show

# Close all sessions when done
playwright-cli close-all
```

## Commands Reference

| Command | Purpose |
|---------|---------|
| `open [url] -s=name` | Launch browser, optionally at URL |
| `goto <url> -s=name` | Navigate to URL |
| `click <ref> -s=name` | Click an element |
| `type <text> -s=name` | Type text into focused element |
| `fill <ref> <text> -s=name` | Fill a form field |
| `select <ref> <val> -s=name` | Choose a dropdown option |
| `press <key> -s=name` | Press a keyboard key |
| `scroll <dir> -s=name` | Scroll the page |
| `screenshot -s=name` | Capture screenshot |
| `snapshot -s=name` | Get full page state |
| `pdf -s=name` | Export as PDF |
| `list` | List active sessions |
| `show` | Open visual dashboard |
| `close-all` | Close all sessions |

## Handling Login / Authentication

Playwright runs its own browser (separate from the user's system Firefox/Chrome), so it does not inherit existing browser sessions.

### Option A: Headed mode — log in once per session

Open in `--headed` mode so the user can see the browser and log in manually. Pause and ask the user to confirm when done before continuing.

```bash
playwright-cli open --headed -s=main
# → ask the user to log in, wait for confirmation
playwright-cli goto https://app.example.com/dashboard -s=main
```

### Option B: Save and restore auth state (recommended for repeat tasks)

Log in once with headed mode, save the state, and load it for future sessions — no re-login required.

```bash
# One-time setup (ask user to do this if a saved state doesn't exist):
playwright-cli open --headed -s=login
# → user logs in manually, then confirms
playwright-cli state-save ~/.playwright-auth/sitename.json -s=login
playwright-cli close -s=login

# Future sessions — load saved state:
playwright-cli open -s=task
playwright-cli state-load ~/.playwright-auth/sitename.json -s=task
playwright-cli goto https://app.example.com -s=task
```

Store saved states in `~/.playwright-auth/` named by site (e.g. `github.json`, `gmail.json`).

**When to use which:**
- Use **Option A** for one-off tasks or when auth state isn't saved yet
- Use **Option B** for recurring automated tasks

**Note:** `--browser firefox` launches playwright's own Firefox binary, not the user's system Firefox — it will not inherit system browser sessions either way.

## Site-Specific References

Before automating a site, check `references/` for saved notes on that site's scroll behavior, selectors, and known quirks:

- [YouTube Music](references/youtube-music.md) — scroll behavior, playlist extraction, known bugs
- [YouTube](references/youtube.md) — liked videos extraction, Videos/Shorts filter tabs, scrolling

## Tips

- Element refs (e.g. `ref=e12`) come from the snapshot output after each command — always read the snapshot before acting
- Always ask the user to confirm they've finished logging in before continuing after `--headed` open
- For scraping, prefer `snapshot` over `screenshot` — it gives structured text the model can parse
- Use `playwright-cli --help` to see all available commands

## Maintenance

If the wrapper breaks (e.g., after upgrading node or reinstalling packages), run:

```bash
~/.claude/skills/playwright/setup.sh
```
