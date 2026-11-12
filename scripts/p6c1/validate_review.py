"""Validate scope, provenance, evidence ownership and non-destructive proposals.

This proves structural consistency, not teaching effectiveness/semantic accuracy.
"""

from collections import Counter
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/p6/p6c1"


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def require(value, message):
    if not value:
        raise ValueError(message)


def validate(data, snapshot, evidence):
    catalog = evidence["evidence_catalog"]
    old = {r["stable_id"]: r for r in snapshot["records"]}
    records = data["records"]
    ids = [r["stable_id"] for r in records]
    require(data["scope"] == "existing_P6C_selected_100_only" and data["publication_status"] == "isolated_independent_review_not_released", "Invalid review scope/release status")
    require(len(records) == len(set(ids)) == len(old) == 100 and set(ids) == set(old), "Exactly the frozen 100 stable IDs required")
    original_count = 0
    candidate_ids = []
    for r in records:
        parent = old[r["stable_id"]]
        head = r["headword"]
        require(r["headword"] == parent["headword"] and r["original_meaning_zh"] == parent["original_meaning_zh"] and r["original_part_of_speech"] == parent["part_of_speech"], "Original text/head/POS changed")
        require(r["parent_record_hash"] == digest(parent) and r["parent_decision_hash"] == parent["decision_hash"] and r["source_hash"] == parent["source_hash"], "Wrong parent/source hash")
        require(r["review_hash"] == digest({k: v for k, v in r.items() if k != "review_hash"}), "Review hash mismatch")
        require(r["human_confirmation"] == "not_claimed" and r["review_required_before_publication"] is True, "AI must not invent human approval")
        require(len(r["eight_checks"]) == 8 and all(r["eight_checks"].values()) and r["first_memory_rationale"], "Incomplete eight-dimensional review")
        source = {a["source_sense_id"]: a for a in parent["source_senses"]}
        aligned = r["source_alignment"]
        require(len(aligned) == len(source) and {a["source_sense_id"] for a in aligned} == set(source), "Original gloss removed from alignment")

        def check_evidence(eids):
            require(eids, f"Missing evidence: {head}")
            for eid in eids:
                require(eid in catalog and head in catalog[eid]["selected_headwords"], f"Wrong-head or invented evidence: {head} {eid}")

        for a in aligned:
            parent_atom = source[a["source_sense_id"]]
            require(all(a[k] == v for k, v in parent_atom.items()), "Changed original source atom")
            check_evidence(a["evidence_ids"])
        by_source = {a["source_sense_id"]: a for a in aligned}
        require(set(r["proposed_layers"]) == {"core_meanings", "extended_meanings", "other_meanings"} and r["proposed_layers"]["core_meanings"], "Three layers and a first-learning proposal required")
        if r["supplemental_evidence_ids"]:
            check_evidence(r["supplemental_evidence_ids"])
        assigned = []
        for groups in r["proposed_layers"].values():
            for g in groups:
                require(g["origin"] == "AI_review_of_formal_gloss_not_original_wording" and g["display_zh"].strip(), "Unlabelled rewrite")
                check_evidence(g["evidence_ids"])
                require(g["source_sense_ids"] == [a["source_sense_id"] for a in g["source_subsenses"]], "Lost sub-sense structure")
                require(len(set(g["source_sense_ids"])) == len(g["source_sense_ids"]), "Repeated source in group")
                if g["grouping_relation"] == "distinct_uses_explicitly_preserved":
                    require(g["usage_note"].strip() and g["source_subsenses"], "Mixed uses need contextual distinctions")
                for sub in g["source_subsenses"]:
                    s = sub["source_sense_id"]
                    require(s in source and sub["original_gloss"] == source[s]["text"] and sub["original_pos"] == source[s]["part_of_speech"], "Changed/unknown sub-sense")
                    require(sub["evidence_ids"] == by_source[s]["evidence_ids"], "Sub-sense evidence drift")
                    if source[s]["part_of_speech"] is None:
                        require(head == "knock" and g["part_of_speech"] == "动词" and "reference_based_pos_recommendation_not_book_confirmation" in r["issue_types"], "Unlabelled guessed POS")
                    else:
                        require(g["part_of_speech"] == source[s]["part_of_speech"], "Cross-POS merge")
                    assigned.append(s)
        for held in r["reserved_original_items"]:
            s = held["source_sense_id"]
            require(s in source and held["original_gloss"] == source[s]["text"] and held["reason"], "Lost reserved original gloss")
            require(held["state"] in {"contextual_paraphrase_only", "unresolved_not_for_standalone_memorization"}, "Invalid reserved state")
            check_evidence(held["evidence_ids"])
            assigned.append(s)
        require(Counter(assigned) == Counter(source.keys()), "Omitted or duplicated original gloss across layers/reserve")
        original_count += len(source)
        for c in r["dictionary_addition_candidates"]:
            candidate_ids.append(c["candidate_id"])
            require(c["source_sense_ids"] == [] and c["origin"] == "dictionary_evidenced_AI_addition_candidate_not_in_formal_gloss", "Addition masquerades as original")
            require(c["suggested_layer"] in {"core", "extended", "other"} and c["review_required"] is True and c["publication_status"] == "isolated_proposal_only", "Unsafe addition status")
            check_evidence(c["evidence_ids"])
    require(len(candidate_ids) == len(set(candidate_ids)), "Duplicate addition IDs")
    summary = data["summary"]
    require(summary["records"] == len(records) and summary["original_source_glosses"] == original_count and summary["addition_candidates"] == len(candidate_ids), "Wrong summary counts")
    require(summary["review_status_counts"] == dict(Counter(r["review_status"] for r in records)), "Wrong review status counts")
    require(summary["human_approvals_added"] == 0, "Invented human approval count")
    for e in catalog.values():
        if str(e.get("direct_open", "")).startswith("HTTP_403"):
            require(e["access"] != "direct_page_retrieved", "Blocked page falsely claimed as read")
    return {"status": "structurally_valid_AI_review_not_human_adjudication", "records": 100,
            "preserved_original_glosses": original_count, "addition_candidates": len(candidate_ids),
            "evidence_entries": len(catalog), "human_approvals_added": 0}


def inputs():
    load = lambda name: json.loads((OUT / name).read_text(encoding="utf-8"))
    return load("independent_review.json"), load("input_p6c_snapshot.json"), load("evidence_catalog.json")


def main():
    data, snapshot, evidence = inputs()
    require(data["input_snapshot_sha256"] == hashlib.sha256((OUT / "input_p6c_snapshot.json").read_bytes()).hexdigest(), "Input snapshot bytes changed")
    print(json.dumps(validate(data, snapshot, evidence), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
