"""Build an isolated500 V4 comparison from sealed semantic review decisions."""
import collections
import copy
from prepare import ROOT,OUT,read,sha,canonical,save,verify_protection
from seal_reviews import frozen_protocols

LAYERS=('core_meanings','extended_meanings','other_meanings')
BASE_FINDINGS={'escape','transfer','neglect','support','stewardess'}

def group_id(g):return g.get('sense_group_id',g.get('review_group_id'))

def matrix(r):
    return [{'use_id':group_id(g),'source_sense_ids':g['source_sense_ids'],
        'part_of_speech':g['part_of_speech'],'meaning_zh':g['display_zh'],
        'evidence_ids':g['evidence_ids'],'location':k,'scope_and_roles':g.get('usage_note',r['core_explanation'])}
        for k in LAYERS for g in r[k]]

def main():
    verify_protection();frozen_protocols()
    seal=read('docs/p6/p6c4/REGRESSION_REVIEW_SEAL.json')
    for p,h in seal['files'].items():assert sha(ROOT/p)==h
    review=read('docs/p6/p6c4/regression_review/review_500.json')
    byid={r['stable_id']:r for r in review['records']}
    original=read('docs/p6/p6c2/core_meanings_500.json')['records']
    c3=read('docs/p6/p6c3/independent_quality_review.json')
    c3fixes={r['stable_id']:r for r in read('docs/p6/p6c3/REVISED_CANDIDATES.json')['records']}
    wn=read('private/p6c4/wordnet_selected600.json')['headwords']
    historical={r['stable_id'] for r in c3['inherited100_pending_queue']}
    source_supp=read('docs/p6/p6c4/regression_review/supplemental_sources.json')
    records=[];findings=[];known=[];new_observations=[]
    for before in original:
        sid=before['stable_id'];w=before['headword'];assessment=byid[sid]
        candidate=copy.deepcopy(c3fixes[sid]['candidate'] if sid in c3fixes else before)
        corrections=[]
        if w in BASE_FINDINGS:
            assert assessment['confirmed_findings']
            for j,f in enumerate(assessment['confirmed_findings'],1):
                i={'issue_id':f'C4-regression-{w}-{j}','stable_id':sid,'headword':w,**copy.deepcopy(f),
                   'domain':'current_candidate_source_use_coverage' if f['severity']=='Major' else 'scope_note_evidence_conflict',
                   'normalized_cause':'one_to_one_source_POS_partition_loss' if f['severity']=='Major' else 'stale_scope_note',
                   'POS_confusion':False,'source_POS_use_coverage_gap':f['severity']=='Major',
                   'parent_adjudication':'confirmed_with_specific_WordNet_or_publisher_evidence; existing_POS_labels_not_declared_wrong',
                   'status':'fixed_in_isolated_candidate_lexically_checked_not_human_approved'}
                findings.append(i);corrections.append(i['issue_id'])
            if w=='stewardess':
                for change in assessment['proposed_changes']:
                    if 'before' not in change:continue
                    found=False
                    for k in LAYERS:
                        for g in candidate[k]:
                            if group_id(g)==group_id(change['before']):
                                assert g==change['before'];g.update(copy.deepcopy(change['after']));found=True
                    assert found
            else:
                changes=[p for p in assessment['proposed_changes'] if 'after' in p]
                assert len(changes)==1
                change=changes[0];g=copy.deepcopy(change['after'])
                if 'sense_group_id' not in g:g['sense_group_id']=g.pop('review_group_id')
                if w=='transfer':
                    # 00202520 is format-to-format transfer, not necessarily
                    # custody handover. Narrow the proposed display to what the
                    # source移转 and location-event evidence directly establish.
                    g['display_zh']='转移（这一过程或事件）';g['evidence_ids']=['wn31:n:00316812']
                    g['usage_note']='源转移同时支持移动动作与移动事件名词；这里仅说明位置转移，不用媒介转换定义冒充移交他人的证明。'
                    for s in g['source_subsenses']:s['evidence_ids']=['wn31:n:00316812']
                    g['parent_proposal_qualification']='将审阅提案转移/移交收窄为转移事件；保留原提案供比对。'
                atoms={a['source_sense_id']:a for a in before['original_meanings']}
                for s in g['source_subsenses']:
                    atom=atoms[s['source_sense_id']]
                    s['original_pos']=atom['part_of_speech'];s['original_pos_evidence']=atom['pos_evidence']
                    assert s['original_gloss']==atom['text']
                candidate['core_meanings'].append(g)
                additions=copy.deepcopy(change['semantic_splits'])
                for s in additions:
                    s['annotation']='AI语义/词性拆解，不新增原文片段'
                    if w=='transfer':s['added_use']='名词位置转移事件';s['evidence_ids']=['wn31:n:00316812']
                candidate.setdefault('semantic_splits',[]).extend(additions)
                existing_refs={e['evidence_id'] for e in candidate['supporting_sources']}
                catalog={e['evidence_id']:e for e in wn[w]}
                for eid in g['evidence_ids']:
                    assert eid in catalog
                    if eid not in existing_refs:candidate['supporting_sources'].append(catalog[eid])
            # The reviewer may strengthen a corrected note with a newly read
            # publisher observation. Keep that actual source alongside the
            # copied groups rather than leaving the reference dangling.
            referenced={eid for k in LAYERS for g in candidate[k] for eid in g['evidence_ids']}
            present={e['evidence_id'] for e in candidate['supporting_sources']}
            supplements={e['evidence_id']:e for e in source_supp['sources']}
            for eid in sorted(referenced-present):
                assert eid in supplements and supplements[eid]['headword']==w
                candidate['supporting_sources'].append(copy.deepcopy(supplements[eid]))
        for old_issue in c3['confirmed_findings']:
            if old_issue['stable_id']==sid:
                ver=assessment.get('C3_revision_candidate_verification')
                assert ver and ver['source_identity_unchanged'] and ver['human_approved'] is False
                known.append({'issue_id':old_issue['issue_id'],'stable_id':sid,'headword':w,'severity':old_issue['severity'],
                    'domain':old_issue['domain'],'verification':ver,
                    'status':'source_gap_tracked_adoption_unresolved' if w=='management' else 'fixed_in_isolated_candidate_lexically_checked_not_adopted',
                    'source_gap_closed':False if w=='management' else None,'human_approved':False})
        observations=[]
        for a in assessment['new_dictionary_candidates']:
            item=copy.deepcopy(a);item['auto_promoted_to_core']=False
            status='new_review_suggestion_not_confirmed_error'
            if w in {'reference','regular','competition','majority','client','machinery'}:status='already_recorded_in_C3_candidate_queue'
            if w=='appreciate':status='partial_C3_overlap_appreciate_intransitive_known_transitive_extra'
            if w=='acquisition':status='C3_already_suggested_semantic_detail_not_new_gap'
            item['prior_observation_status']=status
            observations.append(item);new_observations.append({'stable_id':sid,'headword':w,**item})
        existing_external=bool(candidate['dictionary_additions'] or observations)
        candidate['use_coverage_matrix']=matrix(candidate)
        represented={g['part_of_speech'] for k in LAYERS for g in candidate[k]}
        candidate['source_POS_coverage']={p:('represented_in_layers' if p in represented else
            'tracked_external_candidate_or_historical_mapping_pending' if any(a['part_of_speech']==p for a in candidate['dictionary_additions']) else 'evidence_pending')
            for p in before['part_of_speech'].split('；')}
        candidate['coverage_status']='core_coverage_incomplete_pending_addition_decision' if existing_external else 'source_fragment_pending' if candidate['reserved_original_items'] else 'source_supported_not_exhaustive_dictionary'
        candidate['review_status']='P6C4_V4_1_semantically_reevaluated_AI_candidate'
        candidate['human_approved']=False;candidate['needs_human_review']=True
        candidate['historical_risk_retained']=sid in historical
        candidate['v4_review_risk_flags']=list(dict.fromkeys(
            (['historical_risk_retained_not_auto_cleared'] if sid in historical else [])+
            (['original_fragment_evidence_pending'] if candidate['reserved_original_items'] else [])+
            (['external_observations_pending_adoption'] if existing_external else [])+
            (['isolated_correction_not_formal_adoption'] if corrections or sid in c3fixes else [])))
        candidate['p6c4_provenance']={'base_hash':canonical(before),'review_record_hash':canonical(assessment),
            'rule_sha256':sha(OUT/'RULES_V4_REVISED.md'),'gate_sha256':sha(OUT/'GATE_PROTOCOL.json'),
            'model_configuration':'Codex parent integration; independent reviewer inherited_parent_unexposed',
            'backend_model_id':None,'actual_tokens':None,'actual_cost':None}
        immutable=['stable_id','headword','part_of_speech','source_fields','source_hash','original_meaning_zh','original_meanings']
        assert all(candidate[k]==before[k] for k in immutable),w
        compared=(*LAYERS,'reserved_original_items','dictionary_additions','core_explanation','selection_reason')
        changes={k:{'before':before[k],'after':candidate[k]} for k in compared if before[k]!=candidate[k]}
        records.append({'stable_id':sid,'headword':w,'source_hash':before['source_hash'],
            'baseline_candidate_hash':canonical(before),'candidate':candidate,'semantic_changes':changes,
            'regression_assessment':assessment,'dictionary_observations_unadopted':observations,
            'historical_status':'pending_not_auto_passed' if sid in historical else 'prior_status_retained_not_human_approved',
            'new_regression_introduced_confirmed_findings':[],
            'corrected_baseline_issue_ids':corrections,'human_approved':False})
    assert len(records)==500 and len(historical)==48
    core_before=sum(len(r['core_meanings']) for r in original)
    core_after=sum(len(r['candidate']['core_meanings']) for r in records)
    output={'schema_version':'p6c4_regression500.v1','record_count':500,
        'rules':'P6C4-V4.1','AI_candidates_only':True,'human_approved_count':0,
        'baseline':{'path':'docs/p6/p6c2/core_meanings_500.json','sha256':sha(ROOT/'docs/p6/p6c2/core_meanings_500.json'),
            'version_labels':{k:dict(collections.Counter(r[k] for r in original)) for k in ('model_version','prompt_version')},
            'not_a_pure_V3_controlled_arm':True},
        'records':records,'C3_confirmed_problem_verification':known,'newly_confirmed_baseline_findings':findings,
        'regression_source_observations':new_observations,
        'historical48_review':[{'stable_id':r['stable_id'],'headword':r['headword'],
            'status':r['historical_status'],'historical_risk_retained':True,
            'observation':r['regression_assessment']['historical_observation_zh'],'source_hash':r['source_hash'],
            'review_axes':r['regression_assessment']['review_axes'],'human_approved':False}
            for r in records if r['stable_id'] in historical],
        'metrics':{'reviewed':500,'historical48_checked_pending':48,
            'original_fragments':sum(len(r['original_meanings']) for r in original),
            'core_groups_before':core_before,'core_groups_after':core_after,
            'core_average_before':core_before/500,'core_average_after':core_after/500,
            'changed_content_words':sum(bool(r['semantic_changes']) for r in records),
            'source_derived_layer_changed_words':sum(any(k in r['semantic_changes'] for k in LAYERS) for r in records),
            'newly_confirmed_baseline_Critical':0,'newly_confirmed_baseline_Major':4,'newly_confirmed_baseline_Minor':1,
            'current_candidate_Major_open_after_isolated_correction':0,
            'tracked_C3_major_source_gap_adoption_pending':1,
            'introduced_regression_confirmed_errors':0,
            'preference_suggestion_words':sum(bool(r['preference_suggestions']) for r in review['records']),
            'dictionary_observations':len(new_observations),
            'dictionary_observation_prior_status':dict(collections.Counter(r['prior_observation_status'] for r in new_observations)),
            'unknown_evidence_pending_words':sum(r['regression_assessment']['decision']=='evidence_pending' for r in records)},
        'scope_limits':['原文覆盖缺口仍待采用；不因已登记候选就称人工解决。','不存在纯V3对照实验，不声称因模型升级而改善某准确率。',
                        '新增词典观察不全部等于新词义；C3重复/细化/部分重叠已单列。'],
        'independence':{'context':'fresh_nonblind_regression','backend_model_id':None,'different_backend_proven':False,
            'review_sha256':sha(OUT/'regression_review/review_500.json')},
        'formal_writes':False,'Notion_accessed':False,'SQLite_opened':False,'published':False}
    save(OUT/'regression_500.json',output)
    print(output['metrics'])

if __name__=='__main__':main()
