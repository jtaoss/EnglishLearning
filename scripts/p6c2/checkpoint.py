"""Validate and save explicit per-word decisions; no automatic semantic fallback."""
import collections
import hashlib
import json
import pathlib
import re
import sys

from prepare import ROOT, OUT, load, freeze

POS = {'n':'名词', 'v':'动词', 'a':'形容词', 'r':'副词'}


def read_decisions(batch):
    path = ROOT / f'scripts/p6c2/decisions_{batch:02d}.tsv'
    decisions = {}
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):
            continue
        parts = line.split('|')
        assert len(parts) == 7, parts[:1]
        word, *values = parts
        assert word not in decisions
        decisions[word] = dict(zip(['core','extended','other','reserved','reason','notes'], values))
    return decisions


def parse_record(row, decision, references):
    f = row['source_fields']
    atoms = row['original_meanings']
    layers = {}
    used = []
    for layer in ['core', 'extended', 'other']:
        groups = []
        specs = [] if decision[layer] == '-' else decision[layer].split('/')
        for i, spec in enumerate(specs):
            match = re.fullmatch(r'([nvar])(\d+(?:\+\d+)*)@([\d,]+)', spec)
            assert match, (f['word'], spec)
            pos, indices, evidence = match.groups()
            numbers = list(map(int, indices.split('+')))
            refs = [references[index-1] for index in map(int,evidence.split(',')) if index]
            assert all(ref['pos'] in ({'a','s'} if pos == 'a' else {pos}) for ref in refs), (f['word'],spec,'reference POS mismatch')
            items = [atoms[index-1] for index in numbers]
            assert all(a['part_of_speech'] in (None, POS[pos]) for a in items), (f['word'],spec,'original POS mismatch')
            used.extend(a['source_sense_id'] for a in items)
            groups.append({'sense_group_id': f"{f['entry_id']}:{layer}:{i+1}", 'part_of_speech':POS[pos],
                'display_zh': '／'.join(a['text'] for a in items), 'glosses':[a['text'] for a in items],
                'origin':'AI_grouping_of_formal_fragments_not_original_wording',
                'source_sense_ids':[a['source_sense_id'] for a in items],
                'source_subsenses':[{'source_sense_id':a['source_sense_id'], 'original_gloss':a['text'],
                    'original_pos':a['part_of_speech'], 'original_pos_evidence':a['pos_evidence'],
                    'evidence_ids':[e['evidence_id'] for e in refs]} for a in items],
                'evidence_ids':[e['evidence_id'] for e in refs],
                'evidence_relation':'AI_selected_lexical_compatibility_not_translation_gold_or_sense_frequency' if refs else 'reference_gap_pending_independent_check',
                'grouping_relation':'near_synonym_display_candidate' if len(items)>1 else 'single_original_fragment',
                'pos_assignment':'AI_dictionary_supported_recommendation_original_mapping_unknown' if any(a['part_of_speech'] is None for a in items) else 'source_explicit_or_single_POS',
                'usage_note':decision['reason']})
        layers[layer + '_meanings'] = groups
    reserved = []
    if decision['reserved'] != '-':
        for index in map(int, decision['reserved'].split(',')):
            a = atoms[index-1]
            used.append(a['source_sense_id'])
            reserved.append({**a,'reason':decision['reason'],'state':'original_retained_not_established_for_standalone_teaching'})
    assert used and collections.Counter(used) == collections.Counter(a['source_sense_id'] for a in atoms), (f['word'],'source conservation')
    assert layers['core_meanings'], f['word']
    flags = set(decision['notes'].split(','))
    if reserved:flags.add('reserved_original_items')
    if any(a['part_of_speech'] is None for a in atoms):flags.add('original_multi_POS_mapping_unknown')
    if any(not g['evidence_ids'] for groups in layers.values() for g in groups):flags.add('reference_gap')
    high = bool(flags & {'multi_pos_original_unlabelled','original_multi_POS_mapping_unknown','reserved_original_items',
                        'usage_sensitive_scope','source_translation_scope','reference_gap','medical_translation_scope'}) or len(atoms)>=4
    return {'stable_id':f['entry_id'],'headword':f['word'],'part_of_speech':f['part_of_speech'],
        'book_category':f['book_category'],'cohort':'new_400','selection_ordinal':row['ordinal'],
        'source_fields':f,'source_hash':row['source_hash'],'original_meaning_zh':f['meaning_zh'],
        'original_meanings':atoms, **layers, 'reserved_original_items':reserved,'dictionary_additions':[],
        'core_explanation':decision['reason'],'selection_reason':decision['reason'],
        'risk_level':'high' if high else 'standard','risk_flags':sorted(flags),
        'review_status':'AI_candidate_semantic_review_pending','needs_human_review':True,'human_approved':False,
        'model_version':'codex-session/p6c2-semantic-v4','prompt_version':'p6c2-rules-v4',
        'category_evidence':row['category_evidence'],
        'supporting_sources':list({e['evidence_id']:e for e in references if any(e['evidence_id'] in g['evidence_ids'] for gs in layers.values() for g in gs)}.values()),
        'publication_status':'AI_candidate_not_formal_content','official_exam_focus':False,
        'review_independence':'generation is current Codex session; second-pass review must be separately recorded, not a claimed independent model'}


def main(batch):
    freeze()
    selection = load('docs/p6/p6c2/selection_400.json')['new_records']
    refs = load('docs/p6/p6c2/wordnet_400.json')['headwords']
    rows = [r for r in selection if r['batch'] == batch]
    decisions = read_decisions(batch)
    assert len(rows) == len(decisions) == 50
    assert {r['source_fields']['word'] for r in rows} == set(decisions)
    records = [parse_record(r,decisions[r['source_fields']['word']], refs[r['source_fields']['word']]) for r in rows]
    path = OUT / 'checkpoints' / f'batch_{batch:02d}.json'
    path.parent.mkdir(exist_ok=True)
    payload = {'batch':batch,'record_count':50,'processed':50,'failed':0,
               'generation':'explicit current-session AI decisions; no external model API requests',
               'model_api_usage':None,'model_api_usage_reason':'No external requests; session tokens/cost not exposed',
               'input_hash':hashlib.sha256(json.dumps(rows,ensure_ascii=False,sort_keys=True).encode()).hexdigest(),
               'records':records}
    if path.exists():
        assert json.loads(path.read_text(encoding='utf-8')) == payload, 'Checkpoint drift; record a separate revision instead'
    else:
        with path.open('x',encoding='utf-8') as f:
            json.dump(payload,f,ensure_ascii=False,indent=2)
            f.write('\n')
    print(json.dumps({'batch':batch,'records':50,'high_risk':sum(r['risk_level']=='high' for r in records),'failed':0}))


if __name__ == '__main__':
    main(int(sys.argv[1]))
