#!/usr/bin/env python3
"""Convert ANSI/SGR-colored terminal text into a self-contained HTML page.

Reads ANSI text from a file argument or stdin, emits HTML on stdout: a dark
monospace <pre> with <span>s carrying the foreground colors. Handles the SGR
codes terminal apps actually emit — reset(0), bold(1/22), the 16 base colors
(30-37 / 90-97), 256-color (38;5;N), and truecolor (38;2;R;G;B) — mapped
through the standard xterm-256 palette. Other CSI sequences (cursor moves,
etc.) are passed through as text, so feed it a rendered frame, not a raw
alt-screen byte stream (see SKILL.md for how to capture one).

Usage:
    python3 ansi2html.py input.ansi > out.html
    some-command | python3 ansi2html.py - > out.html
"""
import sys
import html
import re


def palette():
    # 0-15: standard + bright; 16-231: 6x6x6 cube; 232-255: grayscale ramp.
    base = [
        (0, 0, 0), (205, 49, 49), (13, 188, 121), (229, 229, 16),
        (36, 114, 200), (188, 63, 188), (17, 168, 205), (229, 229, 229),
        (102, 102, 102), (241, 76, 76), (35, 209, 139), (245, 245, 67),
        (59, 142, 234), (214, 112, 214), (41, 184, 219), (255, 255, 255),
    ]
    cube = [0, 95, 135, 175, 215, 255]
    pal = list(base)
    for r in cube:
        for g in cube:
            for b in cube:
                pal.append((r, g, b))
    for i in range(24):
        v = 8 + i * 10
        pal.append((v, v, v))
    return pal


PAL = palette()


def rgb(idx):
    r, g, b = PAL[idx % 256]
    return f"#{r:02x}{g:02x}{b:02x}"


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "-"
    data = (sys.stdin.buffer.read() if path == "-" else open(path, "rb").read())
    src = data.decode("utf-8", "replace")

    out = []
    fg = None
    bold = False

    def span():
        styles = []
        if fg is not None:
            styles.append(f"color:{fg}")
        if bold:
            styles.append("font-weight:bold")
        return f'<span style="{";".join(styles)}">' if styles else "<span>"

    def emit(txt):
        if txt:
            out.append(span())
            out.append(html.escape(txt))
            out.append("</span>")

    for part in re.split(r"(\x1b\[[0-9;]*m)", src):
        m = re.match(r"\x1b\[([0-9;]*)m", part)
        if not m:
            emit(part)
            continue
        codes = [int(x) for x in m.group(1).split(";") if x != ""] or [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0:
                fg, bold = None, False
            elif c == 1:
                bold = True
            elif c == 22:
                bold = False
            elif 30 <= c <= 37:
                fg = rgb(c - 30)
            elif 90 <= c <= 97:
                fg = rgb(c - 90 + 8)
            elif c == 39:
                fg = None
            elif c == 38 and i + 2 < len(codes) and codes[i + 1] == 5:
                fg = rgb(codes[i + 2]); i += 2
            elif c == 38 and i + 4 < len(codes) and codes[i + 1] == 2:
                r, g, b = codes[i + 2], codes[i + 3], codes[i + 4]
                fg = f"#{r:02x}{g:02x}{b:02x}"; i += 4
            i += 1

    body = "".join(out)
    print(
        '<!doctype html><html><head><meta charset="utf-8"><style>\n'
        "body{margin:0;background:#0c0c10;padding:22px 26px;}\n"
        'pre{margin:0;font:15px/1.32 "SF Mono","Menlo","DejaVu Sans Mono",monospace;'
        "color:#d6d6d6;white-space:pre;display:inline-block;}\n"
        f"</style></head><body><pre>{body}</pre></body></html>"
    )


if __name__ == "__main__":
    main()
