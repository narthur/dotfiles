---
name: ui-mockups
description: Produce low-fi UI wireframes/mockups as HTML/CSS, render them to a PNG, and (optionally) host the image and embed it in a GitHub issue/PR. Use when asked to mock up a screen/flow, wireframe a feature, sketch a UI, or attach visual mockups to an issue. Match the target app's real design idiom (theme colors, fonts, component style) when one exists.
---

# UI Mockups

Make rough-but-on-brand UI mockups without a design tool. The deliverable is a single PNG (often a filmstrip of screens) that renders inline in a GitHub issue/PR.

The pipeline, proven end to end:

**author HTML/CSS → render with playwright → screenshot → host with surge → embed with `gh`**

## 1. Match the app's design idiom first

A mockup that looks like the real app is worth far more than a generic one. Before writing HTML, extract the design language from the codebase:

- **Theme tokens**: primary/secondary colors (hex), light/dark mode, font family. For MUI apps look for `createTheme`; for Tailwind look at the config; otherwise grep for a `theme`/`colors`/`constants` file.
- **Component look**: how buttons, inputs, cards, list items actually render. Copy the real border/spacing/elevation, button casing (MUI buttons are UPPERCASE), input style (e.g. MUI "standard" text fields have an underline, not a box).

A subagent (e.g. `Explore`) is good for this: ask it for hex colors, font names, and short JSX/markup snippets — not whole files.

If there's no existing app, just go clean and neutral; say so.

## 2. Author the HTML

One self-contained `.html` file, no build step. Tips that held up:

- Lay screens out in a CSS `grid` of fixed-width "phone" frames (≈360px) so one screenshot shows the whole flow.
- Pull a webfont via `@import` (e.g. Roboto for MUI) so text matches.
- A short title/subtitle line at the top stating what this is and which issues it maps to.
- Keep it low-fi: this is for sequencing and intent, not final pixels. Label it as such.
- **Watch wrapping**: inline `<b>` mid-sentence can wrap into accidental "columns" and look janky. Prefer whole-sentence emphasis, set `line-height` on callout/alert boxes, and re-check the rendered image.
- Make copy *true*. Don't advertise features that don't exist or misstate behavior — verify product claims before putting them on a screen.

Write the file under a scratch dir (e.g. the session scratchpad or `/tmp/<name>/`), not the repo.

## 3. Render + screenshot (playwright skill)

Use the `playwright` skill's CLI. Two gotchas on this machine, both handled below:

- Default browser `chrome` may not be installed → use `--browser firefox` (playwright's bundled binary).
- Firefox **blocks `file://`** → serve the file over local HTTP.

```bash
cd /tmp/<name> && python3 -m http.server 8745 >/dev/null 2>&1 &
sleep 1
playwright-cli open --browser firefox -s=mock 2>&1 | tail -1
playwright-cli goto "http://localhost:8745/mockup.html" -s=mock 2>&1 | tail -1
playwright-cli screenshot --full-page --filename /tmp/<name>/mockup.png -s=mock 2>&1 | tail -1
playwright-cli close-all 2>&1 | tail -1
kill %1 2>/dev/null
```

Then `Read` the PNG to eyeball it. Iterate on the HTML and re-run until it's clean. (If chrome *is* installed, you can skip Firefox + the HTTP server and `goto` a `file://` URL directly.)

## 4. Host the image

Use the `surge-image-upload` skill — no login dance, content-addressed, stable URLs, renders in GitHub markdown on private repos too:

```bash
url=$(~/.claude/skills/surge-image-upload/upload.sh /tmp/<name>/mockup.png 2>/dev/null)
```

(Alternative: `github-image-upload` skill gives permanent access-controlled `user-attachments` URLs but needs a logged-in Playwright browser.)

## 5. Embed in the issue/PR

```bash
gh issue comment <n> --body "![mockups]($url)
... per-screen notes, each mapped to the issue it addresses ..."
```

To revise later, edit the comment in place instead of posting a new one:

```bash
gh api --method PATCH repos/<owner>/<repo>/issues/comments/<comment-id> -f body="$(cat <<'EOF'
...new body with new image URL...
EOF
)" -q .html_url
```

Keep the HTML source around (note its path) so screens can be tweaked and re-rendered cheaply.
