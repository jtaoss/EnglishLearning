"""Deterministic merge of successful checkpoints; never invokes a model."""
import copy
from common import *

STATES = {'AI_processed_no_obvious_risk', 'AI_processed_needs_human_review',
          'confirmed_problem_revision_pending', 'processing_failed_or_evidence_insufficient'}

def reuse(entry, cohort, source_path, historical):
    before = entry['candidate']
    r = copy.deepcopy(before)
    flags = []
    for f in r.get('risk_flags', []):
        flags.append(copy.deepcopy(f) if isinstance(f, dict) else {'severity': 'Info', 'code': str(f), 'reason': 'Prior AI flag retained', 'kind': 'historical_AI_risk_not_confirmed_error'})
    for f in r.get('v4_review_risk_flags', []):
        flags.append({'severity': 'Info', 'code': f, 'reason': 'P6C4 semantic review risk retained', 'kind': 'historical_AI_risk_not_confirmed_error'})
    if r['stable_id'] in historical:
        flags.append({'severity': 'Info', 'code': 'historical48_pending_not_auto_cleared',
                      'reason': '旧100中的历史48逐词待审状态继承，不因模型认可解除；本条只是待审台账提醒，不把历史high自动重判为Major。',
                      'inherited_risk_level': 'high', 'original_severity_reclassified': False,
                      'kind': 'historical_queue_information_not_new_error_rating'})
    r['prior_risk_flags'] = copy.deepcopy(before.get('risk_flags', []))
    r['risk_flags'] = flags
    r['rules_hash'] = sha(RULES)
    r['publication_status'] = 'isolated_not_published'
    r['human_approved'] = False
    r['needs_human_review'] = True
    r['review_status'] = 'AI_processed_needs_human_review'
    r['confirmed_problems'] = []
    r['historical_risk_retained'] = r['stable_id'] in historical
    if cohort == 'A_original500':
        r['dictionary_observations_unadopted'] = entry['dictionary_observations_unadopted']
        r['historical_review_status'] = entry['historical_status']
        r['prior_regression_assessment'] = entry['regression_assessment']
        if entry['corrected_baseline_issue_ids'] or entry['headword'] in {'import', 'indicate', 'management'}:
            r['review_status'] = 'confirmed_problem_revision_pending'
            r['quarantine'] = {'status': 'isolated_C3_C4_correction_or_source_gap_adoption_pending',
                               'source_issue_ids': entry['corrected_baseline_issue_ids'],
                               'human_approved': False}
    else:
        r['prior_blind_adjudication'] = entry['adjudication']
        r['prior_source_first_proposal_sha256'] = canonical(entry['independent_source_first_proposal'])
        if entry['headword'] == 'clause':
            r['review_status'] = 'confirmed_problem_revision_pending'
            r['quarantine'] = {'status': 'source_scope_repair_addition_not_adopted', 'human_approved': False}
    r['p6c5_lineage'] = {'cohort': cohort, 'source_path': source_path,
                        'source_file_sha256': sha(ROOT / source_path),
                        'source_stage_record_sha256': canonical(entry),
                        'prior_candidate_sha256': canonical(before),
                        'strategy': 'reuse accepted isolated V4.1 candidate, original and C4 histories remain immutable at hash-addressed source',
                        'regenerated': False}
    return r

