"""Freeze the accepted model preflight/config; never silently updates a run."""
from common import *

def main():
    if (OUT / 'RUN_MANIFEST.json').exists():
        verify_frozen()
        print('Frozen manifest already exists and verifies.')
        return
    adjudication = read(OUT / 'PREFLIGHT_ADJUDICATION.json')
    require(adjudication['accepted'] is True, 'No accepted semantic/model preflight')
    require(read(OUT/'PREFLIGHT_REVIEW_ADJUDICATION.json')['accepted'] is True, 'No accepted error-detector preflight')
    verify_protected()
    paths = [RULES, FORMAL, ROOT / 'docs/p6/p6c2/core_meanings_500.json',
             ROOT / 'docs/p6/p6c3/QUALITY_GATE_REPORT.md',
             ROOT / 'docs/p6/p6c4/regression_500.json', ROOT / 'docs/p6/p6c4/blind_test_100.json',
             ROOT / 'docs/p6/p6c4/QUALITY_GATE_REPORT.md', OUT / 'INPUT_SETS.json',
             OUT / 'evidence/wordnet_4732.json', OUT / 'PREFLIGHT_ADJUDICATION.json',
             OUT / 'PREFLIGHT_REVIEW_ADJUDICATION.json', OUT / 'PREFLIGHT_PUBLISHER_EVIDENCE.json']
    paths += list((OUT / 'inputs').glob('*.json'))
    paths += [ROOT / 'scripts/p6c5' / n for n in ['common.py', 'PROMPT.md', 'REVIEW_PROMPT.md',
              'api_client.py', 'records.py', 'run_batches.py', 'preflight.py', 'prepare.py', 'freeze.py']]
    config = {'batch_words': 100, 'batch_count': 48, 'generation_transport_words': 2,
              'review_transport_words': 1, 'transport_concurrency': 50,
              'next_batch_only_after_validated_checkpoint': True,
              'low_risk_sample_fraction': 0.10, 'low_risk_sample_seed': 'P6C5_lowrisk_sample_v1',
              'max_same_model_structure_repair_calls_per_transport': 1,
              'automatic_network_retries': 0, 'automatic_fallback_model': False,
              'stop_on_Critical_alarm_or_data_corruption': True}
    result = {'schema_version': 'P6C5_frozen_run_v1', 'frozen_utc': now(),
              'rules_version': 'P6C4-V4.1', 'rules_hash': sha(RULES),
              'formal_input_sha256': sha(FORMAL), 'set_counts': {'A': 500, 'B': 100, 'C': 4732, 'total': 5332},
              'requested_model': adjudication['accepted_model'],
              'model_source': 'Existing DEEPSEEK_API_KEY environment credential; official api.deepseek.com; no credential serialization',
              'provider_documented_snapshot': {'deepseek-v4-pro':'DeepSeek-V4-Pro-0813','deepseek-flash':'DeepSeek-V4.1-Flash-1017'}[adjudication['accepted_model']],
              'exact_served_snapshot_returned_by_API': None,
              'model_documentation': 'https://api-docs.deepseek.com/quick_start/pricing/',
              'generation_prompt_version': 'P6C5-generation-v3', 'review_prompt_version': 'P6C5-second-review-v1',
              'thinking': 'enabled', 'reasoning_effort': adjudication['accepted_effort'],
              'review_model': 'deepseek-v4-pro', 'review_reasoning_effort': 'low',
              'review_model_validation': 'PREFLIGHT_REVIEW_ADJUDICATION.json',
              'same_returned_model_required': True, 'batch_config': config,
              'frozen_files': {p.relative_to(ROOT).as_posix(): sha(p) for p in paths},
              'classification_definitions': {
                  'AI_processed_no_obvious_risk': 'Actually generated and structurally checked; no detected substantive flags; NOT human approved/accuracy guarantee',
                  'AI_processed_needs_human_review': 'AI generated, risk/uncertainty or historical queue retained',
                  'confirmed_problem_revision_pending': 'Evidence-adjudicated problem/correction still awaiting adoption or human confirmation',
                  'processing_failed_or_evidence_insufficient': 'No honest supported core or missing/failed model processing; never filled by template'},
              'release_gate_fixed_before_full_generation': {
                  'A': '5332 actual candidates, full source/ID/provenance contracts, no failed generation, no new unresolved confirmed Critical/systematic Major, historical/source adoption risks explicitly quarantined; ready ONLY for pre-release quality review',
                  'B': 'Candidate set substantially generated but missing/failed words or unresolved confirmed repairable defects remain',
                  'C': 'Confirmed systematic semantic/data/rule failure; stop processing and preserve checkpoints'},
              'systematic_stop_definition': 'Two or more newly evidence-confirmed Major issues of the same causal source/POS/use-mapping type in a batch, or parent-confirmed rule-wide failure. AI risk flags alone are not confirmation.',
              'all_output_isolated': True, 'formal_publication_authorized': False}
    once(OUT / 'RUN_MANIFEST.json', result)
    print(json.dumps({'frozen': True, 'rules_hash': result['rules_hash'], 'model': result['requested_model'], 'config': config}))

if __name__ == '__main__':
    main()
