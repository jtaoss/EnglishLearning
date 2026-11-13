"""Reports derived from actual saved outputs; no model calls or source writes."""
from common import *

def main():
    data = read(OUT/'core_meanings_5332_candidates.json')
    m = read(OUT/'QUALITY_METRICS.json')
    cp = read(OUT/'BATCH_CHECKPOINTS.json')
    manifest = read(OUT/'RUN_MANIFEST.json')
    rows = data['records']
    def write(name, text):
        (OUT/name).write_text(text.rstrip()+'\n',encoding='utf-8')
    risk = ['# P6-C.5 风险隔离清单', '',
            '风险标记不是证据支持的错误；全部记录仍为AI候选。纯教学偏好和未采用外部观察不计确认错误。', '',
            '| Stable ID | 词头 | 状态 | 风险/待审原因 |', '|---|---|---|---|']
    for r in rows:
        if r['needs_human_review'] or r.get('quarantine'):
            reasons = '; '.join(f"{f['severity']}:{f['code']} — {f['reason']}" for f in r['risk_flags'])
            if not reasons:
                reasons = '既有AI候选未人工签审，原待审状态保留。'
            risk.append(f"| {r['stable_id']} | {r['headword']} | {r['review_status']} | {reasons.replace('|','/').replace(chr(10),' ')} |")
    write('HIGH_RISK_WORDS.md','\n'.join(risk))
    lines = ['# P6-C.5 全量核心中文释义候选报告', '',
             f"结论 **{m['decision']}：存在系统性质量问题，停止后续处理**。全量目标未完成。实际合并候选 {len(rows)}/5,332（复用600 + 本轮新生成100）；剩余 {len(data['missing_ids'])} 未生成。首批结构检查可通过，语义放行未通过，所有结果隔离保存。", '',
             '## 输入、分组与冻结', '',
             '按实际稳定ID核对A=原500、B=独立盲测100、C=其余4732，互不重叠，无重复/额外ID。旧600的所有原文快照与正式29字段一致。', '',
             f"V4.1规则哈希：`{manifest['rules_hash']}`。正式清单哈希：`{manifest['formal_input_sha256']}`。执行配置与提示词文件哈希见 RUN_MANIFEST.json，规则从未静默替换。", '',
             '## 复用与生成', '',
             'A复用C4独立回归候选；B复用C4盲测经保守处置候选。C2/C3/C4原文件完整保留，每条带来源文件哈希及源记录/候选哈希。旧48个历史风险继续待审。management人员义与clause语法上位概念没有自动采用。', '',
             f"48个计划批次中保存了 {cp['completed_batch_count']} 个结构检查点，语义门槛通过 {cp['semantically_accepted_batch_count']} 批；实际新生成 {cp['validated_new_records']} 词。第2批及以后未启动。每100词为检查点；成功原始输出不可覆盖，失败不填模板、不换未经验证模型。", '',
             f"实际冻结模型：`{manifest['requested_model']}`，thinking={manifest['thinking']}，effort={manifest['reasoning_effort']}。官方文档标注快照 `{manifest['provider_documented_snapshot']}`，API未返回精确部署快照，不能视为逐请求快照证明。", '',
             '预检失败、证据补充与最终模型采用过程见PREFLIGHT_ADJUDICATION.json；预检费用包含在实际API统计内，不隐藏失败或声称旧600重新生成。', '',
             '## 停止原因与证据裁定', '',
             '冻结的停止标准是同批出现至少2个同因、经证据裁定的Major。首批ritual与extend满足该条件；本轮只提独立修订，不改变冻结规则后继续扩量。', '',
             '| 词 | 已确认级别 | 实际问题及待确认修订 |', '|---|---|---|',
             '| ritual | Major | 源“仪式”被限成宗教程序，普通正式仪式未在该源用法的层级/暂存中覆盖。候选修订撤去宗教专有限制；[Collins](https://www.collinsdictionary.com/dictionary/english/ritual)同时涵盖宗教与其他仪式。 |',
             '| extend | Major | 源“伸展”被限成身体部位，已提供WordNet中的折叠桌腿、布料、天线等主动展开对象未覆盖。修订放宽为肢体或可伸展物体；[Collins](https://www.collinsdictionary.com/dictionary/english/extend)与具体WN证据支持该范围。 |',
             '| scholar | Minor | 选择理由无义项频率证据却写“最常用”；修订只改为AI教学建议。 |',
             '| contact | Minor | 接触动词注释误加“使某物……”使动方向，所引WN证明直接接触状态/动作；修订注释。 |', '',
             '新确认2 Major +2 Minor，Critical确认0。未把全部模型标签当错误：render仍证据待核；restore为逐片段引证范围待核；attach情感用途为外部候选建议，未自动计确认Major。详见PARENT_ADJUDICATION.json、REVISED_CANDIDATES.json。4词独立修订均未覆盖封存生成结果或替换活动合并候选。', '',
             '低风险池14词，固定哈希抽2词（spouse、persuade），先给原文与证据、不提供生成答案。未确认漏报错误；persuade合一组或按信念/行动分两组是教学差异。目标二审88词，实际完成87；pursue原响应回显输入，唯一允许的修复仍不符合契约，明确保留审查失败，不再重试。', '',
             '## 质量统计（实际700词）', '', '| 指标 | 数量 |', '|---|---:|']
    for label, key in [('实际候选','record_count'),('原文片段总数','source_original_fragment_total'),
                       ('A 原始片段平均数','A_original_fragment_average'),('B 首次核心义组平均数','B_first_memory_core_group_average'),
                       ('核心义组最大数','core_groups_max'),('超过3组词数','more_than3_core_words'),
                       ('无可靠核心/证据不足','empty_core_evidence_insufficient_words'),('词典补充候选','dictionary_addition_candidates'),
                       ('保留的独立词典观察','dictionary_observations_kept_separate'),('需要人工复核','needs_human_review_words'),
                       ('风险隔离词','candidate_quarantine_words'),('历史48待审','historical48_retained'),
                       ('新词定向二审','targeted_second_reviewed'),('低风险source-first抽检','source_first_lowrisk_sampled'),
                       ('二审失败词数','second_review_failed_words'),('纯教学偏好词数（新增批）','pure_teaching_preference_words_new_batch'),
                       ('人工签审','human_approved_count')]:
        value=m[key]
        lines.append(f'| {label} | {value:.6f} |' if isinstance(value,float) else f'| {label} | {value} |')
    for title,key in [('分组统计（新模型仅处理C中的100词）','cohort_metrics'),('处理状态','states'),('原书分类','book_category_counts'),
                       ('自动AI风险标记（不是确认错误）','AI_risk_flags_by_severity'),
                       ('二审提出问题（未经逐条证据裁定不算确认错误）','AI_second_review_proposed_findings_by_severity_NOT_confirmed_errors'),
                       ('历史证据支持问题','confirmed_historical_problem_severity'),('本轮新增证据支持问题','confirmed_new_problem_severity')]:
        lines += ['',f'### {title}','','```json',json.dumps(m[key],ensure_ascii=False,indent=2),'```']
    lines += ['', f"上述候选均值分母为实际700词。正式5332原文片段平均数为 {m['A_formal5332_original_fragment_average']:.6f}（只读解析原文，不代表生成）；全5332核心组均值不可计算（null）。未处理4632词不填模板。", '',
              '压缩数字只描述展示，不证明学习效果、释义准确率或官方考试义项频率。源外新义全部独立存放，未自动升级核心。所有已生成/复用词的原文片段、Unicode位置、一对多拆解说明保留。', '',
              '## 独立性、失败与成本', '',
              '本轮生成请求与返回为deepseek-flash，二审请求与返回为deepseek-v4-pro；不同模型标识及官方文档版本均有记录，提供方内部实际权重/统计独立性无法自行验证。二审采用无历史API上下文，低风险样本不提供生成答案，定向二审收到候选。AI意见与证据支持错误分别存储。', '',
              f"保存的实际API响应：{m['actual_API_responses_saved']}。实际用量：`{json.dumps(m['actual_API_usage'],ensure_ascii=False)}`。实际账单费用不可获得（null）；按官方缓存/峰谷价格估算USD范围：{m['cost_estimate_USD_range']}，不是实际扣费。", '',
              'API费用估算仅含实际DeepSeek请求，按各请求返回模型分别计价，包含失败/未采用的预检与重试。当前Codex父会话的用量及费用不可获取，均为null。历史48仍为high待审，不将它们重新评为48个Major；新增Info台账提醒不解除原high风险。', '',
              f"失败记录：`{json.dumps(m['saved_failures'],ensure_ascii=False)}`。成功输出原样缓存，重跑整合不会重新调用模型。", '',
              '## 安全、测试与后续门槛', '',
              '正式5332原文、旧500及盲测100文件、个人SQLite及其旁文件均仅做哈希读取；脚本不建立SQL连接、不请求Notion、不上传事件、不改UI/日语模块/数据库路径。', '',
              '自动化验证结果见VALIDATION_RESULTS.json、TEST_EXECUTION.json和REPRODUCIBILITY.json。数据契约通过不等于全量数量验收或语义放行；full5332_count_passed=false。旧证据未全部内嵌lemma列表，旧暂存可仅引用ID，验证器采用原许可词头证据目录与完整原文表核对，没有改写旧成果。', '',
              '输出文件名按任务保留core_meanings_5332_candidates.json，内部record_count=700、generation_complete=false、missing_ids=4632条。风险台账覆盖实际700词，不能称已审完5332。', '',
              '下一阶段先修正模型执行中的通用范围覆盖检查，使用本批100词及旧600回归验证，再评估是否恢复剩余4632词；当前不建议直接继续全量或进入正式发布审核。停止后没有新的模型调用。']
    if (OUT/'TEST_EXECUTION.json').exists():
        tests=read(OUT/'TEST_EXECUTION.json')
        lines += ['', '## 实际测试执行', '',
                  f"Python唯一测试 {tests['unique_Python_tests_passed']} 项，Dart/Flutter唯一契约测试 {tests['unique_Dart_Flutter_tests_passed']} 项通过；新增测试文件静态分析无问题。重复整合字节一致。数量验收未通过，语义结论仍为C。", '',
                  '| 检查 | 结果 |', '|---|---|']
        for t in tests['checks']:
            lines.append(f"| `{t['command']}` | exit {t['exit_code']}；{t['scope']} |")
    write('P6C5_FULL_CANDIDATE_REPORT.md','\n'.join(lines))
    write('RELEASE_READINESS.md',f'''# P6-C.5 未来发布条件评估

本轮数据处理结论：**{m['decision']}**。**正式发布状态：不就绪、未授权、未执行。**

- 首批出现2个同因、经证据裁定的Major，已触发冻结停止条件；第2批未启动。先修正模型执行方式并回归，不直接恢复剩余4632词。
- 实际候选 {len(rows)}/5332；缺失 {len(data['missing_ids'])}；没有可靠核心的词 {m['empty_core_evidence_insufficient_words']}。
- pursue二审失败仍保留；4词独立修订尚未采用。结构测试通过不代表全量数量验收或语义门槛通过。
- 结构、稳定ID、原文追溯、历史48风险及management/clause隔离状态必须通过数据契约。
- AI风险标记、二审意见、证据支持的错误及教学偏好必须继续分开。逐条处理高风险和二审分歧，补充必要出版社/语料证据，不能拿模型自信当准确率。
- 历史48和尚未采用的来源修订继续待审；词典补充候选不能随合并自动进入核心。
- 所有候选 human_approved=false；不得因自动检查通过设置人工签审。发布前确定真实签审/抽检责任与可回退版本。
- 发布前另做只读映射预览、个人状态保护、SQLite/Notion同步影响验证，并取得接入正式数据/页面的单独授权。

本轮没有修改正式5332词、个人SQLite、Notion、学习进度、Flutter UI或日语模块，也没有发起任何发布动作。
''')
    print('Reports written from actual outputs; decision',m['decision'])

if __name__=='__main__':
    main()
