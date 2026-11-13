"""Read-only full-data contracts and auditable quality counts, no model calls."""
import statistics
from common import *

_WN_IDS = None

def wordnet_ids(word):
    global _WN_IDS
    if _WN_IDS is None:
        heads = read(ROOT/'private/p6c4/wordnet_selected600.json')['headwords']
        heads = {**heads, **load_evidence()}
        _WN_IDS = {w:{e['evidence_id'] for e in refs} for w,refs in heads.items()}
    return _WN_IDS.get(word,set())

def validate_record(r, row):
    require(r['stable_id'] == row['entry_id'] and r['headword'] == row['word'], 'ID/headword mismatch')
    require(r['source_fields'] == row and r['source_hash'] == canonical(row), 'Original source/hash mismatch')
    require(r['original_meaning_zh'] == row['meaning_zh'] and r['part_of_speech'] == row['part_of_speech'], 'Original gloss/POS modified')
    require(r['human_approved'] is False and r['publication_status'] == 'isolated_not_published', 'Unauthorized human approval/publication')
    require(r['rules_hash'] == sha(RULES), 'Wrong rules version')
    require(r['review_status'] in ('AI_processed_no_obvious_risk', 'AI_processed_needs_human_review',
                                   'confirmed_problem_revision_pending', 'processing_failed_or_evidence_insufficient'), 'Unclear processing state')
    source = {s['source_sense_id']: s for s in r['original_meanings']}
    require(len(source) == len(r['original_meanings']), 'Duplicate source fragment')
    for s in source.values():
        require(row['meaning_zh'][s['start']:s['end']] == s['text'], 'Source Unicode span changed')
    refs = {e['evidence_id']: e for e in r['supporting_sources']}
    require(len(refs) == len(r['supporting_sources']), 'Duplicate evidence ID')
    mapped = []
    for layer in LAYERS:
        for g in r[layer]:
            require(g['display_zh'] and g['source_sense_ids'] and g['evidence_ids'], 'Untraceable or empty group')
            require(set(g['source_sense_ids']) <= set(source), 'Invented source meaning')
            require(set(g['evidence_ids']) <= set(refs), 'Dangling group evidence')
            require(g['part_of_speech'] in row['part_of_speech'].split('；'), 'Source-derived POS changed')
            for e in g['evidence_ids']:
                if e.startswith('wn31:'):
                    # Earlier frozen records do not all inline the lemma list;
                    # use their actual full licensed headword evidence catalog.
                    require(e in wordnet_ids(row['word']), 'Wrong-headword WordNet evidence')
                    require(e.split(':')[1] in POS.get(g['part_of_speech'], set()), 'WordNet POS mismatch')
                elif e.startswith('source:'):
                    require(e == f"source:{row['entry_id']}:{e.rsplit(':',1)[1]}" and e.rsplit(':',1)[1] in g['source_sense_ids'], 'Wrong source-only evidence')
            subs = {s['source_sense_id']: s for s in g['source_subsenses']}
            require(set(subs) == set(g['source_sense_ids']), 'Source subsense lost')
            require(all(s['original_gloss'] == source[i]['text'] for i, s in subs.items()), 'Source subsense rewritten')
            mapped.extend(g['source_sense_ids'])
    for s in r['reserved_original_items']:
        require(s['source_sense_id'] in source, 'Held original ID changed')
        if 'text' in s:
            require(s['text'] == source[s['source_sense_id']]['text'], 'Held original changed')
        mapped.append(s['source_sense_id'])
    require(set(mapped) == set(source), 'Original sense mapping missing/extra')
    repeated = {s for s, count in collections.Counter(mapped).items() if count > 1}
    require(repeated <= {s['source_sense_id'] for s in r.get('semantic_splits', [])}, 'Unexplained source split')
    for a in r['dictionary_additions']:
        require(a['source_sense_ids'] == [] and not a.get('human_approved', False) and not a.get('auto_promoted_to_core', False), 'External meaning promoted/attached to source')
        require(a['evidence_ids'] and set(a['evidence_ids']) <= set(refs), 'Uncited external candidate')
    if not r['core_meanings']:
        require(r['review_status'] == 'processing_failed_or_evidence_insufficient', 'Empty core hidden as successful')
    return True

