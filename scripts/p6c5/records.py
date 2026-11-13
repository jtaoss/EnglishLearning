"""Expand actual model decisions, enforcing original/source/identity contracts."""
from common import *
import copy

def validate_decision(d, item):
    require(d['id'] == item['id'], 'Wrong stable ID')
    senses = {s['source_sense_id']: s for s in item['senses']}
    refs = {r['id']: r for r in item['evidence']}
    source_refs = {f"source:{item['id']}:{s}" for s in senses}
    allowed = set(item['pos'].split('；'))
    mapped = []
    for layer in COMPACT_LAYERS:
        require(isinstance(d[layer], list), 'Missing layer ' + layer)
        for g in d[layer]:
            require(isinstance(g, list) and len(g) == 5, 'Bad group transport schema')
            z, p, sids, eids, note = g
            require(bool(z) and bool(note) and p in allowed, 'Empty/POS-mismatched group')
            require(bool(sids) and len(set(sids)) == len(sids) and set(sids) <= set(senses), 'Invalid group source IDs')
            require(bool(eids) and set(eids) <= set(refs) | source_refs, 'Unprovided evidence ID')
            for eid in eids:
                if eid in refs:
                    require(refs[eid]['pos'] in POS.get(p, set()), 'Dictionary POS mismatch ' + p + ' ' + eid)
                else:
                    require(eid.rsplit(':', 1)[1] in sids, 'Source citation outside group mapping')
            mapped.extend(sids)
    for sid, reason in d['hold']:
        require(sid in senses and bool(reason), 'Invalid held original')
        mapped.append(sid)
    require(set(mapped) == set(senses), 'Original mapping incomplete')
    repeated = {s for s, n in collections.Counter(mapped).items() if n > 1}
    require(repeated <= set(d['splits']) and all(d['splits'][s] for s in repeated), 'Unannotated one-to-many source mapping')
    require(set(d['splits']) <= set(senses), 'Invented semantic split')
    for z, p, eids, reason in d['additions']:
        require(z and p and reason and eids and set(eids) <= set(refs), 'Unsupported external addition')
        require(all(refs[e]['pos'] in POS.get(p, set()) for e in eids), 'Addition POS mismatch')
    require(bool(d['reason']), 'Missing per-word decision rationale')
    for severity, code, reason in d['flags']:
        require(severity in ('Critical', 'Major', 'Minor', 'Info') and code and reason, 'Bad risk flag')
    return True

