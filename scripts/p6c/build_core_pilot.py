"""Replay 100 AI-authored decisions into an isolated, traceable draft.

No API client, SQLite connection, Notion operation, or formal-data write exists.
Human review is separate and is never overwritten by this builder.
"""

import argparse
from collections import Counter
import csv
import hashlib
import json
import re
from pathlib import Path

from semantic_decisions import DECISIONS

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/p6/p6c"
FORMAL = ROOT / "docs/p5a/public/formal_learning_vocabulary.csv"
MODEL_VERSION = "codex-session/p6c-semantic-v2"
PROMPT_VERSION = "p6c-prompt-2"
LABEL = re.compile(r"^(名词|动词|形容词|副词|数词|介词|连词|代词|限定词|助动词|系动词|情态动词|感叹词)[:：]")
POS_CODES = {"名词": {"n"}, "动词": {"v"}, "形容词": {"a", "s"}, "副词": {"r"}, "数词": {"a", "s", "n"}}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical_hash(row):
    return digest(json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path, payload):
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def source_atoms(row):
    """Lexical slices, not semantic groupings. Punctuation never chooses layers."""
    text = row["meaning_zh"]
    parts = row["part_of_speech"].split("；")
    result = []
    for segment in re.finditer(r"[^；;]+", text):
        start = segment.start() + len(segment[0]) - len(segment[0].lstrip())
        body = segment[0].strip()
        label = LABEL.match(body)
        pos = label[1] if label else parts[0] if len(parts) == 1 else None
        offset = start + (label.end() if label else 0)
        body = body[label.end():] if label else body
        for atom in re.finditer(r"[^，,]+", body):
            gloss = atom[0].strip()
            a = offset + atom.start() + len(atom[0]) - len(atom[0].lstrip())
            result.append({"source_sense_id": f"s{len(result) + 1:03d}", "text": gloss,
                           "part_of_speech": pos,
                           "pos_evidence": "explicit_gloss_label" if label else "single_pos_field" if len(parts) == 1 else "unresolved_multi_pos",
                           "start": a, "end": a + len(gloss)})
    return result


def build_record(row, cohort, evidence):
    decision = DECISIONS[row["word"]]
    atoms = source_atoms(row)
    used = set()
    references = evidence["headwords"][row["word"].lower()]
    layers = {}
    for layer in ("core", "extended", "other"):
        items = []
        for index, group in enumerate(decision[layer]):
            pos = group["part_of_speech"]
            refs = []
            for gloss in group["glosses"]:
                matches = [a for a in atoms if a["text"] == gloss and a["source_sense_id"] not in used and (a["part_of_speech"] == pos or (a["part_of_speech"] is None and pos == "待核实"))]
                if len(matches) != 1:
                    raise ValueError(f"Untraceable or ambiguous decision: {row['word']} {pos} {gloss}")
                used.add(matches[0]["source_sense_id"])
                refs.append(matches[0]["source_sense_id"])
            items.append({"sense_group_id": f"{row['entry_id']}:{layer}:{index + 1}",
                          "layer": layer, "part_of_speech": pos, "glosses": group["glosses"],
                          "origin": "formal_gloss", "source_sense_ids": refs,
                          "reference_ids": [e["evidence_id"] for e in references if pos == "待核实" or e["pos"] in POS_CODES.get(pos, set())],
                          "reference_relation": "headword_pos_reference_only_not_translation_or_frequency_attestation",
                          "merge_basis": "AI近义归组，待人工确认" if len(refs) > 1 else "独立保留该原文解释"})
        layers[layer] = items
    if len(used) != len(atoms):
        raise ValueError(f"Dropped source gloss: {row['word']}")
    flags = list(decision["risk_flags"])
    if sum(map(len, layers.values())) > 1:
        flags.append("rank_not_corpus_verified")
    if any(len(g["glosses"]) > 1 for groups in layers.values() for g in groups):
        flags.append("synonym_group_needs_review")
    high = cohort in {"complex_pos", "polyseme"} or any(f in flags for f in ("pos_unresolved", "source_translation_nuance", "false_merge_corrected", "usage_sensitivity"))
    uncertain = any(f in flags for f in ("pos_unresolved", "source_translation_nuance"))
    confidence = 0.55 if uncertain else 0.68 if high else 0.8
    example = {"en": row["example_en"], "zh": row["example_zh"], "origin": "formal_example_unmodified"} if row["example_en"] else None
    record = {
        "stable_id": row["entry_id"], "headword": row["word"], "part_of_speech": row["part_of_speech"],
        "cohort": cohort, "book_category": row["book_category"], "library_class": row["library_class"],
        "original_meaning_zh": row["meaning_zh"], "core_meanings": layers["core"],
        "extended_meanings": layers["extended"], "other_meanings": layers["other"],
        "core_explanation": decision["core_explanation"], "usage_example": example,
        "selection_reason": decision["selection_reason"], "confidence": confidence,
        "confidence_basis": "conservative_AI_editorial_band_not_calibrated_probability_or_correctness_evidence",
        "review_required": True, "human_review_status": "pending", "risk_level": "high" if high else "standard",
        "risk_flags": flags, "model_version": MODEL_VERSION, "prompt_version": PROMPT_VERSION,
        "source_hash": canonical_hash(row), "source_fields": row, "source_senses": atoms,
        "model_added_senses": [], "official_exam_focus": False,
        "evidence": {"formal_csv_row_key": row["entry_id"], "inherited_lexical_sources": row["lexical_sources"],
                     "reference_file": "docs/p6/p6c/wordnet_evidence.json",
                     "wordnet_archive_sha256": evidence["archive_sha256"],
                     "rank_evidence": "AI_teaching_judgment_no_corpus_or_official_PETS_sense_ranking"},
    }
    record["decision_hash"] = canonical_hash(record)
    return record


