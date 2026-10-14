#!/usr/bin/env -S uv run --quiet --with anki --script
# /// script
# requires-python = ">=3.11"
# ///
"""Self-checks for the two hand gestures.

record_suspended: a suspended card becomes a rejection, and re-running never
duplicates the entry (the run is hourly and the suspend is permanent, so the
second thousand runs must all be no-ops).

rework_flagged: a red-flagged card is queued for rewriting and pulled from the
collection, while other flag colours are left alone."""
import importlib.machinery, importlib.util, json, os, tempfile

from anki.collection import Collection

spec = importlib.util.spec_from_loader("asb", importlib.machinery.SourceFileLoader(
    "asb", os.path.join(os.path.dirname(os.path.abspath(__file__)), "anki-sync-bm")))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

with tempfile.TemporaryDirectory() as tmp:
    m.REJECTED = os.path.join(tmp, "rejected.jsonl")
    col = Collection(os.path.join(tmp, "collection.anki2"))
    model = col.models.by_name("Basic")
    deck = col.decks.id("Cards")
    for guid, front in (("keep-01", "kept"), ("drop-01", "dropped")):
        note = col.new_note(model)
        note.fields[0], note.fields[1] = front, "back"
        note.guid = guid
        col.add_note(note, deck)
    col.sched.suspend_cards([col.card_ids_of_note(
        col.find_notes("front:dropped")[0])[0]])

    m.record_suspended(col)
    logged = [json.loads(l) for l in open(m.REJECTED)]
    m.record_suspended(col)
    again = sum(1 for _ in open(m.REJECTED))
    col.close()

assert [r["id"] for r in logged] == ["drop-01"], logged
assert logged[0]["front"] == "dropped", logged
assert logged[0]["reason"].startswith("suspended by hand"), logged
assert again == 1, f"duplicated on rerun: {again} entries"


def add(col, guid, front):
    note = col.new_note(col.models.by_name("Basic"))
    note.fields[0], note.fields[1] = front, "back"
    note.guid = guid
    col.add_note(note, col.decks.id("Cards"))
    return col.card_ids_of_note(note.id)[0]


with tempfile.TemporaryDirectory() as tmp:
    m.REJECTED = os.path.join(tmp, "rejected.jsonl")
    m.LEECH_QUEUE = os.path.join(tmp, "leeches.jsonl")
    col = Collection(os.path.join(tmp, "collection.anki2"))
    red, blue = add(col, "red-01", "vague"), add(col, "blue-01", "fine")
    col.set_user_flag_for_cards(m.REWORK_FLAG, [red])
    col.set_user_flag_for_cards(4, [blue])

    m.rework_flagged(col)
    queued = [json.loads(l) for l in open(m.LEECH_QUEUE)]
    left = {g for (g,) in col.db.all("select guid from notes")}
    col.close()

assert [q["id"] for q in queued] == ["red-01"], queued
assert queued[0]["reason"].startswith("flagged:"), queued
assert queued[0]["front"] == "vague" and queued[0]["back"] == "back", queued
assert left == {"blue-01"}, f"wrong notes removed: {left}"
print("ok")
