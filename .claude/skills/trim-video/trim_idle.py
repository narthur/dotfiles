#!/usr/bin/env python3
"""
Trim idle periods (no screen change) in a video to a max duration.

Usage:
  python3 trim_idle.py <input_file> [output_file] [--max-idle SECONDS] [--threshold VALUE]

Arguments:
  input_file        Path to the input video file
  output_file       Path for the output file (default: <input>-trimmed.<ext>)
  --max-idle        Max duration of idle periods in seconds (default: 3)
  --threshold       Scene change sensitivity 0.0–1.0, lower = more sensitive (default: 0.003)
"""
import subprocess, json, re, os, sys, argparse, tempfile

def parse_args():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input_file")
    parser.add_argument("output_file", nargs="?")
    parser.add_argument("--max-idle", type=float, default=3.0, metavar="SECONDS",
                        help="Max idle period duration (default: 3)")
    parser.add_argument("--threshold", type=float, default=0.003, metavar="VALUE",
                        help="Scene change sensitivity, 0.0–1.0 (default: 0.003)")
    return parser.parse_args()

def get_duration(input_file):
    probe = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", input_file],
        capture_output=True, text=True, check=True
    )
    return float(json.loads(probe.stdout)["format"]["duration"])

def detect_scene_changes(input_file, threshold):
    print(f"Detecting scene changes (threshold={threshold})...")
    result = subprocess.run(
        ["ffmpeg", "-i", input_file,
         "-vf", f"select=gt(scene\\,{threshold}),showinfo",
         "-vsync", "vfr", "-f", "null", "-"],
        capture_output=True, text=True
    )
    times = sorted(set(
        float(m.group(1))
        for line in result.stderr.splitlines()
        for m in [re.search(r'pts_time:([\d.]+)', line)]
        if m
    ))
    return times

def build_segments(scene_times, duration, max_idle):
    """Build a list of (start, end) keep-segments, capping idle gaps at max_idle."""
    all_times = [0.0] + scene_times + [duration]
    segments = []
    prev = 0.0
    for t in all_times[1:]:
        gap = t - prev
        if gap > max_idle:
            segments.append((prev, prev + max_idle))
        else:
            segments.append((prev, t))
        prev = t

    # merge adjacent/overlapping segments
    merged = []
    for s, e in segments:
        if merged and s <= merged[-1][1] + 0.001:
            merged[-1][1] = max(merged[-1][1], e)
        else:
            merged.append([s, e])
    return merged

def encode(input_file, output_file, segments):
    n = len(segments)
    if n <= 200:
        # filter_complex approach — single pass, no temp files
        filter_parts = []
        inputs = []
        for i, (s, e) in enumerate(segments):
            filter_parts.append(f"[0:v]trim={s:.6f}:{e:.6f},setpts=PTS-STARTPTS[v{i}]")
            inputs.append(f"[v{i}]")
        filter_parts.append("".join(inputs) + f"concat=n={n}:v=1:a=0[outv]")

        subprocess.run(
            ["ffmpeg", "-y", "-i", input_file,
             "-filter_complex", ";".join(filter_parts),
             "-map", "[outv]",
             "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-threads", "4",
             output_file],
            check=True
        )
    else:
        # concat demuxer for very many segments (avoids filter length limits)
        tmpdir = tempfile.mkdtemp()
        part_files = []
        for i, (s, e) in enumerate(segments):
            part = os.path.join(tmpdir, f"part{i:04d}.webm")
            subprocess.run(
                ["ffmpeg", "-y", "-ss", str(s), "-to", str(e), "-i", input_file,
                 "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", part],
                check=True, capture_output=True
            )
            part_files.append(part)
        concat_list = os.path.join(tmpdir, "concat.txt")
        with open(concat_list, "w") as f:
            for p in part_files:
                f.write(f"file '{p}'\n")
        subprocess.run(
            ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat_list,
             "-c", "copy", output_file],
            check=True
        )

def main():
    args = parse_args()
    input_file = os.path.expanduser(args.input_file)

    if args.output_file:
        output_file = os.path.expanduser(args.output_file)
    else:
        base, ext = os.path.splitext(input_file)
        output_file = f"{base}-trimmed{ext}"

    if not os.path.exists(input_file):
        print(f"ERROR: input file not found: {input_file}", file=sys.stderr)
        sys.exit(1)

    duration = get_duration(input_file)
    print(f"Input:    {input_file}")
    print(f"Duration: {duration:.1f}s  ({duration/60:.1f} min)")

    scene_times = detect_scene_changes(input_file, args.threshold)
    print(f"Scene changes found: {len(scene_times)}")

    segments = build_segments(scene_times, duration, args.max_idle)
    total_kept = sum(e - s for s, e in segments)
    saved = duration - total_kept
    print(f"Segments: {len(segments)}")
    print(f"Output duration: {total_kept:.1f}s  (trimmed {saved:.1f}s / {saved/duration*100:.0f}%)")
    print(f"Output:   {output_file}")
    print("Encoding...")

    encode(input_file, output_file, segments)

    size_mb = os.path.getsize(output_file) / 1e6
    print(f"Done. Output size: {size_mb:.1f} MB")

if __name__ == "__main__":
    main()
