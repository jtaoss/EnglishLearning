"""Package local P5-A review data; exclude credentials, DBs, PDF and audio."""
import hashlib
import json
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
DOCS = ROOT / 'docs/p5a'
OUT = ROOT / 'output/p5a'
OUT.mkdir(parents=True, exist_ok=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


files = sorted(p for base in [DOCS, ROOT / 'scripts/p5a'] for p in base.rglob('*')
               if p.is_file() and p.suffix in {'.csv', '.json', '.md', '.txt', '.py'}
               and p.name != 'delivery_manifest.json')
files += [ROOT / 'docs/p41/texture-mapping.json', ROOT / 'assets/pronunciation/ATTRIBUTION.md']
manifest = {
    'scope': 'local data review only; no formal Notion write or app release',
    'requires_existing_project_private_inputs_for_rebuild': True,
    'files': {p.relative_to(ROOT).as_posix(): {'bytes': p.stat().st_size, 'sha256': sha(p)} for p in files},
}
manifest_path = DOCS / 'delivery_manifest.json'
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
files.append(manifest_path)
target = OUT / 'EnglishLearning-P5A-data-review.zip'
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for p in sorted(files):
        rel = p.relative_to(ROOT).as_posix()
        assert not any(part in {'private', '__pycache__'} for part in p.relative_to(ROOT).parts)
        info = zipfile.ZipInfo(rel, date_time=(2026, 11, 9, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        z.writestr(info, p.read_bytes())
with zipfile.ZipFile(target) as z:
    assert z.testzip() is None
    for rel, record in manifest['files'].items():
        assert hashlib.sha256(z.read(rel)).hexdigest() == record['sha256']
(OUT / 'package-sha256.txt').write_text(sha(target) + '  ' + target.name + '\n', encoding='utf-8')
print(json.dumps({'file': str(target), 'bytes': target.stat().st_size, 'files': len(files), 'sha256': sha(target)}))
