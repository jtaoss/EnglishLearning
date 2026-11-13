"""Sequential 100-word checkpoints; bounded concurrent transports inside a batch.

All words receive real model decisions. No heuristic/default meaning generation.
"""
import argparse
import concurrent.futures
import copy
import math
from api_client import call, system_prompt
from common import *
from records import expand, parse_response

def reviewed_packet(item, candidate, source_first):
    result = copy.deepcopy(item)
    result['review_role'] = 'source_first_sample' if source_first else 'targeted_risk'
    if not source_first:
        result['candidate'] = {k: candidate[k] for k in (*LAYERS, 'reserved_original_items', 'dictionary_additions', 'selection_reason', 'source_POS_coverage')}
    return result

def generate_chunk(b, i, items):
    tag = f'generation_{b:03d}_{i:02d}'
    result = call(tag, system_prompt('generation'), {'records': items})
    try:
        return parse_response(result, items), result
    except (ValueError, KeyError, TypeError) as e:
        # Preserve both attempts. A single same-model repair is preregistered;
        # it re-reads original inputs, not a deterministic fallback.
        save(OUT / 'failures' / (tag + '_structure.json'), {'tag': tag, 'utc': now(),
             'error': str(e)[:500], 'original_response_hash': canonical(result),
             'action': 'stop_subchunk_and_request_one_same_rule_same_model_repair'})
        payload = {'records': items, 'previous_invalid_output': result['content'],
                   'validator_failure': str(e)[:500],
                   'instruction': 'Re-evaluate every input with the SAME frozen rules. Correct transport/mapping failures. No missing IDs, fallback/default groups or invented evidence. Return the complete replacement records for these IDs only.'}
        repaired = call(tag + '_repair1', system_prompt('generation'), payload)
        return parse_response(repaired, items), repaired

def review_chunk(b, i, packets):
    tag = f'review_{b:03d}_{i:02d}'
    manifest = read(OUT / 'RUN_MANIFEST.json')  # already hash-verified at batch boundary
    api = call(tag, system_prompt('review'), {'records': packets},
               model=manifest['review_model'], effort=manifest['review_reasoning_effort'])
    obj = json.loads(api['content'])
    rs = obj['records']
    require(len(rs) == len(packets) and [r['id'] for r in rs] == [r['id'] for r in packets], 'Review ID/count mismatch')
    for r, item in zip(rs, packets):
        require(r['verdict'] in ('no_confirmed_problem', 'evidence_pending', 'correction_proposed'), 'Bad review verdict')
        require(r['note'] and isinstance(r['findings'], list) and isinstance(r['preferences'], list), 'Empty semantic review')
        catalog = {e['id'] for e in item['evidence']}
        sids = {s['source_sense_id'] for s in item['senses']}
        catalog |= {f"source:{item['id']}:{s}" for s in sids}
        for f in r['findings']:
            require(f['severity'] in ('Critical', 'Major', 'Minor', 'Info') and f['reason'], 'Invalid semantic finding')
            require(set(f['evidence_ids']) <= catalog and set(f['source_sense_ids']) <= sids, 'Review fabricated reference')
        r['review_role'] = item['review_role']
        r['api_tag'] = tag
        r['response_model'] = api['response_model']
        r['response_id'] = api['response_id']
        r['different_model_identifier_from_generation'] = api['response_model'] != manifest['requested_model']
        r['physical_served_weights_independently_verified'] = False
    return rs

def second_review(b, candidates, items, config):
    byid = {r['stable_id']: r for r in candidates}
    targeted = set()
    for r in candidates:
        # Explicit risk-based second review, including all multi-POS, held
        # fragments, >3 cores, Major/Critical flags and important additions.
        if (r['risk_level'] == 'high' or r['reserved_original_items'] or
            len(r['part_of_speech'].split('；')) > 1 or
            len(r['core_meanings']) > 3 or r['dictionary_additions']):
            targeted.add(r['stable_id'])
    low = sorted((r for r in candidates if r['stable_id'] not in targeted),
                 key=lambda r: canonical(['P6C5_lowrisk_sample_v1', r['stable_id']]))
    n = max(1, math.ceil(len(low) * config['low_risk_sample_fraction'])) if low else 0
    sample = {r['stable_id'] for r in low[:n]}
    packets = [reviewed_packet(item, byid[item['id']], item['id'] in sample)
               for item in items if item['id'] in targeted | sample]
    chunks = [packets[i:i+config['review_transport_words']] for i in range(0, len(packets), config['review_transport_words'])]
    reviewed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=config['transport_concurrency']) as pool:
        jobs = [pool.submit(review_chunk, b, i+1, chunk) for i, chunk in enumerate(chunks)]
        for job in jobs:
            reviewed.extend(job.result())
    return {'targeted_ids': sorted(targeted), 'low_risk_pool': len(low),
            'source_first_sample_ids': sorted(sample), 'records': reviewed,
            'independence': 'new stateless API requests; requested/returned model identifiers recorded; no proof of provider internal weights',
            'source_first_sample_has_no_generated_answers': True}