def quality_metrics(data):
    rs = data['records']
    flags = [f for r in rs for f in r.get('risk_flags', [])]
    reviews = [r['second_review'] for r in rs if r.get('second_review', {}).get('api_tag')]
    findings = [f for r in reviews for f in r['findings']]
    api = [read(p) for p in sorted((OUT / 'api').glob('*.json'))]
    usage = collections.Counter()
    for a in api:
        u = a.get('usage') or {}
        for key in ('prompt_tokens', 'completion_tokens', 'total_tokens', 'prompt_cache_hit_tokens', 'prompt_cache_miss_tokens'):
            if isinstance(u.get(key), int):
                usage[key] += u[key]
        usage['reasoning_tokens'] += u.get('completion_tokens_details', {}).get('reasoning_tokens', 0)
    confirmed = data['known_confirmed_problem_ledger']
    adjudication = OUT / 'PARENT_ADJUDICATION.json'
    new_confirmed = read(adjudication).get('confirmed_findings', []) if adjudication.exists() else []
    core = [len(r['core_meanings']) for r in rs]
    fragments = [len(r['original_meanings']) for r in rs]
    states = dict(collections.Counter(r['review_status'] for r in rs))
    # Official rates frozen as an estimate range, not billed cost. Actual
    # per-request usage is available; no account/financial balance is persisted.
    cache = usage['prompt_cache_hit_tokens']
    miss = usage['prompt_cache_miss_tokens'] or usage['prompt_tokens'] - cache
    low_cost = 0.0
    usage_by_model = {}
    for a in api:
        u = a.get('usage') or {}
        model = a['response_model']
        count = usage_by_model.setdefault(model,collections.Counter())
        for k in ('prompt_tokens','completion_tokens','total_tokens','prompt_cache_hit_tokens','prompt_cache_miss_tokens'):
            count[k] += u.get(k,0)
        count['responses'] += 1
        hit = u.get('prompt_cache_hit_tokens',0)
        missed = u.get('prompt_cache_miss_tokens',u.get('prompt_tokens',0)-hit)
        rates = (.003,.15,.6) if model=='deepseek-flash' else (.022,.66,1.98)
        low_cost += (hit*rates[0] + missed*rates[1] + u.get('completion_tokens',0)*rates[2])/1000000
    high_cost = low_cost*2
    formal=formal_rows()
    formal_fragments=sum(len(atoms(r)) for r in formal)
    cohort_metrics={}
    for cohort in ('A_original500','B_blind100','C_new4732'):
        subset=[r for r in rs if r.get('p6c5_lineage',{}).get('cohort',r.get('generation_provenance',{}).get('cohort'))==cohort]
        if subset:
            cohort_metrics[cohort]={'record_count':len(subset),
                'original_fragments':sum(len(r['original_meanings']) for r in subset),
                'original_fragment_mean':statistics.mean(len(r['original_meanings']) for r in subset),
                'core_groups':sum(len(r['core_meanings']) for r in subset),
                'core_group_mean':statistics.mean(len(r['core_meanings']) for r in subset)}
    return {'record_count': len(rs), 'target_count': 5332, 'actual_candidate_generation_complete': data['generation_complete'],
            'cohorts': data['sets'], 'cohort_metrics':cohort_metrics,
            'distinct_stable_ids': len({r['stable_id'] for r in rs}),
            'states': states, 'risk_words': sum(bool(r.get('risk_flags')) for r in rs),
            'AI_risk_flags_by_severity': dict(collections.Counter(f['severity'] for f in flags)),
            'AI_risk_words_by_max_severity': dict(collections.Counter(
                max((f['severity'] for f in r.get('risk_flags', [])), key={'Info':0,'Minor':1,'Major':2,'Critical':3}.get, default='none') for r in rs)),
            'AI_second_review_proposed_findings_by_severity_NOT_confirmed_errors': dict(collections.Counter(f['severity'] for f in findings)),
            'confirmed_historical_problem_severity': dict(collections.Counter(x['severity'] for x in confirmed)),
            'confirmed_new_problem_severity': dict(collections.Counter(x['severity'] for x in new_confirmed)),
            'confirmed_new_findings': new_confirmed,
            'review_preference_words_NOT_errors': sum(bool(r.get('review_preferences')) for r in rs),
            'pure_teaching_preference_words_new_batch': sum(bool(r.get('review_preferences')) and not r.get('confirmed_problems') and not any(f['severity'] in ('Critical','Major','Minor') for f in r.get('second_review',{}).get('findings',[])) for r in rs if r.get('generation_provenance')),
            'candidate_quarantine_words': sum('quarantine' in r for r in rs),
            'source_first_lowrisk_sampled': sum(r['review_role']=='source_first_sample' for r in reviews),
            'targeted_second_reviewed': sum(r['review_role']=='targeted_risk' for r in reviews),
            'source_original_fragment_total': sum(fragments), 'A_original_fragment_average': statistics.mean(fragments),
            'formal5332_original_fragment_total':formal_fragments,
            'A_formal5332_original_fragment_average':formal_fragments/5332,
            'B_full5332_core_group_average':statistics.mean(core) if len(rs)==5332 else None,
            'averages_denominator_actual_generated_or_reused_records':len(rs),
            'core_group_total': sum(core), 'B_first_memory_core_group_average': statistics.mean(core),
            'core_groups_median': statistics.median(core), 'core_groups_max': max(core),
            'more_than3_core_words': sum(n>3 for n in core),
            'empty_core_evidence_insufficient_words': sum(n==0 for n in core),
            'source_fragment_evidence_pending_words':sum(bool(r['reserved_original_items']) for r in rs),
            'second_review_failed_words':sum(r.get('second_review',{}).get('status')=='review_incomplete_after_bounded_attempts' for r in rs),
            'new_batch_generated':sum(bool(r.get('generation_provenance')) for r in rs),
            'new_batch_different_returned_model_identifier_reviews':sum(r.get('second_review',{}).get('different_model_identifier_from_generation',False) for r in rs if r.get('generation_provenance')),
            'dictionary_addition_candidates': sum(len(r['dictionary_additions']) for r in rs),
            'dictionary_observations_kept_separate': sum(len(r.get('dictionary_observations_unadopted', [])) for r in rs),
            'needs_human_review_words': sum(r['needs_human_review'] for r in rs),
            'unapproved_AI_candidates': len(rs), 'human_approved_count': 0,
            'historical48_retained': sum(r['historical_risk_retained'] for r in rs),
            'book_category_counts': dict(collections.Counter(r['source_fields']['book_category'] for r in rs)),
            'actual_API_responses_saved': len(api), 'actual_API_usage': dict(usage),
            'actual_API_usage_by_returned_model':{k:dict(v) for k,v in usage_by_model.items()},
            'actual_API_usage_includes_failed_or_unused_preflight_and_transport_responses':True,
            'Codex_parent_usage_and_cost':None,
            'actual_billed_cost_USD': None, 'cost_estimate_USD_range': [round(low_cost,6), round(high_cost,6)],
            'cost_estimate_basis': {'currency':'USD', 'per_million_off_peak':{'deepseek-v4-pro':{'cached_input':.022,'uncached_input':.66,'output':1.98},'deepseek-flash':{'cached_input':.003,'uncached_input':.15,'output':.6}},
                'peak_multiplier':2,'source':'https://api-docs.deepseek.com/quick_start/pricing/',
                'not_actual_invoice':True, 'request_timing_cache_and_billing_rounding_may_differ':True},
            'saved_failures': [p.name for p in sorted((OUT/'failures').glob('*.json'))],
            'models_requested': sorted({a['requested_model'] for a in api}),
            'models_returned': sorted({a['response_model'] for a in api}),
            'different_model_identifiers_returned':True,
            'provider_internal_weights_or_statistical_independence_verified':False,
            'learning_effect_improvement_claimed': False}

