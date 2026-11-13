"""Read-only600-word/protocol/source integrity checks and fixed gate evaluation."""
import collections
import copy
import csv
import json
import statistics
import subprocess
from prepare import ROOT,OUT,read,sha,canonical,save,verify_protection
from seal_reviews import frozen_protocols

LAYERS=('core_meanings','extended_meanings','other_meanings')

def require(ok,message):
    if not ok:raise ValueError(message)

def validate_record(r,source,wn):
    for k in ['stable_id','headword','part_of_speech','source_fields','source_hash','original_meaning_zh','original_meanings']:
        require(r[k]==source[k],'Immutable source field changed: '+k)
    require(r['source_hash']==canonical(r['source_fields']),'Wrong source hash')
    require(r['human_approved'] is False and r['needs_human_review'] is True,'AI candidate falsely approved')
    atoms={a['source_sense_id']:a for a in r['original_meanings']}
    require(len(atoms)==len(r['original_meanings']),'Duplicate original IDs')
    for a in atoms.values():require(r['original_meaning_zh'][a['start']:a['end']]==a['text'],'Original Unicode span changed')
    evidence={e['evidence_id']:e for e in r['supporting_sources']};wnids={e['evidence_id'] for e in wn}
    mapped=[]
    for k in LAYERS:
        require(isinstance(r[k],list),'Invalid layer')
        for g in r[k]:
            require(g['display_zh'] and g['source_sense_ids'] and g['evidence_ids'],'Empty/untraceable group')
            require(g['part_of_speech'] in r['part_of_speech'].split('；'),'Unsupported source-derived POS')
            require(set(g['source_sense_ids'])<=set(atoms),'Invented original meaning')
            mapped+=g['source_sense_ids']
            require({a['source_sense_id'] for a in g['source_subsenses']}==set(g['source_sense_ids']),'Lost subsense mapping')
            for a in g['source_subsenses']:require(a['original_gloss']==atoms[a['source_sense_id']]['text'],'Rewritten source subsense')
            for eid in g['evidence_ids']:
                require(eid in evidence,'Dangling reference: '+eid)
                if eid.startswith('wn31:'):require(eid in wnids,'Wrong-headword WordNet reference')
    mapped += [a['source_sense_id'] for a in r['reserved_original_items']]
    require(set(mapped)==set(atoms),'Lost/invented original fragment mapping')
    repeated={s for s,n in collections.Counter(mapped).items() if n>1}
    require(repeated<={a['source_sense_id'] for a in r.get('semantic_splits',[])},'Unexplained one-to-many mapping')
    for a in r['dictionary_additions']:
        require(a['source_sense_ids']==[],'Dictionary content attached to original ID')
        require(not a.get('human_approved',False) and not a.get('auto_promoted_to_core',False),'Unauthorized dictionary adoption')
        require(a['evidence_ids'] and all(e in evidence for e in a['evidence_ids']),'Uncited external candidate')
    require(bool(r['core_meanings']),'No source-supported core to study')
    return True

