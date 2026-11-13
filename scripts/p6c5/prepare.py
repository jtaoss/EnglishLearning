"""Check exact A/B/C sets and freeze authoritative inputs before model generation."""
from common import *

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    PRIVATE.mkdir(parents=True, exist_ok=True)
    if (OUT / 'RUN_MANIFEST.json').exists():
        verify_frozen()
        verify_protected()
        print('Existing frozen run verified; no inputs rewritten.')
        return
    formal = formal_rows()
    byid = {r['entry_id']: r for r in formal}
    old = read(ROOT / 'docs/p6/p6c2/core_meanings_500.json')['records']
    reg = read(ROOT / 'docs/p6/p6c4/regression_500.json')['records']
    blind = read(ROOT / 'docs/p6/p6c4/blind_test_100.json')['records']
    A = {r['stable_id'] for r in old}
    B = {r['stable_id'] for r in blind}
    C = set(byid) - A - B
    require(len(formal) == len(byid) == 5332, 'Formal count or duplicate IDs')
    require(len(old) == len(A) == 500 and len(blind) == len(B) == 100, 'A/B duplicates or count drift')
    require(not A & B and len(C) == 4732 and A | B | C == set(byid), 'A/B/C partition failure')
    require(len(reg) == 500 and {r['stable_id'] for r in reg} == A, 'Regression baseline differs')
    for r in old + [x['candidate'] for x in reg + blind]:
        require(r['source_fields'] == byid[r['stable_id']], 'Source snapshot mismatch ' + r['stable_id'])
        require(r['source_hash'] == canonical(byid[r['stable_id']]), 'Source hash mismatch ' + r['stable_id'])
    require(read(ROOT / 'docs/p6/p6c4/GATE_RESULT.json')['decision'] == 'A', 'C4 has no scale-up gate')
    require(sha(RULES) == '0c94b56ac7bcef28dd3ccda29995ec3d61ade284c6ed95734418f2db87771dbe', 'Accepted rule hash differs')
    historical = read(ROOT / 'docs/p6/p6c4/regression_500.json')['historical48_review']
    require(len(historical) == 48 and all(x['status'] == 'pending_not_auto_passed' for x in historical), 'Historical48 state drift')
    save(OUT / 'PRESERVATION.json', {'utc': now(), 'files': protected(),
         'git_branch': subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip(),
         'git_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
         'git_status': subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True).splitlines()})
    category_order = {'高频词': 0, '简单词': 1, '基础词': 1, '中频词': 2, '低频词': 3, '偶考词': 4}
    order = {r['entry_id']: i for i, r in enumerate(formal)}
    def sort_key(r):
        if r['book_verification'] != '已核验':
            return 5, r['entry_id']
        return category_order.get(r['book_category'], 5), order[r['entry_id']]
    pending = sorted((byid[i] for i in C), key=sort_key)
    sets = {'A_original500': sorted(A), 'B_blind100': sorted(B), 'C_new4732_in_processing_order': [r['entry_id'] for r in pending],
            'historical48': [x['stable_id'] for x in historical],
            'selection_basis': 'Verified book category order high/simple/basic/medium/low/occasional, then existing CSV order; unverified uses stable ID. No sense-frequency claim.',
            'counts': {'A': len(A), 'B': len(B), 'C': len(C), 'formal': len(formal)}}
    save(OUT / 'INPUT_SETS.json', sets)
    refs = {r['word']: [] for r in pending}
    wanted = set(refs)
    for ps, lemmas, definition in legacy().wn_lines():
        for word in wanted.intersection(lemmas):
            refs[word].append({'evidence_id': f'wn31:{ps[2]}:{ps[0]}', 'part_of_speech': ps[2],
                'definition_en': definition, 'lemmas': lemmas,
                'source': 'https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz',
                'license': 'assets/vocabulary/WORDNET_3_1_LICENSE.txt'})
    save(OUT / 'evidence/wordnet_4732.json', {'headwords': refs,
         'archive_sha256': sha(ROOT / 'private/p3/wordnet31.tar.gz'),
         'note': 'Unfiltered licensed definitions; ordering is not a ranking or Chinese meaning mapping.'})
    for i in range(0, len(pending), 100):
        rs = pending[i:i+100]
        save(OUT / f'inputs/batch_{i//100+1:03d}.json', {'batch': i//100+1,
             'records': [packet(r, refs[r['word']]) for r in rs]})
    print(json.dumps({'A': len(A), 'B': len(B), 'C': len(C), 'batches': 48,
                     'licensed_evidence_headwords': len(refs), 'no_WordNet': sum(not v for v in refs.values())}))

if __name__ == '__main__':
    main()