def main():
    verify_frozen()
    protection = verify_protected()
    data = read(OUT / 'core_meanings_5332_candidates.json')
    rows = {r['entry_id']: r for r in formal_rows()}
    rs = data['records']
    ids = {r['stable_id'] for r in rs}
    require(data['record_count']==len(rs) and data['target_count']==5332,'Record/target count inconsistent')
    require(len(rs)==len(ids) and ids <= set(rows), 'Duplicate/extra final IDs')
    require(data['missing_ids'] == sorted(set(rows)-ids), 'Missing IDs misreported')
    require(data['generation_complete']==(ids==set(rows)),'Incomplete generation mislabeled complete')
    for r in rs:
        validate_record(r, rows[r['stable_id']])
    sets = read(OUT / 'INPUT_SETS.json')
    require({r['stable_id'] for r in rs if r.get('generation_provenance')} <= set(sets['C_new4732_in_processing_order']),'New generation outside exact C set')
    hist = set(sets['historical48'])
    require({r['stable_id'] for r in rs if r['historical_risk_retained']} == hist and len(hist)==48, 'Historical48 silently cleared')
    reg = {r['stable_id']: r for r in read(ROOT / 'docs/p6/p6c4/regression_500.json')['records']}
    blind = {r['stable_id']: r for r in read(ROOT / 'docs/p6/p6c4/blind_test_100.json')['records']}
    for r in rs:
        if r['stable_id'] in reg or r['stable_id'] in blind:
            source = (reg | blind)[r['stable_id']]['candidate']
            for k in (*LAYERS, 'original_meanings', 'reserved_original_items', 'dictionary_additions', 'selection_reason'):
                require(r[k] == source[k], 'Reused candidate meaning changed ' + r['headword'])
            require(r['p6c5_lineage']['prior_candidate_sha256'] == canonical(source), 'Reused provenance broken')
    for w in ('management', 'clause'):
        r = next(r for r in rs if r['headword']==w)
        require('quarantine' in r and r['needs_human_review'] and r['review_status']=='confirmed_problem_revision_pending', 'Disputed word released')
    clause = next(r for r in rs if r['headword']=='clause')
    require(any(s['text']=='从句' for s in clause['reserved_original_items']), 'Clause hold lost')
    metric = quality_metrics(data)
    decision = 'A' if data['generation_complete'] and not metric['empty_core_evidence_insufficient_words'] else 'B'
    adjudication = read(OUT/'PARENT_ADJUDICATION.json') if (OUT/'PARENT_ADJUDICATION.json').exists() else {}
    if adjudication.get('systematic_failure_confirmed'):
        causes=collections.Counter(i['normalized_cause'] for i in adjudication['confirmed_findings'] if i['severity']=='Major')
        require(max(causes.values(),default=0)>=2,'Systematic stop lacks repeated confirmed cause')
        decision = 'C'
    elif any(i['severity'] in ('Critical','Major') and not i.get('isolated_resolution_verified') for i in metric['confirmed_new_findings']):
        decision = 'B'
    metric['decision'] = decision
    metric['integrity_contracts_passed'] = True
    metric['full5332_quantity_acceptance_passed'] = len(rs)==5332
    metric['semantic_quality_gate_passed'] = decision=='A'
    metric['can_enter_pre_release_quality_review'] = decision=='A'
    save(OUT/'QUALITY_METRICS.json',metric)
    save(OUT/'VALIDATION_RESULTS.json',{'passed':True,'data_contracts_passed':True,'full_task_acceptance_passed':decision=='A',
         'semantic_quality_gate_passed':decision=='A','record_count':len(rs),'full5332_count_passed':len(rs)==5332,
         'original_senses_complete':True,'stable_IDs_unique':True,'protected_inputs_unchanged':protection,
         'historical48_retained':48,'management_clause_pending':True,'decision':decision,
         'scope':'Data contracts only, not a linguistic accuracy/human signoff guarantee'})
    print(json.dumps({'passed':True,'count':len(rs),'decision':decision,'states':metric['states'],
                      'AI_risks_NOT_errors':metric['AI_risk_flags_by_severity'],'new_confirmed':metric['confirmed_new_problem_severity']}))

if __name__=='__main__':
    main()
