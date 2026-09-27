#!/bin/bash
# Self-check for cards-gen's rework queue: batch cap, attempt cap, give-up, and
# the corpus-verification step that decides what counts as reworked.
set -uo pipefail
cg="$(cd "$(dirname "$0")" && pwd)/cards-gen"   # absolute: HOME is redirected below
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
mkdir -p "$tmp/corpus" "$tmp/.local/state/cards" "$tmp/bin" "$tmp/.claude/projects"
export CARDS_CORPUS="$tmp/corpus"
export CARDS_REWORK_BATCH=2
state="$tmp/.local/state/cards"

# A stub `claude` that deletes the bullets named in the batch file, or not.
cat >"$tmp/bin/claude" <<'STUB'
#!/bin/bash
# The prompt is whichever argument names the batch file.
for a in "$@"; do case "$a" in *cards-leech-batch*) prompt="$a";; esac; done
batch=$(printf '%s\n' "$prompt" | tr '`' '\n' | grep 'cards-leech-batch' | head -1)
[ "${STUB_NOOP:-0}" = 1 ] && exit 0
for f in $(grep '^- file: ' "$batch" | awk '{print $3}'); do
  for id in $(grep '^## ' "$batch" | awk '{print $2}'); do
    sed -i '' "/id: $id /d" "$CARDS_CORPUS/$f" 2>/dev/null
  done
done
echo "changed"
STUB
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"

seed() {
  : >"$state/leeches-done.txt"; : >"$state/leeches-attempts.txt"
  printf 'a >> b <!-- id: c-01 -->\nd >> e <!-- id: c-02 -->\nf >> g <!-- id: c-03 -->\n' \
    >"$tmp/corpus/c.md"
  : >"$state/leeches.jsonl"
  for i in 01 02 03; do
    printf '{"id":"c-%s","front":"q","back":"a","concept":"c","reason":"leech: 3 lapses"}\n' \
      "$i" >>"$state/leeches.jsonl"
  done
  printf '{"id":"z-99","front":"q","back":"a","concept":"missing","reason":"leech: 3 lapses"}\n' \
    >>"$state/leeches.jsonl"
}


# 1. Batch cap honored, and a card whose concept file is absent is given up on
#    immediately rather than retried forever.
seed
out=$("$cg" --limit 1 2>&1)
grep -q "2/2 reworked" <<<"$out" || { echo "FAIL: expected 2/2 reworked, got: $out"; exit 1; }
grep -qx "z-99" "$state/leeches-done.txt" || { echo "FAIL: missing-file card should be given up"; exit 1; }
grep -q "giving up on 1 card" <<<"$out" || { echo "FAIL: expected a give-up line, got: $out"; exit 1; }

# 2. A no-op claude run marks nothing done, so the cards are retried.
seed
out=$(STUB_NOOP=1 "$cg" --limit 1 2>&1)
grep -q "0/2 reworked" <<<"$out" || { echo "FAIL: no-op run should resolve nothing, got: $out"; exit 1; }
grep -qx "c-01" "$state/leeches-done.txt" && { echo "FAIL: no-op run must not mark done"; exit 1; }
[ "$(grep -c . "$state/leeches-attempts.txt")" = 2 ] || { echo "FAIL: attempt not recorded"; exit 1; }

# 3. After REWORK_TRIES failed attempts the card is given up on and stops being
#    selected, so a poison batch cannot block the queue forever.
seed
for _ in 1 2 3; do STUB_NOOP=1 "$cg" --limit 1 >/dev/null 2>&1; done
out=$(STUB_NOOP=1 "$cg" --limit 1 2>&1)
grep -q "giving up on 2 card" <<<"$out" || { echo "FAIL: expected give-up after 3 tries, got: $out"; exit 1; }
grep -qx "c-01" "$state/leeches-done.txt" || { echo "FAIL: given-up card should be marked done"; exit 1; }

# 4. A reworked card is not reported unresolved just because a longer id shares
#    its prefix (c-10 vs c-100) — the check must be anchored, not a substring.
: >"$state/leeches-done.txt"; : >"$state/leeches-attempts.txt"
printf 'a >> b <!-- id: c-10 -->\nx >> y <!-- id: c-100 -->\n' >"$tmp/corpus/c.md"
printf '{"id":"c-10","front":"q","back":"a","concept":"c","reason":"leech: 3 lapses"}\n' \
  >"$state/leeches.jsonl"
out=$("$cg" --limit 1 2>&1)
grep -q "1/1 reworked" <<<"$out" || { echo "FAIL: c-10 resolved should not be masked by c-100, got: $out"; exit 1; }
grep -q "id: c-100" "$tmp/corpus/c.md" || { echo "FAIL: c-100 must be left alone"; exit 1; }

echo ok
