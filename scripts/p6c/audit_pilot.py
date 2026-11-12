"""Write a human review worksheet and AI-audit statistics, never approvals."""

from collections import Counter
import hashlib
import json

from validate_pilot import OUT, ROOT, inputs, validate


def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def group_text(groups):
    return " / ".join(g["part_of_speech"] + "：" + "、".join(g["glosses"]) for g in groups) or "—"


def main():
    args = inputs()
    payload, formal, selection, evidence, ledger = args
    summary = validate(*args)
    before = json.loads((OUT / "draft_v1_findings.json").read_text(encoding="utf-8"))
    current = {r["headword"]: r for r in payload["records"]}
    observed = []
    controls = []
    for old in before["records"]:
        after = current[old["headword"]]
        if "false_merge_corrected" in after["risk_flags"]:
            old["finding_status"] = "AI_suspected_over_merge_split_in_v2_pending_human"
            observed.append(old["headword"])
        else:
            old["finding_status"] = "control_old_draft_already_separated_no_merge_issue_observed"
            controls.append(old["headword"])
    before["finding_type"] = "AI_review_of_possible_over_merges_in_old_draft_including_negative_controls"
    before["audit_summary"] = {"split_candidates": observed, "negative_controls": controls}
    save("draft_v1_findings.json", before)
    stats = {
        **summary,
        "formal_schema": {"rows": len(formal), "columns": list(formal[0]),
                          "library_counts": dict(Counter(r["library_class"] for r in formal)),
                          "book_category_counts": dict(Counter(r["book_category"] for r in formal)),
                          "missing_meaning": sum(not r["meaning_zh"] for r in formal),
                          "missing_pos": sum(not r["part_of_speech"] for r in formal)},
        "old_draft_AI_findings": {"over_merge_split_candidates": len(observed), "headwords": observed, "negative_controls": controls,
                                  "limitation": "AI semantic judgments, not adjudicated human error counts"},
        "source_coverage": "263/263 formal lexical slices retained; does not prove completeness against all English dictionary senses",
        "lexical_reference_coverage": {"matched_headwords": sum(bool(v) for v in evidence["headwords"].values()), "scope": "headword/POS references only; per-Chinese-sense translation and ranking not automatically verified"},
        "review_dimensions": ["important_sense_omission", "rare_sense_first", "pos_confusion", "invented_meaning", "false_merge", "source_traceability", "beginner_PETS3_suitability"],
        "record_reviews": [{"stable_id": r["stable_id"], "headword": r["headword"], "reviewer_type": "AI_session_editorial_audit",
                            "AI_checked_dimensions": "all_seven_with_limits_no_accuracy_claim", "risk_level": r["risk_level"],
                            "findings": r["risk_flags"], "notes": r["selection_reason"], "human_status": "pending"} for r in payload["records"]],
    }
    save("semantic_audit.json", stats)
    table = ["# P6-C 100 词人工复核工作表", "", "这是待签审工作表；所有内容是 AI 草稿。AI 检查不等于人工复核完成。先看高风险词，再看其余词。正式释义没有被改写。", "", "人工审核请在 human_review.json 中逐条填写 reviewer、reviewed_at、notes 和 status。必须保留与当前输入和决定相同的 source_hash、decision_hash；任何改动均需重新绑定审核。", "", "七项核对：重要义遗漏、罕见义排首、词性混淆、凭空增义、误合并、来源追溯、初学/PETS-3适用性。排序没有官方频率证据。", "", "| 词 | 组别 / 风险 | 原始释义 | 核心 | 扩展 | 其他 | AI 选择理由 | 人工状态 |", "|---|---|---|---|---|---|---|---|"]
    for r in sorted(payload["records"], key=lambda r: (r["risk_level"] != "high", r["headword"])):
        columns = [r["headword"], f"{r['cohort']} / {r['risk_level']}", r["original_meaning_zh"], group_text(r["core_meanings"]), group_text(r["extended_meanings"]), group_text(r["other_meanings"]), r["selection_reason"], "待审核"]
        table.append("| " + " | ".join(c.replace("|", "\\|").replace("\n", " ") for c in columns) + " |")
    (OUT / "REVIEW_WORKSHEET.md").write_text("\n".join(table) + "\n", encoding="utf-8")
    # Future model calls need only produce compact semantic decisions; exact
    # traces and hashes are assembled locally, reducing tokens and hallucination.
    rates = json.loads((OUT / "pricing_reference.json").read_text())["rates"]
    scenarios = {}
    for model, rate in rates.items():
        single = (5332 * 1000 * rate["input_usd_per_million"] + 5332 * 700 * rate["output_usd_per_million"]) / 1_000_000
        scenarios[model] = {"single_pass_usd": round(single, 2), "two_full_passes_usd": round(single * 2, 2), "single_plus_20_percent_review_usd": round(single * 1.2, 2)}
    save("cost_estimate.json", {"status": "estimate_only_no_model_API_calls_made", "word_count": 5332,
                              "assumed_input_tokens_per_word": 1000, "assumed_output_tokens_per_word": 700,
                              "token_estimates_not_tokenizer_measurements": True, "assumptions": "10-word chunks with shared prompt, compact AI decisions only; local traces not billed. No cache/batch discount. 20% review is a hypothetical planning scenario, not extrapolation of the deliberately stratified sample.",
                              "excludes": ["reasoning_tokens_if_billed_separately_or_in_output", "retries", "human_review", "Codex subscription/session usage", "tax_and_currency_conversion"],
                              "rates_source": "pricing_reference.json", "scenarios": scenarios,
                              "source_manifest_sha256": hashlib.sha256((OUT / "pricing_reference.json").read_bytes()).hexdigest()})
    print(json.dumps({"records": 100, "high_risk": summary["high_risk"], "old_merge_candidates_split": len(observed), "negative_controls": controls, "costs": scenarios}, ensure_ascii=False))


if __name__ == "__main__":
    main()
