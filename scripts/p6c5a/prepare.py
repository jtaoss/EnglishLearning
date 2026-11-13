"""Freeze exact700, four independent revisions, evidence, holdouts and gate."""
import re
from common import *

EXCLUDED={'ritual','extend','scholar','contact','pursue','import','support','management','clause','escape','indicate','render','restore','attach','spouse','persuade'}

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    if (OUT/'RUN_MANIFEST.json').exists():
        verify_frozen();verify_protection();print('Frozen700 protocol already verified.');return
    if (OUT/'PRESERVATION.json').exists():verify_protection()
    else:save(OUT/'PRESERVATION.json',{'utc':now(),'files':protected(),
      'git_branch':subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip(),
      'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
      'git_status_before':subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True).splitlines()})
    rows=baseline();require(len(rows)==len({r['stable_id'] for r in rows})==700,'Not exact700')
    with FORMAL.open(encoding='utf-8-sig',newline='') as f:formal={r['entry_id']:r for r in csv.DictReader(f)}
    require(len(formal)==5332,'Formal set changed')
    for r in rows:require(r['source_fields']==formal[r['stable_id']] and r['source_hash']==canonical(r['source_fields']),'Original snapshot mismatch')
    require(sum(len(r['original_meanings']) for r in rows)==1702,'Fragment baseline changed')
    ids={r['stable_id'] for r in rows}
    s=read(ROOT/'docs/p6/p6c5/INPUT_SETS.json')
    oldids=set(s['A_original500'])|set(s['B_blind100'])
    newids=ids-oldids
    require(len(oldids)==600 and len(newids)==100,'600/100 membership drift')
    proposals={e['stable_id']:e for e in read(ROOT/'docs/p6/p6c5/REVISED_CANDIDATES.json')['records']}
    require({p['headword'] for p in proposals.values()}=={'ritual','extend','scholar','contact'},'Known repair set differs')
    working=[];revisions=[]
    change_fields=(*LAYERS,'selection_reason','core_explanation','supporting_sources','use_coverage_matrix')
    for before in rows:
        after=copy.deepcopy(before)
        if before['stable_id'] in proposals:
            p=proposals[before['stable_id']];proposed=p['candidate_revision']
            require(all(proposed[k]==before[k] for k in ('source_fields','source_hash','original_meanings','stable_id','part_of_speech')),'Old proposal changes original')
            for k in change_fields:after[k]=copy.deepcopy(proposed[k])
            after['v5_revision']={'source_proposal':'docs/p6/p6c5/REVISED_CANDIDATES.json','source_proposal_sha256':sha(ROOT/'docs/p6/p6c5/REVISED_CANDIDATES.json'),
                 'issue_id':p['issue_id'],'before_candidate_hash':canonical(before),'new_semantic_review_pending':True,'human_approved':False}
            revisions.append({'stable_id':before['stable_id'],'headword':before['headword'],
                'before':before,'candidate':after,'changes':{k:{'before':before[k],'after':after[k]} for k in change_fields if before[k]!=after[k]},
                'human_approved':False,'status':'V5_isolated_revision_pending_actual_scope_validation'})
        working.append(after)
    once(OUT/'working700.json',{'record_count':700,'records':working,'source_sha256':sha(BASE),'new_IDs':0})
    once(OUT/'initial_four_revisions.json',{'records':revisions,'source_proposals_reused_not_regenerated':True})
    allwn={**read(ROOT/'private/p6c4/wordnet_selected600.json')['headwords'],**read(ROOT/'docs/p6/p6c5/evidence/wordnet_4732.json')['headwords']}
    refs={r['headword']:[] for r in rows}
    for r in rows:
        by={}
        for e in allwn.get(r['headword'],[]):
            by[e['evidence_id']]={'id':e['evidence_id'],'pos':e['part_of_speech'],'definition':e['definition_en'],
                                 'source':e['source'],'license':e.get('license')}
        for e in r['supporting_sources']:
            eid=e['evidence_id']
            if not eid.startswith('wn31:') and e.get('observation_zh'):
                by[eid]={'id':eid,'pos':e.get('pos_supported',[]),'definition':e['observation_zh'],
                         'source':e.get('url',e.get('source')),'type':'existing_publisher_observation',
                         'limitation':'prior original summary may include scope commentary; not independent dictionary-frequency evidence'}
        refs[r['headword']]=list(by.values())
    fresh=[
      ('ritual','名词；形容词','名词可指按既定程序进行的宗教或其他仪式，也可指惯常反复行为；形容词与相应礼仪/惯例相关。'),
      ('extend','动词','可把物体伸长、展开或扩大，也可说空间/时间上的延伸；家具可伸缩，伸手为身体用例。'),
      ('pursue','动词','可努力实现目标或结果；可在后跟随人、车或动物以追上/抓住；也可从事或持续进行活动、兴趣或计划。')]
    pubs=[]
    for w,p,text in fresh:
        e={'id':f'pub:p6c5a:collins:{w}','pos':p.split('；'),'definition':text,
           'source':'https://www.collinsdictionary.com/dictionary/english/'+w,
           'type':'fresh_primary_publisher_observation','frequency_evidence':False}
        refs[w].append(e);pubs.append(e)
    once(OUT/'evidence700.json',{'headwords':refs,'selected_ID_count':700,
         'licensed_archive_sha256':sha(ROOT/'private/p3/wordnet31.tar.gz'),
         'publisher_policy':'Only short independently written observations and URL; no full pages/examples/IPA'})
    once(OUT/'fresh_publisher_observations.json',{'utc_observation_recorded':now(),'records':pubs,
         'pursue_new_evidence':True,'actual_primary_pages_opened_this_round':True})
    # Source-only holdout selection, independent of candidate answers/risk labels.
    selected=[];used=set()
    domains=re.compile(r'law|legal|medicin|medical|chemistr|physic|grammar|comput|religi|financ|military|anatom|biolog|psycholog|botan|food|cook',re.I)
    abstract=re.compile('影响|联系|关系|意义|含义|状态|实质|观点|决定|保留|保持|提供|表示|获得|确定|构成|建立|支持|变化|部分')
    strata={}
    for label,fn in [
      ('multi_POS',lambda r:len(r['part_of_speech'].split('；'))>1),
      ('broad_abstract_source',lambda r:bool(abstract.search(r['original_meaning_zh']))),
      ('context_evidence_cue',lambda r:bool(re.search(r'[（(]',r['original_meaning_zh'])) or any(domains.search(e['definition']) for e in refs[r['headword']])),
      ('simple_source',lambda r:len(r['part_of_speech'].split('；'))==1 and len(r['original_meanings'])<=2 and 1<=len(allwn.get(r['headword'],[]))<=5)]:
        for cohort,poolids in [('reused600',oldids),('new100',newids)]:
            pool=[r for r in rows if r['stable_id'] in poolids and r['stable_id'] not in used and r['headword'] not in EXCLUDED and fn(r)]
            pool.sort(key=lambda r:canonical(['P6C5a_holdout_v1',label,cohort,r['stable_id']]))
            require(len(pool)>=3,'Holdout stratum insufficient; stop without guessing: '+label+'/'+cohort)
            strata[label+'/'+cohort]={'available_after_exclusions':len(pool),'chosen':3}
            for r in pool[:3]:
                selected.append({'stable_id':r['stable_id'],'headword':r['headword'],'stratum':label,'cohort':cohort,'source_hash':r['source_hash']})
                used.add(r['stable_id'])
    require(len(used)==24,'Holdout count')
    once(OUT/'HOLDOUT_SELECTION.json',{'records':selected,'count':24,'strata':strata,
       'excluded_words':sorted(EXCLUDED),'source_only_selection':True,'candidate_answers_used_to_select':False,
       'method':'3 per cohort per source/evidence stratum; fixed SHA256 within pool, mutually exclusive',
       'limitation':'Domain metadata cues potential context review, not measured frequency or restriction of every word sense.'})
    once(OUT/'INPUT_SETS.json',{'all700':sorted(ids),'reused600':sorted(oldids),'new100':sorted(newids),
       'historical48':s['historical48'],'holdout24':sorted(used),'repair4':sorted(proposals),
       'no_new_formal_IDs':True,'unprocessed4632_not_loaded_as_candidates':True})
    work={r['stable_id']:r for r in working}
    # Full audit candidates contain only after-four-revision semantic fields,
    # no previous risk/severity conclusions. Model must make its own mapping.
    for b in range(7):
        subset=working[b*100:(b+1)*100]
        once(OUT/f'inputs/audit_{b+1:02d}.json',{'records':[packet(r,refs[r['headword']]) for r in subset]})
    once(OUT/'inputs/holdout_source_only.json',{'records':[packet(work[s['stable_id']],
        [e for e in refs[s['headword']] if e['id'].startswith('wn31:')],False) for s in selected],
        'candidate_answers_included':False,'publisher_commentary_excluded_to_reduce_prior_answer_leakage':True})
    once(OUT/'inputs/calibration_before.json',{'records':[packet(r,refs[r['headword']]) for r in rows if r['stable_id'] in proposals]})
    once(OUT/'inputs/calibration_after.json',{'records':[packet(work[r['stable_id']],refs[r['headword']]) for r in rows if r['stable_id'] in proposals]})
    paths=[RULES,OUT/'GATE_PROTOCOL.json',BASE,FORMAL,OUT/'working700.json',OUT/'initial_four_revisions.json',OUT/'evidence700.json',OUT/'HOLDOUT_SELECTION.json',OUT/'INPUT_SETS.json',OUT/'fresh_publisher_observations.json']
    paths+=sorted((OUT/'inputs').glob('*.json'))
    paths+=[p for p in (ROOT/'scripts/p6c5a').glob('*') if p.is_file()]
    once(OUT/'RUN_MANIFEST.json',{'frozen_utc':now(),'rules_version':'P6C5a-V5.0','rules_hash':sha(RULES),
      'source700_sha256':sha(BASE),'formal5332_sha256':sha(FORMAL),'formal_ID_count_allowed':700,
      'primary_model':'deepseek-flash','secondary_model':'deepseek-v4-pro','thinking':'enabled','effort':'low',
      'primary_batch_words':5,'secondary_batch_words':2,'max_concurrency':24,'max_schema_repairs':1,'network_retries':0,
      'prompt_version':'P6C5a-scope-v1','token_or_cost_limit_imposed':False,
      'provider_documented_versions':{'deepseek-flash':'DeepSeek-V4.1-Flash-1017','deepseek-v4-pro':'DeepSeek-V4-Pro-0813'},
      'actual_deployed_weights_not_independently_verified':True,
      'files':{p.relative_to(ROOT).as_posix():sha(p) for p in paths},
      'no_Notion_SQLite_UI_or_new_vocabulary_writes':True,'no_C5_resume':True})
    print(json.dumps({'source':700,'old':600,'new':100,'fragments':1702,'repairs':4,'holdout':selected,'frozen':True},ensure_ascii=False))

if __name__=='__main__':main()
