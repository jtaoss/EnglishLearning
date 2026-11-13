"""P6-C.5 isolated data utilities. Never opens SQLite or contacts Notion."""
import collections
import csv
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/p6/p6c5'
PRIVATE = ROOT / 'private/p6c5'
RULES = ROOT / 'docs/p6/p6c4/RULES_V4_REVISED.md'
FORMAL = ROOT / 'docs/p5a/public/formal_learning_vocabulary.csv'
LAYERS = ('core_meanings', 'extended_meanings', 'other_meanings')
COMPACT_LAYERS = ('core', 'extended', 'other')
POS = {'名词': {'n'}, '动词': {'v'}, '形容词': {'a', 's'}, '副词': {'r'},
       '数词': {'a', 's', 'n'}, '代词': set(), '连词': set(), '介词': set(),
       '限定词': set(), '感叹词': set(), '助动词': set(), '情态动词': set(), '系动词': {'v'}}
POS.update({'专有名词': {'n'}, '序数词': {'a','s'}, '冠词（限定词）': set(),
            '存在句引导成分': set(), '不定式标记': set()})

def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()

def read(p):
    return json.loads(Path(p).read_text(encoding='utf-8-sig'))

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def canonical(x):
    return hashlib.sha256(json.dumps(x, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()

def save(p, x):
    p = Path(p)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + '.tmp')
    tmp.write_text(json.dumps(x, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(tmp, p)

def once(p, x):
    if Path(p).exists():
        require(read(p) == x, 'Immutable checkpoint differs: ' + str(p))
    else:
        save(p, x)

def require(ok, message):
    if not ok:
        raise ValueError(message)

def formal_rows():
    with FORMAL.open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))

def legacy():
    spec = importlib.util.spec_from_file_location('p6c4_prepare_readonly', ROOT / 'scripts/p6c4/prepare.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def atoms(row):
    return legacy().atoms(row)

def protected():
    result = {}
    folders = ['docs/p6/p6c', 'docs/p6/p6c1', 'docs/p6/p6c2', 'docs/p6/p6c3', 'docs/p6/p6c4',
               'scripts/p6c', 'scripts/p6c1', 'scripts/p6c2', 'scripts/p6c3', 'scripts/p6c4',
               'docs/p5a/public', 'assets', 'lib', 'windows', 'android', 'ios',
               'macos', 'linux', 'web', 'test/p6c2', 'test/p6c3', 'test/p6c4']
    for folder in folders:
        for p in (ROOT / folder).rglob('*'):
            if p.is_file() and not any(x in p.parts for x in ('__pycache__', 'build', '.gradle', '.cxx', 'ephemeral')):
                result[p.relative_to(ROOT).as_posix()] = {'sha256': sha(p), 'bytes': p.stat().st_size}
    for name in ['pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml']:
        p = ROOT / name
        if p.exists():
            result[name] = {'sha256': sha(p), 'bytes': p.stat().st_size}
    db = Path(os.environ['APPDATA']) / 'Personal/English Learning/english_learning_v1.sqlite3'
    for suffix in ('', '-wal', '-shm', '-journal'):
        p = Path(str(db) + suffix)
        result['%APPDATA%/Personal/English Learning/english_learning_v1.sqlite3' + suffix] = {
            'exists': p.exists(), 'sha256': sha(p) if p.exists() else None,
            'bytes': p.stat().st_size if p.exists() else None,
            'mtime_ns': p.stat().st_mtime_ns if p.exists() else None}
    return result

def verify_frozen():
    p = read(OUT / 'RUN_MANIFEST.json')
    for name, h in p['frozen_files'].items():
        require(sha(ROOT / name) == h, 'Frozen input/config changed: ' + name)
    return p

def verify_protected():
    before = read(OUT / 'PRESERVATION.json')['files']
    after = protected()
    drift = [p for p in set(before) | set(after) if before.get(p) != after.get(p)]
    require(not drift, 'Protected source/database changed: ' + ', '.join(drift[:10]))
    return {'unchanged': True, 'checked_files': len(before), 'changed': [], 'utc': now(),
            'method': 'file hashes and side-file metadata; no SQL connection'}

def load_evidence():
    return read(OUT / 'evidence/wordnet_4732.json')['headwords']

def packet(row, evidence):
    return {'id': row['entry_id'], 'word': row['word'], 'pos': row['part_of_speech'],
            'raw': row['meaning_zh'], 'usage_note': row['usage_note'],
            'senses': atoms(row), 'evidence': [
                {'id': e['evidence_id'], 'pos': e['part_of_speech'], 'definition': e['definition_en']}
                for e in evidence]}