def evaluate_gate(reg,blind,integrity_passed):
    """Literal application of the preregistered criteria; no score confidence."""
    rm=reg['metrics'];bm=blind['metrics']
    initial_issues=blind['confirmed_findings']
    causal=collections.Counter(i['normalized_cause'] for i in initial_issues if i['severity']=='Major')
    introduced=[i for r in reg['records'] for i in r['new_regression_introduced_confirmed_findings'] if i['severity']=='Major']
    causal.update(i['normalized_cause'] for i in introduced)
    c3={x['headword']:x for x in reg['C3_confirmed_problem_verification']}
    any_current_critical=any(i['severity']=='Critical' for i in initial_issues+reg['newly_confirmed_baseline_findings'])
    checks={
        'all500_semantically_reviewed_and_historical48_retained':len(reg['records'])==500 and len(reg['historical48_review'])==48 and all(x['status']=='pending_not_auto_passed' for x in reg['historical48_review']),
        'fresh100_source_first_reviewed':bm['source_first_independently_reviewed']==100,
        'identity_original_coverage_one_to_many_human_status':integrity_passed,
        'C3_corrections_verified_management_tracking_not_adoption':set(c3)=={'import','management','indicate'} and all(x['verification']['source_identity_unchanged'] for x in c3.values()) and c3['management']['status']=='source_gap_tracked_adoption_unresolved',
        'no_unresolved_current_Critical_or_Major':not any_current_critical and rm['current_candidate_Major_open_after_isolated_correction']==0 and bm['unresolved_current_misleading_core_Major_after_conservative_correction']==0 and bm['initial_confirmed_Critical']==0,
        'no_same_systematic_major_in_fresh_or_introduced_changes':max(causal.values(),default=0)<2,
        'fresh100_initial_Major_le3_Minor_le10':bm['initial_confirmed_Major']<=3 and bm['initial_confirmed_Minor']<=10,
        'fresh_Major_has_content_correction_and_independent_lexical_validation':all(r['adjudication']['correction_verification'] and r['adjudication']['correction_verification']['lexical_boundary_verified'] and r['adjudication']['correction_verification']['current_misleading_grammar_core_removed'] for r in blind['records'] if r['adjudication']['confirmed_findings']),
        'no_confirmed_new_regression_loss':rm['introduced_regression_confirmed_errors']==0,
        'no_overall_POS_or_mapping_defect':integrity_passed and bm['confirmed_POS_confusion_words']==0,
        'external_and_unapproved_data_stay_candidates':all(not r['human_approved'] for r in reg['records']+blind['records']),
    }
    method=blind.get('fundamental_method_evidence',{})
    proved_fundamental=(method.get('unrepairable_by_local_rule') is True and
                       len(set(method.get('affected_strata',[])))>=3 and bool(method.get('concrete_evidence_ids')))
    decision='C' if proved_fundamental else 'A' if all(checks.values()) else 'B'
    return {'decision':decision,'criteria_sha256':sha(OUT/'GATE_PROTOCOL.json'),'checks':checks,
        'failed_checks':[k for k,v in checks.items() if not v],
        'fresh_or_introduced_Major_cause_counts':dict(causal),
        'baseline_repeated_POS_partition_Major_not_hidden':4,
        'baseline_POS_partition_pattern_correction_status':'four_discovered_baseline_words_corrected_source_use_retained; C3_import_also_corrected',
        'source_gaps_still_pending':['management人员义采用','clause语法上位概念采用'],
        'authority':'Only suggests expanded ISOLATED processing with the same per-batch evidence/checkpoints and stop-on-failure; no publication or automatic full run.',
        'original_4832_remainder_already_sampled':100,'actually_unprocessed_after_this_task':4732,
        'remaining_full_run_started':False,'human_dictionary_quality_claim':False,
        'different_backend_model_proven':False}

