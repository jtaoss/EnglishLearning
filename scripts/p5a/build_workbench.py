"""Build full review workbench from immutable ledger and licensed synset references."""
import collections
import csv
import hashlib
import json
import pathlib
import re
import sys
import tarfile
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/p3'))
from prepare import category, reference_index

OUT = ROOT / 'private/p5a'
SOURCES = OUT / 'sources'


def read_csv(p):
    return list(csv.DictReader(open(ROOT / p, encoding='utf-8-sig')))


ledger = read_csv('private/p3/source/词头候选台账.csv')
pack = read_csv('assets/vocabulary/reviewed500.csv')
old_by_word = {r['word']: r for r in pack}
old_by_id = {r['entry_id']: r for r in pack}
official = reference_index(json.loads((ROOT / 'private/p3/pets3-2015-text.json').read_text(encoding='utf-8')))
data, indices, exceptions = {}, {}, {}
licenses = {}
with tarfile.open(SOURCES / 'wordnet30.tar.gz') as tar:
    for member in tar.getmembers():
        name = pathlib.PurePosixPath(member.name).name
        if name == 'LICENSE':
            licenses['WORDNET30_LICENSE'] = tar.extractfile(member).read().decode()
        if name.startswith('data.') and name in ['data.noun', 'data.verb', 'data.adj', 'data.adv']:
            for raw in tar.extractfile(member):
                line = raw.decode('utf-8').rstrip()
                if not line or line.startswith(' '): continue
                header, gloss = line.split('|', 1)
                bits = header.split()
                pos = 'a' if bits[2] == 's' else bits[2]
                sid = bits[0] + '-' + pos
                count = int(bits[3], 16)
                data[sid] = {'id': sid, 'pos': pos, 'lex_file': int(bits[1]),
                             'lemmas': [bits[4 + 2*i].replace('_', ' ') for i in range(count)],
                             'gloss': gloss.strip()}
        if name.startswith('index.') and name in ['index.noun','index.verb','index.adj','index.adv']:
            for raw in tar.extractfile(member):
                line = raw.decode('utf-8').rstrip()
                if not line or line.startswith(' '): continue
                bits = line.split()
                count, ptrs = int(bits[2]), int(bits[3])
                offsets = bits[6 + ptrs:6 + ptrs + count]
                indices[bits[0], bits[1]] = [o + '-' + bits[1] for o in offsets]
        if name in ['noun.exc', 'verb.exc', 'adj.exc', 'adv.exc']:
            pos = {'noun':'n','verb':'v','adj':'a','adv':'r'}[name.split('.')[0]]
            for raw in tar.extractfile(member):
                b = raw.decode().split()
                if b: exceptions[b[0], pos] = b[1:]
for name, content in licenses.items():
    (SOURCES / name).write_text(content, encoding='utf-8')
cow = collections.defaultdict(list)
for line in (SOURCES / 'cow-cmn.tab').read_text(encoding='utf-8').splitlines():
    bits = line.split('\t')
    if len(bits) == 3 and bits[1] == 'cmn:lemma':
        cow[bits[0]].append(bits[2])
rows = []
for i, original in enumerate(ledger):
    word = original['单词']
    lookups = [word.replace(' ', '_')]
    if word.lower() != word: lookups.append(word.lower())
    senses, forms = [], []
    for pos in 'nvar':
        key = next((w for w in lookups if (w, pos) in indices), None)
        if key is None:
            # Morphology suggestions are evidence only, never replace the head.
            for w in lookups:
                if (w, pos) in exceptions:
                    forms.extend({'pos':pos,'base':b} for b in exceptions[w,pos])
            continue
        for rank, sid in enumerate(indices[key,pos][:3], 1):
            senses.append({**data[sid], 'rank_within_pos': rank, 'lookup': key,
                           'chinese_lemmas': cow.get(sid, [])})
    r = dict(original)
    r.update(candidate_row=i+1, book_category=category(original),
             pets2015_status='已收录' if word in official else '未收录',
             pets2015_evidence=official.get(word,[]), pets2025_status='待核实',
             existing=old_by_id.get(original['词条ID']), senses=senses, morphology_suggestions=forms)
    rows.append(r)
(OUT / 'workbench.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
groups=collections.defaultdict(list)
for r in rows:
    norm=''.join(c for c in unicodedata.normalize('NFKD',r['单词']).casefold() if not unicodedata.combining(c))
    groups[norm].append(r['单词'])
summary={'rows':len(rows),'case_accent_groups':[g for g in groups.values() if len(g)>1],
         'existing_exact_heads':sum(bool(r['existing']) for r in rows),
         'wordnet_matched':sum(bool(r['senses']) for r in rows),
         'cow_any_sense':sum(any(s['chinese_lemmas'] for s in r['senses']) for r in rows),
         'categories':dict(collections.Counter(r['book_category'] for r in rows))}
(OUT/'workbench-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(summary,ensure_ascii=False))
