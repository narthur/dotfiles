#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.11"
# ///
"""Self-check for cards-audit's deterministic halves: which returned fixes are
accepted, and that applying one touches the question and nothing else."""
import importlib.machinery, importlib.util, json, os, tempfile

spec = importlib.util.spec_from_loader("ca", importlib.machinery.SourceFileLoader(
    "ca", os.path.join(os.path.dirname(os.path.abspath(__file__)), "cards-audit")))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

tmp = tempfile.mkdtemp()
m.CORPUS = tmp
m.AUDITED = os.path.join(tmp, "audited.txt")
open(os.path.join(tmp, "enum.md"), "w").write("""---
concept: enum
---

Prose that is not a card, with >> in it even.

## Cards

- Beyond the response body, what leaks whether an address exists? >> Timing. <!-- id: enum-01 -->
- Why does PKCE exist? >> Code interception. <!-- id: enum-02 -->
""")

cards = m.parse_corpus()
assert [c["id"] for c in cards] == ["enum-01", "enum-02"], cards
assert cards[0]["concept"] == "enum" and cards[0]["back"] == "Timing."

# Only the card asked about, only a real rewrite, never a no-op or a mangled one.
batch = [dict(id=c["id"], front=c["front"], back=c["back"]) for c in cards]
fixes = {}
for item in [
    dict(id="enum-01", front="A signup form returns the same page either way. What still leaks that the address exists?"),
    dict(id="not-a-card-99", front="A perfectly fine looking question about nothing at all"),
    dict(id="enum-02", front="short"),
    dict(id="enum-02", front="Why does PKCE exist?"),
    dict(id="enum-02", front="A question that smuggles >> a second field into the bullet"),
    "not even a dict",
]:
    fixes.update(m.accept_fix(item, batch))
assert list(fixes) == ["enum-01"], f"guard let something through: {fixes}"

changed = m.apply_fixes(fixes, cards)
assert changed == 1, changed
text = open(os.path.join(tmp, "enum.md")).read()
assert "<!-- id: enum-01 -->" in text and "<!-- id: enum-02 -->" in text
assert ">> Timing." in text, "answer was altered"
assert "Why does PKCE exist? >> Code interception." in text, "passing card touched"
assert "Beyond the response body" not in text, "question not replaced"
assert "Prose that is not a card" in text, "non-card line touched"
assert len(text.splitlines()) == len("""---
concept: enum
---

Prose that is not a card, with >> in it even.

## Cards

- x >> y <!-- id: enum-01 -->
- x >> y <!-- id: enum-02 -->
""".splitlines()), "line count changed"

# Fingerprint keys on the wording, so a rewritten card is re-audited.
before = m.fingerprint(cards[0])
after = m.fingerprint(dict(id="enum-01", front=fixes["enum-01"]))
assert before != after and before.split("\t")[0] == after.split("\t")[0]
print("ok")
