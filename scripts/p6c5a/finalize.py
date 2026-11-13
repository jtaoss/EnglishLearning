"""Build reports from saved actual reviews; makes no model or service calls."""
from common import *
from extra_checks import advisory_text_risks

def md(path,content):
    Path(path).write_text(content.strip()+'\n',encoding='utf-8')

def main():
    verify_frozen();protection=verify_protection()
    data=read(OUT/'regression_700.json');rs=data['records'];by={r['headword']:r for r in rs}
    p=read(OUT/'COLLECTED_PRIMARY_AUDITS.json')['records']
    s=read(OUT/'COLLECTED_SECONDARY_VERIFICATION.json')['records']
    a=read(OUT/'PARENT_EVIDENCE_ADJUDICATION.json');sets=read(OUT/'INPUT_SETS.json')
    hold=read(OUT/'HOLDOUT_SELECTION.json')['records'];blind=read(OUT/'reviews/holdout_source_first_reconciled.json')
    blindids={r['id'] for r in blind['records']}
    # Individually read comparisons. Different first-screen choices are not errors.
    notes={
      'medium':('source_scope_pending','盲提案分媒介/手段两组，旧候选同框并列，分组偏好；媒介的信息用途与更宽来源边界仍待核。'),
      'brief':('compatible_layer_preference','三种词性均保留；盲提案将概要/介绍情况也放核心，原候选后置扩展，未丢义。'),
      'abstract':('confirmed_Minor_evidence_coverage','显示抽象的并无排他限制；附加英语用途未显式链接，记引证覆盖Minor而非确认Major。盲提案对提取缺WN证据，旧出版社观察仍单独保留。'),
      'attempt':('compatible','原义逐片段POS未定；候选显式保留名/动词两组，盲提案也保留两性，未把中性attempt自动定贬义。'),
      'associate':('compatible','联系/交往、同事/伙伴分别保留；未将副职或学位义混入原义。'),
      'station':('source_scope_pending','名词车站/站有联合覆盖；驻扎状态与派驻方向、一般安置范围未定，盲提案也后置安置。'),
      'keep':('evidence_precision_pending','盲提案保管含看管/存放，原候选中文保管不变但引证为使安全；补链建议待核，不采初审Major。'),
      'influential':('compatible_layer_preference','有势力/有影响同框或分两组为教学展示差异，原两片段均保留。'),
      'maintain':('compatible','原文三个状态保持近义片段同组保留；声称/供养等源外用途不自动加入。'),
      'section':('compatible','部分、章节、部门各有证据与分组，非源内的外科/军队等细分未强塞核心。'),
      'religious':('compatible','宗教相关与虔诚分别保留，没有把一般宗教形容词压成修道誓愿专用。'),
      'symptom':('source_or_external_boundary_pending','源只有症状；医学解释与泛指社会征兆的源内归属有分歧，先盲提案只取医学，二审提泛义Minor。未当已确认错误，源外观察继续分离。'),
      'particular':('compatible','特定/特别/挑剔各原义保留，未用about例子限定所有句式。'),
      'reserve':('compatible_layer_preference','保护区放核心或扩展为教学差异，预订/保留/储备与保护区均映射。'),
      'sceptical':('source_scope_pending','一般怀疑已保留；怀疑论的哲学/宗教范围证据不足，旧held不因盲提案纳核心就解除。'),
      'constitution':('source_scope_pending','体质证据偏宽，旧held保持；盲提案另将构成解释为建立行为可能换义，未采纳盲提案为金标准。'),
      'confine':('compatible','限制与禁闭独立保留，未把英语笼罩等源外用法借来扩大禁闭。'),
      'week':('compatible','星期/周同义合并，一般连续七天而非只限工作日或周日起算。'),
      'imagination':('compatible','想象力能力义保留；过程/产物与机智义不因词典有就自动补核心。'),
      'consequently':('compatible','因此/结果近义副词合并，未与名词结果混淆。'),
      'solution':('compatible','解决办法与溶液分别保留，数学解/答案陈述不自动作源义。'),
      'derive':('compatible','获得与源自分别保留；来源对象以示例处理，未强塞演绎义。'),
      'constitute':('source_first_incomplete','源先盲提案因错误ID/结构未完成；后续实际候选二审支持构成/设立，但不能补称已完成独立源先盲审。'),
      'determine':('confirmed_Major_source_first_incomplete','源先盲审失败未猜改；候选二审及父级WN/Collins核验确认决定结果义缺口，旧候选未改。')}
    hc=[]
    for row in hold:
        word=row['headword'];status,note=notes[word]
        hc.append({**row,'source_first_available':row['stable_id'] in blindids,'comparison_status':status,
           'evidence_comparison_note':note,'human_approved':False})
    save(OUT/'HOLDOUT_COMPARISON.json',{'records':hc,'selected_count':24,'source_first_valid_count':22,
      'candidate_comparison_count':24,'wrong_ID_repaired':False,'resampled':False,'blind_proposals_are_not_gold':True})
    api=[read(path) for path in sorted((OUT/'api').glob('*.json'))]
    totals=collections.Counter();models={}
    for response in api:
        name=response['response_model'];b=models.setdefault(name,collections.Counter())
        b['responses']+=1
        for k,v in response.get('usage',{}).items():
            if isinstance(v,int):totals[k]+=v;b[k]+=v
    lower=0.0
    rates={'deepseek-flash':(.003,.15,.6),'deepseek-v4-pro':(.022,.66,1.98)}
    for name,v in models.items():
        cached,miss,out=rates[name]
        lower+=(v.get('prompt_cache_hit_tokens',0)*cached+v.get('prompt_cache_miss_tokens',v['prompt_tokens'])*miss+v['completion_tokens']*out)/1e6
    before_packet=read(OUT/'inputs/calibration_before.json')['records']
    after_packet=read(OUT/'inputs/calibration_after.json')['records']
    frequency={'before':[(q['word'],advisory_text_risks(q)) for q in before_packet if advisory_text_risks(q)],
               'after':[(q['word'],advisory_text_risks(q)) for q in after_packet if advisory_text_risks(q)],
               'is_lexical_advisory_not_semantic_proof':True}
    save(OUT/'FREQUENCY_CALIBRATION.json',frequency)
    relation=collections.Counter(m['mapping_relation'] for r in rs for m in r['source_scope_mappings'])
    cohort={}
    for name in ('reused600','new100'):
        group=[r for r in rs if r['cohort']==name]
        cohort[name]={'words':len(group),'source_fragments':sum(len(r['source_scope_mappings']) for r in group),
          'primary_reviewed':len(group),'source_POS_unknown_fragments':sum(m['source_pos'] is None for r in group for m in r['source_scope_mappings']),
          'pending_scope_mappings':sum(m['risk_status'].startswith('pending') for r in group for m in r['source_scope_mappings'])}
    metrics={'schema_version':'P6C5a.quality_metrics.v1','candidate_words':700,'new_candidate_IDs':0,
       'source_fragments':1702,'cohorts':cohort,'primary_actual_reviewed_words':len(p),
       'primary_strict_contract_words':sum(r['strict_contract_passed'] for r in p),
       'secondary_targeted_actual_words':len(s),'secondary_strict_contract_words':sum(r['strict_contract_passed'] for r in s),
       'primary_AI_relations_NOT_confirmed_errors':dict(relation),
       'primary_AI_issue_proposals_NOT_confirmed':dict(collections.Counter(i['severity'] for r in p for i in r['review']['issues'])),
       'secondary_AI_issue_proposals_NOT_parent_confirmed':dict(collections.Counter(i['severity'] for r in s for i in r['review']['confirmed_within_supplied_evidence'])),
       'all_major_proposal_word_dispositions':len(a['regression_major_proposal_dispositions']),
       'parent_evidence_confirmed_regression_issues':a['new_confirmed_regression_findings'],
       'remaining_confirmed_Major_words':['determine','sensitive'],
       'known_scope_Major_points_repaired':2,'known_Minor_annotation_points_repaired':2,
       'contact_prior_interpretation_refined_not_whole_word_causative_impossible':True,
       'holdout_selected':24,'holdout_source_first_valid':22,'holdout_source_first_failed':2,
       'holdout_candidate_reviewed':24,'heldout_confirmed_Major_words':['determine'],
       'heldout_confirmed_Minor_evidence_mapping_words':['abstract'],
       'historical48_retained':48,'human_approved_count':0,
       'original_needs_human_review_count':sum(r['needs_human_review'] for r in baseline()),
       'current_requires_human_review_count':sum(r['requires_human_review'] for r in rs),
       'pending_scope_mapping_count':sum(m['risk_status'].startswith('pending') for r in rs for m in r['source_scope_mappings']),
       'actual_API_responses_saved':len(api),'actual_API_usage':dict(totals),
       'actual_API_usage_by_returned_model':{k:dict(v) for k,v in models.items()},
       'actual_billed_cost_USD':None,'Codex_parent_model_exact_version_usage_cost':None,
       'estimated_USD_range_not_invoice':[round(lower,6),round(2*lower,6)],
       'cost_source':'https://api-docs.deepseek.com/quick_start/pricing/',
       'response_model_identifiers':sorted(models),'documented_versions':read(OUT/'RUN_MANIFEST.json')['provider_documented_versions'],
       'provider_internal_weights_or_statistical_independence_proven':False,
       'population_false_positive_rate':None,'population_false_negative_rate':None,
       'known_scope_calibration_before_detected':2,'known_scope_calibration_after_still_flagged_as_narrowing':0,
       'known_scholar_frequency_claim_missed_by_both_semantic_models':True,
       'frequency_advisory_detected_before':len(frequency['before']),'frequency_advisory_detected_after':len(frequency['after']),
       'new_confirmed_critical':0,'same_cause_systemic_C_threshold_proven':False,
       'decision':'B','resume_authorized':False,'release_authorized':False}
    save(OUT/'QUALITY_METRICS.json',metrics)
    tests=read(OUT/'TEST_EXECUTION.json') if (OUT/'TEST_EXECUTION.json').exists() else {'status':'not_run_yet'}
    replay=read(OUT/'REPRODUCIBILITY.json') if (OUT/'REPRODUCIBILITY.json').exists() else {'status':'not_run_yet'}
    fixedhash=sha(OUT/'GATE_PROTOCOL.json');ruleshash=sha(RULES)
    gatechecks=[
      ('700 ID/1702原义映射与600词内容保护','通过'),
      ('四个旧修复点重现、证据对照与独立候选','通过；contact旧标签按新证据细化'),
      ('ritual/extend修复后无新增扩大/词性错误','已知修复点通过；extend变宽仍待核'),
      ('无新增已确认Critical','本轮未确认Critical；不等于证明不存在'),
      ('无重复未解决确认Major','未通过：determine、sensitive仍有具体范围缺口'),
      ('至少20词源先留出与同因系统性检查','数量通过22；24全做候选比较，determine发现Major，2个盲审失败仍隔离'),
      ('历史48与pursue未决保持','通过'),
      ('原文/旧700/检查点/个人库/正式代码保护','通过：'+str(protection['checked_files'])+'个受保护文件'),
      ('测试与幂等重放','见TEST_EXECUTION.json、REPRODUCIBILITY.json；技术通过不放行语义')]
    gate_table='\n'.join('| '+x+' | '+y+' |' for x,y in gatechecks)
    htable='\n'.join(f"| {r['headword']} | {r['cohort']}/{r['stratum']} | {'完成' if r['source_first_available'] else '失败保留'} | {r['evidence_comparison_note']} |" for r in hc)
    dtable='\n'.join(f"| {r['headword']} | {r['confirmed_severity_for_stated_issue'] or '未确认错误'} | {r['rationale']} |" for r in a['regression_major_proposal_dispositions'])
    h48=', '.join(r['headword'] for r in rs if r['historical_risk_retained'])
    md(OUT/'SCOPE_FAILURE_ANALYSIS.md',f'''# P6-C.5a 范围失败分析

实际基线为600词复用+100词新生成=700，不是已完成5332；剩余4632不处理。旧C5结论、原700、失败记录与检查点未覆盖。四项旧问题为2 Major+2 Minor；本轮只有这四词的语义/注释修订进入独立工作快照，复用600词内容全部不变。

## 生成器与检查器根因

| 项目 | 原文与旧目标 | 定位 | 隔离修复及状态 |
|---|---|---|---|
| ritual | s001名词仪式 → 宗教仪式的规定程序；s002惯常程序、s003形容词仪式的另存 | C核心子义选择+D限制性表述；不是原文解析丢片段。生成器已报Minor scope_gap，却用已限定展示视作可接受；E在风险处置/升级上不足，并非完全没检出。C5外部二审/父级裁定实际发现Major并停止 | 仪式；礼仪程序（宗教或非宗教）。[Collins](https://www.collinsdictionary.com/dictionary/english/ritual)及WN宽义支持。惯常行为/形容词仍独立，已知Major修复点通过新审查，未签审 |
| extend | s001伸展 → 只解释身体；原证据已有桌腿/布料/天线。s003空间/时间延伸不能替代s001主动展开 | C子义选择+D对象收窄+E把source ID出现误当用途覆盖。A解析与原文字符完整 | 伸展；展开（肢体或物体），注明可伸展物体与非排他例子；WN v01371528/v02058913及[Collins](https://www.collinsdictionary.com/dictionary/english/extend)支持。s002变宽保留held，未声称全词已核完 |
| scholar | 学习者；学者；文人未丢，选择理由却称最常用 | D无依据频率措辞+E理由字段检查遗漏；不是语义合并错误 | 仅改为AI教学选择，两模型仍漏报旧措辞，通用频率告警补检；不伪造客观频率 |
| contact | 源联系；接触、逐片段POSnull；旧动词注释使某物与另一物接触，绑定WN只描述直接接触 | D注释与具体引用方向不齐；E未逐引用核对。不能据WN局部条目断言整词不存在使动义 | 中性直接接触注释与WN一致。[完整Collins](https://www.collinsdictionary.com/dictionary/english/contact)American verb7/9确有使之接触；旧Minor保留但细化为引证精度，不把它伪造成语义负例 |

四项均没有发现原始片段解析损坏；不通过修改原文掩盖生成器限制。B分组不是两项范围Major的直接主因，F为C/D/E叠加。修订复用C5已有独立建议，建立V5快照并实际复核，没有为新措辞另做无必要生成。前后完整字段差异在revised_candidates.json中。

## 通用保护与自身缺陷

V4偏重源ID守恒、词性和引证存在，缺少同一源片段内部剩余范围、所有层级并集与反例检查。V5固定为先来源范围、再英语证据、最后候选；语义等价/合理概括/收窄/扩大/不匹配/不确定六类显式映射。减少同义展示不等于减少来源用途；不以字符串包含证明覆盖。

本轮发现自己的输入封包遗漏四词修订新增的两个已有出版社引用。原误报保留在calibration_after.json；EVIDENCE_RECONCILIATION.json明确复制真实已有观察后，另建reconciled_inputs并重审，不改冻结规则或旧结果。模型捏造引用ID、大小写级别、同值字段别名及缺失证明字段分开记录，未当语义成功。

## pursue 的真实状态

旧C5首响应与一次结构修复都回显输入，没有合格二审结果，状态仍review_incomplete_after_bounded_attempts。新查[Collins](https://www.collinsdictionary.com/dictionary/english/pursue)分别支持追求目标、追赶与从事活动；本轮Pro也实际返回审阅，但其moderate级别不合枚举，关于寻找/追求的判断与等价映射存在张力。新证据和新结果分开保存，未解除待对账、未将再次请求成功等同语义正确。

## 回归的新发现与边界

29个至少一次被模型提Major的词逐个证据裁定：新增确认范围Major 2（determine、sensitive），引证/映射Minor 6；其余21继续待核或否定该项错误断言。这里确认指父级AI对实际证据的裁定，不是人工签审。未逐项裁定的其他Minor/Info继续保留为提案。细节见PARENT_EVIDENCE_ADJUDICATION.json。

determine原决定被注释限为主动作选择，未覆盖因素决定结果，[出版社定义](https://www.collinsdictionary.com/dictionary/english/determine)与WN v00702806直接支持遗漏用途。sensitive原敏感的仅物理/机密两域；体察他人不是自己容易被冒犯，[出版社定义](https://www.collinsdictionary.com/dictionary/english/sensitive)证实独立非物理用途缺口。两个候选未在本轮擅自改写，已隔离，故不放行下一批。

相反，abstract/tender等显示文本并无只限某例的措辞，少挂一个synset是证据覆盖不足，不能自动升级为删除含义Major。held不是完整覆盖，但正确保留待核也不是新的静默删义。原POSnull未改、推荐组POS另记，检查器不能据此谎称源字段被覆盖。详见测试报告的误报分解。
''')
    md(OUT/'SCOPE_GUARD_TEST_REPORT.md',f'''# P6-C.5a 范围保护测试报告

规则V5哈希：`{ruleshash}`；验证前冻结门槛：`{fixedhash}`。没有在结果后改变门槛。规则/输入/提示词/原脚本封存见RUN_MANIFEST.json；补充引用和只读对账适配器另有清单。

## 完整回归

| 指标 | 数量 |
|---|---:|
| 既有候选/新增ID | 700 / 0 |
| 复用600/新100原义映射 | 1453 / 249 |
| 原文总片段 | 1702 |
| 实际首审 / 规范契约通过 | {len(p)} / {metrics['primary_strict_contract_words']} |
| 定向不同模型二审 / 规范契约通过 | {len(s)} / {metrics['secondary_strict_contract_words']} |
| 逐词Major提案证据裁定 | 29 |
| 本轮新确认Critical / Major / 引证映射Minor | 0 / 2 / 6 |
| 旧已知范围Major修复点 | 2 |
| 历史48待审保留 | 48 |
| 待人工复核（不解除旧状态） | {metrics['current_requires_human_review_count']} |
| 人工签审 | 0 |

700/1702都是实际保存的逐词逐义审阅，不是模板填充。首审700、二审124通过同值别名/级别字母大小写对账回收实际独立行；剩余1/5个规范缺陷仍标待核，未修改模型语义标签，原响应及其哈希保留。API原始整块结构验收失败不等于该块所有词语义无效；不能猜改错误稳定ID。22个源先盲提案中仅补空的可选观察数组并标未单报，未发明语义内容；constitute/determine的错误ID/内容不修复。

源范围关系为AI判定：`{json.dumps(dict(relation),ensure_ascii=False)}`。其中87条收窄不是87个确认错误；暂存、源中文偏宽、引证不足和新增限制须分别裁定。统计与每条源POS/文本/目标层/上下文/理由/证据/残余范围在regression_700.json，未知不当通过。

## 检出、误报与漏报

- 已知ritual/extend的s001在修前均被Flash识别收窄；Pro亦给出收窄，其中extend级别不同，不抹历史Major。修后两点均转等价/合理概括，无已证实扩大或POS错配；extend的变宽仍未知。
- scholar旧理由的无证据最常用被两个语义审查模型漏报。通用词频措辞告警修前命中{len(frequency['before'])}、修后命中{len(frequency['after'])}，只是风险线索，不声称正则证明或推断词频。
- contact不能用整个词无使动义作负例。新出版社证据支持使动用法；修订只让当前WN注释忠于绑定证据。两模型未报告旧引用精度疑点，不报告为已证实语义漏报。
- held的adopt/institute/ensure/clause/constitution/attach被提Major，但原先已显式隔离。记录未覆盖及待核，拒绝将保守暂存算新删义错误，也绝不将其视作通过。
- damage/transfer/comment/compromise/knock/dip/collapse的原逐片段POSnull仍null，推荐组词性不是篡改原文；真实词性归属继续待核，拒绝无依据的全部词性笛卡尔积。
- abstract/tender/reverse/demand显示仍宽、注释未排他；证据覆盖不足确认为Minor，不以synset个数代替含义完整性。represent的象征已在另一源ID的核心显示，是显式交叉映射缺口，不谎称全词象征被删。
- dismiss解散人群可兼容现有让人离开等注释，新的[出版社对照](https://www.collinsdictionary.com/dictionary/english/dismiss)支持；来源是否制度废止继续待核。condition使适应与英语习惯/训练边界待核。spread不是词频证据不等于不是词义依据。
- 29个Major提案词的实际裁定如下；其他自动Minor/Info未全部父级裁定，仍是风险。无全体人工金标准，不计算或虚报总体误报率/漏报率。留出发现determine表明旧低风险标记不足以放行；V5检查实际检出，不把它记成本轮检查器漏报。

| 词 | 证据裁定级别 | 实际边界 |
|---|---|---|
{dtable}

## 留出24词

在审查前按源POS、释义广度、语境线索和简单释义分层固定，旧600与新100各12，排除修复四词及已知校准词。来源/候选哈希固定，不以通过结果换样。22个先看来源+许可WN的Pro提案封存后，才提供候选作比较；另2源先失败保留，24词都有实际候选二审。盲提案本身不是金标准，constitution的构成被盲提案解释为建立行为也未自动采用。未出现至少2个留出确认同因Major，不能据此声称不存在系统性风险。

| 词 | 分层 | 源先 | 验证结果 |
|---|---|---|---|
{htable}

## 自动测试与数据保护

实际命令、退出码、输出尾部见TEST_EXECUTION.json。当前记录：`{json.dumps({k:v for k,v in tests.items() if k!='commands'},ensure_ascii=False)}`。Python覆盖通用范围状态路由、引用图缺失、错误ID拒绝、未知/held不能通过、中文包含不作证明，以及真实四修复/700/1702/旧48/旧600保护。Dart验证JSON、Unicode跨度、各层与POS可解析，无UI接入。

638个既存受保护文件哈希/个人DB旁文件元数据一致；不打开SQL连接、不调用Notion、不上传事件。重放结果：`{json.dumps(replay,ensure_ascii=False)}`。规则测试降低风险，不是形式化语义正确性证明。未建立人工金标准，不能从压缩率或模型置信度宣称质量准确率。
''')
    md(OUT/'QUALITY_GATE_REPORT.md',f'''# P6-C.5a 质量门槛结论

**B：仍有未解决问题，需要继续修正规则与逐词覆盖；不恢复批处理。** 本轮范围修复与700词验证已完成，不新增第701词，不发布，不处理剩余4632词。新范围保护有检出价值，尚不足以作为自动放行门槛。

## 固定门槛结果

验证前门槛哈希`{fixedhash}`；规则哈希`{ruleshash}`。执行期间没有静默变更。固定原文/原700/留出集合及提示词哈希见RUN_MANIFEST.json。

| 检查 | 实际结果 |
|---|---|
{gate_table}

不满足A：determine与sensitive仍有经实际源文、候选与词典对照确认的范围Major，不能因四个旧问题已修复就放行；引证覆盖/交叉映射6项Minor也待核。判C的固定系统性证据门槛未被证明：22份可用源先留出中没有至少2词确认同因Major，全700只确认2项剩余同因Major；其他Major提案有来源/POS/held或证据链误报，不能为达到数量而全算实错。两个剩余问题表明范围收窄仍会出现，B不等于否认风险或证明策略普遍可靠。

## 已完成与未决

- ritual恢复宗教/非宗教仪式范围；extend恢复肢体/可伸展物体范围，变宽仍held。两者在修前重现、修后实际审查，无覆盖旧700。scholar去掉无频率依据措辞；contact中性注释与WN相符，完整出版社条目支持整词的使动义，历史Minor只细化解释。
- 600旧词语义内容不变；新100完整249条源义检查；合计700个唯一ID、1702条原义映射。每条保留原POS/原文位置/目标层/上下文/关系/证据/残余疑点。字面守恒不冒充语义正确。
- 24固定留出、22源先提案、24候选对照；constitute/determine源先结构/ID失败未重映射，后续返回也未补称盲审完成。determine为留出确认Major；abstract为引证覆盖Minor，其他边界问题继续隔离。
- pursue旧二审失败和待对账保留；新词典证据与新Pro响应存在不合枚举/范围判断张力，未设通过。历史48和clause/management等旧隔离仍在。
- 本轮没有全量重新生成700词；只有四个已有修订在独立V5快照中验证。其余风险保留原候选并增加审阅/映射，不伪造V5重新生成成功。

历史48（全部继续原风险、待人工）：{h48}。

## 实际模型、失败与费用

首审请求/返回deepseek-flash；Pro源先盲提案与二审请求/返回deepseek-v4-pro，均为无旧会话历史的独立API上下文。不同模型标识确有返回，提供方实际权重/统计独立性无法证明；父级证据裁定仍为AI，没有人工签审。官方文档版本记录为DeepSeek-V4.1-Flash-1017 / DeepSeek-V4-Pro-0813，不伪装逐请求权重快照。

实际保存API响应{len(api)}，含未采用与一次结构修复：`{json.dumps(dict(totals),ensure_ascii=False)}`。每请求usage、实际返回模型、请求/响应哈希保留，推理全文/密钥不保存。实际账单费用不可取得，null；按[提供方峰谷/缓存价格](https://api-docs.deepseek.com/quick_start/pricing/)估算USD {round(lower,6)}～{round(2*lower,6)}，不是扣费账单。父级Codex用量/成本不可获取，null。

原始整块严格验收未完成行、一次结构修复、真实行对账、两条源先失败及所有引用/枚举异常均保留在api、reviews、failures和COLLECTED_*，没有无限重试、替换模型或模板填词。首审规范通过{metrics['primary_strict_contract_words']}/700，二审规范通过{metrics['secondary_strict_contract_words']}/124，其余有真实语义响应但不作规范通过。

## 交付与下一步条件

六份要求文件齐备：SCOPE_FAILURE_ANALYSIS.md、RULES_V5_SCOPE_GUARD.md、SCOPE_GUARD_TEST_REPORT.md、revised_candidates.json、regression_700.json、QUALITY_GATE_REPORT.md。另有冻结门槛、真实API/盲审/对账/证据/指标/测试/保护清单，脚本均在scripts/p6c5a。

后续只建议在现有700内处理determine/sensitive的剩余范围、补核引证/源POS/held边界，校准误报与scholar类理由漏报，再用同一固定门槛复验。不能通过关检查或把所有中文联想都补核心解决；也不能靠多一轮模型认可清历史风险。本轮结束，不执行这些后续任务，不恢复4632、不写Notion/SQLite或学习记录、不改正式UI/日语/数据库路径。
''')
    save(OUT/'PROTECTION_CHECK.json',protection)
    files=[q for q in (ROOT/'scripts/p6c5a').glob('*') if q.is_file()]+[q for q in (ROOT/'test/p6c5a').glob('*') if q.is_file()]
    save(OUT/'FINAL_EXECUTION_MANIFEST.json',{'files':{q.relative_to(ROOT).as_posix():sha(q) for q in files},
       'frozen_run_manifest_unchanged':True,'no_new_model_calls_in_reporting':True,
       'new_supplements_do_not_change_frozen_rules':True,'rule_hash':ruleshash})
    print('Reports finalized; decision B, no next batch. Metrics:',json.dumps({'API_responses':len(api),'confirmed':a['new_confirmed_regression_findings'],'human_pending':metrics['current_requires_human_review_count']},ensure_ascii=False))

if __name__=='__main__':main()
