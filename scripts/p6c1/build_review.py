"""Assemble a separate, evidence-driven review of exactly the frozen 100 words.

Writes only docs/p6/p6c1. No P6-C generator import, SQL or network clients.
"""

import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path

from evidence_plan import ALIGNMENTS, CONDITIONAL, WEB_OBSERVATIONS
from review_decisions import CANDIDATES, NOTES, REVISIONS

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/p6/p6c1"
LAYERS = ("core", "extended", "other")


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return sha(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode())


def refs(spec):
    return [part if part.startswith("web:") else "wn31:" + part for part in spec.split("+")]


def group_from_old(old):
    return {"part_of_speech": old["part_of_speech"], "display_zh": "；".join(old["glosses"]),
            "source_numbers": [int(s[1:]) for s in old["source_sense_ids"]], "usage_note": "",
            "grouping_relation": "near_synonymous" if len(old["source_sense_ids"]) > 1 else "single_sense"}


def build():
    original_path = OUT / "input_p6c_snapshot.json"
    original = load(original_path)
    references_path = ROOT / "docs/p6/p6c/wordnet_evidence.json"
    reference = load(references_path)
    formal_path = ROOT / "docs/p5a/public/formal_learning_vocabulary.csv"
    with formal_path.open(encoding="utf-8-sig", newline="") as stream:
        rows = list(csv.DictReader(stream))
    formal = {r["entry_id"]: r for r in rows}
    records = original["records"]
    heads = {r["headword"] for r in records}
    if len(records) != 100 or len({r["stable_id"] for r in records}) != 100 or set(NOTES) != heads or set(ALIGNMENTS) != heads:
        raise ValueError("Review scope must be exactly the existing selected 100")
    if len(rows) != 5332 or len(formal) != 5332:
        raise ValueError("Formal IDs must remain unique")
    source_humans = load(ROOT / "docs/p6/p6c/human_review.json")
    catalog = {}
    for head, values in reference["headwords"].items():
        for e in values:
            entry = catalog.setdefault(e["evidence_id"], {"name": "Princeton WordNet 3.1", "pos": e["pos"],
                "definition_en": e["definition_en"], "selected_headwords": [],
                "local_file": "docs/p6/p6c/wordnet_evidence.json", "url": reference["source"],
                "license": reference["license"], "access": "existing_licensed_local_reference"})
            entry["selected_headwords"].append(head)
    failed_direct = {"notify", "engage", "obvious", "knock", "chop", "consumption", "couple"}
    for head, (name, url, observation) in WEB_OBSERVATIONS.items():
        catalog["web:" + head] = {"name": name, "url": url, "selected_headwords": [head],
            "observation_zh": observation, "retrieved_date_asia_shanghai": "2026-11-12",
            "access": "direct_page_retrieved" if head in {"abstract", "flush"} else "public_search_index_excerpt",
            "direct_open": "HTTP_403_no_bypass_or_mass_scraping" if head in failed_direct else "success" if head in {"abstract", "flush"} else "not_attempted",
            "copyright_handling": "short_original_paraphrase_and_link_only_no_dictionary_page_copy",
            "limitations": "词典义项/搭配参考；非语料频率、非PETS官方义项排名；搜索摘要可能不是当日页面。"}

    def check_refs(head, ids):
        for eid in ids:
            if eid not in catalog or head not in catalog[eid]["selected_headwords"]:
                raise ValueError(f"Unverified/cross-head evidence: {head} {eid}")

    reviews = []
    for old in records:
        head, stable_id = old["headword"], old["stable_id"]
        row = formal[stable_id]
        if row != old["source_fields"] or canonical(row) != old["source_hash"]:
            raise ValueError(f"Stale formal source: {head}")
        if len(ALIGNMENTS[head]) != len(old["source_senses"]):
            raise ValueError(f"Missing per-gloss alignment: {head}")
        alignment = []
        for index, atom in enumerate(old["source_senses"], 1):
            ids = refs(ALIGNMENTS[head][index - 1])
            check_refs(head, ids)
            status, note = CONDITIONAL.get((head, index), ("compatible_in_recorded_context", "逐义英语参照与中文语境相容；不是人工双语金标准或词频证明。"))
            alignment.append({**atom, "evidence_ids": ids, "assessment": status, "evidence_conclusion": note})
        revised = REVISIONS.get(head, {})
        layers = {}
        for layer in LAYERS:
            groups = revised.get(layer, [group_from_old(g) for g in old[layer + "_meanings"]])
            layers[layer + "_meanings"] = []
            for index, g in enumerate(groups, 1):
                sub = [alignment[i - 1] for i in g["source_numbers"]]
                layers[layer + "_meanings"].append({
                    "review_group_id": f"{stable_id}:p6c1:{layer}:{index}",
                    "part_of_speech": g["part_of_speech"], "display_zh": g["display_zh"],
                    "origin": "AI_review_of_formal_gloss_not_original_wording",
                    "source_sense_ids": [a["source_sense_id"] for a in sub],
                    "source_subsenses": [{"source_sense_id": a["source_sense_id"], "original_gloss": a["text"],
                                         "original_pos": a["part_of_speech"], "evidence_ids": a["evidence_ids"]} for a in sub],
                    "grouping_relation": g["grouping_relation"], "usage_note": g["usage_note"],
                    "evidence_ids": sorted({eid for a in sub for eid in a["evidence_ids"]}),
                })
        reserved = [{"source_sense_id": alignment[i - 1]["source_sense_id"], "original_gloss": alignment[i - 1]["text"],
                     "state": "contextual_paraphrase_only" if key == "contextual_only" else "unresolved_not_for_standalone_memorization",
                     "reason": alignment[i - 1]["evidence_conclusion"], "evidence_ids": alignment[i - 1]["evidence_ids"]}
                    for key in ("unresolved", "contextual_only") for i in revised.get(key, [])]
        candidates = []
        for i, (pos, zh, layer, spec, reason) in enumerate(CANDIDATES.get(head, []), 1):
            ids = refs(spec)
            check_refs(head, ids)
            candidates.append({"candidate_id": f"{stable_id}:p6c1:added:{i}", "part_of_speech": pos,
                "meaning_zh": zh, "suggested_layer": layer,
                "origin": "dictionary_evidenced_AI_addition_candidate_not_in_formal_gloss",
                "source_sense_ids": [], "evidence_ids": ids, "selection_reason": reason,
                "review_required": True, "publication_status": "isolated_proposal_only"})
        assigned = [s for groups in layers.values() for g in groups for s in g["source_sense_ids"]] + [r["source_sense_id"] for r in reserved]
        if Counter(assigned) != Counter(a["source_sense_id"] for a in alignment):
            raise ValueError(f"Dropped/duplicated original gloss: {head}")
        issue_types = []
        if reserved:
            issue_types.append("standalone_gloss_not_established_or_ambiguous")
        if candidates:
            issue_types.append("additional_use_candidate")
        if head in {"subject", "tender", "quarter", "tone", "procedure", "payment", "settlement", "chamber", "carve", "couple"}:
            issue_types.append("translation_scope_or_context")
        if head in {"chop", "consumption", "correlate", "extension", "minor"}:
            issue_types.append("memory_presentation_preserves_distinct_subsenses")
        if head in {"imitate", "remarkable", "obesity", "ability"}:
            issue_types.append("redundant_chinese_display")
        if head in {"back", "void", "get", "term", "keep", "resolution", "tone", "cripple"}:
            issue_types.append("teaching_priority_adjustment_not_frequency_fact")
        if head == "knock":
            issue_types.append("reference_based_pos_recommendation_not_book_confirmation")
        if head == "garbage":
            issue_types.append("reference_scope_limitation")
        status = "revise_with_reserved_original_items" if reserved else "revise_layer_or_display" if revised else "retain_with_addition_candidates" if candidates else "retain_with_evidence_notes"
        review = {
            "stable_id": stable_id, "headword": head, "original_part_of_speech": old["part_of_speech"],
            "original_meaning_zh": old["original_meaning_zh"], "original_risk_level": old["risk_level"],
            "source_hash": old["source_hash"], "parent_decision_hash": old["decision_hash"],
            "parent_record_hash": canonical(old), "review_version": "p6c1-independent-ai-review-1",
            "review_status": status, "issue_types": issue_types,
            "proposed_layers": layers, "reserved_original_items": reserved,
            "dictionary_addition_candidates": candidates, "source_alignment": alignment,
            "supplemental_evidence_ids": ["web:" + head] if head in WEB_OBSERVATIONS else [],
            "first_memory_rationale": NOTES[head][0],
            "illustrative_collocations": {"text": NOTES[head][1], "origin": "reviewer_authored_illustrations_not_corpus_attestations_or_frequency_evidence"},
            "eight_checks": {
                "first_learning_priority": NOTES[head][0],
                "common_extension": "保留所列扩展；扩展不等于罕见，先后是教学建议。",
                "specialized_or_limited": "其他层只表示后学/限语境；没有独立语料统计，不声称实测罕见。",
                "missing_important_uses": f"记录{len(candidates)}个来源外候选；未穷尽所有英语义项。",
                "part_of_speech": "推荐动词有独立英语依据，原书逐义词性仍未确认。" if head == "knock" else "按每个原文解释逐义对照；保持词性边界，数词教学标签不与词典编码强行等同。",
                "near_synonym_burden": "近义显示压缩与不同子义并列分开标记，不以显示单元数量冒充义项数量。",
                "over_reduction": "全部原文解释仍在冻结快照、逐义映射及修订/保留区；不以核心较少为质量目标。",
                "PETS3_learning_value": "依据上列生活/阅读/表达语境作教学判断；非PETS-3官方高频或精确考试概率。",
            },
            "evidence_strength": "mixed_with_explicit_limits" if reserved or head == "garbage" else "lexically_supported_teaching_order_unvalidated",
            "semantic_accuracy": "not_measured_against_independent_human_gold",
            "human_confirmation": "not_claimed", "review_required_before_publication": True,
        }
        review["review_hash"] = canonical(review)
        reviews.append(review)
    used_ids = {eid for r in reviews for a in r["source_alignment"] for eid in a["evidence_ids"]}
    used_ids.update(eid for r in reviews for c in r["dictionary_addition_candidates"] for eid in c["evidence_ids"])
    used_ids.update("web:" + r["headword"] for r in reviews if r["headword"] in WEB_OBSERVATIONS)
    summary = {
        "records": len(reviews), "inherited_risk_counts": dict(Counter(r["original_risk_level"] for r in reviews)),
        "original_source_glosses": sum(len(r["source_alignment"]) for r in reviews),
        "review_status_counts": dict(Counter(r["review_status"] for r in reviews)),
        "issue_type_word_counts": dict(Counter(t for r in reviews for t in r["issue_types"])),
        "reserved_original_item_count": sum(len(r["reserved_original_items"]) for r in reviews),
        "addition_candidate_words": sum(bool(r["dictionary_addition_candidates"]) for r in reviews),
        "addition_candidates": sum(len(r["dictionary_addition_candidates"]) for r in reviews),
        "original_human_status_counts": dict(Counter(r["status"] for r in source_humans["records"])),
        "human_approvals_added": 0,
        "disclaimer": "AI review findings/teaching proposals, not human-adjudicated error counts or measured accuracy",
    }
    payload = {"schema_version": 1, "scope": "existing_P6C_selected_100_only", "publication_status": "isolated_independent_review_not_released",
               "reviewer": {"actor": "Codex AI current session", "backend_model_id": None,
                            "independence": "separate files, rules and per-gloss evidence pass; same assistant, non-blind; NOT a second independent model or human review"},
               "input_snapshot": "docs/p6/p6c1/input_p6c_snapshot.json", "input_snapshot_sha256": sha(original_path.read_bytes()),
               "formal_csv_sha256": sha(formal_path.read_bytes()), "wordnet_reference_sha256": sha(references_path.read_bytes()),
               "review_plan_sha256": sha((Path(__file__).parent / "review_decisions.py").read_bytes()),
               "evidence_plan_sha256": sha((Path(__file__).parent / "evidence_plan.py").read_bytes()),
               "summary": summary, "records": reviews}
    evidence = {"evidence_catalog": {eid: catalog[eid] for eid in sorted(used_ids)},
                "limitations": "WordNet licensed local text; web sources only short paraphrases. Direct Cambridge opens returned 403 where noted; indexed excerpts are not claimed to be live full-page inspection. No corpus-frequency table or official PETS sense ranking used."}
    return payload, evidence


