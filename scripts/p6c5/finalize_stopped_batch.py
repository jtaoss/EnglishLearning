"""No-network audit/finalization of batch001 after a semantic stop.

Does not call a model, replace rules or generate unprocessed vocabulary.
"""
import copy
import math
from common import *
from recover_reviews import parse_review
from run_batches import reviewed_packet, integrate_reviews

def parse_existing(api, packets):
    obj=json.loads(api['content'])
    changes=[]
    require(len(obj['records'])==len(packets),'Review count differs')
    for r,p in zip(obj['records'],packets):
        # A targeted comparison never has a source-only proposal. An omitted
        # not-applicable empty field is not a missing semantic review.
        if p['review_role']=='targeted_risk' and 'independent_core' not in r and all(k in r for k in ('verdict','findings','preferences','note')):
            r['independent_core']=[]
            changes.append({'stable_id':p['id'],'field':'independent_core',
                            'before':'absent','after':[], 'reason':'not applicable to targeted review; no proposal fabricated'})
    adapted={**api,'content':json.dumps(obj,ensure_ascii=False)}
    rs=parse_review(adapted,packets)
    return rs,changes

def main():
    manifest=verify_frozen()
    verify_protected()
    generation=read(OUT/'generation/batch_001.json')
    candidates=copy.deepcopy(generation['records'])
    items=read(OUT/'inputs/batch_001.json')['records']
    byid={r['stable_id']:r for r in candidates}
    targeted={r['stable_id'] for r in candidates if r['risk_level']=='high' or r['reserved_original_items'] or len(r['part_of_speech'].split('；'))>1 or len(r['core_meanings'])>3 or r['dictionary_additions']}
    low=sorted((r for r in candidates if r['stable_id'] not in targeted),key=lambda r:canonical(['P6C5_lowrisk_sample_v1',r['stable_id']]))
    n=max(1,math.ceil(len(low)*manifest['batch_config']['low_risk_sample_fraction'])) if low else 0
    sample={r['stable_id'] for r in low[:n]}
    packets=[reviewed_packet(item,byid[item['id']],item['id'] in sample) for item in items if item['id'] in targeted|sample]
    reviewed=[]
    failures=[]
    normalizations=[]
    for i,p in enumerate(packets,1):
        tag=f'review_001_{i:02d}'
        accepted=False
        for suffix in ('','_repair1'):
            path=OUT/'api'/(tag+suffix+'.json')
            if not path.exists():
                continue
            api=read(path)
            require(api['response_model']==manifest['review_model'] and api['finish_reason']=='stop','Unexpected saved review model/output')
            try:
                rs,changes=parse_existing(api,[p])
            except (ValueError,KeyError,TypeError) as e:
                failures.append({'stable_id':p['id'],'api_tag':api['tag'],'error':str(e)[:500],'response_sha256':sha(path)})
                continue
            for r in rs:
                r.update({'review_role':p['review_role'],'api_tag':api['tag'],'response_model':api['response_model'],
                          'response_id':api['response_id'],
                          'different_model_identifier_from_generation':api['response_model']!=manifest['requested_model'],
                          'physical_served_weights_independently_verified':False})
                reviewed.append(r)
                normalizations.extend(changes+[{'stable_id':p['id'],**c} for c in r['transport_normalizations']])
            accepted=True
            break
        if not accepted:
            failures.append({'stable_id':p['id'],'status':'review_incomplete_after_existing_bounded_attempts_no_more_calls'})
    reviews={'targeted_ids':sorted(targeted),'low_risk_pool':len(low),'source_first_sample_ids':sorted(sample),
             'records':reviewed,'failed_review_ids':sorted({x['stable_id'] for x in failures if x.get('status')}),
             'independence':'new stateless API requests; generation Flash and review Pro returned different model identifiers; internal deployed weights not independently verified',
             'source_first_sample_has_no_generated_answers':True,'transport_normalizations':normalizations,
             'invalid_original_responses_preserved':failures,'no_new_model_calls':True,
             'adapter_sha256':sha(Path(__file__))}
    once(OUT/'reviews/batch_001.json',reviews)
    critical=integrate_reviews(candidates,reviews)
    for r in candidates:
        if r['stable_id'] in reviews['failed_review_ids']:
            r['second_review']={'status':'review_incomplete_after_bounded_attempts','not_fabricated':True}
            r['review_status']='processing_failed_or_evidence_insufficient'
            r['needs_human_review']=True
    causes=collections.Counter(f['kind'] for r in reviewed for f in r['findings'] if f['severity']=='Major')
    result={'batch':1,'status':'validated_checkpoint','rules_hash':sha(RULES),
            'input_hash':canonical(read(OUT/'inputs/batch_001.json')),
            'generation_snapshot_hash':sha(OUT/'generation/batch_001.json'),
            'second_review_snapshot_hash':sha(OUT/'reviews/batch_001.json'),
            'records':candidates,'records_sha256':canonical(candidates),
            'targeted_review_count':len(targeted),'source_first_lowrisk_sample_count':len(sample),
            'proposed_Major_cause_counts_NOT_confirmed':dict(causes),
            'semantic_gate_status':'repeated_Major_proposals_await_parent_evidence_check',
            'confirmed_Critical':0,'human_approved':False,
            'no_network_finalization':True,'semantic_stop_required':True,
            'note':'Validated source/ID structure only; semantic gate is BLOCKED. Do not equate checkpoint existence with semantic acceptance.'}
    once(OUT/'batches/batch_001.json',result)
    once(OUT/'parent_gates/batch_001.json',{'checkpoint_records_sha256':result['records_sha256'],
         'continue_processing':False,'human_approved':False,'reason':'Two same-cause source-scope Major errors confirmed in parent evidence adjudication; no next batch.',
         'parent_adjudication_path':'docs/p6/p6c5/PARENT_ADJUDICATION.json'})
    print(json.dumps({'generated_new_words':100,'second_reviews_completed':len(reviewed),
                     'targeted':len(targeted),'source_first_samples':len(sample),
                     'review_failures':reviews['failed_review_ids'],'Critical_alarms':critical,
                     'raw_Major_proposals':dict(causes),'next_batch_started':False},ensure_ascii=False))

if __name__=='__main__':main()
