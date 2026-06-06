#!/usr/bin/env bash
# Render ANSI/SGR-colored terminal text to a PNG.
#
#   render.sh <input.ansi|-> [-o out.png] [-s SCALE]
#
# Reads ANSI text (file or stdin), converts it to HTML (ansi2html.py), then
# rasterises to PNG. Prints the PNG path on stdout.
#
#   -o   output PNG path (default: alongside input, or /tmp/ascii-shot-<ts>.png for stdin)
#   -s   max image dimension in px (default 1400)
#
# Rasteriser preference: macOS Quick Look (qlmanage, zero-install) → wkhtmltoimage
# → rsvg/chromium headless. qlmanage produces a square canvas with the content
# top-left on a dark background; that's usually fine. To trim trailing dead
# space, crop afterward (see SKILL.md).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out=""; scale=1400; input=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -s) scale="$2"; shift 2 ;;
    -) input="-"; shift ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) input="$1"; shift ;;
  esac
done
[ -n "$input" ] || { echo "usage: render.sh <input.ansi|-> [-o out.png] [-s SCALE]" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
html="$work/page.html"

if [ "$input" = "-" ]; then
  python3 "$here/ansi2html.py" - > "$html"
  [ -n "$out" ] || out="/tmp/ascii-shot-$$.png"
else
  python3 "$here/ansi2html.py" "$input" > "$html"
  [ -n "$out" ] || out="${input%.*}.png"
fi

if command -v qlmanage >/dev/null 2>&1; then
  qlmanage -t -s "$scale" -o "$work" "$html" >/dev/null 2>&1
  thumb="$work/$(basename "$html").png"
  [ -f "$thumb" ] || { echo "qlmanage produced no thumbnail" >&2; exit 1; }
  cp -f "$thumb" "$out"
elif command -v wkhtmltoimage >/dev/null 2>&1; then
  wkhtmltoimage --width "$scale" --quality 100 "$html" "$out" >/dev/null 2>&1
else
  echo "no rasteriser found (need qlmanage on macOS, or wkhtmltoimage)" >&2
  echo "HTML is at: $html (copy it out before this script exits)" >&2
  cp -f "$html" "${out%.png}.html"
  exit 1
fi

echo "$out"
