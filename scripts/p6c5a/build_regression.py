"""Deterministic isolated regression export from actual model judgments."""
from common import *
from scope_guard import make_mappings

def model_mappings(candidate,audit,review_metadata):
    # All lexical semantic judgments come from the saved model response. Missing
    # proof fields stay visibly missing; they are not filled with fake prose.
    by={m['sid']:m for m in audit['mappings']};out=[]
    for s in candidate['original_meanings']:
        sid=s['source_sense_id'];m=by[sid]
        links=[{'layer':k,'group_id':gid(g),'recommended_pos':g['part_of_speech'],
                'display_zh':g['display_zh'],'usage_note':g.get('usage_note',''),'evidence_ids':g['evidence_ids']}
               for k in LAYERS for g in candidate[k] if sid in g['source_sense_ids']]
        held=[h for h in candidate['reserved_original_items'] if h['source_sense_id']==sid]
        require(links or held,'Original fragment lost')
        pending=bool(held or m.get('risk')!='none' or m['relation']=='无法确定' or
                     m.get('context')=='unlicensed_limit' or review_metadata['unverified_citation_ids'] or review_metadata['derived_conservative_flags'])
        out.append({'source_sense_id':sid,'source_pos':s['part_of_speech'],'source_pos_evidence':s['pos_evidence'],
           'original_text':s['text'],'original_span':[s['start'],s['end']],
           'source_scope_AI_interpretation':m['source_scope'],'source_scope_is_not_new_original_fact':True,
           'target_links':links,'held_original':held,'necessary_context_classification':m['context'],
           'mapping_relation':m['relation'],'mapping_reason':m['reason'],
           'evidence_ids':m.get('evidence_ids',[]),'residual_scope':m.get('residual_scope'),
           'counterexample':m.get('counterexample'),'counterexample_evidence_ids':m.get('counterexample_evidence_ids',[]),
           'risk_status':'pending_evidence_or_adjudication' if pending else 'AI_no_obvious_scope_problem',
           'unverified_model_citation_ids':m.get('unverified_model_citation_ids',[]),
           'all_layer_retention_is_not_first_screen_completeness':True,
           'human_approved':False})
    return out

def main():
    verify_frozen();protection=verify_protection()
    originals={r['stable_id']:r for r in baseline()};candidates=working()
    ps=read(OUT/'COLLECTED_PRIMARY_AUDITS.json')
    primary={e['id']:e for e in ps['records']}
    require(len(primary)==700 and not ps['missing_ids'],'Not all700 actual primary semantic audits available')
    secondary={}
    path=OUT/'COLLECTED_SECONDARY_VERIFICATION.json'
    if path.exists():secondary={e['id']:e for e in read(path)['records']}
    known=read(OUT/'COLLECTED_KNOWN_VERIFICATION.json')
    known_after={e['id']:e for e in known['after']['records']}
    h=read(OUT/'HOLDOUT_SELECTION.json');holdouts={r['stable_id']:r for r in h['records']}
    proposals=read(OUT/'reviews/holdout_source_first_reconciled.json')
    blind={r['id']:r for r in proposals['records']}
    sets=read(OUT/'INPUT_SETS.json');old=set(sets['reused600']);hist=set(sets['historical48'])
    adjudication=read(OUT/'PARENT_EVIDENCE_ADJUDICATION.json')
    decisions={r['stable_id']:r for r in adjudication['regression_major_proposal_dispositions']}
    records=[]
    for c in candidates:
        sid=c['stable_id'];before=originals[sid];entry=primary[sid]
        for k in ('stable_id','headword','source_hash','source_fields','part_of_speech','original_meanings','original_meaning_zh'):
            require(c[k]==before[k],'Source changed '+c['headword']+':'+k)
        if sid in old:
            for k in (*LAYERS,'reserved_original_items','dictionary_additions'):
                require(c[k]==before[k],'Unnecessary reused600 semantic change '+c['headword'])
        mappings=model_mappings(c,entry['review'],entry['metadata'])
        second=secondary.get(sid,known_after.get(sid))
        second_pending=bool(second and (second['review'].get('confirmed_within_supplied_evidence') or
             second['review'].get('unresolved') or not second['strict_contract_passed'] or
             second['metadata']['unverified_citation_ids'] or second['metadata']['derived_conservative_flags']))
        row={'stable_id':sid,'headword':c['headword'],'cohort':'reused600' if sid in old else 'new100',
             'source_hash':c['source_hash'],'baseline_candidate_hash':canonical(before),'candidate':c,
             'source_scope_mappings':mappings,'primary_scope_audit':entry,
             'independent_candidate_verification':second,
             'parent_evidence_adjudication':decisions.get(sid),
             'holdout_selection':holdouts.get(sid),'sealed_source_first_proposal':blind.get(sid),
             'source_first_proposal_status':'available' if sid in blind else 'selected_but_ID_or_schema_failure_not_remapped' if sid in holdouts else 'not_selected',
             'requires_human_review':before['needs_human_review'] or second_pending or
                 any(m['risk_status'].startswith('pending') or m['source_pos'] is None for m in mappings) or sid in decisions,
             'historical_risk_retained':sid in hist,'old_review_and_risks_unchanged':True,
             'rules_hash':sha(RULES),'human_approved':False,'publication_status':'isolated_not_published'}
        if c['headword']=='pursue':
            row.update({'prior_review_status':before['second_review']['status'],
                        'prior_failure_reconciliation_pending':True,
                        'new_primary_publisher_evidence':'pub:p6c5a:collins:pursue',
                        'new_review_does_not_rewrite_C5_failure':True})
        records.append(row)
    require(len(records)==len({r['stable_id'] for r in records})==700,'ID drift')
    require(sum(len(r['source_scope_mappings']) for r in records)==1702,'Original mapping count changed')
    out={'schema_version':'P6C5a.scope_regression700.v1','record_count':700,'original_fragment_count':1702,
         'source_file_sha256':sha(BASE),'rules_hash':sha(RULES),'run_manifest_sha256':sha(OUT/'RUN_MANIFEST.json'),
         'records':records,'new_formal_IDs':0,'human_approved_count':0,
         'scope_judgments_are_AI_candidates_not_formal_semantic_proofs':True,
         'reused600_semantic_content_unchanged':True,'changed_word_count':4,
         'formal_SQLite_Notion_UI_writes':False,'C5_checkpoints_preserved':True,
         'unresolved_risks_not_cleared':True}
    save(OUT/'regression_700.json',out)
    initial=read(OUT/'initial_four_revisions.json')
    revised=[]
    for r in initial['records']:
        sid=r['stable_id'];after=next(x for x in records if x['stable_id']==sid)
        revised.append({**r,'rules_hash':sha(RULES),'scope_mappings':after['source_scope_mappings'],
            'new_primary_audit':primary[sid],'independent_verification':known_after.get(sid),
            'human_approved':False,'old700_overwritten':False,
            'repair_adjudication':None})
    adjudication=OUT/'PARENT_EVIDENCE_ADJUDICATION.json'
    if adjudication.exists():
        statuses=read(adjudication).get('known_four_status',{})
        for r in revised:r['repair_adjudication']=statuses.get(r['headword'])
    save(OUT/'revised_candidates.json',{'schema_version':'P6C5a.isolated_revisions.v1','record_count':4,
        'source_sha256':sha(BASE),'rules_hash':sha(RULES),'records':revised,
        'human_approved_count':0,'not_adopted_or_published':True})
    save(OUT/'PROTECTION_CHECK.json',protection)
    print('Exported real700 reviews /1702 mappings; four isolated revisions; no new IDs.')

if __name__=='__main__':main()