def integrate_reviews(candidates, reviews):
    byid = {r['id']: r for r in reviews['records']}
    stop = []
    for r in candidates:
        review = byid.get(r['stable_id'])
        r['second_review'] = review or {'status': 'not_selected_for_second_pass', 'selection': 'risk-based plus fixed10% source-first low-risk sample'}
        if not review:
            continue
        r['review_preferences'] = review['preferences']
        for i, finding in enumerate(review['findings'], 1):
            r['risk_flags'].append({'severity': finding['severity'], 'code': 'second_review_' + finding['kind'],
                                   'reason': finding['reason'], 'kind': 'AI_second_review_not_parent_confirmed',
                                   'finding_id': f"{r['stable_id']}:second:{i}", 'evidence_ids': finding['evidence_ids']})
            if finding['severity'] == 'Critical':
                stop.append({'stable_id': r['stable_id'], **finding})
        # A substantive proposed defect is quarantined. A reviewer suggestion
        # never edits meanings or becomes a confirmed error by counting alone.
        if review['verdict'] == 'correction_proposed':
            r['quarantine'] = {'status': 'AI_correction_proposed_evidence_adjudication_pending',
                               'reason': '二次审查提出具体问题；未自动修改核心或冒充已确认。'}
            r['review_status'] = 'AI_processed_needs_human_review'
            r['needs_human_review'] = True
            r['risk_level'] = 'high'
        elif review['verdict'] == 'evidence_pending' or review['findings']:
            r['review_status'] = 'AI_processed_needs_human_review' if r['core_meanings'] else 'processing_failed_or_evidence_insufficient'
            r['needs_human_review'] = True
        r['human_approved'] = False
    return stop

def semantic_gate_ok(b, checkpoint):
    if checkpoint.get('semantic_gate_status') != 'repeated_Major_proposals_await_parent_evidence_check':
        return True
    path = OUT / f'parent_gates/batch_{b:03d}.json'
    if not path.exists():
        return False
    gate = read(path)
    require(gate['checkpoint_records_sha256'] == checkpoint['records_sha256'], 'Parent semantic gate points at changed candidates')
    return gate['continue_processing'] is True and gate['human_approved'] is False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--through', type=int, default=48)
    args = parser.parse_args()
    manifest = verify_frozen()
    verify_protected()
    config = manifest['batch_config']
    byid = {r['entry_id']: r for r in formal_rows()}
    evidence = load_evidence()
    for b in range(1, args.through+1):
        verify_frozen()
        checkpoint = OUT / f'batches/batch_{b:03d}.json'
        if checkpoint.exists():
            old = read(checkpoint)
            require(old['status'] == 'validated_checkpoint', 'Batch is stopped, cannot skip it')
            require(old['rules_hash'] == sha(RULES), 'Checkpoint rule drift')
            require(old['records_sha256'] == canonical(old['records']), 'Checkpoint content changed')
            require(semantic_gate_ok(b, old), 'Repeated Major proposals need parent evidence check; no next batch')
            print(f'RESUME verified batch {b}: {len(old["records"])} records', flush=True)
            continue
        start = now()
        batch_input = read(OUT / f'inputs/batch_{b:03d}.json')
        items = batch_input['records']
        print(f'BEGIN batch {b}/48: {len(items)} words', flush=True)
        try:
            n = config['generation_transport_words']
            chunks = [items[i:i+n] for i in range(0, len(items), n)]
            generated = []
            with concurrent.futures.ThreadPoolExecutor(max_workers=config['transport_concurrency']) as pool:
                jobs = [pool.submit(generate_chunk, b, i+1, chunk) for i, chunk in enumerate(chunks)]
                for job in jobs:
                    ds, api = job.result()
                    generated.extend(expand(d, byid[d['id']], evidence[byid[d['id']]['word']], api, b) for d in ds)
            require([r['stable_id'] for r in generated] == [i['id'] for i in items], 'Batch identity drift')
            # Immutable pre-review snapshot: reviewers cannot rewrite generation.
            once(OUT / f'generation/batch_{b:03d}.json', {'rules_hash': sha(RULES), 'records': generated,
                 'input_hash': canonical(batch_input)})
            reviews = second_review(b, generated, items, config)
            once(OUT / f'reviews/batch_{b:03d}.json', reviews)
            critical = integrate_reviews(generated, reviews)
            require(not critical, 'Critical second-review alarm; stop batch for evidence adjudication')
            require(not any(f['severity'] == 'Critical' for r in generated for f in r['risk_flags']), 'Critical generation alarm; stop batch')
            causes = collections.Counter(f['kind'] for r in reviews['records'] for f in r['findings'] if f['severity']=='Major')
            needs_gate = max(causes.values(), default=0) >= 2
            result = {'batch': b, 'status': 'validated_checkpoint', 'started_utc': start, 'completed_utc': now(),
                      'rules_hash': sha(RULES), 'input_hash': canonical(batch_input),
                      'generation_snapshot_hash': sha(OUT / f'generation/batch_{b:03d}.json'),
                      'second_review_snapshot_hash': sha(OUT / f'reviews/batch_{b:03d}.json'),
                      'records': generated, 'records_sha256': canonical(generated),
                      'targeted_review_count': len(reviews['targeted_ids']),
                      'source_first_lowrisk_sample_count': len(reviews['source_first_sample_ids']),
                      'proposed_Major_cause_counts_NOT_confirmed': dict(causes),
                      'semantic_gate_status': 'repeated_Major_proposals_await_parent_evidence_check' if needs_gate else 'no_repeated_Major_proposal_alarm',
                      'confirmed_Critical': 0, 'human_approved': False}
            once(checkpoint, result)
            print(f'PASS batch {b}: {len(generated)} words, targeted {len(reviews["targeted_ids"])}, low-risk source-first {len(reviews["source_first_sample_ids"])}, quarantined {sum("quarantine" in r for r in generated)}', flush=True)
            require(semantic_gate_ok(b, result), 'Repeated Major proposals need parent evidence check; checkpoint preserved, no next batch')
        except Exception as e:
            save(OUT / f'failures/batch_{b:03d}_STOP.json', {'batch': b, 'utc': now(), 'type': type(e).__name__,
                 'error': str(e)[:700], 'next_batch_started': False, 'successful_outputs_preserved': True,
                 'action': 'stop and preserve; no fallback rules/model or fabricated records'})
            raise
    print('REQUESTED BATCHES COMPLETE', flush=True)

if __name__ == '__main__':
    main()
