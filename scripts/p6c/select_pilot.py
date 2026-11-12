"""Select the mutually exclusive P6-C 100-word pilot. Read-only on the formal CSV."""

import csv
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORMAL = ROOT / "docs" / "p5a" / "public" / "formal_learning_vocabulary.csv"
OUT = ROOT / "docs" / "p6" / "p6c" / "selection.json"

POS_SPLIT = re.compile(r"[；;]")
LABEL = re.compile(
    r"(名词|动词|形容词|副词|介词|连词|代词|数词|限定词|助动词|系动词|情态动词|感叹词)[:：]"
)


def pos_parts(row):
    return [part.strip() for part in POS_SPLIT.split(row["part_of_speech"] or "") if part.strip()]


def segments(row):
    return [part.strip() for part in POS_SPLIT.split(row["meaning_zh"]) if part.strip()]


def page_number(row):
    match = re.search(r"\d+", row["source_pdf_pages"] or "")
    return int(match.group(0)) if match else 10**9


def stable_hash(entry_id):
    return hashlib.sha256(f"p6c-pilot-1:{entry_id}".encode()).hexdigest()


def evenly_spaced(pool, count):
    if len(pool) <= count:
        return list(pool)
    return [pool[round(i * (len(pool) - 1) / (count - 1))] for i in range(count)]


def take(pool, count, used):
    chosen = []
    for row in pool:
        if row["entry_id"] in used:
            continue
        chosen.append(row)
        if len(chosen) == count:
            break
    used.update(row["entry_id"] for row in chosen)
    return chosen


def main():
    rows = list(csv.DictReader(FORMAL.open(encoding="utf-8-sig")))
    for row in rows:
        row["_pos"] = pos_parts(row)
        row["_segs"] = segments(row)
        row["_labels"] = len(LABEL.findall(row["meaning_zh"]))

    simple_pool = [
        row
        for row in rows
        if row["book_category"] == "基础词"
        and len(row["_pos"]) == 1
        and len(row["_segs"]) == 1
        and row["_labels"] == 0
    ]
    simple_pool.sort(key=lambda row: row["entry_id"])
    complex_pool = [row for row in rows if len(row["_pos"]) >= 2]
    complex_pool.sort(key=lambda row: (-len(row["_pos"]), -row["_labels"], row["entry_id"]))
    synonym_clusters = {
        "pub",
        "imitate",
        "adequate",
        "apparatus",
        "rectify",
        "turmoil",
    }
    # These single-POS heads have visibly different senses in the formal gloss.
    # They replace semicolon lists that are only near-synonyms.
    explicit_polysemes = ["volume", "bank", "run", "date", "yard", "miss"]
    by_word = {row["word"].lower(): row for row in rows}
    poly_rest = [
        row
        for row in rows
        if len(row["_pos"]) == 1
        and len(row["_segs"]) >= 3
        and row["word"].lower() not in synonym_clusters
        and row["word"].lower() not in explicit_polysemes
    ]
    poly_rest.sort(key=lambda row: (-len(row["_segs"]), row["entry_id"]))
    poly_pool = [by_word[word] for word in explicit_polysemes] + poly_rest
    high_pool = [
        row
        for row in rows
        if row["book_category"] == "高频词" and len(row["_pos"]) == 1
    ]
    high_pool.sort(key=lambda row: (page_number(row), row["word"].lower(), row["entry_id"]))

    used = set()
    groups = {
        "complex_pos": take(complex_pool, 20, used),
        "polyseme": take(poly_pool, 20, used),
    }
    high_remaining = [row for row in high_pool if row["entry_id"] not in used]
    groups["high_frequency"] = evenly_spaced(high_remaining, 20)
    used.update(row["entry_id"] for row in groups["high_frequency"])
    simple_remaining = [row for row in simple_pool if row["entry_id"] not in used]
    groups["simple"] = evenly_spaced(simple_remaining, 20)
    used.update(row["entry_id"] for row in groups["simple"])
    random_pool = [row for row in rows if row["entry_id"] not in used]
    random_pool.sort(key=lambda row: stable_hash(row["entry_id"]))
    groups["random"] = take(random_pool, 20, used)

    def pack(row, cohort):
        return {
            "cohort": cohort,
            "entry_id": row["entry_id"],
            "word": row["word"],
            "meaning_zh": row["meaning_zh"],
            "part_of_speech": row["part_of_speech"],
            "book_category": row["book_category"],
            "library_class": row["library_class"],
            "source_pdf_pages": row["source_pdf_pages"],
            "pets2015_status": row["pets2015_status"],
            "pets2025_status": row["pets2025_status"],
            "meaning_review_status": row["meaning_review_status"],
            "lexical_sources": row["lexical_sources"],
            "usage_note": row["usage_note"],
            "example_en": row["example_en"],
            "example_zh": row["example_zh"],
            "sense_segments": row["_segs"],
            "pos_parts": row["_pos"],
        }

    payload = {
        "formal_rows": len(rows),
        "pool_sizes": {
            "simple_single_gloss_basic": len(simple_pool),
            "complex_pos": len(complex_pool),
            "single_pos_three_or_more_segments": len(poly_pool),
            "high_frequency": len(high_pool),
        },
        "groups": {
            name: [pack(row, name) for row in chosen] for name, chosen in groups.items()
        },
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print("wrote", OUT)
    for name, chosen in groups.items():
        print(f"## {name} {len(chosen)}")
        for row in chosen:
            print(f"{row['word']}\t{row['part_of_speech']}\t{row['meaning_zh']}")


if __name__ == "__main__":
    main()
