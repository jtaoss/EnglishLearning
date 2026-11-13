"""Explicit transport-only recovery adapter. Frozen rules/models are unchanged.

Keeps original responses, normalizes enum case only, and uses the frozen one
same-model schema-repair allowance. Never fabricates findings or semantic QA.
"""
import argparse
import copy
import run_batches as frozen
from api_client import call, system_prompt
from common import *

def parse_review(api, packets):
    obj = json.loads(api['content'])
    rows = obj['records']
    require(len(rows)==len(packets) and [r['id'] for r in rows]==[p['id'] for p in packets], 'Review IDs/count/order mismatch')
    rows = copy.deepcopy(rows)
    for r, p in zip(rows,packets):
        for k in ('independent_core','verdict','findings','preferences','note'):
            require(k in r,'Review missing '+k)
        before = r['verdict']
        r['verdict'] = before.lower()
        require(r['verdict'] in ('no_confirmed_problem','evidence_pending','correction_proposed'),'Bad review verdict')
        require(isinstance(r['independent_core'],list) and isinstance(r['findings'],list) and isinstance(r['preferences'],list) and bool(r['note']),'Invalid semantic review fields')
        if p['review_role']=='source_first_sample':
            require(bool(r['independent_core']),'Source-first sample has no independent core')
        lex = {e['id'] for e in p['evidence']}
        sids = {s['source_sense_id'] for s in p['senses']}
        lex |= {f"source:{p['id']}:{s}" for s in sids}
        changes=[]
        if before!=r['verdict']:
            changes.append({'field':'verdict','before':before,'after':r['verdict'],'reason':'enum case normalization only'})
        for i,f in enumerate(r['findings']):
            for k in ('severity','kind','reason','evidence_ids','source_sense_ids','candidate_group_ref','proposed_fix'):
                require(k in f,'Review finding missing '+k)
            before=f['severity']
            f['severity']=before.title()
            require(f['severity'] in ('Critical','Major','Minor','Info') and f['reason'],'Bad review severity/reason')
            if before!=f['severity']:
                changes.append({'field':f'findings[{i}].severity','before':before,'after':f['severity'],'reason':'enum case normalization only'})
            require(set(f['evidence_ids'])<=lex and set(f['source_sense_ids'])<=sids,'Unprovided review evidence/source ID')
        r['transport_normalizations']=changes
    return rows

def review_chunk(b,i,packets):
    manifest=read(OUT/'RUN_MANIFEST.json')
    tag=f'review_{b:03d}_{i:02d}'
    api=call(tag,system_prompt('review'),{'records':packets},model=manifest['review_model'],effort=manifest['review_reasoning_effort'])
    try:
        rs=parse_review(api,packets)
    except (ValueError,KeyError,TypeError) as e:
        save(OUT/'failures'/(tag+'_structure.json'),{'tag':tag,'error':str(e)[:500],
             'original_response_sha256':sha(OUT/'api'/(tag+'.json')),
             'recovery_adapter_sha256':sha(Path(__file__)), 'same_frozen_model_rules':True,
             'allowed_repair_attempt':1,'original_response_preserved':True})
        api=call(tag+'_repair1',system_prompt('review'),
                 {'records':packets,'previous_invalid_output':api['content'],
                  'validator_failure':str(e)[:500],
                  'instruction':'Return actual semantic reviews under exactly the frozen rules and review schema, not echoed inputs/generation records. Re-read source and supplied evidence. No invented/default reviews. One complete review per input ID.'},
                 model=manifest['review_model'],effort=manifest['review_reasoning_effort'])
        rs=parse_review(api,packets)
    for r,p in zip(rs,packets):
        r['review_role']=p['review_role']
        r['api_tag']=api['tag']
        r['response_model']=api['response_model']
        r['response_id']=api['response_id']
        r['different_model_identifier_from_generation']=api['response_model']!=manifest['requested_model']
        r['physical_served_weights_independently_verified']=False
    return rs

def main():
    verify_frozen()
    path=OUT/'RECOVERY_ADAPTER_MANIFEST.json'
    value={'original_frozen_run_manifest_sha256':sha(OUT/'RUN_MANIFEST.json'),
           'frozen_runner_sha256':sha(ROOT/'scripts/p6c5/run_batches.py'),
           'adapter_sha256':sha(Path(__file__)), 'rules_hash':sha(RULES),
           'semantic_rules_or_models_changed':False,
           'reason':'First-batch provider returned lowercase enum variants, input echo, and empty content. Original runner halted, no next batch started. Implements the already frozen one same-model structure-repair allowance for reviews.',
           'no_semantic_decisions_fabricated':True,'original_responses_preserved':True}
    once(path,value)
    frozen.review_chunk=review_chunk
    frozen.main()

if __name__=='__main__':main()