def build():
    selection = read_json(OUT / "selection.json")
    evidence = read_json(OUT / "wordnet_evidence.json")
    formal = list(csv.DictReader(FORMAL.open(encoding="utf-8-sig", newline="")))
    by_id = {r["entry_id"]: r for r in formal}
    if len(formal) != 5332 or len(by_id) != 5332:
        raise ValueError("Formal library must contain exactly 5,332 unique stable IDs")
    selected = [(cohort, r) for cohort, rows in selection["groups"].items() for r in rows]
    if len(selected) != 100 or len({r["entry_id"] for _, r in selected}) != 100 or set(DECISIONS) != {r["word"] for _, r in selected}:
        raise ValueError("Only the 100 explicitly selected headwords may be processed")
    records = []
    for cohort, sample in selected:
        row = by_id[sample["entry_id"]]
        for key, value in sample.items():
            if key in row and row[key] != value:
                raise ValueError(f"Stale selection: {row['word']} {key}")
        records.append(build_record(row, cohort, evidence))
    return {
        "schema_version": 2, "publication_status": "isolated_draft_not_approved",
        "model_version": MODEL_VERSION, "prompt_version": PROMPT_VERSION,
        "generation": {"actor": "Codex AI session", "backend_model_id": None, "backend_snapshot": None,
                       "method": "100 explicit AI-authored semantic decisions, deterministically replayed; no external model API request",
                       "limitation": "Exact backend model identity is not exposed. This label is a pipeline version, not an API model claim."},
        "source": "docs/p5a/public/formal_learning_vocabulary.csv",
        "source_file_sha256": digest(FORMAL.read_bytes()),
        "source_hash_format": "SHA256(UTF8(JSON(all 29 CSV fields, sorted keys, ensure_ascii=False, compact separators))); full snapshot retained",
        "prompt_sha256": digest((OUT / "PROMPT_V2.md").read_bytes()),
        "semantic_decisions_sha256": digest((ROOT / "scripts/p6c/semantic_decisions.py").read_bytes()),
        "record_count": 100, "cohort_counts": dict(Counter(r["cohort"] for r in records)),
        "rules": ["仅处理选定100词，不改正式词库", "词性分开，全部原文解释恰好保留一次", "核心通常1–2组，多重要义可超过两组", "考研分类不证明义项频率", "confidence仅是AI自评信号", "人工审核待完成，结构通过不等于审核通过"],
        "records": records,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Read-only stale-output check")
    parser.add_argument("--init-review", action="store_true", help="Create human ledger exclusively; never overwrite")
    args = parser.parse_args()
    if args.check and args.init_review:
        parser.error("--check cannot write a review ledger")
    payload = build()
    target = OUT / "core_meanings_pilot.json"
    if args.check:
        if read_json(target) != payload:
            raise ValueError("Generated output differs; inspect before rebuilding")
    else:
        old = read_json(target) if target.exists() else None
        baseline = OUT / "draft_v1_findings.json"
        if old and old.get("model_version") == "p6c-core-1" and not baseline.exists():
            affected = {r["headword"] for r in payload["records"] if "false_merge_corrected" in r["risk_flags"]}
            write_json(baseline, {"reviewer_type": "AI_semantic_audit_not_human_approval",
                                 "draft_v1_sha256": digest(target.read_bytes()),
                                 "finding_type": "different_senses_grouped_as_near_synonyms",
                                 "status": "corrected_in_v2_pending_human_review",
                                 "records": [{"stable_id": r["stable_id"], "headword": r["headword"], "before": {k: r[k] for k in ("core_meanings", "extended_meanings", "other_meanings")}} for r in old["records"] if r["headword"] in affected]})
        write_json(target, payload)
    if args.init_review:
        with (OUT / "human_review.json").open("x", encoding="utf-8") as stream:
            json.dump({"policy": "AI must not fill human sign-off. Approval binds source_hash AND decision_hash.",
                       "records": [{"stable_id": r["stable_id"], "headword": r["headword"], "risk_level": r["risk_level"],
                                    "source_hash": r["source_hash"], "decision_hash": r["decision_hash"], "status": "pending",
                                    "reviewer": None, "reviewed_at": None, "notes": "",
                                    "review_questions": [r["selection_reason"], "检查遗漏、罕见义排序、词性、虚构、误合并、追溯、初学适用性；AI不能代签。"]} for r in payload["records"]]}, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
    print(json.dumps({"mode": "checked" if args.check else "built", "records": len(payload["records"]), "high_risk": sum(r["risk_level"] == "high" for r in payload["records"]), "human_approved": 0}))


if __name__ == "__main__":
    main()
