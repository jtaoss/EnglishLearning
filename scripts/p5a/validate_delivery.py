"""Independent checks of persisted P5-A files. No network or database writes.

--check-rebuild also runs the offline compiler twice and compares byte hashes.
This checks data contracts and preservation, not teacher-level lexical accuracy.
"""
import argparse
import collections
import csv
import hashlib
import json
import pathlib
import re
import sqlite3
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/p5a'


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def rows(name):
    with open(OUT / name, encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8-sig'))


def run(rebuild=False):
    checks = {}
    groups = {name: rows(name + '.csv') for name in
              ['selected_vocabulary', 'deferred_vocabulary', 'manual_review']}
    audit = rows('all_candidates_audit.csv')
    raw = rows('original_candidates.csv')
    ids = {r['词条ID'] for r in raw}
    assert len(raw) == len(ids) == len(audit) == 5552
    assert sha(OUT / 'original_candidates.csv') == sha(ROOT / 'private/p3/source/词头候选台账.csv')
    joined = [r for group in groups.values() for r in group]
    assert len(joined) == 5552 and {r['entry_id'] for r in joined} == ids
    assert len({r['entry_id'] for r in joined}) == 5552
    assert {r['entry_id']: r for r in joined} == {r['entry_id']: r for r in audit}
    expected = {'selected_vocabulary': '正式入选', 'deferred_vocabulary': '暂缓学习',
                'manual_review': '待人工核实'}
    for group, records in groups.items():
        assert all(r['processing_status'] == expected[group] for r in records)
    original = {r['词条ID']: r for r in raw}
    for r in audit:
        assert all(r['original_' + k] == v for k, v in original[r['entry_id']].items())
    checks['5552_exclusive_conservation_and_all_original_fields'] = True
    mandatory = [r for r in audit if r['book_category'] in {'高频词', '中频词', '基础词'}]
    assert len(mandatory) == 3407
    assert all(r['recommend_keep'] == '保留' and r['processing_status'] != '暂缓学习' for r in mandatory)
    checks['mandatory_keep_without_ai_rejection'] = True

    by_head = {r['word']: r for r in audit}
    assert len(by_head) == 5552
    for left, right in [('May', 'may'), ('March', 'march'), ('resume', 'résumé')]:
        assert by_head[left]['entry_id'] != by_head[right]['entry_id']
    normalization = rows('head_normalizations.csv')
    assert len(normalization) == 1 and normalization[0]['original_单词'] == 'Leap'
    assert normalization[0]['word'] == 'leap'
    checks['case_accent_separation_and_historical_Leap_id'] = True

    with open(ROOT / 'assets/vocabulary/reviewed500.csv', encoding='utf-8-sig') as f:
        old = list(csv.DictReader(f))
    formal = rows('formal_learning_vocabulary.csv')
    preserved = rows('preserved_existing500.csv')
    assert preserved == old and len(old) == 500
    assert len(formal) == len({r['entry_id'] for r in formal}) == 5332
    formal_by_id = {r['entry_id']: r for r in formal}
    assert all(formal_by_id[r['entry_id']] == r for r in old)
    retained = rows('retained_supplemental.csv')
    assert len(retained) == 1 and retained[0]['word'] == 'texture'
    assert retained[0]['entry_id'] not in ids and retained[0] in old
    checks['existing500_all29_fields_and_texture_preserved'] = True

    required = ['entry_id', 'word', 'part_of_speech', 'meaning_zh', 'book_category',
                'source_file', 'source_pdf_pages', 'learning_priority', 'pets2015_status',
                'pets2025_status', 'meaning_review_status', 'audio_status', 'reading_review_status']
    assert all(all(r[k].strip() for k in required) for r in formal)
    assert all(r['pets2025_status'] == '待核实' for r in formal)
    new = [r for r in formal if r['entry_id'] not in {x['entry_id'] for x in old}]
    assert len(new) == 4832
    assert all(not r[k] for r in new for k in ['phonics_note', 'syllables', 'stress', 'example_en', 'example_zh'])
    display_fields = ['word', 'meaning_zh', 'part_of_speech', 'phonics_note', 'syllables', 'stress', 'example_en', 'example_zh']
    assert not any(re.search('[\u0250-\u02af\u02c8\u02cc]', r[k]) for r in formal for k in display_fields)
    checks['required_content_present_no_invented_new_phonics_or_IPA'] = True

    preview = rows('notion_import_preview.csv')
    assert len(preview) == len({r['entry_id'] for r in preview}) == 5553
    counts = collections.Counter(r['action'] for r in preview)
    assert dict(counts) == {'新增': 4832, '保持不变': 500, '跳过-待核实': 194, '跳过-暂缓': 27}
    plans = read('docs/p5a/notion_content_payloads.json')
    snapshot = read('private/p5a/notion-direct-live.json')
    schema = snapshot['schema']['properties']
    assert len(plans) == 4832 and len(snapshot['results']) == 500
    forbidden = {'学习状态', '发音状态', '自然拼读状态', '个人笔记', '最近复习', '下次复习', '词义评级', '发音评级'}
    lengths = []
    for p in plans:
        props = p['properties']
        assert p['action'] == '新增' and props['词条ID'] == p['entry_id']
        assert not (set(props) & forbidden)
        for key, value in props.items():
            assert key in schema and not any(x in key for x in ['复习', '评级', '日期'])
            assert schema[key]['type'] in {'rich_text', 'title', 'select'}
            assert isinstance(value, str)
            lengths.append(len(value))
            if schema[key]['type'] == 'select':
                assert value in {x['name'] for x in schema[key]['select']['options']}
    assert max(lengths) <= 2000
    assert not rows('stable_id_conflicts.csv') and not rows('notion_updates.csv')
    assert snapshot['content_writes'] == snapshot['event_uploads'] == 0
    checks['preview_schema_safe_personal_fields_excluded_max_text_length'] = max(lengths)

    before = read('private/p5a/personal-before.json')
    db = pathlib.Path('C:/Users/Administrator/AppData/Roaming/Personal/English Learning/english_learning_v1.sqlite3')
    with sqlite3.connect(db.as_uri() + '?mode=ro', uri=True) as con:
        con.row_factory = sqlite3.Row
        assert con.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        after = {t: [dict(r) for r in con.execute(f'SELECT * FROM "{t}" ORDER BY 1')] for t in before}
    assert before == after
    checks['personal_sqlite_tables_unchanged'] = {t: len(v) for t, v in after.items()}

    protected = {
        'assets/vocabulary/reviewed500.csv': '09cd736d61c40f9614239e451f5894ad464f2ff69a863d50bde95b03b87f651d',
        'output/windows/EnglishLearning-0.7.0+10-Windows.zip': '902bf437bf528ce49973b7625fce1c3d920b7fe9e825bc17a1fc3e4e30c6466e',
        'E:/desktop/2025考研英语词汇闪过.pdf': '5e4501eb7237e59ddbc6a2ba0d83bfc3874c963ded439e6394b711afd2ba192a',
    }
    for path, expected_sha in protected.items():
        assert sha(ROOT / path) == expected_sha, path
    checks['protected_source_pack_and_release_hashes'] = protected
    starter = read('private/p3/starter-hashes-before.json')
    count = 0
    for base, files in starter.items():
        for path, expected_sha in files.items():
            assert sha(pathlib.Path(base) / path) == expected_sha, (base, path)
            count += 1
    checks['unchanged_starter_files'] = count

    files = [p for base in [OUT, ROOT / 'scripts/p5a'] for p in base.rglob('*')
             if p.is_file() and p.suffix in {'.csv', '.json', '.py', '.md', '.txt'}]
    secret_pattern = re.compile(r'\b(?:ntn_|secret_)[A-Za-z0-9_-]{20,}')
    assert not any(secret_pattern.search(p.read_text(encoding='utf-8-sig')) for p in files)
    checks['public_files_without_notion_token_patterns'] = len(files)

    if rebuild:
        # Reports/independent validator output are excluded: only compiler-owned files.
        ignored = {'independent_validation.json', 'delivery_manifest.json'}
        targets = [p for p in OUT.iterdir() if p.suffix in {'.csv', '.json'} and p.name not in ignored]
        baseline = {p.name: sha(p) for p in targets}
        for _ in range(2):
            result = subprocess.run([sys.executable, '-X', 'utf8', str(ROOT / 'scripts/p5a/build_delivery.py')],
                                    cwd=ROOT, capture_output=True, text=True, encoding='utf-8')
            assert result.returncode == 0, result.stderr[-2000:]
            assert {p.name: sha(p) for p in targets} == baseline
        checks['two_offline_rebuilds_byte_identical'] = len(targets)

    result = {'status': 'PASS', 'scope': 'data contracts, preservation, local dry run; not teacher certification or remote write acceptance',
              'checks': checks, 'cloud_writes': 0, 'event_uploads': 0}
    (OUT / 'independent_validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': 'PASS', 'checks': len(checks), 'starter_files': count, 'csv_counts': {k: len(v) for k, v in groups.items()}}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check-rebuild', action='store_true')
    run(parser.parse_args().check_rebuild)
