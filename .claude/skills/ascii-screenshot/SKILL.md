---
name: ascii-screenshot
description: >
  Turn colored terminal / ASCII output (charts, TUIs, CLI output, asciigraph,
  lipgloss/bubbletea views) into a PNG image — preserving ANSI colors — for
  embedding in PRs, issues, docs, or READMEs. Use when asked to screenshot a
  TUI/CLI, capture terminal output as an image, or "add a screenshot" of
  text-based/ASCII output. Pairs with the surge-image-upload skill to host the
  result and `gh` to embed it. Not for GUI/browser screenshots (use playwright).
---

# ASCII / Terminal Screenshot

Render colored terminal output to a PNG. The hard part is **preserving ANSI
colors** (a plain copy-paste into a markdown code block loses them and is
monochrome), and doing it **without a browser or ImageMagick** — which often
aren't installed. This skill does ANSI → HTML → PNG with a zero-install
rasteriser.

## Pipeline

```
ANSI text ──ansi2html.py──▶ HTML ──qlmanage (macOS Quick Look)──▶ PNG
```

`render.sh` runs the whole chain:

```bash
~/.claude/skills/ascii-screenshot/render.sh input.ansi -o /tmp/shot.png
some-command-with-color | ~/.claude/skills/ascii-screenshot/render.sh - -o /tmp/shot.png
```

It prints the PNG path. `-s N` sets the max dimension (default 1400).

Then host + embed:

```bash
url=$(~/.claude/skills/surge-image-upload/upload.sh /tmp/shot.png)
gh pr edit <num> --body-file <(...)        # or: gh pr comment <num> --body "![shot]($url)"
```

## Step 1 — Capture the ANSI text (the part that bites you)

You need a **rendered frame with color codes intact**. Two cases:

### A. The program is a Go app using lipgloss / bubbletea (or similar)

Don't try to screenshot the live alt-screen TUI — it's a stream of cursor-move
diffs, not a clean frame, and **lipgloss strips all color when stdout is not a
TTY** (your capture comes out monochrome). Instead, render the view string
directly in a throwaway test and force the color profile:

```go
// zz_shot_test.go (delete after)
import (
    "github.com/charmbracelet/lipgloss"
    "github.com/muesli/termenv"
)
func TestZZShot(t *testing.T) {
    lipgloss.SetColorProfile(termenv.TrueColor) // emit colors despite no TTY
    // ...build the model/data...
    os.WriteFile("/tmp/shot.ansi", []byte(model.View()), 0644)
}
```

Run it (`go test -run TestZZShot`), then `rm` the test file. This also **skips
slow startup** (network fetches, etc.) since you construct the model directly.

### B. A live TUI / CLI you must drive

Use `expect` (or tmux) to run it in a real PTY at a fixed size and capture the
pane. Set the size with `set stty_init "rows 40 cols 120"`, `log_file` the
output, drive keys/input, then exit. For mouse-driven TUIs, inject SGR mouse
events, e.g. left click+release at col,row: `\033[<0;COL;ROWM\033[<0;COL;ROWm`.
The captured log is raw ANSI; if it's a full alt-screen stream you may need to
extract the final frame.

For plain (non-alt-screen) colored CLI output, just pipe it straight in:
`mycli --color=always | render.sh - -o shot.png`.

## Step 2 — Render

`render.sh` handles it. Rasteriser preference:

1. **`qlmanage`** (macOS Quick Look) — zero install, always present on macOS.
   This is why the skill works when Playwright/Chrome/webkit/ImageMagick/`aha`
   are all missing (a common situation).
2. `wkhtmltoimage` — fallback if present.

If neither exists, `render.sh` writes the `.html` next to the output and tells
you, so you can rasterise it elsewhere.

## Gotchas (learned the hard way)

- **lipgloss color stripping**: no TTY → no color. Force the profile (Case A).
- **qlmanage output is a square canvas** with content top-left on the dark
  background. Usually fine. To trim trailing dead space:
  `sips -c <H> <W> in.png --out out.png` — but note `sips -c` crops **centered**,
  which can clip the top; prefer leaving the full canvas, or use a top-anchored
  crop tool.
- **Match the page background to the terminal** (the converter uses `#0c0c10`)
  so padding blends in.
- **Feed a frame, not a byte stream**: ansi2html passes through non-SGR escape
  sequences as text, so an alt-screen capture full of cursor moves renders
  garbled. Capture/extract a single rendered frame first.
- **Width**: render the source at a fixed terminal width (e.g. 100–120 cols) so
  the image is reproducible and not dependent on the live terminal size.

## Files

- `ansi2html.py` — ANSI/SGR → HTML (xterm-256 palette, truecolor, bold).
- `render.sh` — full ANSI → PNG wrapper.

## Related skills

- **surge-image-upload** — host the PNG at a public URL for markdown embeds.
- **playwright** — for GUI/web screenshots (not terminal output).
