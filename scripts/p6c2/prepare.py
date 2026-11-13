"""Freeze existing work and select only 400 additional formal IDs. No SQL/network."""
import csv
import hashlib
import json
import os
import pathlib
import re
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/p6/p6c2'
sys.path.insert(0, str(ROOT / 'scripts/p6c'))
from build_core_pilot import source_atoms, canonical_hash


def load(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8-sig'))


def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


def protected_state():
    paths = []
    for base in ['docs/p6/p6c', 'docs/p6/p6c1', 'scripts/p6c', 'scripts/p6c1',
                 'lib/features/core_meanings_pilot', 'lib/features/japanese']:
        paths.extend(p for p in (ROOT / base).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    paths += [ROOT / p for p in ['docs/p6/P6C_CORE_MEANINGS_PILOT_REPORT.md',
              'docs/p6/P6C1_INDEPENDENT_REVIEW_REPORT.md', 'docs/p5a/public/formal_learning_vocabulary.csv',
              'assets/vocabulary/verified100.csv', 'assets/vocabulary/reviewed500.csv',
              'lib/p6c_pilot_main.dart', 'lib/core/storage/sqlite_learning_repository.dart']]
    state = {p.relative_to(ROOT).as_posix(): {'bytes': p.stat().st_size, 'sha256': sha(p)} for p in paths if p.exists()}
    db = pathlib.Path(os.environ['APPDATA']) / 'Personal/English Learning/english_learning_v1.sqlite3'
    for suffix in ['', '-wal', '-shm', '-journal']:
        p = pathlib.Path(str(db) + suffix)
        state['%APPDATA%/Personal/English Learning/english_learning_v1.sqlite3' + suffix] = {
            'exists': p.exists(), 'bytes': p.stat().st_size if p.exists() else None,
            'sha256': sha(p) if p.exists() else None,
            'mtime_ns': p.stat().st_mtime_ns if p.exists() else None}
    return state


def freeze():
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / 'preservation.json'
    now = protected_state()
    if path.exists():
        assert load(path.relative_to(ROOT))['before'] == now, 'Protected input changed; do not replace baseline'
    else:
        with path.open('x', encoding='utf-8') as f:
            json.dump({'method': 'read-only byte hashes; no database connections', 'before': now}, f, ensure_ascii=False, indent=2)


def write_once(path, data):
    if path.exists():
        assert json.loads(path.read_text(encoding='utf-8')) == data, 'Selection/reference drift'
    else:
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def main():
    freeze()
    with (ROOT / 'docs/p5a/public/formal_learning_vocabulary.csv').open(encoding='utf-8-sig', newline='') as f:
        formal = list(csv.DictReader(f))
    assert len(formal) == len({r['entry_id'] for r in formal}) == 5332
    old = load('docs/p6/p6c/core_meanings_pilot.json')['records']
    reviews = load('docs/p6/p6c1/independent_review.json')['records']
    assert len(old) == len(reviews) == 100 and {r['stable_id'] for r in old} == {r['stable_id'] for r in reviews}
    old_ids = {r['stable_id'] for r in old}
    by_id = {r['entry_id']: r for r in formal}
    assert all(r['source_hash'] == canonical_hash(by_id[r['stable_id']]) for r in old)
    order = {'高频词': 0, '基础词': 1, '简单词': 1, '中频词': 2, '低频词': 3, '偶考词': 4}

    def sort_key(r):
        pages = [int(x) for x in re.findall(r'\d+', r['source_pdf_pages'])]
        return (order.get(r['book_category'], 5), min(pages) if pages else 10**9, r['entry_id'])

    remaining = [r for r in formal if r['entry_id'] not in old_ids]
    selected = sorted(remaining, key=sort_key)[:400]
    assert len({r['entry_id'] for r in selected}) == 400
    # Reuse saved original-category evidence, not an estimated word/sense frequency.
    with (ROOT / 'docs/p5a/all_candidates_audit.csv').open(encoding='utf-8-sig', newline='') as f:
        audit = {r['entry_id']: r for r in csv.DictReader(f)}
    rows = []
    for index, r in enumerate(selected):
        a = audit[r['entry_id']]
        assert r['book_category'] == a['book_category'] and r['book_verification'] == '已核验'
        rows.append({'ordinal': index + 1, 'batch': index // 50 + 1,
                     'source_fields': r, 'source_hash': canonical_hash(r), 'original_meanings': source_atoms(r),
                     'category_evidence': {'status': a['book_category_status'], 'basis': a['book_category_evidence'],
                                           'source_verification': a['source_verification_method']}})
    selection = {'old_ids': [r['stable_id'] for r in old], 'new_count': 400,
                 'ordering': 'verified book category -> minimum source PDF page -> stable ID; no sense frequency inference',
                 'old_order_retained': True, 'new_records': rows}
    write_once(OUT / 'selection_400.json', selection)
    archive = ROOT / 'private/p3/wordnet31.tar.gz'
    assert sha(archive) == '3f7d8be8ef6ecc7167d39b10d66954ec734280b5bdcd57f7d9eafe429d11c22a'
    heads = {r['word'] for r in selected}
    refs = {head: [] for head in heads}
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if pathlib.PurePosixPath(member.name).name not in {'data.noun', 'data.verb', 'data.adj', 'data.adv'}:
                continue
            for raw in tar.extractfile(member):
                line = raw.decode().strip('\r\n')
                if not line or line.startswith(' '):
                    continue
                header, gloss = line.split('|', 1)
                p = header.split()
                lemmas = [p[4 + i*2].split('(')[0] for i in range(int(p[3], 16))]
                for head in heads.intersection(lemmas):
                    refs[head].append({'evidence_id': f'wn31:{p[2]}:{p[0]}', 'pos': p[2],
                                       'definition_en': gloss.strip(), 'lemmas': lemmas})
    write_once(OUT / 'wordnet_400.json', {'archive_sha256': sha(archive),
        'source': 'https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz',
        'license': 'assets/vocabulary/WORDNET_3_1_LICENSE.txt', 'headwords': refs,
        'limitations': 'Licensed lexical evidence only, not usage frequency or official PETS sense focus.'})
    print(json.dumps({'old':100,'new':400,'category_counts':{c:sum(r['book_category']==c for r in selected) for c in order},
                      'wordnet_matched':sum(bool(v) for v in refs.values())}, ensure_ascii=False))


if __name__ == '__main__':
    main()
