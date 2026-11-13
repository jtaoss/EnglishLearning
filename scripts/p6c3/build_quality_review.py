"""Assemble explicit P6-C.3 adjudications; never generate meanings or call APIs.

The TSV and issue/addition decisions below are authored AI adjudications of the
sealed proposals, not an automatic semantic classifier or human gold standard.
Run the source-only prepare/review/seal steps before this comparison step.
"""
import collections
import copy
import csv
import hashlib
import json
import pathlib
import subprocess

from prepare_review import ROOT, OUT, PRIVATE, load, save, state, preservation_check
from seal_blind_reviews import digest

LAYERS = ('core_meanings', 'extended_meanings', 'other_meanings')
VERSION = 'P6C3_evidence_adjudication_v1'


def canonical(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def partitions(record):
    """A reproducible comparison, NOT a semantic correctness measurement."""
    return sorted((layer, g['part_of_speech'], tuple(sorted(g['source_sense_ids'])))
                  for layer in LAYERS for g in record[layer])


def core_ids(record):
    return sorted({s for g in record['core_meanings'] for s in g['source_sense_ids']})


def display_signature(record):
    return [(layer, g['part_of_speech'], g['display_zh'])
            for layer in LAYERS for g in record[layer]]


# Explicit reviewed findings. Severity refers to the named issue domain.
# A missing dictionary-supplied use is NOT an erroneous original translation.
ISSUES = {
    'import': [{
        'issue_id': 'C3-001', 'severity': 'Major',
        'domain': 'current_candidate_important_use_omission',
        'evidence_supported_problem': True, 'translation_falsehood': False,
        'important_omission': True, 'pos_confusion': False,
        'observation': '候选把原片段进口只分配为名词，又把动词输入限定为数据，未显式保留从国外购入货物的贸易动词用法。不是名词进口或数据导入本身无效。',
        'evidence_ids': ['wn31:v:02351132', 'wn31:v:02237504', 'wn31:n:03569847', 'p6c3:collins:import'],
        'cause': '原文片段一次性分配与逐义词性未知相遇，保住了片段却漏了该片段支持的重要动词用法；名词行为还误用了进口品证据。',
        'remedy': '允许有证据的原片段一对多语义拆解：贸易动词与名词行为分别对应；数据导入独立，进口品另列外部候选。',
        'status': 'revision_proposed_not_adopted', 'human_approved': False,
    }],
    'management': [{
        'issue_id': 'C3-002', 'severity': 'Major',
        'domain': 'original_source_important_use_coverage_gap',
        'evidence_supported_problem': True, 'translation_falsehood': False,
        'important_omission': True, 'pos_confusion': False,
        'observation': '原文及现有分层只有管理活动，没有负责经营管理的人员群体这一独立用法；日常职场理解上活动与人员需要区别。',
        'evidence_ids': ['wn31:n:01135602', 'wn31:n:08397896', 'p6c3:collins:management'],
        'cause': '只审核原文覆盖和压缩，未发现原文三个中文片段都指同一活动而缺少人员义；重要性为明确标注的教学判断，存在性由两种词典证据支持，非频率统计。',
        'remedy': '单列管理层的词典补充候选，保留原核心；不得把来源外内容伪装成原文。',
        'status': 'addition_candidate_pending_adoption_decision', 'human_approved': False,
    }],
    'indicate': [{
        'issue_id': 'C3-003', 'severity': 'Minor',
        'domain': 'per_use_evidence_and_chinese_scope',
        'evidence_supported_problem': True, 'translation_falsehood': False,
        'important_omission': False, 'pos_confusion': False,
        'observation': '近义组指出/指示所引词典项是指向对象和简要陈述，没有给信号表明这一指示读法提供对应证据；显示亦未排除发命令的中文歧义。',
        'evidence_ids': ['wn31:v:00925764', 'wn31:v:00929986', 'wn31:v:00774685', 'wn31:v:00923271', 'p6c3:mw:indicate'],
        'cause': '把宽泛中文近义显示当作逐用法证据完备；不据此断言原中文完全错误或每种英文用法都应独占核心组。',
        'remedy': '按对象/信号/陈述给出限定与逐用法引证，保留原片段并标AI拆解。',
        'status': 'revision_proposed_not_adopted', 'human_approved': False,
    }],
}


# Adjudicated additions from the blind reviewers. Old additions are recognized
# semantically, not by matching Chinese wording. Tuple values are one decision
# per blind addition in its original list order.
ADDITION_DECISIONS = {
    'account': ['already_tracked'], 'acquisition': ['new_candidate'],
    'adapt': ['already_tracked'], 'adopt': ['already_tracked'],
    'agree': ['already_tracked'], 'apparent': ['already_tracked'],
    'appearance': ['already_tracked'], 'appreciate': ['new_candidate'],
    'client': ['new_candidate'], 'competition': ['new_candidate'],
    'conduct': ['new_candidate'],
    'confront': ['already_tracked', 'new_candidate'],
    'critical': ['already_tracked'], 'criticism': ['already_tracked'],
    'cultivate': ['already_tracked'], 'cycle': ['new_candidate'],
    'declare': ['already_tracked'], 'definition': ['already_tracked'],
    'enquiry': ['already_tracked'], 'flush': ['new_candidate'],
    'import': ['new_candidate'], 'indeed': ['new_candidate'],
    'jury': ['already_tracked'], 'legislation': ['already_tracked'],
    'license': ['new_candidate'], 'machinery': ['new_candidate'],
    'maintain': ['already_tracked', 'already_tracked', 'already_tracked'],
    'majority': ['new_candidate'], 'management': ['new_important_source_gap'],
    'nuclear': ['already_covered_in_qualified_original_group', 'new_candidate'],
    'occur': ['already_tracked', 'already_tracked'],
    'operate': ['already_tracked', 'already_tracked'],
    'physical': ['already_tracked', 'already_tracked'],
    'possess': ['new_scope_supplement_not_proven_error'],
    'private': ['new_candidate'],
    'propose': ['already_tracked', 'already_covered_in_original_group_evidence'],
    'reasonable': ['already_covered_in_original_group_evidence'],
    'recession': ['new_candidate'], 'reference': ['new_candidate'],
    'regular': ['new_candidate'], 'separate': ['already_tracked'],
    'suppress': ['new_candidate'],
}


def source_group(original, layer, ordinal, pos, display, ids, refs, usage):
    atoms = {a['source_sense_id']: a for a in original['original_meanings']}
    return {
        'sense_group_id': f"{original['stable_id']}:p6c3:{layer}:{ordinal}",
        'part_of_speech': pos, 'display_zh': display,
        'origin': 'P6C3_AI_semantic_decomposition_or_qualified_rephrasing',
        'source_sense_ids': ids,
        'source_subsenses': [{
            'source_sense_id': s, 'original_gloss': atoms[s]['text'],
            'original_pos': atoms[s]['part_of_speech'],
            'original_pos_evidence': atoms[s]['pos_evidence'],
            'evidence_ids': refs,
        } for s in ids],
        'evidence_ids': refs,
        'evidence_relation': 'specific_use_lexically_supported_not_frequency_gold',
        'pos_assignment': 'AI_recommendation_original_mapping_unchanged',
        'usage_note': usage,
    }


def addition(original, meaning, refs):
    return {
        'candidate_id': original['stable_id'] + ':p6c3:addition:1',
        'part_of_speech': '名词', 'meaning_zh': meaning,
        'source_sense_ids': [], 'evidence_ids': refs,
        'origin': 'external_dictionary_AI_candidate_not_original_fragment',
        'suggested_layer': 'adoption_and_layer_decision_pending',
        'status': 'AI_candidate_not_adopted', 'human_approved': False,
        'auto_promoted_to_core': False,
    }


def revised(original, blind, catalog):
    r = copy.deepcopy(original); w = r['headword']
    if w == 'import':
        r['core_meanings'] = [
            source_group(r, 'core', 1, '动词', '进口；从国外购入（货物等）', ['s001'],
                         ['wn31:v:02351132', 'p6c3:collins:import'], '贸易动词；不要仅学成数据导入。'),
            source_group(r, 'core', 2, '名词', '进口（行为、业务）', ['s001'],
                         ['p6c3:collins:import'], '这是行为名词，不把进口商品的WordNet定义当作行为证据。'),
        ]
        r['extended_meanings'] = [source_group(r, 'extended', 1, '动词',
            '输入；导入（数据）', ['s002'], ['wn31:v:02237504'],
            '这是对宽泛原片段输入的有证据语境收窄；原文逐义对应仍未知。')]
        r['semantic_splits'] = [{
            'source_sense_id': 's001', 'annotation': 'AI语义拆解；不是两个原文片段',
            'uses': [{'part_of_speech': '动词', 'evidence_ids': ['wn31:v:02351132']},
                     {'part_of_speech': '名词', 'evidence_ids': ['p6c3:collins:import']}],
        }]
        r['dictionary_additions'].append(addition(r, '进口商品；进口品',
                                                  ['wn31:n:03569847', 'p6c3:collins:import']))
        r['core_explanation'] = '先辨贸易动词进口与名词进口行为，数据导入后学建议；原文逐义词性仍未知。进口品只作独立补充候选，不自动升核心。'
    elif w == 'indicate':
        r['core_meanings'] = [
            source_group(r, 'core', 1, '动词', '指出；指向（地点或对象）', ['s002'],
                         ['wn31:v:00925764', 'p6c3:mw:indicate'], '对象/方向提示。'),
            source_group(r, 'core', 2, '动词', '指示；表明（某种情况）', ['s003'],
                         ['wn31:v:00774685', 'wn31:v:00923271', 'p6c3:mw:indicate'],
                         '指迹象、信号或信息表明情况，不是向人发命令。'),
        ]
        r['extended_meanings'] = [source_group(r, 'extended', 1, '动词',
            '指出；简要表达（意愿等）', ['s002'],
            ['wn31:v:00929986', 'p6c3:mw:indicate'], '同一中文指出可支持另一陈述用法，显式保留区别。')]
        r['semantic_splits'] = [{
            'source_sense_id': 's002', 'annotation': 'AI语义拆解；原文仍只有一个指出片段',
            'uses': [{'part_of_speech': '动词', 'evidence_ids': ['wn31:v:00925764']},
                     {'part_of_speech': '动词', 'evidence_ids': ['wn31:v:00929986']}],
        }]
        r['core_explanation'] = '分别提示指向对象、信号表明和简要陈述；层级是教学建议，不是义项频率。原指片段继续暂存。'
    elif w == 'management':
        r['dictionary_additions'].append(addition(r, '管理层；负责经营管理的一群人',
                                                  ['wn31:n:08397896', 'p6c3:collins:management']))
        # Core/extended/originals are deliberately left intact. External content
        # requires an adoption decision independent from its lexical existence.
    else:
        raise ValueError(w)
    ids = {e['evidence_id'] for e in r['supporting_sources']}
    refs = {e for k in LAYERS for g in r[k] for e in g['evidence_ids']}
    refs |= {e for a in r['dictionary_additions'] for e in a['evidence_ids']}
    for eid in sorted(refs - ids):
        r['supporting_sources'].append(copy.deepcopy(catalog[eid]))
    r['review_status'] = 'P6C3_AI_revision_candidate_not_adopted'
    r['prior_generation_metadata'] = {k: original[k] for k in ('model_version', 'prompt_version', 'revision_history')}
    r['model_version'] = 'codex-adjudicator/backend-unknown; blind-review-config:gpt-6-astra'
    r['prompt_version'] = 'P6C3/RULES_V4'
    r['human_approved'] = False; r['needs_human_review'] = True
    r['is_AI_candidate'] = True
    r['p6c3_revision'] = {
        'version': VERSION, 'prompt_version': 'RULES_V4',
        'adjudicator_backend_model_id': None,
        'configured_blind_review_model': 'gpt-6-astra',
        'issues': [x['issue_id'] for x in ISSUES[w]],
        'rules_sha256': digest(OUT/'RULES_V4.md'),
        'original_candidate_hash': canonical(original),
        'sealed_blind_record_hash': canonical(blind),
        'source_hash_unchanged': True, 'formal_publication_allowed': False,
    }
    changed = {k: {'before': original.get(k), 'after': r.get(k)}
               for k in sorted(set(r) | set(original)) if r.get(k) != original.get(k)}
    return {'stable_id': r['stable_id'], 'headword': w,
            'issue_ids': [x['issue_id'] for x in ISSUES[w]],
            'base_record_hash': canonical(original), 'candidate_record_hash': canonical(r),
            'changes': changed, 'candidate': r,
            'human_approved': False, 'adopted': False}


def main():
    preservation_check()
    base = load('docs/p6/p6c2/core_meanings_500.json')
    old = {r['stable_id']: r for r in base['records']}
    plan = load('docs/p6/p6c3/selection_plan.json')
    selected = {r['stable_id']: r for r in plan['selected']}
    manifest = load('docs/p6/p6c3/BLIND_REVIEW_MANIFEST.json')
    blind = {}; owners = {}; raw = {}; failures = []
    for name in 'AB':
        path = OUT / 'blind_reviews' / f'reviewer_{name}.json'
        assert digest(path) == manifest['reviewers'][name]['proposal_sha256']
        packet_path = PRIVATE / f'blind_packet_{name}.json'
        assert digest(packet_path) == manifest['reviewers'][name]['input_sha256']
        job = json.loads(path.read_text(encoding='utf-8'))
        for r in job['records']:
            assert r['stable_id'] not in blind
            blind[r['stable_id']] = r; owners[r['stable_id']] = name
        for r in json.loads(packet_path.read_text(encoding='utf-8'))['records']:
            raw[r['stable_id']] = r
        failures += job.get('external_access_failures', job.get('unavailable_sources', []))
    assert set(blind) == set(selected)
    with (ROOT / 'scripts/p6c3/adjudication_notes.tsv').open(encoding='utf-8', newline='') as f:
        notes_list = list(csv.DictReader(f, delimiter='\t'))
    notes = {r['headword']: r for r in notes_list}
    assert len(notes_list) == len(notes) == 90
    assert set(notes) == {r['headword'] for r in blind.values()}
    observations = load('docs/p6/p6c3/publisher_observations.json')
    publisher = {e['evidence_id']: e for e in observations['observations']}
    failures += observations['failed_accesses']
    records = []; revisions = []; source_findings = []; new_additions = []
    all_issues = []; all_prefs = []
    for sid, selection in selected.items():
        a, b = old[sid], blind[sid]; w = a['headword']; n = notes[w]
        wn = {e['evidence_id']: e for e in raw[sid]['unfiltered_wordnet_senses']}
        issues = copy.deepcopy(ISSUES.get(w, []))
        refs = {e for issue in issues for e in issue['evidence_ids']}
        assert all(e in wn or e in publisher and publisher[e]['headword'] == w for e in refs)
        additions = []
        decisions = ADDITION_DECISIONS.get(w, [])
        assert len(decisions) == len(b['dictionary_additions']), w
        for i, (proposal, decision) in enumerate(zip(b['dictionary_additions'], decisions), 1):
            item = {'candidate_id': f'{sid}:p6c3:blind_addition:{i}',
                    'blind_proposal': proposal, 'disposition': decision,
                    'source_sense_ids': [], 'human_approved': False,
                    'auto_promoted_to_core': False,
                    'evidence_existence_is_not_priority_or_adoption_proof': True}
            additions.append(item)
            if decision.startswith('new_'):
                new_additions.append({'stable_id': sid, 'headword': w, **item})
        differences = {
            'layer_POS_source_partition_differs': partitions(a) != partitions(b),
            'core_source_membership_differs': core_ids(a) != core_ids(b),
            'literal_display_or_order_differs': display_signature(a) != display_signature(b),
            'interpretation': '机械差异用于定位，不等于语义错误、真正跨模型身份分歧或真人意见。',
        }
        preferences = []
        if n['disposition'] == 'teaching_preference':
            preferences.append({'type': 'layering_or_display_preference',
                                'reason': n['note'], 'counted_as_error': False,
                                'word_frequency_or_official_PETS_claim': False})
            all_prefs.append(w)
        candidate_findings = []
        for finding in b['source_findings']:
            # A blind reviewer saw the RAW source, so its severity cannot be
            # copied into an error count about a candidate it never saw.
            item = {'blind_source_finding': finding,
                    'automatically_counted_as_current_candidate_error': False,
                    'current_candidate_context': n['note'],
                    'adjudication_links': [i['issue_id'] for i in issues]}
            candidate_findings.append(item)
            source_findings.append({'stable_id': sid, 'headword': w, **item})
        unresolved = bool(a['reserved_original_items'] or a['dictionary_additions'] or additions or issues or preferences)
        records.append({
            'stable_id': sid, 'headword': w, 'source_hash': a['source_hash'],
            'part_of_speech': a['part_of_speech'], 'original_meaning_zh': a['original_meaning_zh'],
            'original_meanings': a['original_meanings'], 'book_category': a['book_category'],
            'selection': selection, 'reviewer': owners[sid],
            'blind_record_hash': canonical(b),
            'previous_candidate': {k: a[k] for k in (*LAYERS, 'reserved_original_items', 'dictionary_additions', 'core_explanation')},
            'independent_proposal': {k: b.get(k, []) for k in (*LAYERS, 'reserved_original_items', 'dictionary_additions', 'semantic_splits', 'ai_semantic_splits')},
            'comparison': differences,
            'adjudication': {'disposition': n['disposition'], 'reason': n['note'],
                            'confirmed_evidence_supported_findings': issues,
                            'teaching_preferences': preferences,
                            'source_findings_not_auto_transferred': candidate_findings,
                            'dictionary_addition_comparison': additions,
                            'unresolved_questions': b['unresolved_questions'],
                            'review_status': 'AI_evidence_adjudicated_not_human_approved',
                            'remaining_items': unresolved},
            'evidence_sources': b['evidence_sources'] + [publisher[e] for e in sorted(refs) if e in publisher],
            'human_approved': False, 'needs_human_review': True,
        })
        all_issues += [{'stable_id': sid, 'headword': w, **i} for i in issues]
        if issues:
            revisions.append(revised(a, b, {**wn, **publisher}))

    # Preserve the broad original risk labels without treating them as errors.
    high = [{'stable_id': r['stable_id'], 'headword': r['headword'], 'cohort': r['cohort'],
             'baseline_risk': r['risk_level'], 'reviewed_in_C3': r['stable_id'] in selected,
             'status': 'original_risk_tag_retained_not_an_error_count'}
            for r in base['records'] if r['risk_level'] == 'high']
    checked = set(blind)
    known_core_adds = [{'stable_id': r['stable_id'], 'headword': r['headword'], 'candidate': c}
                      for r in base['records'] for c in r['dictionary_additions']
                      if c.get('suggested_layer') in ('core', 'core_candidate')]
    focus_reasons = collections.defaultdict(list)
    for r in plan['old_unresolved_high_or_reserved']:
        focus_reasons[r['stable_id']].append('inherited100_unresolved_high_or_reserved')
    for r in base['records']:
        if r['reserved_original_items']:
            focus_reasons[r['stable_id']].append('unresolved_original_fragment')
    for a in known_core_adds:
        if 'old_core_addition_adoption_pending' not in focus_reasons[a['stable_id']]:
            focus_reasons[a['stable_id']].append('old_core_addition_adoption_pending')
    for i in all_issues:
        if i['severity'] in ('Critical', 'Major'):
            focus_reasons[i['stable_id']].append(i['issue_id'])
    focused_pending = [{'stable_id': sid, 'headword': old[sid]['headword'],
                        'reasons': reasons, 'status': 'pending_not_auto_passed_not_an_error_count'}
                       for sid, reasons in sorted(focus_reasons.items(), key=lambda p: old[p[0]]['headword'])]
    audit_records = [r for r in records if r['selection']['role'] == 'stratified_audit']
    target_records = [r for r in records if r['selection']['role'] == 'target_major']
    std_records = [r for r in audit_records if r['selection']['prior_risk'] == 'standard']

    def severity(items):
        counts = collections.Counter(i['severity'] for i in items)
        return {s: counts[s] for s in ('Critical', 'Major', 'Minor', 'Info')}

    summary = {
        'scope_words': 500, 'fresh_blind_reviewed_words': len(records),
        'major_flags_checked': len(target_records), 'stratified_other_words': len(audit_records),
        'sample_new400_nonmajor': 40, 'sample_old100_standard': 8,
        'not_semantically_rechecked_in_C3': len(old) - len(checked),
        'confirmed_findings_by_severity': severity(all_issues),
        'confirmed_findings_by_domain': dict(collections.Counter(i['domain'] for i in all_issues)),
        'current_candidate_major_omissions': sum(i['important_omission'] and i['domain'].startswith('current_') for i in all_issues),
        'newly_confirmed_important_original_source_gaps': sum(i['important_omission'] and i['domain'].startswith('original_') for i in all_issues),
        'new_important_omission_words': len({i['stable_id'] for i in all_issues if i['important_omission']}),
        'confirmed_POS_confusion_words': len({i['stable_id'] for i in all_issues if i['pos_confusion']}),
        'confirmed_false_translation_claims': sum(i['translation_falsehood'] for i in all_issues),
        'preference_only_words': len(all_prefs),
        'fresh_blind_proposal_partition_disagreement_words': sum(r['comparison']['layer_POS_source_partition_differs'] for r in records),
        'fresh_blind_proposal_core_membership_disagreement_words': sum(r['comparison']['core_source_membership_differs'] for r in records),
        'literal_display_or_order_difference_words': sum(r['comparison']['literal_display_or_order_differs'] for r in records),
        'proven_different_backend_model_disagreement_words': None,
        'target_42_confirmed_current_findings': severity([i for r in target_records for i in r['adjudication']['confirmed_evidence_supported_findings']]),
        'target_42_primary_dispositions': dict(collections.Counter(r['adjudication']['disposition'] for r in target_records)),
        'nonmajor_stratified_audit_findings': severity([i for r in audit_records for i in r['adjudication']['confirmed_evidence_supported_findings']]),
        'strict_standard_risk_sample_words': len(std_records),
        'strict_standard_risk_sample_confirmed_findings': severity([i for r in std_records for i in r['adjudication']['confirmed_evidence_supported_findings']]),
        'new_addition_proposals_not_auto_adopted': len(new_additions),
        'new_addition_words': len({a['stable_id'] for a in new_additions}),
        'blind_addition_dispositions': dict(collections.Counter(a['disposition'] for r in records for a in r['adjudication']['dictionary_addition_comparison'])),
        'existing_C2_additions_retained': sum(len(r['dictionary_additions']) for r in base['records']),
        'existing_C2_core_layer_suggestions_pending': len(known_core_adds),
        'existing_C2_core_layer_suggestion_words_pending': len({a['stable_id'] for a in known_core_adds}),
        'inherited100_unresolved_high_or_reserved': len(plan['old_unresolved_high_or_reserved']),
        'original500_broad_high_risk_tags_retained': len(high),
        'focused_pending_priority_words_union': len(focused_pending),
        'unresolved_C3_Critical_or_Major_findings': sum(i['severity'] in ('Critical', 'Major') for i in all_issues),
        'revised_candidate_words': len(revisions), 'human_approved_words': 0,
        'source_fragments_in_reviewed90': sum(len(r['original_meanings']) for r in records),
        'direct_publisher_access_failures': len(failures),
        'actual_tokens': None, 'actual_cost': None,
    }
    conclusion = {
        'decision': 'B', 'expand_remaining_4832_now': False,
        'reason': '先修复原片段与多词性/独立用法的映射，以及原文之外重要用法的覆盖检查，再用现有500中的样本验证。不是否定全部提炼方法，也不把所有历史Major标记当作已证实错误。',
        'evidence_issue_ids': ['C3-001', 'C3-002', 'C3-003'],
        'why_not_A': '补充抽检发现两项尚未采用解决方案的重要用法缺口；逐用法映射与证据门槛未稳定，不能据结构覆盖或压缩率放行。',
        'why_not_C': '未发现词库整体错译、跨词性强行合组或原文丢失；问题有局部规则和候选修订方案，现有材料不足以证明方法整体失效。',
        'release_conditions': [
            '在现有500范围验证原片段一对多映射，确认import贸易动词不再遗漏，indicate逐用法证据与范围提示齐全。',
            '对management管理层及旧有重要补充候选作独立的采用/不采用决定；保持外部候选与原文分离，不自动升级。',
            '按V4对现有500中的其他未标记多词性/宽中文词再次分层抽检；不能把本次有目的分层抽检当随机准确率。',
            '未解决Critical或同类系统性Major不得放行；验证具体修订，不能只调低风险标签。',
        ],
        'does_not_require_initial_learner_to_supply_professional_gold_standard': True,
    }
    review = {
        'schema_version': 'p6c3_quality_review.v1', 'version': VERSION,
        'status': 'isolated_AI_candidate_quality_review_no_publication',
        'input_dataset': {'path': 'docs/p6/p6c2/core_meanings_500.json',
                          'sha256': digest(ROOT/'docs/p6/p6c2/core_meanings_500.json'), 'records': 500},
        'input_generation_metadata': base['generation'],
        'input_project_version_labels': {k: dict(collections.Counter(r[k] for r in base['records']))
                                         for k in ('model_version', 'prompt_version')},
        'independence': manifest,
        'adjudicator': {'backend_model_id': None, 'context': 'parent_comparison_after_blind_proposals_sealed',
                       'not_a_third_blind_model': True, 'prompt_rules': 'RULES_V4'},
        'provenance_hashes': {p: digest(ROOT/p) for p in (
            'docs/p6/p6c3/selection_plan.json', 'docs/p6/p6c3/BLIND_REVIEW_MANIFEST.json',
            'docs/p6/p6c3/publisher_observations.json', 'scripts/p6c3/adjudication_notes.tsv',
            'docs/p6/p6c1/RULES_V3.md', 'docs/p6/p6c3/RULES_V4.md',
            'docs/p6/p6c2/P6C2_500_REPORT.md', 'docs/p6/p6c2/HIGH_RISK_REVIEW.md',
            'docs/p6/p6c2/QUALITY_METRICS.json')},
        'selection': plan, 'summary': summary, 'quality_gate': conclusion,
        'records': records, 'confirmed_findings': all_issues,
        'new_dictionary_candidates': new_additions,
        'existing_core_addition_suggestions_still_pending': known_core_adds,
        'inherited100_pending_queue': plan['old_unresolved_high_or_reserved'],
        'original_broad_high_risk_queue': high,
        'focused_pending_priority_queue': focused_pending,
        'not_rechecked_ids': [r['stable_id'] for r in base['records'] if r['stable_id'] not in checked],
        'external_access_failures': failures,
        'limitations': [
            '已完成两组新上下文source-first盲审；原生成模型精确后端未知，未完成可证明不同后端身份的跨模型验证。',
            '两个审者各45词且无重叠，不能计算同词双审者一致率；差异数是新盲审提案与旧候选的差异。',
            '中文准确性和重要性结论仍是带词典证据的AI裁定，非人工金标准或学习效果实验。',
            '审查90词而不是500词重新盲审；其余410词不自动通过。',
            '所有旧词典补充、未解高风险与人工未签审状态保留；没有来源证明具体义项考试频率。',
            'API用量/费用和后端快照未暴露，以null记录，不能将检查点数当API调用数。',
        ],
        'safety': {'formal_5332_changed': False, 'C2_500_overwritten': False,
                   'personal_SQLite_opened': False, 'Notion_accessed': False,
                   'UI_changed_by_this_task': False, 'remaining4832_processed': False,
                   'evidence': 'preservation.json before/after hashes; validation script'},
    }
    revision_file = {'schema_version': 'p6c3_revised_candidates.v1',
                     'status': 'AI_candidates_only_not_adopted_not_published',
                     'input_sha256': review['input_dataset']['sha256'],
                     'record_count': len(revisions), 'records': revisions,
                     'other_blind_new_candidates': 'independent_quality_review.json:new_dictionary_candidates',
                     'human_approved': False}
    save(OUT/'independent_quality_review.json', review)
    save(OUT/'REVISED_CANDIDATES.json', revision_file)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
