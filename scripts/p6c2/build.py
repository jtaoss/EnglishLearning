"""Assemble 100 inherited + 400 reviewed AI candidates. Offline, no SQL/network.

Successful generation checkpoints are read, never regenerated. Existing records
are copied without edits. All proposed changes remain isolated AI candidates.
"""
import collections
import copy
import csv
import hashlib
import json
import pathlib

from prepare import ROOT, OUT, load, freeze
from revisions import DISPLAY, REFERENCE_FIX

LAYERS = ['core_meanings','extended_meanings','other_meanings']


def canonical(x):
    return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()


def save(path,obj):
    path.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def read_reviews():
    result={}
    for batch in range(1,9):
        for line in (ROOT / f'scripts/p6c2/review_{batch:02d}.tsv').read_text(encoding='utf-8').splitlines():
            if not line or line.startswith('#'):continue
            word,severity,observation=line.split('|')
            assert word not in result and severity in ['Critical','Major','Minor','Info']
            result[word]={'severity':severity,'observation':observation,'batch':batch}
    assert len(result)==400
    return result


def web_catalog():
    result={}
    for line in (ROOT/'scripts/p6c2/web_observations.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):continue
        key,word,publisher,url,access,observation=line.split('|')
        result['web:'+key]={'evidence_id':'web:'+key,'selected_headwords':[word],
            'source_headword':'percent' if key=='percent' else word,
            'relation':'contrast_only_not_direct_attestation' if key=='percent' else 'lexical_or_context_support',
            'publisher':publisher,'url':url,'access':access,'observation_zh':observation,
            'date_asia_shanghai':'2026-11-13','limitations':'Original paraphrase of inspected entry/index text; not corpus frequency or official PETS sense focus. Indexed text may be stale; 403 was not bypassed.',
            'copyright_handling':'short_original_paraphrase_and_URL_no_full_dictionary_page_or_example_copy'}
    return result


def set_evidence(group, refs):
    group['evidence_ids']=refs
    for item in group['source_subsenses']:
        item['evidence_ids']=refs
    group['evidence_relation']='AI_selected_context_compatibility_not_human_gold_or_frequency'


def subgroup(r,layer,ids,pos,display,refs,web=None):
    atoms={a['source_sense_id']:a for a in r['original_meanings']}
    return {'sense_group_id':r['stable_id']+':review:'+layer+':'+','.join(ids),
        'part_of_speech':pos,'display_zh':display,'glosses':[atoms[i]['text'] for i in ids],
        'origin':'AI_review_rephrasing_not_original_wording','source_sense_ids':ids,
        'source_subsenses':[{'source_sense_id':i,'original_gloss':atoms[i]['text'],
            'original_pos':atoms[i]['part_of_speech'],'original_pos_evidence':atoms[i]['pos_evidence'],
            'evidence_ids':refs} for i in ids], 'evidence_ids':refs,
        'evidence_relation':'AI_selected_context_compatibility_not_human_gold_or_frequency',
        'grouping_relation':'single_original_fragment' if len(ids)==1 else 'near_synonym_display_candidate',
        'pos_assignment':'AI_dictionary_supported_recommendation_original_mapping_unknown' if any(atoms[i]['part_of_speech'] is None for i in ids) else 'source_explicit_or_single_POS',
        'usage_note':r['selection_reason']}


def additions_for(word,refs,web):
    result=[]
    for line in (ROOT/'scripts/p6c2/additions.tsv').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'):continue
        w,pos,meaning,evidence,layer,reason=line.split('|')
        if w!=word:continue
        if evidence.startswith('wn:'):
            entries=[refs[int(i)-1] for i in evidence[3:].split(',')]
            ids=[e['evidence_id'] for e in entries]
        else:
            ids=[evidence]; assert evidence in web and word in web[evidence]['selected_headwords']
        result.append({'candidate_id':word+':addition:'+str(len(result)+1), 'part_of_speech':pos,
            'meaning_zh':meaning,'evidence_ids':ids,'source_sense_ids':[],
            'suggested_layer':layer,'selection_reason':reason,'origin':'dictionary_supported_AI_addition_candidate',
            'status':'AI_candidate_not_adopted','human_approved':False,'auto_promoted_to_core':False})
    return result


def build():
    freeze()
    old=load('docs/p6/p6c/core_meanings_pilot.json')['records']
    old_reviews={r['stable_id']:r for r in load('docs/p6/p6c1/independent_review.json')['records']}
    old_evidence=load('docs/p6/p6c1/evidence_catalog.json')['evidence_catalog']
    refs=load('docs/p6/p6c2/wordnet_400.json')['headwords']
    web=web_catalog()
    judgments=read_reviews()
    records=[]; diffs=[]
    for origin in old:
        review=old_reviews[origin['stable_id']]
        evidence_ids={e for a in review['source_alignment'] for e in a['evidence_ids']}
        evidence_ids.update(e for a in review['dictionary_addition_candidates'] for e in a['evidence_ids'])
        evidence_ids.update(review['supplemental_evidence_ids'])
        record={'stable_id':origin['stable_id'],'headword':origin['headword'],'part_of_speech':origin['part_of_speech'],
            'original_meaning_zh':origin['original_meaning_zh'],'original_meanings':copy.deepcopy(origin['source_senses']),
            'source_fields':copy.deepcopy(origin['source_fields']),'source_hash':origin['source_hash'],
            **copy.deepcopy(review['proposed_layers']), 'reserved_original_items':copy.deepcopy(review['reserved_original_items']),
            'dictionary_additions':copy.deepcopy(review['dictionary_addition_candidates']),
            'core_explanation':review['first_memory_rationale'],'selection_reason':review['first_memory_rationale'],
            'supporting_sources':[{'evidence_id':e,**copy.deepcopy(old_evidence[e])} for e in sorted(evidence_ids)],
            'risk_level':origin['risk_level'],'risk_origin':'inherited_original_100_no_new_risk_reclassification',
            'review_status':'AI_reviewed_inherited_C1_not_human_approved', 'needs_human_review':True,'human_approved':False,
            'model_version':review['review_version'],'prompt_version':'p6c-prompt-2 + p6c1-RULES_V3',
            'book_category':origin['book_category'],'cohort':'inherited_100','publication_status':'AI_candidate_not_formal_content',
            'official_exam_focus':False,'prior_generation':copy.deepcopy(origin),'prior_independent_review':copy.deepcopy(review),
            'revision_history':{'original_decision_hash':origin['decision_hash'],'review_hash':review['review_hash'],
                                'inherited_original_record_hash':canonical(origin),'inherited_review_record_hash':canonical(review)},
            'high_risk_review':{'status':'inherited_C1_not_reexecuted','independence':'same prior AI session, non-blind; not human or separate-model approval'}}
        records.append(record)
    generation=[]
    for batch in range(1,9):
        cp=load(f'docs/p6/p6c2/checkpoints/batch_{batch:02d}.json')
        assert cp['failed']==0 and cp['record_count']==50
        generation.extend(cp['records'])
    assert len(generation)==400 and {r['headword'] for r in generation}==set(judgments)
    for initial in generation:
        r=copy.deepcopy(initial); word=r['headword']; opinion=judgments[word]
        relevant_web=[e for e in web.values() if word in e['selected_headwords']]
        # Resolve gaps only with explicit, actually inspected publisher entries.
        for layer in LAYERS:
            for group in r[layer]:
                if not group['evidence_ids']:
                    ids={REFERENCE_FIX[(word,s)] for s in group['source_sense_ids']}
                    set_evidence(group,['web:'+i for i in sorted(ids)])
                target=DISPLAY.get((word,tuple(group['source_sense_ids'])))
                if target:
                    group['display_zh']=target; group['origin']='AI_review_rephrasing_not_original_wording'
        if word=='agent':
            g=r['core_meanings'][0]
            g['grouping_relation']='distinct_roles_explicitly_preserved'
            g['display_zh']='代理人（含经纪等具体角色）'
            for s in g['source_subsenses']:
                s['evidence_ids']=[refs[word][3 if s['source_sense_id']=='s001' else 2]['evidence_id']]
        if word=='adapt':
            set_evidence(r['core_meanings'][0],[refs[word][1]['evidence_id']])
        if word=='stewardess':
            r['core_meanings']=[subgroup(r,'core',['s001'],'名词','女乘务员（旧式、性别化称谓）',['web:stewardess'])]
            r['extended_meanings']=[subgroup(r,'extended',['s002'],'名词','空中小姐（航空语境的旧称）',['web:stewardess'])]
            r['core_explanation']='一般女乘务员可涉及船、列车等，航空旧称另留；不把全部用法限为飞机。'
        if word=='benefit':
            r['core_meanings']=[r['core_meanings'][0],subgroup(r,'core',['s004'],'动词','得益',[refs[word][3]['evidence_id']])]
            r['extended_meanings'].append(subgroup(r,'extended',['s003'],'动词','使受益',[refs[word][4]['evidence_id']]))
            r['core_explanation']='益处是名词，得益是主体获得好处；使受益是令他人获益，方向分开。'
        if word=='critical':
            set_evidence(next(g for g in r['core_meanings'] if g['source_sense_ids']==['s001']),[refs[word][0]['evidence_id']])
            r['core_explanation']='关键与批评指出不足分开；审慎评价是另列候选，危急仍保留。'
        if word=='property':
            r['core_meanings']=[subgroup(r,'core',['s002','s003'],'名词','财产／所有物',[refs[word][4]['evidence_id']])]
            r['extended_meanings']=[g for g in r['extended_meanings'] if g['source_sense_ids']==['s001']]
        if word=='core':
            g=next(g for g in r['extended_meanings'] if g['source_sense_ids']==['s002'])
            set_evidence(g,['web:core'])
        if word=='primary':
            for g in r['extended_meanings']:set_evidence(g,['web:primary'])
        r['dictionary_additions']=additions_for(word,refs[word],web)
        selected_ids={e for layer in LAYERS for g in r[layer] for e in g['evidence_ids']}
        selected_ids.update(e for g in r['dictionary_additions'] for e in g['evidence_ids'])
        r['supporting_sources']=[{'evidence_id':e['evidence_id'],**e,'selected_headwords':[word],
                                 'source':'https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz',
                                 'license':'assets/vocabulary/WORDNET_3_1_LICENSE.txt'} for e in refs[word] if e['evidence_id'] in selected_ids]
        r['supporting_sources'].extend(copy.deepcopy(relevant_web))
        total_groups=sum(len(r[k]) for k in LAYERS)
        high=initial['risk_level']=='high' or total_groups>1 or bool(r['dictionary_additions']) or opinion['severity']=='Major'
        r['risk_level']='high' if high else 'standard'
        r['initial_risk_flags']=list(initial['risk_flags'])
        r['risk_flags']=[flag for flag in initial['risk_flags'] if flag!='reference_gap']
        r['reference_gap_resolution']='all_initial_empty_reference_slots_filled_by_recorded_publisher_observations' if 'reference_gap' in initial['risk_flags'] else 'not_applicable'
        r['risk_origin']='multiple semantic/POS groups, source ambiguity, evidence gap/history, or proposed additions; not accuracy probability'
        r['review_status']='AI_reviewed_with_open_source_questions' if r['reserved_original_items'] else 'AI_reviewed_candidate_not_human_approved'
        r['ai_semantic_review']={'status':'completed','actor':'Codex current AI session','backend_model_id':None,
            'severity':opinion['severity'],'observation':opinion['observation'],
            'method':'explicit per-word post-structure source-first judgment, saved in review_01..08.tsv; no independent model claim'}
        r['high_risk_review']={'status':'source_reinspection_completed_with_stated_limits' if high else 'not_required_by_risk_rule',
            'independence':'separate source-first review pass in same AI session, non-blind; NOT a second independent model or human',
            'independent_model_review':'not_run_no_separate_model_call_capability_used',
            'observation':opinion['observation'],'evidence_ids':sorted(selected_ids | {e['evidence_id'] for e in relevant_web}),
            'source_limits':'Original multi-POS mapping may remain unknown; dictionary compatibility is not a translation gold standard, corpus ranking or teacher approval.'}
        before={k:initial[k] for k in LAYERS+['core_explanation']}
        after={k:r[k] for k in LAYERS+['core_explanation']}
        changed=before!=after
        r['revision_history']={'initial_checkpoint':f"checkpoints/batch_{opinion['batch']:02d}.json",'initial_record_hash':canonical(initial),
            'source_first_review_observation':opinion['observation'],'layer_or_display_or_reference_changed':changed}
        if changed:
            diffs.append({'stable_id':r['stable_id'],'headword':word,'severity':opinion['severity'],
                          'reason':opinion['observation'],'before':before,'after':after})
        # No generated label can be mistaken for publication or human approval.
        assert r['human_approved'] is False and r['needs_human_review'] is True
        records.append(r)
    assert len(records)==len({r['stable_id'] for r in records})==500
    payload={'schema_version':'p6c2-1','publication_status':'isolated_AI_candidates_not_formal_content',
        'record_count':500,'inherited_count':100,'new_count':400,'human_approved_count':0,
        'source':'docs/p5a/public/formal_learning_vocabulary.csv',
        'source_file_sha256':hashlib.sha256((ROOT/'docs/p5a/public/formal_learning_vocabulary.csv').read_bytes()).hexdigest(),
        'original_meanings_definition':'verbatim fragments of the formal CSV meaning_zh; NOT a claim of verbatim Chinese from the textbook PDF, nor one fragment per true English sense',
        'source_span_unit':'Unicode code points [start,end), not UTF-16 code units',
        'model_version':'codex-session/p6c2-semantic-v4','prompt_version':'p6c2-rules-v4',
        'generation':{'actor':'Codex current AI session','backend_model_id':None,'backend_snapshot':None,
            'external_model_api_calls':0,'actual_api_tokens':None,'session_cost':None,
            'cost_limitation':'No external model API requests. Actual Codex session token usage/billing not exposed; not claimed zero cost.',
            'independent_model_review':'not_run; evidence-driven same-session non-blind review is distinguished from an independent model'},
        'protection_baseline':'preservation.json','old_100_strategy':'deep-copy prior generation and independent review; adopt proposed C1 layers without rewriting prior records',
        'prompt_sha256':hashlib.sha256((OUT/'PROMPT_V4.md').read_bytes()).hexdigest(),
        'rules_v3_sha256':hashlib.sha256((ROOT/'docs/p6/p6c1/RULES_V3.md').read_bytes()).hexdigest(),
        'records':records}
    save(OUT/'core_meanings_500.json',payload)
    save(OUT/'review_revisions.json',diffs)
    save(OUT/'external_evidence.json',{'records':list(web.values()),
        'failed_access':{'HTTP_403':{'percentage':1,'faculty':2,'profitable':2,'privilege':1,'account-for':1},
                         'no_matching_text_on_first_find':['Collins privilege honour/honor']},
        'retry_policy':'No automatic retries; at most two unsuccessful direct opens for the same Cambridge entry; use stated indexed-text limits or a different publisher.',
        'model_usage':payload['generation']})
    print(json.dumps({'records':500,'inherited':100,'new':400,'new_fragments':sum(len(r['original_meanings']) for r in records[100:]),
        'new_high_risk':sum(r['risk_level']=='high' for r in records[100:]),'revised_new':len(diffs),
        'new_additions':sum(len(r['dictionary_additions']) for r in records[100:])},ensure_ascii=False))
    return payload


if __name__=='__main__':build()