def validate_all():
    frozen_protocols();protection=verify_protection()
    for seal_name in ['REGRESSION_REVIEW_SEAL.json','BLIND_REVIEW_SEAL.json']:
        s=read('docs/p6/p6c4/'+seal_name)
        maps=[s['files']] if 'files' in s else [r['files'] for r in s['reviewers'].values()]
        for m in maps:
            for p,h in m.items():require(sha(ROOT/p)==h,'Review output modified after seal')
    reg=read('docs/p6/p6c4/regression_500.json');blind=read('docs/p6/p6c4/blind_test_100.json')
    baseline={r['stable_id']:r for r in read('docs/p6/p6c2/core_meanings_500.json')['records']}
    gen={r['stable_id']:r for r in read('docs/p6/p6c4/generation/generated_100.json')['records']}
    wns=read('private/p6c4/wordnet_selected600.json')['headwords']
    with (ROOT/'docs/p5a/public/formal_learning_vocabulary.csv').open(encoding='utf-8-sig',newline='') as f:formal={r['entry_id']:r for r in csv.DictReader(f)}
    require(len(formal)==5332,'Formal count drift')
    require(len(reg['records'])==len({r['stable_id'] for r in reg['records']})==500,'Regression IDs')
    require(len(blind['records'])==len({r['stable_id'] for r in blind['records']})==100,'Fresh IDs')
    require(not set(baseline)&set(gen) and set(baseline)|set(gen)<=set(formal),'Fresh overlap/nonformal IDs')
    selection=read('docs/p6/p6c4/selection_100.json')
    require(set(gen)=={r['stable_id'] for r in selection['records']},'Selection drift')
    require(collections.Counter(r['stratum'] for r in gen.values())=={k:20 for k in selection['strata']},'Strata drift')
    for entry in reg['records']+blind['records']:
        c=entry['candidate'];source=baseline[c['stable_id']] if c['stable_id'] in baseline else gen[c['stable_id']]
        require(c['source_fields']==formal[c['stable_id']],'Formal source snapshot mismatch')
        validate_record(c,source,wns[c['headword']])
        require(entry['human_approved'] is False,'Fake approval on comparison entry')
    require(sum(len(r['candidate']['original_meanings']) for r in reg['records'])==1216,'500 source loss')
    require(sum(len(r['candidate']['original_meanings']) for r in blind['records'])==237,'100 source loss')
    hist={r['stable_id'] for r in reg['historical48_review']}
    c3=read('docs/p6/p6c3/independent_quality_review.json')
    old48={r['stable_id'] for r in c3['inherited100_pending_queue']}
    extra48={r['stable_id'] for r in c3['records'] if r['selection']['role']=='stratified_audit'}
    require(hist==old48 and len(hist)==len(extra48)==48 and not hist&extra48,'Two distinct48 sets confused')
    require(all(r['candidate']['historical_risk_retained'] for r in reg['records'] if r['stable_id'] in hist),'Historical risk cleared')
    known={r['headword']:r for r in reg['C3_confirmed_problem_verification']}
    require(known['management']['source_gap_closed'] is False,'Management source gap falsely closed')
    core_changes={r['headword'] for r in reg['records'] if r['semantic_changes']}
    require(core_changes=={'import','indicate','management','escape','transfer','neglect','support','stewardess'},'Unnecessary regression changes')
    # New corrections retain all old accurate groups. Scope-note changes and
    # C3 fixes are separately documented rather than silently equated.
    for w in ['escape','transfer','neglect','support']:
        e=next(r for r in reg['records'] if r['headword']==w);old=baseline[e['stable_id']]
        for k in LAYERS:require(e['candidate'][k][:len(old[k])]==old[k],'Existing correct use removed')
    clause=next(r for r in blind['records'] if r['headword']=='clause')
    require(clause['initial_generation']==gen[clause['stable_id']],'Sealed initial generation changed')
    require(any(a['source_sense_id']=='s001' and a['text']=='从句' for a in clause['candidate']['reserved_original_items']),'Narrow source lost')
    require(not any('s001' in g['source_sense_ids'] for g in clause['candidate']['core_meanings']),'Misleading grammar core not removed')
    require(any(a['source_sense_ids']==[] and '分句' in a['meaning_zh'] for a in clause['candidate']['dictionary_additions']),'Scope correction not independently held')
    require([r['headword'] for r in blind['records'] if r['semantic_changes']]==['clause'],'Unnecessary fresh100 changes')
    require(collections.Counter(i['severity'] for i in blind['confirmed_findings'])=={'Major':1},'Blind error metric drift')
    require(all(r['initial_generation']==gen[r['stable_id']] for r in blind['records']),'Rewrote sealed generation to match blind answers')
    require(blind['metrics']['human_review_required']==100 and blind['proven_different_model'] is False,'Fake human/backend validation')
    gate=evaluate_gate(reg,blind,True)
    return {'passed':True,'formal5332_unchanged':True,'old500_unchanged':True,'regression500_reviewed':500,
            'fresh100_reviewed':100,'original_fragments_retained':1453,'historical48_retained':48,
            'extra_C3_sample48_is_distinct':True,'model_and_network_calls_by_validation':0,
            'personal_SQLite_and_sidefiles_unchanged':True,'gate':gate},protection

def main():
    result,protection=validate_all();save(OUT/'VALIDATION_RESULTS.json',result);save(OUT/'GATE_RESULT.json',result['gate'])
    protection['git_branch_after']=subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()
    protection['git_status_after']=subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True).splitlines()
    protection['scope_note']='本轮只写p6c4文档/脚本/测试及私有源包；工作区已有日语/UI并行改动未触碰、未回退，不能把整个Git差异说成本轮改动。'
    save(OUT/'preservation_check.json',protection)
    print(result)

if __name__=='__main__':main()