def group_text(groups):
    return " / ".join(g["part_of_speech"] + "：" + g["display_zh"] for g in groups) or "—"


def render_worksheet(payload):
    lines = ["# P6-C.1 100词独立AI复核对照表", "", "独立附加版本；原P6-C及正式原文未改。原始全部解释保留在快照。补充候选不混入原义项；原文疑点不当作罕见义教学。所有例搭配由复核者编写，不是语料频率证据。人工确认没有增加。", "",
             "| 词 | 原中文 | 建议核心（原义项范围） | 建议扩展 | 建议其他 | 暂存/语境转述 | 来源外候选 | 独立判断 |", "|---|---|---|---|---|---|---|---|"]
    for r in payload["records"]:
        cells = [r["headword"], r["original_meaning_zh"], *[group_text(r["proposed_layers"][layer + "_meanings"]) for layer in LAYERS],
                 "；".join(x["original_gloss"] + "（" + x["state"] + "）" for x in r["reserved_original_items"]) or "—",
                 "；".join(c["part_of_speech"] + "：" + c["meaning_zh"] + " [" + c["suggested_layer"] + "]" for c in r["dictionary_addition_candidates"]) or "—",
                 r["first_memory_rationale"]]
        lines.append("| " + " | ".join(x.replace("|", "\\|").replace("\n", " ") for x in cells) + " |")
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    payload, evidence = build()
    for name, value in (("independent_review.json", payload), ("evidence_catalog.json", evidence)):
        path = OUT / name
        if args.check:
            if load(path) != value:
                raise ValueError(f"Stale independent output: {name}")
        else:
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    worksheet = render_worksheet(payload)
    if args.check:
        if (OUT / "REVIEW_COMPARISON.md").read_text(encoding="utf-8") != worksheet:
            raise ValueError("Stale worksheet")
    else:
        (OUT / "REVIEW_COMPARISON.md").write_text(worksheet, encoding="utf-8")
    print(json.dumps(payload["summary"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
