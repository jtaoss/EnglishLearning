"""Independent structural/source validator. Passing is NOT semantic approval."""

from collections import Counter
import csv
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/p6/p6c"


def canonical_hash(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate(payload, formal, selection, evidence, ledger):
    require(payload["schema_version"] == 2 and payload["publication_status"] == "isolated_draft_not_approved", "Not an isolated v2 draft")
    records = payload["records"]
    ids = [r["stable_id"] for r in records]
    expected = {r["entry_id"]: cohort for cohort, rows in selection["groups"].items() for r in rows}
    require(len(records) == payload["record_count"] == len(set(ids)) == 100 and set(ids) == set(expected), "Must contain only 100 selected unique IDs")
    counts = dict(Counter(r["cohort"] for r in records))
    require(counts == payload["cohort_counts"] == {key: 20 for key in ("simple", "polyseme", "complex_pos", "high_frequency", "random")}, "Bad cohorts")
    require(len(formal) == 5332, "Wrong formal size")
    by_id = {r["entry_id"]: r for r in formal}
    require(len(by_id) == 5332, "Duplicate formal stable IDs")
    ledger_ids = [r["stable_id"] for r in ledger["records"]]
    reviews = {r["stable_id"]: r for r in ledger["records"]}
    require(len(ledger_ids) == len(set(ledger_ids)) == 100 and set(reviews) == set(ids), "Incomplete/duplicate review ledger")
    for r in records:
        head = r["headword"]
        row = by_id[r["stable_id"]]
        require(r["cohort"] == expected[r["stable_id"]], f"Wrong selected cohort: {head}")
        require(r["source_fields"] == row and r["source_hash"] == canonical_hash(row), f"Stale source: {head}")
        require(r["original_meaning_zh"] == row["meaning_zh"] and r["headword"] == row["word"] and r["part_of_speech"] == row["part_of_speech"], f"Altered input: {head}")
        require(r["decision_hash"] == canonical_hash({k: v for k, v in r.items() if k != "decision_hash"}), f"Altered decision: {head}")
        require(type(r["confidence"]) in (int, float) and 0 <= r["confidence"] <= 1, f"Bad confidence: {head}")
        require(r["review_required"] is True and r["official_exam_focus"] is False and r["model_added_senses"] == [], f"Unsupported approval/exam/new-sense claim: {head}")
        require(r["core_meanings"] and r["core_explanation"].strip() and r["selection_reason"].strip(), f"Empty decision: {head}")
        example = r["usage_example"]
        require(example == ({"en": row["example_en"], "zh": row["example_zh"], "origin": "formal_example_unmodified"} if row["example_en"] else None), f"Changed example: {head}")
        atoms = {a["source_sense_id"]: a for a in r["source_senses"]}
        require(len(atoms) == len(r["source_senses"]) and atoms, f"Duplicate/empty source atoms: {head}")
        # Independently cover every non-separator character in the original;
        # prevents an output from dropping an atom and its trace together.
        covered = set()
        for a in atoms.values():
            start, end = a["start"], a["end"]
            require(0 <= start < end <= len(row["meaning_zh"]) and row["meaning_zh"][start:end] == a["text"], f"Invalid source slice: {head}")
            require(not covered.intersection(range(start, end)), f"Overlapping trace slices: {head}")
            covered.update(range(start, end))
        remainder = "".join(ch for i, ch in enumerate(row["meaning_zh"]) if i not in covered)
        remainder = re.sub(r"(名词|动词|形容词|副词|数词|介词|连词|代词|限定词|助动词|系动词|情态动词|感叹词)[:：]", "", remainder)
        require(not re.sub(r"[，,；;\s]", "", remainder), f"Omitted original characters: {head}")
        valid_refs = {x["evidence_id"] for x in evidence["headwords"][head.lower()]}
        assigned = []
        for layer, key in (("core", "core_meanings"), ("extended", "extended_meanings"), ("other", "other_meanings")):
            for g in r[key]:
                require(g["layer"] == layer and g["origin"] == "formal_gloss", f"Wrong layer/origin: {head}")
                source_ids = g["source_sense_ids"]
                require(source_ids and all(s in atoms for s in source_ids), f"Invented reference: {head}")
                require(g["glosses"] == [atoms[s]["text"] for s in source_ids], f"Invented gloss: {head}")
                for s in source_ids:
                    a = atoms[s]
                    if a["part_of_speech"] is None:
                        require(g["part_of_speech"] == "待核实" and "pos_unresolved" in r["risk_flags"], f"Guessed POS: {head}")
                    else:
                        require(a["part_of_speech"] == g["part_of_speech"], f"Cross-POS merge: {head}")
                require(set(g["reference_ids"]) <= valid_refs, f"Wrong lexical reference: {head}")
                assigned.extend(source_ids)
        require(Counter(assigned) == Counter({s: 1 for s in atoms}), f"Missing/duplicated source sense: {head}")
        review = reviews[r["stable_id"]]
        require(review["source_hash"] == r["source_hash"] and review["decision_hash"] == r["decision_hash"], f"Stale human review binding: {head}")
        require(review["status"] in {"pending", "approved", "rejected", "needs_changes"}, f"Unknown review status: {head}")
        if review["status"] == "approved":
            require(review["reviewer"] and review["reviewed_at"] and review["notes"], f"Unsigned human approval: {head}")
    return {"records": 100, "cohort_counts": counts, "source_atoms": sum(len(r["source_senses"]) for r in records),
            "high_risk": sum(r["risk_level"] == "high" for r in records),
            "risk_flag_counts": dict(Counter(f for r in records for f in r["risk_flags"])),
            "human_status_counts": dict(Counter(r["status"] for r in reviews.values())),
            "semantic_accuracy": "not_measured_no_human_ground_truth",
            "status": "structurally_valid_pending_human_review"}


def inputs():
    load = lambda name: json.loads((OUT / name).read_text(encoding="utf-8"))
    with (ROOT / "docs/p5a/public/formal_learning_vocabulary.csv").open(encoding="utf-8-sig", newline="") as stream:
        formal = list(csv.DictReader(stream))
    return (load("core_meanings_pilot.json"), formal, load("selection.json"), load("wordnet_evidence.json"), load("human_review.json"))


def main():
    args = inputs()
    require(args[0]["source_file_sha256"] == hashlib.sha256((ROOT / args[0]["source"]).read_bytes()).hexdigest(), "Changed formal file")
    print(json.dumps(validate(*args), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
