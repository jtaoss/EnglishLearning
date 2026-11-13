"""Structural/evidence guard over actual semantic judgments, not string matching."""
from common import *

def validate_result(result,packets,kind):
    require(result['response_model']==result['requested_model'] and result['finish_reason']=='stop','Wrong/incomplete model result')
    value=json.loads(result['content']);rows=value['records']
    require(len(rows)==len(packets) and [r['id'] for r in rows]==[p['id'] for p in packets],'Missing/extra/duplicate/out-of-order review IDs')
    for r,p in zip(rows,packets):
        sids={s['source_sense_id'] for s in p['senses']};eids={e['id'] for e in p['evidence']}
        source_eids={f"source:{p['id']}:{s}" for s in sids};eids|=source_eids
        def refs(es):require(isinstance(es,list) and set(es)<=eids,'Unprovided evidence')
        if kind=='audit':
            ms=r['mappings'];require(len(ms)==len(sids) and {m['sid'] for m in ms}==sids,'Original fragment audit missing/duplicated')
            require(r['word_status'] in ('complete','partial','uncertain') and r['core_status'] in ('adequate','justified_deferred','pending'),'Invalid word/core status')
            for m in ms:
                require(m['relation'] in RELATIONS and m['source_scope'] and m['reason'],'Missing semantic scope/relation/rationale')
                require(m['context'] in ('required_from_source','required_for_lexical_use','example_not_exclusive','unlicensed_limit','uncertain','none'),'Bad context reason')
                require(m['risk'] in ('none','pending','suspected_Major','suspected_Minor'),'Bad risk status')
                refs(m['evidence_ids']);refs(m['counterexample_evidence_ids'])
                for k in ('residual_scope','counterexample'):require(isinstance(m[k],str),'Missing scope contrast')
                if m['relation'] in ('范围收窄','范围扩大','语义不匹配'):
                    require(m['risk']!='none' and bool(m['residual_scope']),'Scope defect silently passed without residual range')
                if m['relation']=='无法确定':require(m['risk']!='none','Uncertainty silently cleared')
                if m['context']=='unlicensed_limit':require(m['risk']!='none','Unlicensed limit silently passed')
            held={h['source_id'] for h in p['held']}
            require(not held or r['word_status']!='complete','Held fragment falsely complete')
            groups={g['id'] for g in p['groups']}
            for issue in r['issues']:
                require(issue['severity'] in ('Critical','Major','Minor','Info') and issue['reason'] and issue['repair_suggestion'],'Bad review issue')
                require(set(issue['source_ids'])<=sids and set(issue['group_ids'])<=groups,'Review invented source/group')
                refs(issue['evidence_ids'])
            require(bool(r['note']),'Empty word audit')
        elif kind=='holdout':
            ms=r['source_scopes'];require(len(ms)==len(sids) and {m['sid'] for m in ms}==sids,'Missing holdout source scope')
            require(bool(r['proposed_core']) and bool(r['note']),'No real independent proposal')
            for m in ms:
                require(m['scope_zh'] and 'recommended_pos' in m and 'required_context' in m and 'uncertainty' in m,'Incomplete independent scope')
                refs(m['evidence_ids'])
            require(set(r['deferred_source_ids'])<=sids and 'deferral_reason' in r and 'unadopted_observations' in r,'Incomplete holdout result')
        else:
            ms=r['scope_checks'];require(len(ms)==len(sids) and {m['sid'] for m in ms}==sids,'Missing independent per-source scope')
            for m in ms:
                require(m['relation'] in RELATIONS and m['reason'],'Missing independent relation')
                refs(m['evidence_ids'])
            require(isinstance(r['unresolved'],list) and isinstance(r['preferences'],list) and r['note'],'Incomplete independent review')
            groups={g['id'] for g in p['groups']}
            for i in r['confirmed_within_supplied_evidence']:
                require(i['severity'] in ('Critical','Major','Minor','Info') and i['reason'] and i['counterexample'],'Missing independent issue contrast')
                require(set(i['source_ids'])<=sids and set(i['group_ids'])<=groups,'Independent review invented source/group')
                refs(i['evidence_ids'])
    return rows

def decision(mapping):
    """Only a routing result; cannot claim formal semantic proof or confirmation."""
    if mapping['relation']=='无法确定' or mapping['risk']=='pending':return 'evidence_pending_not_passed'
    if mapping['relation'] in ('范围收窄','范围扩大','语义不匹配') or mapping['context']=='unlicensed_limit':return 'scope_risk_requires_evidence_adjudication'
    return 'AI_no_obvious_scope_defect_not_human_approved'

def make_mappings(candidate,audit):
    by={m['sid']:m for m in audit['mappings']};rows=[]
    for original in candidate['original_meanings']:
        sid=original['source_sense_id'];m=by[sid]
        links=[{'layer':k,'group_id':gid(g),'recommended_pos':g['part_of_speech'],
                'display_zh':g['display_zh'],'scope_note':g.get('usage_note',''),'evidence_ids':g['evidence_ids']}
               for k in LAYERS for g in candidate[k] if sid in g['source_sense_ids']]
        held=[h for h in candidate['reserved_original_items'] if h['source_sense_id']==sid]
        require(bool(links or held),'Original fragment not retained anywhere')
        rows.append({'source_sense_id':sid,'source_pos':original['part_of_speech'],'source_pos_evidence':original['pos_evidence'],
            'original_text':original['text'],'original_span':[original['start'],original['end']],
            'target_links':links,'held_original':held,'context_requirement':m['context'],
            'relation':m['relation'],'source_scope':m['source_scope'],'mapping_reason':m['reason'],
            'residual_scope':m['residual_scope'],'scope_counterexample':m['counterexample'],
            'counterexample_evidence_ids':m['counterexample_evidence_ids'],'evidence_ids':m['evidence_ids'],
            'risk_status':decision(m),'AI_risk_not_confirmed_error':True})
    return rows
