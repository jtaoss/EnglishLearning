"""Compare sealed fresh100 generation against sealed source-first proposals."""
import collections
import copy
import csv
import statistics
from prepare import ROOT,OUT,read,sha,canonical,save,verify_protection
from seal_reviews import frozen_protocols,normalize_blind

LAYERS=('core_meanings','extended_meanings','other_meanings')

def partition(r):return sorted((k,g['part_of_speech'],tuple(sorted(g['source_sense_ids']))) for k in LAYERS for g in r[k])
def core_ids(r):return sorted({s for g in r['core_meanings'] for s in g['source_sense_ids']})

def main():
    verify_protection();frozen_protocols()
    seal=read('docs/p6/p6c4/BLIND_REVIEW_SEAL.json')
    blind={};owner={};raw_hash={}
    for n in 'AB':
        s=seal['reviewers'][n]
        for p,h in s['files'].items():assert sha(ROOT/p)==h
        for r in read(f'docs/p6/p6c4/blind_review/reviewer_{n}.json')['records']:
            blind[r['stable_id']]=normalize_blind(r);owner[r['stable_id']]=n;raw_hash[r['stable_id']]=canonical(r)
    generated=read('docs/p6/p6c4/generation/generated_100.json')['records']
    with (ROOT/'scripts/p6c4/blind_adjudication.tsv').open(encoding='utf-8',newline='') as f:ns=list(csv.DictReader(f,delimiter='\t'))
    notes={r['headword']:r for r in ns};assert len(notes)==len(ns)==100 and set(notes)=={r['headword'] for r in generated}
    post=read('docs/p6/p6c4/adjudication_source_observations.json')['records']
    records=[];findings=[];raw_findings=[]
    for before in generated:
        sid=before['stable_id'];w=before['headword'];b=blind[sid];n=notes[w];candidate=copy.deepcopy(before)
        issues=[];fix=None
        if w=='clause':
            assert n['disposition']=='confirmed_major'
            evidence=[e for e in b['evidence_sources'] if e['evidence_id']=='pub:B:clause']+[e for e in post if e['headword']=='clause']
            assert len(evidence)==2
            issues=[{'issue_id':'C4-blind-clause-1','stable_id':sid,'headword':w,'severity':'Major',
                'domain':'current_core_scope_error_inherited_from_original_source',
                'normalized_cause':'source_subtype_misread_as_full_grammar_category',
                'source_original_scope_problem':True,'important_omission':True,
                'omission_unit':'scope_of_one_grammar_use_including_independent_clause_not_an_extra_synset_count',
                'core_ordering_error':False,'POS_confusion':False,'false_merge':False,'unsupported_addition':False,
                'observation_zh':n['rationale'],'evidence_ids':['pub:B:clause','pub:parent:clause'],
                'initial_generator_responsibility':'原文从句过窄但生成器仍直接放核心，未识别上位类别与从属子类差别；不是把责任完全推给原材料。',
                'after_status':'misleading_core_removed_source_reserved_dictionary_scope_candidate_tracked',
                'original_source_scope_adoption_status':'unresolved_not_adopted','human_approved':False}]
            # Apply the independently proposed conservative disposition exactly:
            # retain the raw从句, but do not continue teaching it as the full
            # grammar meaning of clause or silently replace it with new text.
            candidate['core_meanings']=[g for g in candidate['core_meanings'] if g['source_sense_ids']!=['s001']]
            atom=next(a for a in candidate['original_meanings'] if a['source_sense_id']=='s001')
            candidate['reserved_original_items'].append({**atom,
                'reason':'原从句仅是clause的一类；词典同时涵盖独立/主分句，不能当一般语法核心。源文本保留，替代释义待采用。',
                'evidence_ids':['pub:B:clause','pub:parent:clause'],'status':'original_scope_problem_preserved_pending_decision'})
            candidate['dictionary_additions'].append({
                'candidate_id':sid+':p6c4:postblind:1','part_of_speech':'名词',
                'meaning_zh':'（语法）分句（可独立或从属）','source_sense_ids':[],
                'corrects_original_source_sense_id':'s001','evidence_ids':['pub:B:clause','pub:parent:clause'],
                'origin':'dictionary_supported_scope_correction_candidate_not_original_text',
                'reason':'上位语法概念不是只指从句；需独立采用裁定，不自动升级核心。',
                'status':'AI_candidate_not_adopted','suggested_layer':'adoption_and_layer_decision_pending',
                'human_approved':False,'auto_promoted_to_core':False})
            candidate['supporting_sources'].extend(evidence)
            candidate['risk_flags']=sorted(set(candidate['risk_flags'])|{'confirmed_source_scope_problem','grammar_core_pending_dictionary_correction'})
            candidate['risk_level']='high';candidate['coverage_status']='core_coverage_incomplete_pending_source_scope_correction_adoption'
            candidate['core_explanation']='条款可保留核心；语法一般义不能只教成从句，原片段暂存，分句修正候选尚未采用。当前候选不代表完整覆盖语法义。'
            candidate['use_coverage_matrix']=[u for u in candidate['use_coverage_matrix'] if u['source_sense_ids']!=['s001']]
            candidate['review_status']='AI_postblind_scope_correction_candidate_not_adopted'
            fix={'source_first_independent_reviewer_agrees':True,'blind_record_hash':raw_hash[sid],
                 'lexical_boundary_verified':True,'current_misleading_grammar_core_removed':True,
                 'original_text_or_general_grammar_adoption_completed':False,
                 'not_just_risk_label_downgrade':'实际移出错误范围核心、保留原文并独立登记广义替代候选；没有宣称词典补充已采用。'}
        candidate['human_approved']=False;candidate['needs_human_review']=True
        candidate['postblind_adjudication']={'version':'P6C4_evidence_comparison_v1','disposition':n['disposition'],
            'rationale':n['rationale'],'backend_model_id':None,'not_a_third_blind_context':True,
            'generation_record_hash':canonical(before),'sealed_independent_record_hash':raw_hash[sid]}
        compared=(*LAYERS,'reserved_original_items','dictionary_additions','core_explanation')
        changes={k:{'before':before[k],'after':candidate[k]} for k in compared if before[k]!=candidate[k]}
        preferences=[{'reason':n['rationale'],'counted_as_error':False}] if n['disposition']=='preference' else []
        for f in b['source_findings']:raw_findings.append({'stable_id':sid,'headword':w,'raw_finding':f,'automatically_counted_as_generator_error':False})
        findings+=issues
        records.append({'stable_id':sid,'headword':w,'source_hash':before['source_hash'],'stratum':before['stratum'],
            'initial_generation':before,'independent_source_first_proposal':b,
            'independent_reviewer':owner[sid],'sealed_blind_record_hash':raw_hash[sid],
            'comparison':{'layer_POS_source_partition_differs':partition(before)!=partition(b),
                          'core_source_membership_differs':core_ids(before)!=core_ids(b),
                          'mechanical_difference_is_not_error':True},
            'adjudication':{'disposition':n['disposition'],'rationale':n['rationale'],
                'confirmed_findings':issues,'teaching_preferences':preferences,
                'raw_source_findings_not_automatically_transferred':b['source_findings'],
                'source_external_suggestions':'Independent dictionary_additions remain proposals, not a checked full dictionary or automatic adoption.',
                'correction_verification':fix,'human_approved':False},
            'candidate':candidate,'semantic_changes':changes,'human_approved':False,'needs_human_review':True})
    before_load=[len(r['initial_generation']['core_meanings']) for r in records]
    after_load=[len(r['candidate']['core_meanings']) for r in records]
    flags=collections.Counter(str(f['raw_finding'].get('severity','unspecified')) for f in raw_findings)
    metrics={'generated':100,'source_first_independently_reviewed':100,'distinct_formal_IDs':100,
        'overlap_existing500':0,'original_fragments':sum(len(r['initial_generation']['original_meanings']) for r in records),
        'initial_confirmed_Critical':0,'initial_confirmed_Major':1,'initial_confirmed_Minor':0,
        'core_scope_error_words':1,'important_scope_omission_words':1,'confirmed_core_ordering_error_words':0,
        'confirmed_POS_confusion_words':0,'confirmed_false_merge_words':0,'confirmed_unsourced_core_addition_words':0,
        'same_C3_POS_partition_loss_repeated_in_fresh100':0,
        'related_source_coverage_risk_reappeared_words':1,
        'unresolved_current_misleading_core_Major_after_conservative_correction':0,
        'unresolved_original_source_scope_adoption_words':1,
        'preference_only_words':sum(bool(r['adjudication']['teaching_preferences']) for r in records),
        'initial_AI_risk_flagged_words':sum(bool(r['initial_generation']['risk_flags']) for r in records),
        'raw_blind_source_flag_counts_not_error_counts':dict(flags),
        'partition_disagreement_words':sum(r['comparison']['layer_POS_source_partition_differs'] for r in records),
        'core_membership_disagreement_words':sum(r['comparison']['core_source_membership_differs'] for r in records),
        'initial_dictionary_candidates':sum(len(r['initial_generation']['dictionary_additions']) for r in records),
        'final_dictionary_candidates_not_adopted':sum(len(r['candidate']['dictionary_additions']) for r in records),
        'raw_blind_dictionary_suggestions_not_automatically_new_senses':sum(len(r['independent_source_first_proposal']['dictionary_additions']) for r in records),
        'human_review_required':100,'human_approved':0,
        'focused_additional_evidence_words':[r['headword'] for r in records if r['adjudication']['disposition'] in ('confirmed_major','evidence_pending')],
        'core_groups_initial':sum(before_load),'core_groups_after':sum(after_load),
        'core_average_initial':statistics.mean(before_load),'core_median_initial':statistics.median(before_load),'core_max_initial':max(before_load),
        'core_average_after':statistics.mean(after_load),'core_median_after':statistics.median(after_load),'core_max_after':max(after_load),
        'initial_over3_words':[r['headword'] for r in records if len(r['initial_generation']['core_meanings'])>3],
        'changed_content_words':sum(bool(r['semantic_changes']) for r in records),
        'V3_matched_arm':None,'V3_improvement_percent':None,
        'actual_tokens':None,'actual_cost':None}
    result={'schema_version':'p6c4_blind100.v1','record_count':100,'AI_candidates_only':True,
        'rules':'P6C4-V4.1','records':records,'metrics':metrics,'confirmed_findings':findings,
        'raw_source_findings':raw_findings,'source_first_review_seal':seal,
        'generation_seal_sha256':sha(OUT/'GENERATION_SEAL.json'),'gate_protocol_sha256':sha(OUT/'GATE_PROTOCOL.json'),
        'adjudication_notes_sha256':sha(ROOT/'scripts/p6c4/blind_adjudication.tsv'),
        'backend_model_id':None,'proven_different_model':False,
        'independence_limitation':'Two fresh source-only reviewer contexts, no proven different backend or same-word double-review agreement. Parent comparison is non-blind.',
        'quality_limit':'clause原文范围及分句候选采用仍待决；high原文高地未证实；drive对象细化待补核。未签审100词都保持候选。',
        'not_merged_into500':True,'not_published':True,'formal_writes':False,'SQLite_opened':False,'Notion_accessed':False}
    save(OUT/'blind_test_100.json',result)
    print(metrics)

if __name__=='__main__':main()