def build():
    manifest = verify_frozen()
    verify_protected()
    sets = read(OUT / 'INPUT_SETS.json')
    historical = set(sets['historical48'])
    rp = 'docs/p6/p6c4/regression_500.json'
    bp = 'docs/p6/p6c4/blind_test_100.json'
    reg = read(ROOT / rp)
    blind = read(ROOT / bp)
    rs = [reuse(e, 'A_original500', rp, historical) for e in reg['records']]
    rs += [reuse(e, 'B_blind100', bp, historical) for e in blind['records']]
    known = copy.deepcopy(reg['C3_confirmed_problem_verification'] + reg['newly_confirmed_baseline_findings'] + blind['confirmed_findings'])
    for r in rs:
        r['confirmed_problems'] = [x for x in known if x['stable_id'] == r['stable_id']]
    completed = []
    for path in sorted((OUT / 'batches').glob('batch_*.json')):
        d = read(path)
        require(d['status'] == 'validated_checkpoint', 'Stopped batch cannot be merged')
        require(canonical(d['records']) == d['records_sha256'], 'Batch content changed')
        rs.extend(copy.deepcopy(d['records']))
        completed.append({'batch': d['batch'], 'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
                          'record_count': len(d['records']), 'ids': [r['stable_id'] for r in d['records']],
                          'status': d['status'], 'semantic_gate_status': d['semantic_gate_status'],
                          'semantic_accepted': False if (OUT/f'parent_gates/batch_{d["batch"]:03d}.json').exists() and not read(OUT/f'parent_gates/batch_{d["batch"]:03d}.json')['continue_processing'] else d['semantic_gate_status']=='no_repeated_Major_proposal_alarm',
                          'targeted_review_count': d['targeted_review_count'],
                          'source_first_lowrisk_sample_count': d['source_first_lowrisk_sample_count']})
    adjudication = read(OUT/'PARENT_ADJUDICATION.json') if (OUT/'PARENT_ADJUDICATION.json').exists() else {}
    new_findings = adjudication.get('confirmed_findings', [])
    for r in rs:
        findings = [f for f in new_findings if f['stable_id']==r['stable_id']]
        if findings:
            r['confirmed_problems'] = r.get('confirmed_problems', []) + findings
            r['review_status'] = 'confirmed_problem_revision_pending'
            r['needs_human_review'] = True
            r['risk_level'] = 'high'
            r['quarantine'] = {'status':'parent_evidence_confirmed_problem_revision_not_adopted',
                               'issue_ids':[f['issue_id'] for f in findings],
                               'revision_path':'docs/p6/p6c5/REVISED_CANDIDATES.json',
                               'raw_generation_unchanged':True, 'human_approved':False}
    byid = {r['stable_id']: r for r in rs}
    require(len(rs) == len(byid), 'Duplicate ID in merge')
    formal = formal_rows()
    missing = sorted({r['entry_id'] for r in formal} - set(byid))
    require(set(byid) <= {r['entry_id'] for r in formal}, 'Extra nonformal IDs')
    ordered = [byid[r['entry_id']] for r in formal if r['entry_id'] in byid]
    dataset = {'schema_version': 'p6c5_core_meanings_candidates.v1', 'record_count': len(ordered),
               'target_count': 5332, 'generation_complete': not missing,
               'AI_candidates_only': True, 'human_approved_count': 0,
               'publication_status': 'isolated_not_published', 'rules_hash': sha(RULES),
               'run_manifest_sha256': sha(OUT / 'RUN_MANIFEST.json'), 'formal_source_sha256': sha(FORMAL),
               'sets': {'A': 500, 'B': 100, 'C_completed': len(ordered)-600, 'C_expected': 4732},
               'original_span_unit': 'Unicode code points; original fragment definition inherited from C4',
               'known_confirmed_problem_ledger': known, 'new_confirmed_problem_ledger':new_findings,
               'systematic_stop':adjudication.get('systematic_failure_confirmed',False),
               'missing_ids': missing,
               'formal_writes': False, 'SQLite_opened': False, 'Notion_accessed': False,
               'records': ordered}
    checkpoints = {'schema_version': 'p6c5_checkpoints.v1', 'manifest_sha256': sha(OUT / 'RUN_MANIFEST.json'),
                   'rules_hash': sha(RULES), 'expected_new_records': 4732,
                   'validated_new_records': len(ordered)-600, 'completed_batch_count': len(completed),
                   'planned_batch_count': 48, 'batches': completed,
                   'semantically_accepted_batch_count':sum(b['semantic_accepted'] for b in completed),
                   'systematic_stop':adjudication.get('systematic_failure_confirmed',False),
                   'stop_after_batch':adjudication.get('generation_stopped_after_batch'),
                   'missing_ids': missing, 'next_batch': None if adjudication.get('systematic_failure_confirmed') else len(completed)+1 if len(completed)<48 else None,
                   'idempotence_key': '(stable_id, source_hash, rules_hash, prompt version, model config)',
                   'successful_outputs_overwritten': False}
    save(OUT / 'core_meanings_5332_candidates.json', dataset)
    save(OUT / 'BATCH_CHECKPOINTS.json', checkpoints)
    print(json.dumps({'records': len(ordered), 'new_completed': len(ordered)-600, 'missing': len(missing), 'batches': len(completed)}))
    return dataset

if __name__ == '__main__':
    build()
