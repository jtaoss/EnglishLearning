"""Replay explicit AI-authored per-word decisions into isolated checkpoints."""
import argparse
import collections
import copy
import datetime
import importlib.util
import json
from pathlib import Path
from prepare import ROOT,OUT,PRIVATE,read,sha,canonical,save,once,atoms,verify_protection

LAYERS=('core_meanings','extended_meanings','other_meanings')
POS={'名词':{'n'},'动词':{'v'},'形容词':{'a','s'},'副词':{'r'},'数词':{'n','a','s'}}

def publishers():
    p={r['evidence_id']:copy.deepcopy(r) for r in read('docs/p6/p6c4/supplementary_source_evidence.json')['records']}
    for r in read('docs/p6/p6c4/source_evidence_errata.json')['corrections']:
        p[r['evidence_id']]['observation_before_erratum']=p[r['evidence_id']]['observation_zh']
        p[r['evidence_id']]['observation_zh']=r['observation_zh']
        p[r['evidence_id']]['erratum_reason']=r['reason']
    return p

def record(row,decision,raw_refs,stratum):
    original=atoms(row);byid={a['source_sense_id']:a for a in original}
    wn={e['evidence_id']:e for e in raw_refs};pub=publishers();catalog={**wn,**pub}
    refs=set();mapped=[];layers={};uses=[]
    for layer in LAYERS:
        groups=[]
        for i,group in enumerate(decision[layer],1):
            g=copy.deepcopy(group);g['sense_group_id']=f"{row['entry_id']}:p6c4:{layer}:{i}"
            assert g['part_of_speech'] in row['part_of_speech'].split('；'),(row['word'],'outside original POS',g)
            assert g['display_zh'] and g['source_sense_ids'] and g['evidence_ids'],row['word']
            assert set(g['source_sense_ids'])<=set(byid)
            for e in g['evidence_ids']:
                assert e in catalog,(row['word'],e)
                if e.startswith('wn31:'):
                    assert e.split(':')[1] in POS.get(g['part_of_speech'],set()),(row['word'],'WN POS',e)
                else:
                    assert catalog[e]['headword']==row['word'] and g['part_of_speech'] in catalog[e]['pos_supported']
            refs.update(g['evidence_ids']);mapped+=g['source_sense_ids']
            g['source_subsenses']=[{'source_sense_id':s,'original_gloss':byid[s]['text'],
                'original_pos':byid[s]['part_of_speech'],'original_pos_evidence':byid[s]['pos_evidence'],
                'evidence_ids':g['evidence_ids']} for s in g['source_sense_ids']]
            g['origin']='AI_V4_1_qualified_rephrasing_not_verbatim_source'
            if not g['usage_note']:g['usage_note']=decision['core_explanation']
            groups.append(g)
            uses.append({'use_id':g['sense_group_id'],'source_sense_ids':g['source_sense_ids'],
                         'part_of_speech':g['part_of_speech'],'meaning_zh':g['display_zh'],
                         'scope_and_roles':g['usage_note'],'evidence_ids':g['evidence_ids'],
                         'location':layer,'origin':'source_compatible_AI_recommendation','evidence_status':'lexical_support_not_frequency_or_human_gold'})
        layers[layer]=groups
    reserved=[]
    for s,reason in decision['reserved_original_items']:
        sid=f's{s:03d}';assert sid in byid
        reserved.append({**byid[sid],'reason':reason,'status':'original_preserved_evidence_pending'})
        mapped.append(sid)
    assert set(mapped)==set(byid),(row['word'],'source coverage',mapped,byid)
    repeated={s for s,n in collections.Counter(mapped).items() if n>1}
    split_reasons={f's{int(s):03d}':reason for s,reason in decision['semantic_split_reasons'].items()}
    assert repeated<=set(split_reasons),(row['word'],'unexplained repeated source refs',repeated)
    splits=[{'source_sense_id':s,'annotation':'AI语义/词性拆解，不是新的原文片段','reason':reason,
             'uses':[u for u in uses if s in u['source_sense_ids']]} for s,reason in split_reasons.items()]
    additions=copy.deepcopy(decision['dictionary_additions'])
    for i,a in enumerate(additions,1):
        assert a['source_sense_ids']==[] and a['human_approved'] is False and a['auto_promoted_to_core'] is False
        assert a['evidence_ids'] and all(e in catalog for e in a['evidence_ids']),(row['word'],'uncited addition')
        for e in a['evidence_ids']:
            if e.startswith('pub:'):assert catalog[e]['headword']==row['word']
            else:assert e.split(':')[1] in POS.get(a['part_of_speech'],set())
        refs.update(a['evidence_ids']);a['candidate_id']=f"{row['entry_id']}:p6c4:addition:{i}"
        a['suggested_layer']='adoption_and_layer_decision_pending';a['priority_basis']='AI_teaching_judgment_not_measured_frequency'
    represented={g['part_of_speech'] for layer in LAYERS for g in layers[layer]}
    source_pos_coverage={p:('represented_in_source_derived_layers' if p in represented else 'unrepresented_evidence_pending') for p in row['part_of_speech'].split('；')}
    flags=list(decision['risk_flags'])
    if len(row['part_of_speech'].split('；'))>1:flags.append('multiple_source_POS')
    if any(a['part_of_speech'] is None for a in original):flags.append('source_fragment_POS_correspondence_unknown')
    if additions:flags.append('external_use_candidates_pending_adoption')
    if reserved:flags.append('original_fragment_evidence_pending')
    if any('pending' in v for v in source_pos_coverage.values()):flags.append('source_POS_not_yet_represented')
    return {'stable_id':row['entry_id'],'headword':row['word'],'part_of_speech':row['part_of_speech'],
            'book_category':row['book_category'],'stratum':stratum,'source_fields':row,'source_hash':canonical(row),
            'original_meaning_zh':row['meaning_zh'],'original_meanings':original,**layers,
            'reserved_original_items':reserved,'dictionary_additions':additions,'semantic_splits':splits,
            'use_coverage_matrix':uses,'source_POS_coverage':source_pos_coverage,
            'core_explanation':decision['core_explanation'],'selection_reason':decision['core_explanation'],
            'risk_flags':sorted(set(flags)),'risk_level':'high' if flags else 'standard',
            'coverage_status':'core_coverage_incomplete_pending_addition_decision' if additions else 'source_fragment_pending' if reserved else 'source_supported_candidates_not_exhaustive_dictionary',
            'supporting_sources':[catalog[e] for e in sorted(refs)],
            'review_status':'AI_candidate_generation_sealed_before_blind_review','needs_human_review':True,'human_approved':False,
            'publication_status':'isolated_not_published','model_version':'Codex_parent_backend_unexposed',
            'backend_model_id':None,'prompt_version':'P6C4-V4.1','rules_sha256':sha(OUT/'RULES_V4_REVISED.md'),
            'official_exam_sense_frequency':None}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--batch',type=int);parser.add_argument('--seal',action='store_true');args=parser.parse_args()
    verify_protection()
    for p,h in read('docs/p6/p6c4/PROTOCOL_SEAL.json')['files'].items():assert sha(ROOT/p)==h,'Protocol drift'
    selected=read('docs/p6/p6c4/selection_100.json')['records'];refs=read('private/p6c4/wordnet_selected600.json')['headwords']
    if args.batch:
        b=args.batch;assert 1<=b<=5
        p=ROOT/f'scripts/p6c4/generation_{b:02d}.py'
        spec=importlib.util.spec_from_file_location(f'p6c4_generation_{b:02d}',p);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        subset=selected[(b-1)*20:b*20];assert set(module.DECISIONS)=={s['headword'] for s in subset}
        rs=[record(s['source_fields'],module.DECISIONS[s['headword']],refs[s['headword']],s['stratum']) for s in subset]
        once(OUT/f'generation/batch_{b:02d}.json',{'batch':b,'record_count':20,'decision_file_sha256':sha(p),'records':rs})
        print(f'Generation checkpoint {b}: 20 words saved.')
    if args.seal:
        assert not (OUT/'blind_review/reviewer_A.json').exists() and not (OUT/'blind_review/reviewer_B.json').exists(),'Cannot first seal generation after reviews'
        records=[];paths=[]
        for b in range(1,6):
            p=OUT/f'generation/batch_{b:02d}.json';d=json.loads(p.read_text(encoding='utf-8'));records+=d['records'];paths.append(p)
        assert len(records)==len({r['stable_id'] for r in records})==100
        once(OUT/'generation/generated_100.json',{'version':'P6C4-V4.1','records':records,'record_count':100,'AI_candidates_only':True})
        paths += [OUT/'generation/generated_100.json',OUT/'source_evidence_errata.json',OUT/'SUPPLEMENT_SEAL.json',Path(__file__).resolve(),ROOT/'scripts/p6c4/decision_helpers.py']
        paths += [ROOT/f'scripts/p6c4/generation_{i:02d}.py' for i in range(1,6)]
        save(OUT/'GENERATION_SEAL.json',{'before_blind_reviews':True,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'files':{p.relative_to(ROOT).as_posix():sha(p) for p in paths},'actual_tokens':None,'actual_cost':None,
            'backend_model_id':None,'model_configuration':'Codex parent, exact backend not exposed'})
        print('100 generated candidates sealed before independent source-only reviews.')

if __name__=='__main__':main()
