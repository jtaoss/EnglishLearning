"""Read-only contracts and provenance checks for isolated P6-C.3 artifacts."""
import collections
import copy
import csv
import json
import subprocess

from prepare_review import ROOT, OUT, PRIVATE, load, save, preservation_check
from seal_blind_reviews import main as seal, digest
from build_quality_review import canonical, LAYERS, partitions, core_ids


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_candidate(candidate, original, raw_packet):
    for field in ('stable_id', 'headword', 'part_of_speech', 'source_fields',
                  'source_hash', 'original_meaning_zh', 'original_meanings'):
        require(candidate[field] == original[field], 'Immutable original changed: '+field)
    require(candidate['human_approved'] is False and candidate['needs_human_review'] is True,
            'AI candidate cannot become human approved')
    original_ids = {a['source_sense_id'] for a in original['original_meanings']}
    require(len(original_ids) == len(original['original_meanings']), 'Duplicate original IDs')
    atoms = {a['source_sense_id']: a for a in original['original_meanings']}
    for a in atoms.values():
        require(original['original_meaning_zh'][a['start']:a['end']] == a['text'], 'Unicode source span')
    wn = {e['evidence_id']: e for e in raw_packet['unfiltered_wordnet_senses']}
    pubs = {e['evidence_id']: e for e in load('docs/p6/p6c3/publisher_observations.json')['observations']}
    evidence = {e['evidence_id']: e for e in candidate['supporting_sources']}
    mapped = []; group_ids = []
    source_pos = original['part_of_speech'].split('；')
    for layer in LAYERS:
        for group in candidate[layer]:
            require(group['display_zh'] and group['part_of_speech'] in source_pos, 'Invalid group POS/text')
            group_ids.append(group['sense_group_id'])
            require(group['source_sense_ids'] and group['evidence_ids'], 'Untraceable group')
            mapped += group['source_sense_ids']
            require({a['source_sense_id'] for a in group['source_subsenses']} == set(group['source_sense_ids']), 'Missing subsense mapping')
            for sub in group['source_subsenses']:
                require(sub['original_gloss'] == atoms[sub['source_sense_id']]['text'], 'Rewritten original subsense')
            for eid in group['evidence_ids']:
                require(eid in evidence, 'Dangling group evidence')
                if eid.startswith('wn31:'):
                    require(eid in wn, 'WordNet evidence belongs to another headword')
                    require(wn[eid]['definition_en'] == evidence[eid]['definition_en'], 'Altered licensed definition')
                    require(eid.split(':')[1] == 'v' if group['part_of_speech'] == '动词' else eid.split(':')[1] == 'n', 'Evidence POS mismatch')
                elif eid.startswith('p6c3:'):
                    require(eid in pubs and pubs[eid]['headword'] == candidate['headword'], 'Wrong publisher observation')
    mapped += [a['source_sense_id'] for a in candidate['reserved_original_items']]
    require(set(mapped) == original_ids, 'Lost or invented original source reference')
    require(len(group_ids) == len(set(group_ids)), 'Duplicate group IDs')
    repeated = {s for s, n in collections.Counter(mapped).items() if n > 1}
    splits = candidate.get('semantic_splits', [])
    require(repeated <= {a['source_sense_id'] for a in splits}, 'Unexplained one-to-many mapping')
    for split in splits:
        require(split['source_sense_id'] in original_ids and len(split['uses']) >= 2, 'Invalid semantic split')
        require('AI' in split['annotation'], 'Split must not masquerade as original text')
    old_adds = original['dictionary_additions']
    require(candidate['dictionary_additions'][:len(old_adds)] == old_adds, 'Old addition overwritten')
    for addition in candidate['dictionary_additions']:
        require(addition['source_sense_ids'] == [], 'External content promoted into original mapping')
        require(addition.get('human_approved', False) is False and not addition.get('auto_promoted_to_core', False), 'Unauthorized adoption')
        require(addition['evidence_ids'] and all(e in evidence for e in addition['evidence_ids']), 'Uncited addition')
    return True


