"""Offline P5-B Notion import preview.

Reads the public P5-A tables only. It does not open Notion, credentials,
SQLite, or the source PDF.
"""

import csv
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PUBLIC = ROOT / "docs" / "p5a" / "public"
OUT = ROOT / "docs" / "p5b"
CLIENT_FIELDS = [
    "entry_id",
    "word",
    "meaning_zh",
    "book_category",
    "source_file",
    "source_id",
    "source_pdf_pages",
    "source_index_pages",
    "book_verification",
    "meaning_review_status",
    "pets2015_status",
    "pets2025_status",
    "library_class",
    "part_of_speech",
    "usage_note",
    "lexical_sources",
    "example_en",
    "example_zh",
    "learning_priority",
    "selection_reason",
    "phonics_note",
    "syllables",
    "stress",
    "reading_review_status",
    "audio_status",
    "audio_source",
    "audio_license",
    "pets2015_evidence",
    "pets2015_match_method",
]
PERSONAL_FIELDS = [
    "学习状态",
    "发音状态",
    "自然拼读状态",
    "听音学习状态",
    "笔记",
    "评级",
    "复习日期",
    "学习事件",
]
POLICY = "不提供、不重置、不覆盖；日期/评级/笔记保留"


def read_rows(path: Path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_rows(path: Path, rows, fields):
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main():
    formal = read_rows(PUBLIC / "formal_learning_vocabulary.csv")
    reviewed = read_rows(ROOT / "assets" / "vocabulary" / "reviewed500.csv")
    selected = read_rows(PUBLIC / "selected_vocabulary.csv")
    pending = read_rows(PUBLIC / "manual_review.csv")
    deferred = read_rows(PUBLIC / "deferred_vocabulary.csv")
    mapping = read_rows(PUBLIC / "field_mapping.csv")
    reviewed_by_id = {row["entry_id"]: row for row in reviewed}
    selected_ids = {row["entry_id"] for row in selected}
    formal_ids = [row["entry_id"] for row in formal]
    if len(formal_ids) != len(set(formal_ids)):
        raise SystemExit("formal library has duplicate IDs")
    if set(formal[0]) != set(CLIENT_FIELDS):
        raise SystemExit("formal columns differ from the client field list")

    preview = []
    changed_rows = []
    for row in formal:
        old = reviewed_by_id.get(row["entry_id"])
        if old is None:
            action = "新增"
            changed = ""
        else:
            changed_fields = [field for field in CLIENT_FIELDS if (old.get(field) or "") != (row.get(field) or "")]
            action = "更新" if changed_fields else "保持不变"
            changed = "|".join(changed_fields)
            if changed_fields:
                changed_rows.append(row["entry_id"])
        preview.append(
            {
                "entry_id": row["entry_id"],
                "word": row["word"],
                "action": action,
                "processing_status": "正式入选",
                "candidate_scope": "original_5552" if row["entry_id"] in selected_ids else "retained_texture",
                "changed_fields": changed,
                "personal_fields_policy": POLICY,
            }
        )
    for row in pending:
        preview.append(
            {
                "entry_id": row["entry_id"],
                "word": row["word"],
                "action": "跳过-待核实",
                "processing_status": row["processing_status"],
                "candidate_scope": "original_5552",
                "changed_fields": "",
                "personal_fields_policy": POLICY,
            }
        )
    for row in deferred:
        preview.append(
            {
                "entry_id": row["entry_id"],
                "word": row["word"],
                "action": "跳过-暂缓",
                "processing_status": row["processing_status"],
                "candidate_scope": "original_5552",
                "changed_fields": "",
                "personal_fields_policy": POLICY,
            }
        )

    actions = Counter(row["action"] for row in preview)
    mapped_names = {row["notion_property"] for row in mapping}
    client_names = {
        "词条ID",
        "单词",
        "中文词义",
        "原书分类",
        "来源文件",
        "来源ID",
        "原书PDF页码",
        "索引PDF页码",
        "原书核验状态",
        "释义复核说明",
        "PETS3 2015收录状态",
        "PETS3 2025收录状态",
        "学习词库分类",
        "词性",
        "用法说明",
        "释义来源",
        "原创例句",
        "例句译文",
        "学习优先级",
        "筛选理由",
        "拼读提示",
        "音节说明",
        "重音说明",
        "拼读复核说明",
        "音频许可状态",
        "标准音频来源",
        "标准音频许可",
        "PETS3 2015证据",
        "PETS3 2015匹配方法",
    }
    disposition = []
    for row in pending:
        head_pending = "原书正文词头仍待核实" in row["blocking_issues"]
        disposition.append(
            {
                "entry_id": row["entry_id"],
                "word": row["word"],
                "book_category": row["book_category"],
                "book_verification": row["book_verification"],
                "blocking_issues": row["blocking_issues"],
                "source_verification_method": row["source_verification_method"],
                "disposition": "仍待人工核实",
                "promoted_to_formal_library": "否",
                "evidence_note": (
                    "本机没有原书 PDF，也没有 private/p5a 补查缓存；未重新 OCR，未把拟用释义改成已确认。"
                    + (
                        "既有记录仍是正文词头未得到行首完整词形支持。"
                        if head_pending
                        else "既有来源记录不能消除释义、语域或大小写上的人工核实要求。"
                    )
                ),
            }
        )

    OUT.mkdir(parents=True, exist_ok=True)
    fields = [
        "entry_id",
        "word",
        "action",
        "processing_status",
        "candidate_scope",
        "changed_fields",
        "personal_fields_policy",
    ]
    write_rows(OUT / "notion_import_preview.csv", preview, fields)
    write_rows(
        OUT / "manual_review_disposition.csv",
        disposition,
        list(disposition[0]),
    )
    summary = {
        "version": "0.7.0+10",
        "stage": "P5-B",
        "remote_writes": 0,
        "events_uploaded": 0,
        "live_notion_queried": False,
        "ocr_performed": False,
        "source_pdf_rechecked": False,
        "formal_library": len(formal),
        "selected_original": len(selected),
        "retained_texture": len(formal) - len(selected),
        "existing_reviewed": len(reviewed),
        "content_field_updates": len(changed_rows),
        "updated_entry_ids": changed_rows,
        "preview_actions": dict(actions),
        "pending_remaining": len(pending),
        "pending_promoted": 0,
        "deferred_remaining": len(deferred),
        "duplicate_formal_ids": 0,
        "client_field_count": len(CLIENT_FIELDS),
        "formal_columns_match_client": True,
        "mapping_properties_not_read_by_client": sorted(mapped_names - client_names),
        "client_properties_missing_from_mapping_file": sorted(client_names - mapped_names),
        "personal_fields_excluded": PERSONAL_FIELDS,
        "notion_query_groups": (len(formal) + 99) // 100,
        "notion_page_size": 100,
        "notion_max_pages_per_group": 10,
        "notion_spacing_milliseconds": 350,
    }
    (OUT / "diff_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()
