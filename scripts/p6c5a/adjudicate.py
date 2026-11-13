"""Explicit evidence adjudications, kept separate from model risk predictions.

These are parent-agent AI decisions after reading the actual source, target and
references. They are not human sign-offs or a detector keyed by headword.
"""
from common import *

def main():
    verify_frozen()
    ws={r['headword']:r for r in working()}
    supplement=[]
    observations={
      'contact':('Collins British verb13 / American verb7 and9',
        '完整条目同时支持直接接触与使之接触；因此不能将使动义判为英语不存在。旧WN引证本身仅证明直接接触，属于绑定证据和注释精度问题。'),
      'determine':('Collins COBUILD verbs1 and3',
        '既可由人作出决定，也可由因素决定事物的性质或结果；后者不要求有意识作选择。'),
      'sensitive':('Collins COBUILD adjectives1 and2',
        '能体察他人需要与自己容易因话题而担忧或被冒犯是不同用途；后者不是皮肤物理反应或机密信息义。'),
      'condition':('Collins American verb22b / COBUILD verb7',
        '可通过经验或训练使人习惯于某事；中文使适应的精确范围仍须语境，不宜从现有心理训练证据推断任意一般适应。'),
      'dismiss':('Collins British verb2 / American verb1; Merriam-Webster verb1',
        '允许或命人离开，包括解散聚集的人群；当前候选让人离开等场景可兼容该义。不能仅因词典另有议会例证，就判现有中文解散只剩单人离开。')}
    for word,(locator,obs) in observations.items():
        supplement.append({'id':f'pub:p6c5a:supplement:collins:{word}','headword':word,
          'source':f'https://www.collinsdictionary.com/dictionary/english/{word}',
          'locator':locator,'observation_zh':obs,'read_via':'web.open/find actual publisher entry',
          'date':'2026-11-13','frequency_evidence':False,'verbatim_entry_saved':False,
          'not_in_frozen_model_packets':True,'not_automatically_adopted':True})
    save(OUT/'SUPPLEMENTAL_PUBLISHER_OBSERVATIONS.json',{'records':supplement,
        'frozen_rule_or_model_packets_changed':False,'full_commercial_entries_or_examples_copied':False})
    def known(word,root,status,reason,refs):
        return {'stable_id':ws[word]['stable_id'],'root_causes':root,'repair_status':status,
           'evidence_adjudication':reason,'evidence_ids':refs,'human_approved':False,
           'source_meanings_unchanged':True,'old_C5_finding_preserved':True}
    known4={
      'ritual':known('ritual',['C_core_selection','D_scope_in_note','E_gap_flagged_but_qualification_treated_as_resolution'],
          'known_Major_point_repaired_in_isolated_candidate',
          's001仪式无宗教限定；旧核心仅宗教程序，s002惯常做法与形容词不能补名词仪式缺口。生成器已标Minor scope_gap，却以用限定展示视作可接受，问题在处置/升级而非完全未识别。修订同时保留宗教/非宗教礼仪，未扩大为一切随意行为；惯常程序与形容词仍分别保留。',
          ['wn31:n:01029801','wn31:n:01032852','pub:p6c5a:collins:ritual']),
      'extend':known('extend',['C_core_selection','D_object_limit','E_self_checker_missed'],
          'known_Major_point_repaired_other_source_uncertainty_retained',
          's001伸展的肢体限定遗漏已提供的桌腿、布料、天线展开。修订允许肢体或可伸展物体；不及物空间/时间延伸仍独立，s002变宽的施受方向证据待核没有自动解除。',
          ['wn31:v:00027261','wn31:v:01371528','wn31:v:02058913','pub:p6c5a:collins:extend']),
      'scholar':known('scholar',['D_unsupported_frequency_reason','E_reason_check_missed'],
          'known_Minor_frequency_claim_removed',
          '仅将无义项频率依据的最常用改成AI教学建议；学习者、学者、文人原文及既有分组不变。词典释义不是义项频率计量。',
          ['wn31:n:10271476','wn31:n:10577282']),
      'contact':known('contact',['D_note_direction_vs_bound_evidence','E_citation_precision'],
          'known_Minor_annotation_neutralized_historical_interpretation_refined',
          '改成与另一人或物直接接触，与绑定WN相符。新查完整Collins确有使之接触用法，故旧问题仅就WN引证不足成立，不能作为整词无使动义的语义错误金标准；旧Minor原记录不改。原片段词性仍null，推荐名/动词分组不冒充源词性。',
          ['wn31:v:01208316','pub:p6c5a:supplement:collins:contact'])}
    # Severity decisions below apply to the stated issue, not every sense of a word.
    cases={
      'determine':('confirmed_Major_scope_defect','Major',['s001'],['wn31:v:00699355','wn31:v:00702806','pub:p6c5a:supplement:collins:determine'],
        '源决定无限定；核心注明对选择或行动作出决定，其他层确定/查明没有保留因素决定结果义。WN与出版社均支持非意志因素决定结果；该限制构成真实范围缺口。',
        '移除主动作选择的排他解释，另保留因素决定结果的子用法并逐链接证据；本轮未改第五个候选。'),
      'sensitive':('confirmed_Major_scope_defect','Major',['s001'],['wn31:a:02110761','wn31:a:02113270','pub:p6c5a:supplement:collins:sensitive'],
        's001敏感的被分成物理刺激和机密信息；s002体察他人感受不是本人因话题而担忧/被冒犯。出版社支持后一独立用途，现有各层无对应；不是要求一切字典义均进核心。',
        '先补足或明确暂存非物理情绪/话题敏感的剩余范围，再复核；不把体贴义当替代。'),
      'define':('confirmed_Minor_evidence_mapping','Minor',['s002'],['wn31:v:02742653','wn31:v:00949109'],
        '指明的绑定证据仅为显出外形/轮廓；现有同词证据另有明确指定参数。中文指明仍显示，尚不足以判重要含义已删除，确认引证精度缺陷，未采二审Major。','保留原文，重新核定指明与具体指定/轮廓用法的链接。'),
      'demand':('confirmed_Minor_coverage_evidence','Minor',['s001'],['wn31:n:13482365','wn31:n:14472592'],
        '需求中文未被改为仅购买，注释也提醒不将所有请求理解为购买需求。唯一绑定经济购买证据不能证明一般需求全覆盖，属覆盖证明不足，未证实显示文本真被收窄。','补一般需求证据或明确剩余范围，不机械加核心组。'),
      'abstract':('confirmed_Minor_coverage_evidence','Minor',['s001'],['wn31:a:00011776','wn31:s:00865713','wn31:s:01987622'],
        '显示仍为抽象的、注释为空，没有仅心理概念的排他用语；抽象推理/艺术证据未链接，故不能宣称已全面验证，也不能因少挂synset就确认Major删义。','在不改变概括中文前提下补用途映射，艺术子义是否源内仍待确认。'),
      'tender':('confirmed_Minor_coverage_evidence','Minor',['s002'],['wn31:a:02455719','wn31:s:01654003'],
        '显示嫩的且注释为空；只有易咀嚼证据，但并未写仅食物。幼嫩等证据可能属于原义或外部细分；确认覆盖论证不足，保留来源范围待核，不判已确认Major。','逐用途核对嫩的，而非把每个可译嫩的synset自动塞入核心。'),
      'reverse':('confirmed_Minor_coverage_evidence','Minor',['s003'],['wn31:n:04092293','wn31:n:13880801'],
        '反面文本没有硬币限制，但所引只有钱币反面；一般相反情况证据未链接。确认引证覆盖不足；不把名词反面与相反情况是否同源预设成Major。','补核反面/相反情形的来源范围；原倒退继续held。'),
      'represent':('confirmed_Minor_source_link_gap','Minor',['s001','s002'],['wn31:v:00837915','wn31:v:00990060'],
        '象征用法在核心表示组已完整显示，故不是全词丢失象征义。s001代表与s002表示的交叠没有显式双向映射，按V5不能自动借义，确认链接缺口，二审Major过度升级。','为重叠源义补显式交叉链接或解释语义分工，不重复堆核心组。'),
      'condition':('source_scope_or_evidence_pending',None,['s003'],['wn31:v:02559394','wn31:v:02577683','pub:p6c5a:supplement:collins:condition'],
        '中文使适应宽，现证据与注释为训练/条件作用，出版社亦支持使习惯。是否必须涵盖任意一般适应，原语境不足；不能把自己的无证据广义当金标准。','保持来源与英语范围待核，未解除。'),
      'dismiss':('source_scope_or_evidence_pending',None,['s002'],['wn31:v:00902491','wn31:v:00339369','pub:p6c5a:supplement:collins:dismiss'],
        '让人离开等场景可涵盖人群解散；出版社明确支持解散聚集者。二审将其读成仅单人，又从WN议会例推制度废止，现证据不足判这种理解必属原解散；不确认Major，保留差异。','核实教材是遣散人群还是制度解散；不得强制把所有解散都教成废除机构。'),
      'collapse':('source_POS_pending',None,['s001','s002'],['wn31:v:01993067','wn31:n:07493085'],
        '源逐片段POS原来就是null且仍null；推荐名词倒塌/动词崩溃不等于源字段被改写。跨词性用途值得待核，但整体名/动词不证明每个片段都同时含两性。','保留未知词性及跨词性范围待审，不作笛卡尔积自动补义。'),
      'adopt':('already_held_not_silent_loss',None,['s001'],['wn31:v:02351891'],
        '跟随原本明确held待核，没有伪装成已覆盖；二审自己建议继续暂存。英语抽象follow与中文可能物理跟随的分歧不是已证实生成器删义。','保持held，不通过。'),
      'institute':('already_held_not_silent_loss',None,['s004'],['wn31:v:01621566'],
        '实行原本held，英语提出诉讼不能证明一般实行。已隔离证据不足，不计新的确认Major。','保持held，不通过。'),
      'ensure':('already_held_not_silent_loss',None,['s002'],[],
        '担保的承诺范围原来held；不能把原文保留解释成已完成语义覆盖，也不将正确隔离判生成器新错误。','保持held，不通过。'),
      'clause':('already_held_not_silent_loss',None,['s001'],['wn31:n:06325134','pub:parent:clause'],
        '语法从句/分句争议沿C4隔离，词典上位分句候选未自动采用，历史未决没有被通过。','继续隔离，不能用再审成功消除争议。'),
      'constitution':('already_held_not_silent_loss',None,['s002'],['wn31:n:04940721'],
        '体质原来held，composition的宽定义不能独立证明身体健康义；来源待核不是新删义。','保持held。'),
      'attach':('already_held_not_silent_loss',None,['s003'],['wn31:v:02543752'],
        '重视依赖搭配的证据待核已明确held，保留原文与风险；不当完整覆盖，也不新增确认Major。','保留搭配证据待审。'),
      'damage':('source_POS_pending',None,['s001','s002'],['wn31:n:00403900','wn31:v:00259743'],
        '原POSnull逐字保留，所谓静默修改源词性不属实；推荐词性仍需审核。','不把推荐分组冒充源字段。'),
      'transfer':('source_POS_pending',None,['s002','s003'],['wn31:n:01109837'],
        '各原片段POSnull保留；名词用途可待核，不能从整词名/动直接断言每片段名词都被删。','保留未知与未采用名词观察。'),
      'comment':('source_POS_pending',None,['s001'],['wn31:n:06777755','wn31:v:01060446'],
        '评论片段源POS未定仍未定，发表评论另有动词组；需要源ID交叠核验，不是已证实全词无动词。','保留原POS待核。'),
      'compromise':('source_POS_pending',None,['s001','s002','s003'],['wn31:v:01037675','wn31:n:01208054'],
        '妥协/折中中文词性不定与实际名/动词分组分开存储，无源字段变更；跨片段覆盖继续待核。','保留未知，不自动补满所有词性组合。'),
      'knock':('source_POS_pending',None,['s001','s002'],['wn31:n:07400970','wn31:n:07424807'],
        '未证实源两片段都必须含名词；确有名词词典观察未采用，原片段POS仍null。','原始词性归属待人工核验，不能当全通过。'),
      'dip':('source_POS_pending',None,['s001','s002','s003'],[],
        '保留源null、推荐名/动词组和不确定性；推荐组有词性不是静默改写源POS。','继续核对逐义词性。'),
      'extreme':('evidence_precision_pending',None,['s003'],['wn31:n:08586694','wn31:n:05105361'],
        '中文极限既可能限度也可能端点，候选字面保留；现有原语境不足确认哪一种，应补核证据而非直接判词义错。','逐用途核对限度与端点。'),
      'master':('source_scope_or_evidence_pending',None,['s003'],['wn31:n:10318465'],
        '候选已说明学位持有者与学位结构不同；硕士可指人或学位，原片段未定，不能把其中一种一律当错。','保留人物/学位边界待核。'),
      'spread':('rejected_frequency_lexicon_conflation',None,['s004'],['pub:spread'],
        '出版方观察被声明不是义项频率证据，不等于不是词义证据。现有范围观察可供审查；独立性强度可待核，不能仅据非频率证据判Major。','保留观察来源限制。'),
      'strike':('source_scope_or_evidence_pending',None,['s001'],['wn31:v:01412877','wn31:v:01126313'],
        '物理击打与攻击敌方可能有交叠，但原动词打击无语境，军事进攻是否为源内独立义待核；名词攻击另已保留但不能直接替代动词。','保留动词抽象/军事剩余范围疑点，不宣称已覆盖。'),
      'keep':('evidence_precision_pending',None,['s002'],['wn31:v:02738997','wn31:v:02207710','wn31:v:02208876'],
        '保管字面及原义未缩改；使物免受伤害可为保管的一面，看管/存放证据更直接。补链建议合理，是否真丢原义尚不确定，未采初审Major。','保留引证精度问题，不自动改正确分组。'),
      'model':('evidence_precision_pending',None,['s005'],['wn31:v:01747665'],
        '按模型规划或制作可含仿照，但不证明任意模仿；原中文无例句，证据边界待核，模型断言完全不支持一般模仿也非已证实。','继续核对对象与imitate边界。')}
    primary=read(OUT/'COLLECTED_PRIMARY_AUDITS.json')['records']
    secondary=read(OUT/'COLLECTED_SECONDARY_VERIFICATION.json')['records']
    majorids={r['id'] for r in primary+secondary if any(i.get('severity') in ('Major','Critical') for i in r['review'].get('issues',r['review'].get('confirmed_within_supplied_evidence',[])))}
    require(majorids=={ws[w]['stable_id'] for w in cases},'A proposed Major was not explicitly adjudicated')
    ds=[]
    for word,(status,sev,sids,refs,reason,action) in cases.items():
        ds.append({'stable_id':ws[word]['stable_id'],'headword':word,'status':status,
          'confirmed_severity_for_stated_issue':sev,'source_sense_ids':sids,'evidence_ids':refs,
          'rationale':reason,'next_action_without_this_run_mutating_candidate':action,
          'human_approved':False,'reviewer':'parent_agent_AI_evidence_adjudication',
          'actual_display_and_notes_read_not_headword_inference':True})
    save(OUT/'PARENT_EVIDENCE_ADJUDICATION.json',{'known_four_status':known4,'regression_major_proposal_dispositions':ds,
       'new_confirmed_regression_findings':{s:sum(r['confirmed_severity_for_stated_issue']==s for r in ds) for s in ('Critical','Major','Minor')},
       'not_entire_minor_or_info_pool_adjudicated':True,'raw_model_labels_preserved':True,'human_approved_count':0,
       'pursue':{'stable_id':ws['pursue']['stable_id'],'prior_failure_reconciliation_pending':True,
         'new_evidence':'pub:p6c5a:collins:pursue','new_review_returned_but_not_semantically_reconciled':True,
         'reason':'原C5两次响应回显输入；本轮实际Pro检查已有，但其中Moderate不合级别枚举，关于寻找/目标的范围判断也与其等价映射存在张力。不得把再次HTTP/JSON成功当语义通过。'},
       'scope_error_gold_is_not_missing_every_dictionary_synset':True})
    print('Adjudicated',len(ds),'Major-proposal words; confirmed',collections.Counter(r['confirmed_severity_for_stated_issue'] for r in ds))

if __name__=='__main__':main()
