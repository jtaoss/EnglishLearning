"""Explicit input/optional-field reconciliation. No semantic rules overwritten."""
import argparse
from common import *
from scope_guard import validate_result
from run import stage

def supplement():
    es=evidence();updates={}
    for r in working():
        have={e['id'] for e in es[r['headword']]}
        source={e['evidence_id']:e for e in r['supporting_sources']}
        missing={eid for k in LAYERS for g in r[k] for eid in g['evidence_ids'] if eid not in have and not eid.startswith('source:')}
        for eid in sorted(missing):
            require(eid in source and source[eid].get('observation_zh'),'Cannot invent missing evidence '+eid)
            old=source[eid]
            e={'id':eid,'pos':old['pos_supported'],'definition':old['observation_zh'],
               'source':old['url'],'type':'existing_verified_C5_proposal_publisher_observation',
               'origin_proposal_file':'docs/p6/p6c5/REVISED_CANDIDATES.json',
               'origin_evidence_hash':canonical(old)}
            updates.setdefault(r['headword'],[]).append(e)
    once(OUT/'EVIDENCE_RECONCILIATION.json',{'additions_by_headword':updates,
        'reason':'Initial packet builder used baseline supporting_sources rather than revised proposal supporting_sources; two real existing publisher citations were omitted.',
        'original_inputs_and_model_outputs_unchanged':True,'rules_hash_unchanged':sha(RULES),
        'no_new_meanings_or_IDs':True,'parent_verified_missing_count':sum(map(len,updates.values()))})
    return updates

def adapted_packets(packets,updates):
    rs=copy.deepcopy(packets)
    for p in rs:
        have={e['id'] for e in p['evidence']}
        p['evidence'] += [copy.deepcopy(e) for e in updates.get(p['word'],[]) if e['id'] not in have]
    return rs

def recover_holdout():
    packets=read(OUT/'inputs/holdout_source_only.json')['records'];records=[];failures=[];normalizations=[];raw=[]
    for i in range(0,len(packets),2):
        chunk=packets[i:i+2];tag=f'holdout_source_first_{i//2+1:03d}';done=False
        for suffix in ('','_repair1'):
            path=OUT/'api'/(tag+suffix+'.json')
            if not path.exists():continue
            api=read(path)
            try:
                d=json.loads(api['content'])
                # This field is optional in the semantic proposal. [] denotes
                # no separately structured observation reported, not a claim
                # that the model independently reviewed/denied external uses.
                changes=[]
                for r in d['records']:
                    if 'unadopted_observations' not in r and all(k in r for k in ('id','source_scopes','proposed_core','deferred_source_ids','deferral_reason','note')):
                        r['unadopted_observations']=[]
                        r['external_observations_not_separately_reported']=True
                        changes.append({'id':r['id'],'field':'unadopted_observations','before':'absent','after':[],
                                        'meaning':'optional separate array not reported; original note preserved'})
                canon={**api,'content':json.dumps(d,ensure_ascii=False)}
                rs=validate_result(canon,chunk,'holdout')
                records+=rs;normalizations+=changes;raw.append({'api_tag':api['tag'],'sha256':sha(path)})
                done=True;break
            except (ValueError,KeyError,TypeError) as e:
                failures.append({'api_tag':api['tag'],'validator_error':str(e), 'ids':[p['id'] for p in chunk],
                                 'response_sha256':sha(path),'raw_IDs_not_silently_corrected':True})
        if not done:
            failures.append({'ids':[p['id'] for p in chunk],'status':'source_first_not_completed_after_bounded_calls','no_more_calls':True})
    require(len({r['id'] for r in records})==len(records),'Duplicate recovered proposal')
    result={'stage':'holdout_source_first_reconciled','records':records,'record_count':len(records),'planned_count':24,
            'failures':failures,'transport_normalizations':normalizations,'raw_response_files':raw,
            'source_packet_sha256':sha(OUT/'inputs/holdout_source_only.json'),
            'rules_hash':sha(RULES),'candidate_answers_provided':False,'new_model_calls':0,
            'no_resampling_or_wrong_ID_repair':True,'all_AI_proposals_not_human_approved':True}
    once(OUT/'reviews/holdout_source_first_reconciled.json',result)
    once(OUT/'HOLDOUT_PROPOSAL_SEAL.json',{'sealed_before_700_comparison':not any((OUT/'reviews').glob('audit_v5e_*.json')),
        'reconciled_proposals_sha256':sha(OUT/'reviews/holdout_source_first_reconciled.json'),
        'source_packet_sha256':sha(OUT/'inputs/holdout_source_only.json'),
        'input_selection_sha256':sha(OUT/'HOLDOUT_SELECTION.json'), 'record_count':len(records),
        'required_at_least':20,'utc':now(),'no_wrong_ID_remapping':True})
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('part',choices=['prepare','calibration','audit']);args=p.parse_args()
    verify_frozen();verify_protection()
    updates=supplement()
    once(OUT/'RECONCILIATION_MANIFEST.json',{'adapter_sha256':sha(Path(__file__)),
      'original_run_manifest_sha256':sha(OUT/'RUN_MANIFEST.json'),'rules_hash':sha(RULES),
      'evidence_reconciliation_sha256':sha(OUT/'EVIDENCE_RECONCILIATION.json'),
      'purpose':'add two omitted real proposal citations; preserve raw inputs; normalize optional empty observation array only; do not repair wrong stable IDs',
      'semantic_rules_or_gate_or_models_changed':False})
    m=read(OUT/'RUN_MANIFEST.json')
    if args.part=='prepare':
        d=recover_holdout();print('Actual source-first proposals',d['record_count'],'of24; unresolved IDs preserved.')
    elif args.part=='calibration':
        ps=adapted_packets(read(OUT/'inputs/calibration_after.json')['records'],updates)
        once(OUT/'reconciled_inputs/calibration_after.json',{'records':ps})
        stage('calibration_after_evidence_reconciled','audit',ps,m['primary_model'],2)
    else:
        require((OUT/'HOLDOUT_PROPOSAL_SEAL.json').exists(),'Holdout proposals not sealed')
        for b in range(1,8):
            ps=adapted_packets(read(OUT/f'inputs/audit_{b:02d}.json')['records'],updates)
            once(OUT/f'reconciled_inputs/audit_{b:02d}.json',{'records':ps,'original_input_sha256':sha(OUT/f'inputs/audit_{b:02d}.json')})
            stage(f'audit_v5e_{b:02d}','audit',ps,m['primary_model'],m['primary_batch_words'])

if __name__=='__main__':main()