def expand(d, row, evidence, api, batch):
    item = packet(row, evidence)
    validate_decision(d, item)
    sid = row['entry_id']
    original = item['senses']
    byid = {s['source_sense_id']: s for s in original}
    catalog = {e['evidence_id']: copy.deepcopy(e) for e in evidence}
    for a in original:
        eid = f"source:{sid}:{a['source_sense_id']}"
        catalog[eid] = {'evidence_id': eid, 'source_type': 'formal_Chinese_traceability_only',
                        'stable_id': sid, 'headword': row['word'], 'source_sense_id': a['source_sense_id'],
                        'source': FORMAL.relative_to(ROOT).as_posix(), 'source_hash': canonical(row),
                        'independent_lexical_verification': False}
    layers = {}
    uses = []
    used_refs = set()
    for key, transport in zip(LAYERS, COMPACT_LAYERS):
        layers[key] = []
        for i, (z, pos, sids, eids, note) in enumerate(d[transport], 1):
            g = {'sense_group_id': f'{sid}:p6c5:{key}:{i}', 'display_zh': z,
                 'part_of_speech': pos, 'source_sense_ids': sids, 'evidence_ids': eids,
                 'usage_note': note, 'origin': 'AI_V4_1_source_derived_candidate',
                 'source_subsenses': [{'source_sense_id': s, 'original_gloss': byid[s]['text'],
                                     'original_pos': byid[s]['part_of_speech'],
                                     'original_pos_evidence': byid[s]['pos_evidence'],
                                     'evidence_ids': eids} for s in sids]}
            layers[key].append(g)
            uses.append({'use_id': g['sense_group_id'], 'source_sense_ids': sids,
                         'part_of_speech': pos, 'meaning_zh': z, 'scope_and_roles': note,
                         'evidence_ids': eids, 'location': key,
                         'evidence_status': 'lexical_support_not_frequency' if any(e.startswith('wn31:') for e in eids) else 'source_traceability_only_evidence_pending'})
            used_refs.update(eids)
    reserved = [{**byid[s], 'reason': reason, 'status': 'original_preserved_evidence_pending'} for s, reason in d['hold']]
    additions = []
    for i, (z, pos, eids, reason) in enumerate(d['additions'], 1):
        additions.append({'candidate_id': f'{sid}:p6c5:addition:{i}', 'meaning_zh': z,
                          'part_of_speech': pos, 'source_sense_ids': [], 'evidence_ids': eids,
                          'reason': reason, 'status': 'AI_candidate_not_adopted',
                          'human_approved': False, 'auto_promoted_to_core': False,
                          'priority_basis': 'AI_teaching_suggestion_not_measured_frequency'})
        used_refs.update(eids)
    flags = [{'severity': sev, 'code': code, 'reason': reason, 'kind': 'AI_risk_not_confirmed_error'}
             for sev, code, reason in d['flags']]
    def addflag(code, reason, severity='Info'):
        if not any(f['code'] == code for f in flags):
            flags.append({'severity': severity, 'code': code, 'reason': reason, 'kind': 'automatic_risk_not_confirmed_error'})
    if len(row['part_of_speech'].split('；')) > 1:
        addflag('multiple_source_POS', '多词性需逐用途检查，不能按原片段位置分配。')
    if any(a['part_of_speech'] is None for a in original):
        addflag('original_POS_correspondence_unknown', '源释义与各词性对应未知；推荐标签不是原文已确认标签。')
    if any(e.startswith('source:') for e in used_refs):
        addflag('lexical_evidence_insufficient', '部分用法只有原文追溯，未获独立词典确认。')
    if reserved:
        addflag('source_fragment_held', '原文片段保留暂存，不断言其错误或罕见。')
    if len(layers['core_meanings']) > 3:
        addflag('more_than_three_core_groups', '独立用途需复核；不为压缩指标删义。')
    represented = {g['part_of_speech'] for layer in LAYERS for g in layers[layer]}
    coverage = {p: 'source_derived_use_represented' if p in represented else 'unrepresented_evidence_pending'
                for p in row['part_of_speech'].split('；')}
    if any('pending' in x for x in coverage.values()):
        addflag('source_POS_coverage_pending', '至少一个源词性没有有证据的原文用法；未自动生成或采用外部义。', 'Major')
    if additions:
        addflag('dictionary_additions_pending', '外部独立用途只列候选，未升级为核心。')
    failed = not bool(layers['core_meanings'])
    state = 'processing_failed_or_evidence_insufficient' if failed else 'AI_processed_needs_human_review' if flags or additions or reserved else 'AI_processed_no_obvious_risk'
    rank = {'Info': 0, 'Minor': 1, 'Major': 2, 'Critical': 3}
    max_severity = max((f['severity'] for f in flags), key=rank.get, default='Info')
    return {'stable_id': sid, 'headword': row['word'], 'part_of_speech': row['part_of_speech'],
            'source_fields': row, 'source_hash': canonical(row), 'original_meaning_zh': row['meaning_zh'],
            'original_meanings': original, **layers, 'reserved_original_items': reserved,
            'dictionary_additions': additions, 'selection_reason': d['reason'], 'core_explanation': d['reason'],
            'semantic_splits': [{'source_sense_id': s, 'reason': why, 'annotation': 'AI语义/词性拆解，不新增原文片段'} for s, why in d['splits'].items()],
            'use_coverage_matrix': uses, 'source_POS_coverage': coverage,
            'supporting_sources': [catalog[e] for e in sorted(used_refs)], 'book_category': row['book_category'],
            'risk_flags': flags, 'risk_level': 'high' if max_severity in ('Critical', 'Major') else 'review' if flags else 'standard',
            'review_status': state, 'needs_human_review': bool(flags or additions or reserved or failed),
            'human_approved': False, 'publication_status': 'isolated_not_published',
            'model_version': api['response_model'], 'provider_snapshot_version': {'deepseek-v4-pro':'DeepSeek-V4-Pro-0813','deepseek-flash':'DeepSeek-V4.1-Flash-1017'}.get(api['response_model']) + ' (official documentation; API exact snapshot not returned)',
            'prompt_version': 'P6C5-generation-v3', 'rules_hash': sha(RULES),
            'historical_risk_retained': False, 'confirmed_problems': [], 'review_preferences': [],
            'generation_provenance': {'cohort': 'C_new4732', 'batch': batch, 'api_tag': api['tag'],
                'response_id': api['response_id'], 'request_hash': api['request_hash'],
                'decision_hash': canonical(d), 'response_file_sha256': sha(OUT / 'api' / (api['tag'] + '.json'))},
            'official_exam_sense_frequency': None}

def parse_response(api, items):
    require(api['finish_reason'] == 'stop', 'Truncated API response')
    obj = json.loads(api['content'])
    decisions = obj['records']
    require(len(decisions) == len(items), 'API omitted/added records')
    require([d['id'] for d in decisions] == [i['id'] for i in items], 'API ID order, duplicate or membership mismatch')
    for d, item in zip(decisions, items):
        validate_decision(d, item)
    return decisions
