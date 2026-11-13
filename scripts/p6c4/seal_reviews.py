"""Seal actual review outputs and verify source-first scope/provenance."""
import argparse
import collections
import datetime
import json
from prepare import ROOT,OUT,PRIVATE,read,sha,canonical,save,once,verify_protection

LAYERS=('core_meanings','extended_meanings','other_meanings')

def normalize_blind(r):
    """Read-only adapter for A's groups/core envelope; proposals stay sealed."""
    if 'groups' not in r:return r
    return {**r,**{k:r['groups'][k.removesuffix('_meanings')] for k in LAYERS},
            'reserved_original_items':r['reserved']}

def frozen_protocols():
    for name in ['PROTOCOL_SEAL.json','GENERATION_SEAL.json']:
        for p,h in read('docs/p6/p6c4/'+name)['files'].items():assert sha(ROOT/p)==h,'Sealed input changed: '+p
    s=read('docs/p6/p6c4/SUPPLEMENT_SEAL.json');assert sha(ROOT/s['file'])==s['sha256']
    assert s['base_protocol_sha256']==sha(OUT/'PROTOCOL_SEAL.json')
    verify_protection()

def regression():
    frozen_protocols()
    path=OUT/'regression_review/review_500.json';d=json.loads(path.read_text(encoding='utf-8'))
    assert d['context']=='fresh_nonblind_regression' and d['backend_model_id'] is None
    original={r['stable_id']:r for r in read('docs/p6/p6c2/core_meanings_500.json')['records']}
    records=[];paths=[]
    for b in range(1,11):
        p=OUT/f'regression_review/batch_{b:02d}.json';rs=json.loads(p.read_text(encoding='utf-8'))['records']
        assert len(rs)==50;records+=rs;paths.append(p)
    assert records==d['records'] and len(records)==len({r['stable_id'] for r in records})==500
    assert {r['stable_id'] for r in records}==set(original)
    historical=set(read('docs/p6/p6c4/selection_100.json')['historical48_ids'])
    for r in records:
        a=original[r['stable_id']];assert r['headword']==a['headword'] and r['source_hash']==a['source_hash']
        assert set(r['review_axes']) >= {'core_choice','POS','merge','ordering','source_coverage','important_use_coverage'}
        assert r['rationale_zh'] and all(r['review_axes'].values()) and r['human_approved'] is False
        if r['stable_id'] in historical:
            assert r['historical_risk_retained'] is True and r['historical_status']=='pending_not_auto_passed'
        for x in r['new_dictionary_candidates']:
            assert x['source_sense_ids']==[] and x['human_approved'] is False and x['evidence_ids']
    paths.append(path)
    once(OUT/'REGRESSION_REVIEW_SEAL.json',{'context':'fresh_nonblind_regression','records':500,
        'files':{p.relative_to(ROOT).as_posix():sha(p) for p in paths},
        'backend_difference_proven':False,'actual_tokens':None,'actual_cost':None})
    print('500 source-anchored semantic regression records sealed.')

def blind():
    frozen_protocols();manifest={'records':100,'context':'fresh_fork_none_source_only',
        'different_backend_proven':False,'actual_tokens':None,'actual_cost':None,'reviewers':{}}
    allids=[]
    for name in 'AB':
        path=OUT/f'blind_review/reviewer_{name}.json';packet_path=PRIVATE/f'blind_{name}.json'
        d=json.loads(path.read_text(encoding='utf-8'));packet=json.loads(packet_path.read_text(encoding='utf-8'))
        raw={r['stable_id']:r for r in packet['records']}
        assert d['context']=='fresh_fork_none_source_only' and d['input_sha256']==sha(packet_path)
        rs=d['records'];assert len(rs)==len({r['stable_id'] for r in rs})==50 and {r['stable_id'] for r in rs}==set(raw)
        parts=[];partpaths=[]
        for i in range(1,6):
            p=OUT/f'blind_review/reviewer_{name}_part_{i}.json';part=json.loads(p.read_text(encoding='utf-8'))
            sub=part['records'] if isinstance(part,dict) else part
            assert len(sub)==10;parts+=sub;partpaths.append(p)
        assert parts==rs,'Final blind records differ from checkpoints'
        for original_r in rs:
            r=normalize_blind(original_r)
            a=raw[r['stable_id']]
            for key in ('headword','source_hash','original_meaning_zh','original_meanings'):assert r[key]==a[key],(r['headword'],key)
            assert r['human_approved'] is False
            originalids={s['source_sense_id'] for s in a['original_meanings']};mapped=[]
            wn={e['evidence_id'] for e in a['unfiltered_wordnet_senses']}
            ev={e['evidence_id']:e for e in r['evidence_sources']}
            for k in LAYERS:
                for g in r[k]:
                    assert g['display_zh'] and g['part_of_speech'] and g['source_sense_ids'] and g['evidence_ids']
                    mapped+=g['source_sense_ids']
                    for eid in g['evidence_ids']:
                        assert eid in ev,(r['headword'],'uncited',eid)
                        if eid.startswith('wn31:'):assert eid in wn,(r['headword'],'wrong WordNet head',eid)
            mapped += [s['source_sense_id'] for s in r['reserved_original_items']]
            assert set(mapped)==originalids,(r['headword'],'source coverage')
            repeated={s for s,n in collections.Counter(mapped).items() if n>1}
            splits=r.get('semantic_splits',[])
            assert repeated<={s['source_sense_id'] for s in splits},(r['headword'],'unexplained split')
            for x in r['dictionary_additions']:
                assert x['source_sense_ids']==[] and x['evidence_ids'] and not x.get('human_approved',False) and not x.get('auto_promoted_to_core',False)
        manifest['reviewers'][name]={'input_sha256':sha(packet_path),'proposal_sha256':sha(path),'records':50,
             'schema_adapter':'groups.core/extended/other + reserved -> layer view only; original bytes unchanged' if name=='A' else 'identity',
             'model_configuration':d.get('model_configuration'),'backend_model_id':d.get('backend_model_id'),
             'files':{p.relative_to(ROOT).as_posix():sha(p) for p in [*partpaths,path]}}
        allids+=list(raw)
    assert len(allids)==len(set(allids))==100
    once(OUT/'BLIND_REVIEW_SEAL.json',manifest)
    print('100 independent source-only proposals sealed before comparison.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--regression',action='store_true');p.add_argument('--blind',action='store_true');args=p.parse_args()
    if args.regression:regression()
    if args.blind:blind()
