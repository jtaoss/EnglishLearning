"""Public-data contract validator and source conservation checks. No SQL/network."""
import collections
import csv
import hashlib
import json
import pathlib

from prepare import ROOT, OUT, load, freeze, source_atoms, canonical_hash

LAYERS=['core_meanings','extended_meanings','other_meanings']
POS={'名词':{'n'},'动词':{'v'},'形容词':{'a','s'},'副词':{'r'},'数词':{'a','s','n'}}


def require(ok,message):
    if not ok:raise ValueError(message)


def inputs():
    with (ROOT/'docs/p5a/public/formal_learning_vocabulary.csv').open(encoding='utf-8-sig',newline='') as f:
        formal={r['entry_id']:r for r in csv.DictReader(f)}
    old={r['stable_id']:r for r in load('docs/p6/p6c/core_meanings_pilot.json')['records']}
    reviews={r['stable_id']:r for r in load('docs/p6/p6c1/independent_review.json')['records']}
    selected=load('docs/p6/p6c2/selection_400.json')
    return formal,old,reviews,selected


def validate(payload,formal,old,reviews,selected):
    records=payload['records']
    require(len(records)==payload['record_count']==500,'Exactly 500 records required')
    ids=[r['stable_id'] for r in records]
    require(len(set(ids))==500,'Duplicate stable ID')
    old_ids=set(old)
    selected_ids={r['source_fields']['entry_id'] for r in selected['new_records']}
    require(set(ids[:100])==old_ids and len(old_ids)==100,'Old 100 missing or displaced')
    require(set(ids[100:])==selected_ids and len(selected_ids)==400 and not old_ids&selected_ids,'New selection mismatch')
    require(payload['human_approved_count']==0,'No actual human signatures supplied')
    counts=collections.Counter(); seen_headers=set()
    for r in records:
        uid=r['stable_id'];word=r['headword']
        require(uid in formal,'ID not formal')
        source=formal[uid]
        require(word==source['word'] and word not in seen_headers,'Headword mismatch/duplicate')
        seen_headers.add(word)
        require(r['part_of_speech']==source['part_of_speech'],'Original POS changed')
        require(r['source_fields']==source and r['source_hash']==canonical_hash(source),'Source snapshot/hash drift')
        require(r['original_meaning_zh']==source['meaning_zh'],'Original text changed')
        require(r['original_meanings']==source_atoms(source),'Original fragments changed')
        require(r['needs_human_review'] is True and r['human_approved'] is False,'Fake human approval')
        require(r['publication_status']=='AI_candidate_not_formal_content' and r['official_exam_focus'] is False,'Publication or official exam claim')
        for field in ['core_explanation','selection_reason','risk_level','review_status','model_version','prompt_version','source_hash']:
            require(isinstance(r[field],str) and bool(r[field]),'Missing string '+field)
        require(r['core_meanings'],'Empty core')
        evidence={e['evidence_id']:e for e in r['supporting_sources']}
        require(len(evidence)==len(r['supporting_sources']),'Duplicate evidence IDs')
        used=[]; signatures=set()
        atoms={a['source_sense_id']:a for a in r['original_meanings']}
        for a in atoms.values():
            require(source['meaning_zh'][a['start']:a['end']]==a['text'],'Bad Unicode source span')
        for layer in LAYERS:
            require(isinstance(r[layer],list),'Expected group list')
            for g in r[layer]:
                require(g['display_zh'].strip() and g['part_of_speech'].strip(),'Empty group')
                require(g['source_sense_ids'] and g['source_subsenses'],'Unattributed core or erased subsenses')
                require(set(g['source_sense_ids'])=={s['source_sense_id'] for s in g['source_subsenses']},'Missing subsense mapping')
                signature=(g['part_of_speech'],g['display_zh'],tuple(g['source_sense_ids']))
                require(signature not in signatures,'Duplicate group')
                signatures.add(signature)
                used.extend(g['source_sense_ids'])
                require(g['evidence_ids'],'No source for teaching group')
                for e in g['evidence_ids']:
                    require(e in evidence and word in evidence[e]['selected_headwords'],'Invented or unrelated evidence')
                    if uid not in old_ids and e.startswith('wn31:'):
                        require(evidence[e]['pos'] in POS.get(g['part_of_speech'],set()),'Reference POS mismatch')
                for s in g['source_subsenses']:
                    require(s['source_sense_id'] in atoms and s['original_gloss']==atoms[s['source_sense_id']]['text'],'Original subsense text lost')
                    if uid not in old_ids:
                        original_pos=atoms[s['source_sense_id']]['part_of_speech']
                        require(original_pos is None or original_pos==g['part_of_speech'],'Cross-POS merge')
                        if original_pos is None:
                            require(g['pos_assignment']=='AI_dictionary_supported_recommendation_original_mapping_unknown','Unresolved original POS concealed')
        for item in r['reserved_original_items']:
            uid_s=item['source_sense_id'];used.append(uid_s)
            require(uid_s in atoms and item.get('original_gloss',item.get('text'))==atoms[uid_s]['text'],'Reserved original lost')
        require(collections.Counter(used)==collections.Counter(atoms.keys()),'Omitted, duplicated or invented source fragment: '+word)
        for add in r['dictionary_additions']:
            require(add['source_sense_ids']==[] and add['origin']!='formal_gloss','Addition pretends to be original')
            require(add.get('auto_promoted_to_core',False) is False and add.get('human_approved',False) is False,'Addition promoted without approval')
            require(add['meaning_zh'] and add['part_of_speech'] and add['evidence_ids'],'Empty/unsupported addition')
            for e in add['evidence_ids']:
                require(e in evidence and word in evidence[e]['selected_headwords'],'Bad addition evidence')
        if uid in old_ids:
            require(r['prior_generation']==old[uid] and r['prior_independent_review']==reviews[uid],'Prior 100 review rewritten')
            require(all(r[k]==reviews[uid]['proposed_layers'][k] for k in LAYERS),'Prior reviewed layers changed')
            require(r['dictionary_additions']==reviews[uid]['dictionary_addition_candidates'],'Prior additions changed')
            require(r['reserved_original_items']==reviews[uid]['reserved_original_items'],'Prior reserve changed')
        else:
            require(r['ai_semantic_review']['status']=='completed','New word semantic review not completed')
            require(r['ai_semantic_review']['severity'] in ['Critical','Major','Minor','Info'],'Missing severity')
            if r['risk_level']=='high':
                require(r['high_risk_review']['status']=='source_reinspection_completed_with_stated_limits','High-risk source review incomplete')
            counts['new_fragments']+=len(atoms)
        counts['original_fragments']+=len(atoms)
        counts['core_groups']+=len(r['core_meanings'])
        counts['reserved_fragments']+=len(r['reserved_original_items'])
        counts['dictionary_additions']+=len(r['dictionary_additions'])
    return {'status':'PASS','records':500,'unique_ids':500,'inherited_100_exactly_preserved':True,
            'new_400_exact_selection':True,**dict(counts),'core_mean_A':counts['original_fragments']/500,
            'core_mean_B':counts['core_groups']/500,'human_approved':0,
            'scope':'structural provenance and preservation contract, not a teacher-rated semantic accuracy score'}


if __name__=='__main__':
    freeze()
    result=validate(load('docs/p6/p6c2/core_meanings_500.json'),*inputs())
    (OUT/'validation_results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))