def run_validation():
    seal()  # Includes input/proposal SHA and exact licensed definitions.
    preservation = preservation_check()
    base = load('docs/p6/p6c2/core_meanings_500.json')
    original = {r['stable_id']: r for r in base['records']}
    review = load('docs/p6/p6c3/independent_quality_review.json')
    revised = load('docs/p6/p6c3/REVISED_CANDIDATES.json')
    plan = load('docs/p6/p6c3/selection_plan.json')
    require(len(original) == len(base['records']) == 500, 'Base scope not 500')
    require(digest(ROOT/'docs/p6/p6c2/core_meanings_500.json') == review['input_dataset']['sha256'] == revised['input_sha256'], 'Base dataset changed')
    with (ROOT/'docs/p5a/public/formal_learning_vocabulary.csv').open(encoding='utf-8-sig', newline='') as f:
        formal = {r['entry_id']: r for r in csv.DictReader(f)}
    require(len(formal) == 5332 and set(original) <= set(formal), 'Nonformal IDs in scope')
    for sid, r in original.items():
        require(r['source_fields'] == formal[sid] and r['source_hash'] == canonical(formal[sid]), 'Source fields/hash drift')
    require(len(review['records']) == len({r['stable_id'] for r in review['records']}) == 90, 'Review scope not 90 unique')
    require({r['stable_id'] for r in review['records']} == {r['stable_id'] for r in plan['selected']}, 'Sample selection drift')
    actual_major = {r['stable_id'] for r in base['records'][100:] if r['ai_semantic_review']['severity'] == 'Major'}
    reviewed_major = {r['stable_id'] for r in review['records'] if r['selection']['role'] == 'target_major'}
    require(len(actual_major) == 42 and reviewed_major == actual_major, 'Missed one of 42 flags')
    require(len(review['not_rechecked_ids']) == 410 and set(review['not_rechecked_ids']) | {r['stable_id'] for r in review['records']} == set(original), 'Unreviewed words auto-passed or dropped')
    require(review['inherited100_pending_queue'] == plan['old_unresolved_high_or_reserved'], 'Old pending queue cleared')
    require(len(review['inherited100_pending_queue']) == 48, 'Old high-risk count drift')
    focused = review['focused_pending_priority_queue']
    focused_ids = {r['stable_id'] for r in focused}
    expected_focused = {r['stable_id'] for r in review['inherited100_pending_queue']}
    expected_focused |= {r['stable_id'] for r in base['records'] if r['reserved_original_items']}
    expected_focused |= {r['stable_id'] for r in review['existing_core_addition_suggestions_still_pending']}
    expected_focused |= {r['stable_id'] for r in review['confirmed_findings'] if r['severity'] in ('Critical', 'Major')}
    require(len(focused_ids) == len(focused) == review['summary']['focused_pending_priority_words_union'] == 85 and focused_ids == expected_focused, 'Pending union lost/duplicated words')
    for p, sha in review['provenance_hashes'].items():
        require(digest(ROOT/p) == sha, 'Provenance input changed: '+p)
    raw = {r['stable_id']: r for n in 'AB' for r in json.loads((PRIVATE/f'blind_packet_{n}.json').read_text(encoding='utf-8'))['records']}
    for r in review['records']:
        a = original[r['stable_id']]
        require(r['original_meanings'] == a['original_meanings'] and r['source_hash'] == a['source_hash'], 'Review changed original')
        require(r['human_approved'] is False, 'Fake human approval')
        require(r['comparison']['layer_POS_source_partition_differs'] == (partitions(a) != partitions(r['independent_proposal'])), 'Comparison metric drift')
        for sf in r['adjudication']['source_findings_not_auto_transferred']:
            require(sf['automatically_counted_as_current_candidate_error'] is False, 'Raw flag counted as candidate error')
        for p in r['adjudication']['teaching_preferences']:
            require(p['counted_as_error'] is False, 'Preference counted as error')
        for a in r['adjudication']['dictionary_addition_comparison']:
            require(not a['auto_promoted_to_core'] and not a['human_approved'], 'Addition silently adopted')
    issues = review['confirmed_findings']
    require({i['issue_id'] for i in issues} == {'C3-001', 'C3-002', 'C3-003'}, 'Unexpected adjudication scope')
    require(collections.Counter(i['severity'] for i in issues) == {'Major': 2, 'Minor': 1}, 'Severity totals incorrect')
    require(review['summary']['confirmed_POS_confusion_words'] == 0 and not any(i['pos_confusion'] for i in issues), 'Omission confused with POS error')
    gate = review['quality_gate']
    require(gate['decision'] == 'B' and gate['expand_remaining_4832_now'] is False, 'Premature expansion')
    require(review['independence']['proven_different_model_identity'] is False and review['summary']['proven_different_backend_model_disagreement_words'] is None, 'Invented cross-model identity proof')
    require(revised['record_count'] == len(revised['records']) == 3, 'Unexpected revised scope')
    require({r['headword'] for r in revised['records']} == {'import', 'management', 'indicate'}, 'Revised unconfirmed word')
    for entry in revised['records']:
        a = original[entry['stable_id']]; c = entry['candidate']
        require(entry['base_record_hash'] == canonical(a) and entry['candidate_record_hash'] == canonical(c), 'Revision hash drift')
        require(entry['adopted'] is False and entry['human_approved'] is False, 'Unauthorized adoption')
        validate_candidate(c, a, raw[a['stable_id']])
        changed = {k: {'before': a.get(k), 'after': c.get(k)} for k in sorted(set(a)|set(c)) if a.get(k) != c.get(k)}
        require(changed == entry['changes'], 'Incomplete before/after diff')
        require(c['p6c3_revision']['rules_sha256'] == digest(OUT/'RULES_V4.md'), 'Candidate rule hash drift')
    # A diagnostic counter-example: management cannot be "fixed" by inserting
    # the external people sense into an original-derived core group.
    management = next(e['candidate'] for e in revised['records'] if e['headword'] == 'management')
    require(management['core_meanings'] == next(r for r in original.values() if r['headword'] == 'management')['core_meanings'], 'External management sense auto-promoted')
    return {'passed': True, 'formal_words_unchanged': 5332, 'base_words_unchanged': 500,
            'blind_records_sealed': 90, 'all_major_flags_checked': 42,
            'additional_sample': 48, 'original_fragments_reviewed': 221,
            'revised_candidates': 3, 'unique_revised_original_fragments': sum(len(e['candidate']['original_meanings']) for e in revised['records']),
            'protected_English_sources_and_personal_DB_unchanged': True,
            'concurrent_Japanese_drift_observed': bool(preservation['out_of_scope_concurrent_Japanese_changes_observed']),
            'model_API_calls_during_validation': 0, 'network_calls_during_validation': 0}


def main():
    result = run_validation()
    snapshot = preservation_check()
    snapshot['git_branch_observed'] = subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT, text=True).strip()
    snapshot['git_HEAD_observed'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    snapshot['git_status_observed'] = subprocess.check_output(['git', 'status', '--short'], cwd=ROOT, text=True).splitlines()
    snapshot['attribution_note'] = '共享工作区另有日语/应用设置改动；本轮未切换分支、修改或恢复这些文件。Git状态不是本轮改动清单。'
    save(OUT/'preservation_check.json', snapshot)
    save(OUT/'VALIDATION_RESULTS.json', result)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
