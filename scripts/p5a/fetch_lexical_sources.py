"""Cache openly licensed lexical reference data; no commercial dictionary scraping."""
import hashlib
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'private/p5a/sources'
OUT.mkdir(parents=True, exist_ok=True)
SOURCES = {
    'wordnet30.tar.gz': 'https://wordnetcode.princeton.edu/3.0/WordNet-3.0.tar.gz',
    'cow-cmn.tab': 'https://raw.githubusercontent.com/omwn/omw-data/main/wns/cow/wn-data-cmn.tab',
    'COW_LICENSE': 'https://raw.githubusercontent.com/omwn/omw-data/main/wns/cow/LICENSE',
}
EXPECTED = {
    'wordnet30.tar.gz':'640db279c949a88f61f851dd54ebbb22d003f8b90b85267042ef85a3781d3a52',
    'cow-cmn.tab':'379fd2e41d3e1395f9f27cf23a39c6181849ffb4020c14a07ed2a4d4dd651122',
    'COW_LICENSE':'81a3cb1f97e120581d67c71424f2de5dd96325d951f991e8a092147a2a4b2321',
}
manifest = []
for name, url in SOURCES.items():
    path = OUT / name
    if not path.exists():
        request = urllib.request.Request(url, headers={'User-Agent': 'EnglishLearning-P5A-data-audit/1.0'})
        with urllib.request.urlopen(request, timeout=120) as r:
            data = r.read()
        path.write_bytes(data)
    assert hashlib.sha256(path.read_bytes()).hexdigest()==EXPECTED[name], 'Reference changed: review the new source, never silently replace approvals.'
    manifest.append({'file': name, 'url': url, 'bytes': path.stat().st_size,
                     'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps(manifest))
