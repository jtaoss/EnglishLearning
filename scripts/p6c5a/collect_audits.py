"""Recover individual genuine review rows without guessing IDs or semantics.

Representation aliases/case are logged. Unverified citations and contradictory
status claims are retained as pending, never converted to semantic success.
"""
from common import *
from scope_guard import validate_result

def canonical_row(raw,p,kind):
    r=copy.deepcopy(raw);changes=[]
    require(r.get('id')==p['id'],'Wrong stable ID; no guessing correction')
    key={'audit':'mappings','verify':'scope_checks','holdout':'source_scopes'}[kind]
    require(isinstance(r.get(key),list),'No actual per-source judgments')
    for m in r[key]:
        if 'sid' not in m and 'source_sense_id' in m:
            m['sid']=m.pop('source_sense_id')
            changes.append({'field':'source_sense_id->sid','reason':'same source identifier field alias; value unchanged'})
    sids={s['source_sense_id'] for s in p['senses']}
    require(len(r[key])==len(sids) and {m['sid'] for m in r[key]}==sids,'Missing/duplicate/invented per-source judgments')
    for m in r[key]:
        if kind!='holdout':require(m.get('relation') in RELATIONS and bool(m.get('reason')),'No usable semantic relation/reason')
        else:require(m.get('scope_zh') and 'uncertainty' in m,'No actual independent source scope')
    issuekey='issues' if kind=='audit' else 'confirmed_within_supplied_evidence' if kind=='verify' else None
    for issue in r.get(issuekey,[]) if issuekey else []:
        before=issue.get('severity')
        if isinstance(before,str) and before.title() in ('Critical','Major','Minor','Info') and before!=before.title():
            issue['severity']=before.title();changes.append({'field':'severity','before':before,'after':issue['severity'],'reason':'enum letter case only'})
    available={e['id'] for e in p['evidence']}|{f"source:{p['id']}:{sid}" for sid in sids}
    invalid=[]
    for obj in r[key]+(r.get(issuekey,[]) if issuekey else []):
        for ekey in ('evidence_ids','counterexample_evidence_ids'):
            if ekey not in obj:continue
            bad=[e for e in obj[ekey] if e not in available]
            if bad:
                invalid.extend(bad)
                obj.setdefault('unverified_model_citation_ids',[]).extend(bad)
                obj[ekey]=[e for e in obj[ekey] if e in available]
    derived=[]
    if kind=='audit':
        require(r.get('note') and isinstance(r.get('issues'),list),'No real word audit')
        for m in r['mappings']:
            require(m.get('source_scope') and 'evidence_ids' in m and 'context' in m and 'risk' in m,'Incomplete source-scope judgment')
            if m['relation'] in ('范围收窄','范围扩大','语义不匹配') and (m.get('risk')=='none' or not m.get('residual_scope')):
                derived.append({'sid':m['sid'],'kind':'scope_defect_proposal_lacks_structured_proof','not_passed':True})
            if m['relation']=='无法确定' and m.get('risk')=='none':derived.append({'sid':m['sid'],'kind':'unknown_cannot_pass','not_passed':True})
            if m.get('context')=='unlicensed_limit' and m.get('risk')=='none':derived.append({'sid':m['sid'],'kind':'unlicensed_limit_cannot_pass','not_passed':True})
        if p.get('held') and r.get('word_status')=='complete':
            derived.append({'kind':'model_complete_conflicts_with_explicit_held_source','not_passed':True})
    elif kind=='verify':
        require(r.get('note') and isinstance(r.get('unresolved'),list) and isinstance(r.get('preferences'),list),'No actual independent verification')
        for issue in r['confirmed_within_supplied_evidence']:
            if not issue.get('counterexample'):
                derived.append({'kind':'independent_issue_no_separate_counterexample','not_automatically_confirmed':True})
    return r,{'representation_normalizations':changes,'unverified_citation_ids':sorted(set(invalid)),
              'derived_conservative_flags':derived,'semantic_labels_not_changed':True,
              'no_wrong_ID_or_source_text_repair':True}

def read_stage(name,kind,packets,size):
    rows=[];missing=[];log=[]
    for offset in range(0,len(packets),size):
        chunk=packets[offset:offset+size];tag=f'{name}_{offset//size+1:03d}'
        options=[]
        for suffix in ('','_repair1'):
            path=OUT/'api'/(tag+suffix+'.json')
            if not path.exists():continue
            api=read(path)
            try:contents=json.loads(api['content'])['records']
            except Exception as e:
                log.append({'api_tag':api['tag'],'error_type':type(e).__name__,'status':'no_usable_JSON'});continue
            counts=collections.Counter(r.get('id') for r in contents)
            for p in chunk:
                if counts[p['id']]!=1:continue
                raw=next(r for r in contents if r.get('id')==p['id'])
                try:
                    normalized,metadata=canonical_row(raw,p,kind)
                    test={**api,'content':json.dumps({'records':[normalized]},ensure_ascii=False)}
                    try:validate_result(test,[p],kind);strict=True;failure=None
                    except (ValueError,KeyError,TypeError) as e:strict=False;failure=str(e)
                    entry={'id':p['id'],'review':normalized,'api_tag':api['tag'],'response_model':api['response_model'],
                           'response_id':api['response_id'],'raw_response_sha256':sha(path),
                           'raw_record_sha256':canonical(raw),'strict_contract_passed':strict,
                           'strict_failure':failure,'metadata':metadata,'review_is_AI_not_human':True}
                    # Prefer structurally usable transport, never the most
                    # favorable relation/severity/word verdict.
                    score=(not strict,len(metadata['unverified_citation_ids']),len(metadata['derived_conservative_flags']),bool(suffix))
                    options.append((p['id'],score,entry))
                except (ValueError,KeyError,TypeError) as e:
                    log.append({'api_tag':api['tag'],'id':p['id'],'status':'not_reconstructed','reason':str(e)})
        for p in chunk:
            found=[(score,row) for sid,score,row in options if sid==p['id']]
            if found:rows.append(min(found,key=lambda x:x[0])[1])
            else:missing.append(p['id'])
    return {'stage':name,'kind':kind,'records':rows,'record_count':len(rows),'expected_count':len(packets),
            'missing_ids':missing,'transport_errors_preserved':log,
            'no_new_model_calls':True,'collector_sha256':sha(Path(__file__))}

def main():
    verify_frozen()
    allrows=[];missing=[];stages=[]
    for b in range(1,8):
        path=OUT/f'reconciled_inputs/audit_{b:02d}.json'
        if not path.exists() or not (OUT/f'reviews/audit_v5e_{b:02d}.json').exists():continue
        d=read_stage(f'audit_v5e_{b:02d}','audit',read(path)['records'],5)
        allrows+=d['records'];missing+=d['missing_ids'];stages.append(d)
    save(OUT/'COLLECTED_PRIMARY_AUDITS.json',{'records':allrows,'record_count':len(allrows),'missing_ids':missing,
         'completed_outer_stages':len(stages),'stages':stages,'semantic_labels_changed':False,'actual_scope_judgments_not_templates':True})
    print('Actual per-word source-scope reviews',len(allrows),'missing from completed stages',missing)

if __name__=='__main__':main()
