---
name: trim-video
description: "Trim long idle/static periods in a screen recording (or any video) down to a max duration using ffmpeg scene detection. Use when asked to trim idle periods, remove dead air, or shorten a video recording."
---

# Trim Video

You are a video editor. Your role is to trim long idle periods from a video file using scene change detection, keeping only a configurable maximum duration of any static stretch.

## What You Do

- Accept an input video file and optional parameters
- Run the bundled Python script using ffmpeg scene detection
- Report the before/after duration and file size

## What You Don't Do

- Modify the original file — always write to a new output file
- Require the user to understand ffmpeg internals

## Prerequisites

`ffmpeg` must be installed:

```bash
ffmpeg -version
```

If missing: `sudo apt-get install -y ffmpeg`

## Workflow

### Step 1: Determine Inputs

Ask the user (or infer from context):

- **Input file** — path to the video to trim
- **Max idle duration** — how long to allow static periods (default: 3 seconds)
- **Output path** — where to save the result (default: same dir as input, with `-trimmed` suffix)

If the user says something like "trim the video I just recorded" and a recent path is evident from context, use it directly without asking.

### Step 2: Run the Script

```bash
python3 ~/.claude/skills/trim-video/trim_idle.py \
  <input_file> \
  [output_file] \
  [--max-idle SECONDS] \
  [--threshold VALUE]
```

**Parameters:**

| Parameter | Default | Notes |
|-----------|---------|-------|
| `--max-idle` | `3` | Max seconds of idle to keep |
| `--threshold` | `0.003` | Scene change sensitivity (0–1). Lower = more sensitive. Try `0.01` if too many false-positives; `0.001` if too many idle periods slip through. |

**Example — trim with defaults:**
```bash
python3 ~/.claude/skills/trim-video/trim_idle.py ~/Videos/playwright/recording.webm
```

**Example — trim to 5s idle max, custom output:**
```bash
python3 ~/.claude/skills/trim-video/trim_idle.py \
  ~/Videos/playwright/recording.webm \
  ~/Videos/playwright/recording-trimmed.webm \
  --max-idle 5
```

The script prints progress and a summary:
```
Input:    /path/to/input.webm
Duration: 1071.9s  (17.9 min)
Scene changes found: 479
Segments: 199
Output duration: 709.1s  (trimmed 362.8s / 34%)
Output:   /path/to/input-trimmed.webm
Encoding...
Done. Output size: 3.1 MB
```

### Step 3: Report Results

Report to the user:
- Original and trimmed duration
- Amount of time removed
- Output file path and size

If the result still seems too long (user expected more trimming), suggest increasing `--threshold` (e.g. `0.01`) to be less sensitive to minor changes. If too much was trimmed, suggest decreasing it (e.g. `0.001`).

## Tips

- Screen recordings compress very well after trimming because static frames encode tiny. Expect large file size reductions even with modest duration reductions.
- The default threshold `0.003` works well for browser/screen recordings. For talking-head or action video, try `0.02`–`0.05`.
- Output is encoded as VP9 WebM (good for web sharing). To change format, modify the `-c:v` flag in the script's `encode()` function.
