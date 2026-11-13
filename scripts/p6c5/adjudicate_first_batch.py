"""Explicit parent evidence adjudication; no model/API/formal-data writes."""
import copy
from common import *

def main():
    verify_frozen()
    gen=read(OUT/'generation/batch_001.json')['records']
    byword={r['headword']:r for r in gen}
    source=read(OUT/'inputs/batch_001.json')['records']
    evidence={r['word']:{e['id']:e for e in r['evidence']} for r in source}
    publisher=[
        {'evidence_id':'pub:p6c5:parent:ritual','headword':'ritual','url':'https://www.collinsdictionary.com/dictionary/english/ritual',
         'publisher':'HarperCollins','access':'actually_opened_and_read_by_parent_this_round',
         'locator':'COBUILD noun1 and British noun1, noun5',
         'observation_zh':'仪式义同时包括宗教与非宗教的正式仪式；惯常反复行为另列。不能以宗教仪式程序代替全部一般仪式义。',
         'pos_supported':['名词'],'frequency_evidence':False},
        {'evidence_id':'pub:p6c5:parent:extend','headword':'extend','url':'https://www.collinsdictionary.com/dictionary/english/extend',
         'publisher':'HarperCollins','access':'actually_opened_and_read_by_parent_this_round',
         'locator':'COBUILD verb5/6/9 and British verb1; licensed WN v01371528/v02058913 supplies direct non-body unfolding objects',
         'observation_zh':'伸展/展开适用于身体及非身体物体；可伸缩家具和伸出手分别成立。已提供的WordNet还直接列桌子折叠腿、布料、天线等展开对象。',
         'pos_supported':['动词'],'frequency_evidence':False},
        {'evidence_id':'pub:p6c5:parent:render','headword':'render','url':'https://www.collinsdictionary.com/dictionary/english/render',
         'publisher':'HarperCollins','access':'actually_opened_and_read_by_parent_this_round',
         'locator':'American4/5/10 and performance sense',
         'observation_zh':'词典另有表现/提交/演绎等用途；原文宽词呈现是否包含哪些抽象用途仍需逐用途判断，不自动将所有词典用法升级核心。',
         'pos_supported':['动词'],'frequency_evidence':False}]
    once(OUT/'PARENT_SOURCE_OBSERVATIONS.json',{'method':'Short original Chinese observations from actually read primary pages; no full definitions/examples/IPA copied',
         'records':publisher,'licensed_WordNet_source_already_frozen':True})
    issues=[
        {'word':'ritual','severity':'Major','kind':'important_source_use_omitted',
         'normalized_cause':'unsupported_subtype_restriction_of_source_general_use',
         'reason':'源s001仪式被明确收窄为宗教仪式规定程序，普通非宗教正式仪式没有进入该源用法的核心/扩展/暂存。s002惯常程序的另一个名词组不能替代s001的正式仪式用法；形容词社会礼仪也不能补名词缺口。已有WordNet宽义与出版社宗教或其他仪式的定义反证该限制。',
         'evidence_ids':['wn31:n:01029801','wn31:n:01032852','pub:p6c5:parent:ritual'],
         'source_sense_ids':['s001'],'group_index':0},
        {'word':'extend','severity':'Major','kind':'important_source_use_omitted',
         'normalized_cause':'unsupported_subtype_restriction_of_source_general_use',
         'reason':'源s001伸展被限定为身体部位，已提供的展开桌腿/布料/天线等非身体主动展开用法未在任何层级或暂存得到该源用法覆盖；另一不及物空间/时间延伸组不能代替此及物对象用法。问题是新增对象限制，不是要求所有词典细分都放核心。s002变宽的独立证据不足仍可保持暂存。',
         'evidence_ids':['wn31:v:00027261','wn31:v:01371528','wn31:v:02058913','pub:p6c5:parent:extend'],
         'source_sense_ids':['s001'],'group_index':0},
        {'word':'scholar','severity':'Minor','kind':'unsupported_sense_frequency_claim',
         'normalized_cause':'unsupported_frequency_wording',
         'reason':'选择理由直接写最常用的学者，但没有提供义项频率证据。应改为明确的AI教学选择，原文和核心无需因此删除。',
         'evidence_ids':[],'source_sense_ids':[],'group_index':None},
        {'word':'contact','severity':'Minor','kind':'causative_direction_mismatch_in_note',
         'normalized_cause':'causative_vs_contact_state',
         'reason':'动词接触组的注释写使某物与另一物发生物理接触，是使动结构；所引WN v01208316为直接接触/相碰的状态或动作，不能据此断言使动。核心中文接触可保留，修正对象方向注释。',
         'evidence_ids':['wn31:v:01208316'],'source_sense_ids':['s002'],'group_index':3}]
    confirmed=[]
    revisions=[]
    for i,item in enumerate(issues,1):
        w=item['word'];before=byword[w]
        finding={'issue_id':f'P6C5-b001-confirmed-{i:02d}', 'stable_id':before['stable_id'],'headword':w,
                 **{k:v for k,v in item.items() if k not in ('word','group_index')},
                 'adjudication':'parent compared actual original, group scope, complete frozen lexical evidence and available primary publisher observations',
                 'status':'candidate_revision_proposed_not_adopted', 'isolated_resolution_verified':False,
                 'human_approved':False,'no_exam_or_measured_frequency_claim':True}
        confirmed.append(finding)
        after=copy.deepcopy(before)
        if w=='scholar':
            after['selection_reason']=after['selection_reason'].replace('首屏先给最常用的','AI教学建议首屏先给')
            after['core_explanation']=after['selection_reason']
        elif w=='contact':
            after['core_meanings'][3]['usage_note']='与另一人或物直接发生物理接触；相碰。此证据为接触状态/动作，不据此断言使动。'
        else:
            g=after['core_meanings'][0]
            if w=='ritual':
                g['display_zh']='仪式；礼仪程序（宗教或非宗教）'
                g['usage_note']='按既定程序进行的仪式，可属宗教或非宗教正式礼仪；与惯常反复行为的另一组分开。'
                g['evidence_ids']=['wn31:n:01029801','wn31:n:01032852','pub:p6c5:parent:ritual']
            else:
                g['display_zh']='伸展；展开（肢体或物体）'
                g['usage_note']='可指伸展肢体，也可指展开或伸出可伸展物体（如折叠桌腿、布料或天线）；与不及物空间/时间延伸分开。'
                g['evidence_ids']=['wn31:v:00027261','wn31:v:01371528','wn31:v:02058913','pub:p6c5:parent:extend']
            for a in g['source_subsenses']:
                a['evidence_ids']=g['evidence_ids'][:]
            existing={e['evidence_id'] for e in after['supporting_sources']}
            for eid in g['evidence_ids']:
                if eid in existing:
                    continue
                if eid.startswith('pub:'):
                    after['supporting_sources'].append(copy.deepcopy(next(p for p in publisher if p['evidence_id']==eid)))
                else:
                    e=evidence[w][eid]
                    after['supporting_sources'].append({'evidence_id':eid,'part_of_speech':e['pos'],'definition_en':e['definition'],
                        'lemmas':[w],'source':'https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz','license':'assets/vocabulary/WORDNET_3_1_LICENSE.txt'})
        for u in after['use_coverage_matrix']:
            g=next(g for layer in LAYERS for g in after[layer] if g['sense_group_id']==u['use_id'])
            u.update({'meaning_zh':g['display_zh'],'scope_and_roles':g['usage_note'],'evidence_ids':g['evidence_ids']})
        after['model_version']='Codex-current-parent/backend-snapshot-unexposed'
        after['prior_generation_model_version']=before['model_version']
        after['review_status']='confirmed_problem_revision_pending'
        after['human_approved']=False;after['needs_human_review']=True
        after['revision_provenance']={'issue_id':finding['issue_id'],'before_candidate_sha256':canonical(before),
            'rules_hash':sha(RULES),'source_unchanged':True,'formal_adoption':False,
            'status':'AI_revision_proposed_after_evidence_check_not_independently_regression_validated'}
        revisions.append({'issue_id':finding['issue_id'],'stable_id':before['stable_id'],'headword':w,
             'before_candidate_sha256':canonical(before),'before':before,'candidate_revision':after,
             'after_candidate_sha256':canonical(after),'original_input_hash':before['source_hash'],
             'human_approved':False,'active_merged_candidate_replaced':False})
    output={'schema_version':'p6c5_parent_evidence_adjudication.v1','confirmed_findings':confirmed,
            'systematic_failure_confirmed':True,
            'systematic_basis':{'batch':1,'same_causal_Major_count':2,
                 'cause':'unsupported_subtype_restriction_of_source_general_use',
                 'pre_registered_stop_rule':'RUN_MANIFEST.json systematic_stop_definition',
                 'rules_file_unchanged':True,'problem_location':'new generation model/rule execution, not formal source corruption'},
            'other_model_Major_adjudications':[
                {'headword':'render','status':'evidence_pending_not_confirmed_Major', 'reason':'生成已限定图片语境并标scope gap；是否有原文支持的重要抽象用途仍需具体核验，不能仅凭广中文就把所有英语用法并入。'},
                {'headword':'restore','status':'evidence_mapping_granularity_pending_not_confirmed_Major','reason':'复原/恢复近邻合并不必然为语义错误；逐片段引用范围可细化，中文排斥某对象的断言未获独立充分证据。'},
                {'headword':'attach','status':'external_candidate_suggestion_not_confirmed_Major','reason':'情感联系用法可作为外部候选建议；其首次学习重要性仍为教学判断，未跟踪不直接等于当前原文核心错误。'}],
            'other_Minor_adjudications':'外部补充遗漏保留为候选建议；constitution词性已有一项表示被误读为全部片段核验完备，不计确认错误；consume消费范围保留证据待核。',
            'lowrisk_source_first_comparison':{'words':['spouse','persuade'],'confirmed_new_errors':0,
                'persuade':'独立建议合为一组，生成分信念/行动对象两组，属于教学分层差异，不计错误。'},
            'generation_stopped_after_batch':1,'remaining_unprocessed_new_IDs':4632,
            'human_approved':False,'not_published':True,'adjudicator':'Codex parent; exact backend not exposed'}
    once(OUT/'PARENT_ADJUDICATION.json',output)
    once(OUT/'REVISED_CANDIDATES.json',{'AI_candidates_only':True,'human_approved_count':0,
         'rules_hash':sha(RULES),'records':revisions,'not_adopted_into_active_merge':True})
    print('Confirmed 2 Major +2 Minor; same-cause Major stop. 4 separate unadopted revisions; no new generation.')

if __name__=='__main__':main()
