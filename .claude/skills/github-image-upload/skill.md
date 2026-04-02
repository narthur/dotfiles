# GitHub Image Upload

Upload local images for use in GitHub PR/issue comments. Produces permanent `user-attachments` URLs that render inline in markdown on both public and private repos.

## How It Works

Uses Playwright to inject images into GitHub's file-attachment input on a PR/issue page, which triggers GitHub's own upload pipeline. The resulting URLs are on `github.com/user-attachments/assets/` — the same as drag-and-drop in the web UI.

## Prerequisites

1. A **headed** Playwright browser session logged into GitHub
2. The browser must have a GitHub PR or issue page open (needs the comment form)
3. The `playwright` npm package must be available (e.g., in a project's `node_modules`)

## Setup (one-time)

### GitHub Auth State

If `~/.claude/playwright-github-auth.json` exists, load it. Otherwise:

```bash
npx playwright-cli open --browser chromium --headed https://github.com/login
# User logs in manually in the headed browser
npx playwright-cli state-save ~/.claude/playwright-github-auth.json
```

## Step-by-Step Upload Process

### 1. Open a headed browser with GitHub auth

```bash
npx playwright-cli open --browser chromium --headed
npx playwright-cli state-load ~/.claude/playwright-github-auth.json
npx playwright-cli goto https://github.com/OWNER/REPO/pull/NUMBER
```

### 2. Find the CDP port

```bash
pgrep -af 'remote-debugging-port' | grep -oP '(?<=remote-debugging-port=)\d+'
```

### 3. Upload images

The upload script is at `~/.claude/skills/github-image-upload/upload.js`.

```bash
NODE_PATH=./node_modules node ~/.claude/skills/github-image-upload/upload.js <cdp-port> image1.png image2.png ...
```

If the current project doesn't have playwright, point NODE_PATH to one that does:

```bash
NODE_PATH=/path/to/project/node_modules node ~/.claude/skills/github-image-upload/upload.js <cdp-port> image1.png
```

**Output:** One URL per line to stdout:
```
https://github.com/user-attachments/assets/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### 4. Use the URLs in comments

```bash
gh pr comment NUMBER --body "![description](URL_FROM_STEP_3)"
```

### 5. Close the browser when done

```bash
npx playwright-cli close
```

## Notes

- URLs are permanent — no cleanup needed (unlike release assets or branch-hosted images)
- Works for private repos — URLs are accessible to anyone with repo access
- The comment textarea is cleared after each upload; no accidental comments are posted
- Supports png, jpg, gif, webp, svg
