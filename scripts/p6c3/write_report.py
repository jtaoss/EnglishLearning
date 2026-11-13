"""Render the quality gate report from saved, sealed/adjudicated artifacts."""
from prepare_review import ROOT, OUT, load


def cell(value):
    return str(value).replace('|', '／').replace('\n', ' ')


LABELS = {
    'previous_fix_present': '前轮修正已在',
    'known_addition_pending': '旧补充候选待决',
    'reserved_source_pending': '原文疑点已暂存，仍待核',
    'teaching_preference': '教学偏好差异',
    'confirmed_evidence_and_scope_minor': '确认Minor：用法证据/范围',
    'confirmed_current_core_gap': '确认Major：当前候选漏用法',
    'confirmed_source_coverage_gap': '确认Major：原文覆盖缺口',
    'source_warning_already_qualified': '现有候选已限定原文范围',
    'no_confirmed_issue': '本次未确认新问题（非人工通过）',
}


def main():
    review = load('docs/p6/p6c3/independent_quality_review.json')
    rev = load('docs/p6/p6c3/REVISED_CANDIDATES.json')
    result = load('docs/p6/p6c3/VALIDATION_RESULTS.json')
    tests = load('docs/p6/p6c3/TEST_EXECUTION.json')
    preservation = load('docs/p6/p6c3/preservation_check.json')
    base = load('docs/p6/p6c2/core_meanings_500.json')
    s = review['summary']; lines = []
    add = lines.append
    add('# P6-C.3 核心释义质量门槛报告\n')
    add('核验日期：2026-11-13。产物仅为隔离 AI 候选；未发布、未执行全量处理。\n')
    add('## 1. 结论：B，先修正规则并在现有500词验证，再扩容\n')
    add('**暂不直接进入剩余4,832词处理。** 42项旧Major全部复查，另抽48词；补充样本发现1项当前候选的重要用法遗漏和1项原文覆盖缺口。两者都还没有正式采用解决方案。原文片段全部覆盖并不能证明英语用法覆盖完整。\n')
    add('- **不选A**：`import` 的贸易动词未明确保留，`management` 的人员义在原材料与现有分层均未表达；不能只看压缩率或旧风险标签放行。')
    add('- **选择B**：问题集中于“原片段一次分配”与“原文之外重要用法检查”；已有局部修订和V4规则，可以在现有500内验证。')
    add('- **不选C**：本轮没有证据证明整套核心提炼方法整体失效，也未确认批量错译、原文丢失或稳定ID损坏。90词不是全500的重新盲审，更不能据此断言全库无缺陷。\n')
    add('## 2. 实际输入与审查范围\n')
    add('已读取C2的500词JSON、试点报告、高风险报告、质量指标，以及C1 RULES_V3。结构以实际文件为准。正式词库为5,332词；旧100与新400均保留。\n')
    add('| 项目 | 数量 | 含义 |\n|---|---:|---|')
    rows = [
        ('既有数据集',500,'原100+新增400，均未改写'),
        ('定向复查',42,'新增400中全部旧Major标记，不等于42个确认错误'),
        ('额外分层抽检',48,'新400非Major抽40，旧100 standard抽8'),
        ('源先行盲审总数',90,'90个不同正式稳定ID，两个任务各45且不相交'),
        ('本轮审查原文片段',221,'保持全部完整文本及映射'),
        ('本轮没有重新语义审查',410,'保持旧状态，不自动通过'),
        ('本轮修订候选',3,'import、management、indicate；新文件，不覆盖旧500'),
    ]
    for a,b,c in rows:add(f'| {a} | {b} | {c} |')
    add('\n固定配额内按SHA256(`p6c3:分层:stable_id`)排序，不按置信度挑词。旧100子样本覆盖其standard池中可用的原书分类。原书分类只用于抽样记录，不推断义项频率。\n')
    add('| 分层 | 池大小 | 抽取 |\n|---|---:|---:|')
    for k,v in review['selection']['sample_strata'].items():add(f"| {k} | {v['population']} | {v['sample']} |")
    categories = {}
    for r in review['records']:categories[r['book_category']] = categories.get(r['book_category'],0)+1
    add('\n本轮90词原书分类：'+ '；'.join(f'{k} {v}' for k,v in categories.items())+'。分类不是英语义项的使用频率证据。\n')
    add('## 3. 独立性、证据与局限\n')
    add('两组审查使用fresh fork-none上下文，配置模型为`gpt-6-astra`。先给原词头、词性、原始中文和未按旧结论筛选的合法WordNet3.1定义，不给旧核心/风险/Major标签/旧评审意见；每15词保存检查点，45词提案封存哈希后才由父上下文对照旧候选。封存后没有回填旧结论。父上下文裁定不是第三次盲审。\n')
    add('**未完成可证明不同后端身份的跨模型验证**：原生成后端ID未暴露；复核配置名不能证明它必然不同于原后端。新上下文盲审真实完成，但不同后端模型分歧数记为`null`。两个45词任务没有同词重叠，也不能计算同词双审者一致率。\n')
    add('原文件的项目版本标签也原样记录：旧100词`model_version=p6c1-independent-ai-review-1`、`prompt_version=p6c-prompt-2 + p6c1-RULES_V3`；新400词`model_version=codex-session/p6c2-semantic-v4`、`prompt_version=p6c2-rules-v4`。这些是项目标签，不是可证明的后端模型身份。本轮`P6C3/RULES_V4`是基于C1 RULES_V3增补的质量标准，与C2自身的`p6c2-rules-v4`标签分开。\n')
    add('WordNet3.1使用项目已有许可；逐定义原文、归属词头和哈希均已校验。出版社网页只保存自写的短中文观察与URL，不复制整页/商业例句。共记录17次403：两审者各8次，父上下文reference页1次；均未把失败页当成功证据，使用已许可WordNet和可访问出版社作替代，未绕过。记录见`publisher_observations.json`及审查JSON。\n')
    add('两项独立审查任务、六个15词检查点不等于API调用次数；实际token、计费和精确后端快照均不可见，记录为null，不估造金额或零成本。裁定仍是有词典依据的AI判断，不是人工金标准、随机准确率或学习效果实验。\n')
    add('## 4. 确认问题与原标记的区别\n')
    add('| 指标 | 数量 |\n|---|---:|')
    metrics = [
        ('证据支持的问题：Critical',0),('证据支持的问题：Major',2),('证据支持的问题：Minor',1),
        ('确认的原文错译断言',0),('当前候选重要用法遗漏',1),('新确认原文重要用法覆盖缺口',1),
        ('确认词性混淆',0),('仅教学层级/展示偏好词',s['preference_only_words']),
        ('盲审与旧候选分层/POS/来源划分不同',s['fresh_blind_proposal_partition_disagreement_words']),
        ('其中核心原片段集合不同',s['fresh_blind_proposal_core_membership_disagreement_words']),
        ('字面显示或顺序不同',s['literal_display_or_order_difference_words']),
        ('尚未关闭的本轮Critical/Major',s['unresolved_C3_Critical_or_Major_findings']),
    ]
    for k,v in metrics:add(f'| {k} | {v} |')
    add('\n40项分层差异、28项核心片段集合差异、78项字面/顺序差异是定位指标，不能相加或改称40/78处语义错误。19词只属教学偏好；其他“已限定、旧候选、暂存”也不因此算当前错误。未确认错译/词性混淆并不等于证明全库不存在。\n')
    add('### 4.1 三项实际裁定与新候选\n')
    add('1. **C3-001 import — Major，当前候选用法遗漏**。旧核心把“进口”只分给名词并引用进口品，动词“输入”又限定为数据；贸易动词没有显式保留。新候选让同一原片段`s001`分别对应贸易动词和名词行为，以`semantic_splits`说明这是AI用法拆解而非新增原文。数据导入后学，进口品单列候选，不升核心。WordNet `v:02351132`（从国外引入）、`v:02237504`（数据导入）、`n:03569847`（进口品）相互有别；出版社也分别支持贸易动词、名词行为与进口品。[Collins import](https://www.collinsdictionary.com/dictionary/english/import)。\n')
    add('2. **C3-002 management — Major，原文覆盖缺口**。原“指导/指挥/管理”及旧分层都描述管理活动，不能表达管理人员群体。WordNet `n:01135602`为活动，`n:08397896`为负责经营的一群人。新候选只新增“管理层”词典候选，旧核心/扩展不变；**不是两处原文错译中的一处**。该用法重要性是职场理解的教学裁定，存在性与概念区别有词典证据，未声称语料频率。[Collins management](https://www.collinsdictionary.com/dictionary/english/management)。\n')
    add('3. **C3-003 indicate — Minor，用法证据与中文范围**。旧“指出/指示”组引用指向对象和简要陈述的词典项，缺少为信号表明读法对应的引证，短显示也未排除发命令的中文歧义。新候选按对象/信号/陈述给出提示，保留原片段，`s002`的重复引用显式声明AI拆解，原`s001`继续暂存。不是判定原中文完全错误。具体WordNet引用与新旧差异见JSON。[Merriam-Webster indicate](https://www.merriam-webster.com/dictionary/indicate)。\n')
    add('`REVISED_CANDIDATES.json`为3词的新版本，保存完整原文、原字段、稳定ID、原/候选哈希、逐字段before/after和审查来源。`human_approved=false`、`adopted=false`。生成候选不等于问题已关闭；本轮没有把词典补充自动放入原文核心。\n')
    add('### 4.2 原42项Major的主处理状态（互斥，总数42）\n')
    add('| 主状态 | 词数 |\n|---|---:|')
    for k,v in s['target_42_primary_dispositions'].items():add(f'| {LABELS[k]} | {v} |')
    add('\n该42词中本轮确认0 Critical、0 Major、1 Minor；不表示其余41词全部合格。19词的来源语境仍未解决，17词的旧补充仍待采用裁定。`benefit`的施受方向、`stewardess`的范围、`core`果核限定等已有修正不能再计旧错误；`committee`、`cultivate`的usage_note亦须一并读取。\n')
    add('### 4.3 抽检漏报\n')
    add('48词额外样本中发现2项Major，均原为`Minor/high`：import、management。它们揭示旧审查严重度没有充分反映用法覆盖风险。**不称为“2个原standard低风险漏报”**：严格standard子样本24词没有确认问题；剩余24词属于其他非Major的high风险分层。本次配额和高风险过采样不支持外推总体准确率或错误率。`nuclear`盲审Major针对未限定原文，旧候选已有核能/原子核限定，故不计新的Major；`planet`当前并未引用含九大行星的旧WordNet项，也不转计当前错误。\n')
    add('## 5. 保留的待审与补充候选\n')
    add(f"- 旧100词高风险/暂存 **{s['inherited100_unresolved_high_or_reserved']}词** 继续待审；没有因未抽到或旧文件被继承而通过。")
    add(f"- 原500词宽泛high风险标签 **{s['original500_broad_high_risk_tags_retained']}词** 保留。这是旧风险标签，不是342个证实错误或342个Critical/Major。")
    add(f"- 具体优先待处理集合 **{s['focused_pending_priority_words_union']}个不同ID**：旧48词、所有原文暂存词、旧核心层补充建议词、本轮2个Major的并集；不是85个新错误，原因逐词见JSON。")
    add(f"- 原55条词典候选完整保留；其中23条/22词原建议核心层，仍未采用。盲审重新提出的26条与旧候选相同，另3条其实已在现有组/证据范围，不重复当作新缺口。")
    add(f"- 本轮另发现 **{s['new_addition_proposals_not_auto_adopted']}条/{s['new_addition_words']}词** 新候选，包括management管理层；其余多为扩展或范围提示，不能全部改称重要遗漏。所有候选继续单列、无人工签审。\n")
    add('旧48词待审名单：'+ '、'.join(r['headword'] for r in review['inherited100_pending_queue'])+'。具体原因沿用原文件/选择台账，未重复生成旧审查结论。\n')
    add('| 新候选词 | 内容 | 状态 |\n|---|---|---|')
    for a in sorted(review['new_dictionary_candidates'],key=lambda a:a['headword']):
        add(f"| {a['headword']} | {cell(a['blind_proposal']['meaning_zh'])} | {a['disposition']}；未采用 |")
    add('\n## 6. 验证、不可变性及共享工作区\n')
    add('本轮脚本不连接SQLite或Notion、不写学习状态、不下载商业音频、不运行原词书OCR、不改正式UI。字节哈希和DB side-file元数据核对英语源文件、旧100/C1、旧500/C2、正式CSV及个人数据库。原数据保持不变，修订仅另存。\n')
    add('| 实际检查 | 结果 |\n|---|---|')
    add('| 5332正式ID、原字段canonical hash、500输入哈希 | 通过 |')
    add('| 42+48范围、90盲审记录/221片段及封存提案 | 通过 |')
    add('| 3词/8个唯一原片段、完整before/after、一对多映射注释 | 通过 |')
    add('| 原文/POS/稳定ID/旧候选状态、外部补充隔离 | 通过 |')
    for t in tests['runs']:
        add(f"| `{cell(t['command'])}` | exit {t['exit_code']}；{t.get('tests','—')}项；{cell(t['result'])} |")
    add('\nPython共13项，包括篡改原文、错误词头引证、缺少重复映射解释、伪造人工通过、外部义挂原文ID等反例拒绝测试及待审并集校验。Dart/Flutter共9项（原C2四项+C3五项），仅验证数据解析/契约；未发布或启动正式背词UI。初次unittest同名模块导入问题已修复，最终13项通过。测试记录见`TEST_EXECUTION.json`，数据校验记录见`VALIDATION_RESULTS.json`。\n')
    add('共享工作区观察到别的日语/应用设置工作，当前分支为`'+preservation['git_branch_observed']+'`，HEAD `'+preservation['git_HEAD_observed']+'`。本轮没有切换分支、回退或改写这些文件；`preservation_check.json`单列外部变化，不以“全工作区不变”作虚假保证。保护范围内英语词库/个人数据库无变动。没有Git提交、合并或推送。\n')
    add('关键输入SHA256：\n')
    add('```text\ncore_meanings_500.json '+review['input_dataset']['sha256']+'\nformal_learning_vocabulary.csv '+preservation['before']['docs/p5a/public/formal_learning_vocabulary.csv']['sha256']+'\n```\n')
    add('原1,216个中文片段、688个核心展示组及平均2.432/1.376均未更改；本轮没有把压缩数字作为质量门槛。\n')
    add('## 7. 下一次扩容前的验收条件（本轮不执行）\n')
    for n,c in enumerate(review['quality_gate']['release_conditions'],1):add(f'{n}. {c}')
    add('\n需保留人工/专家可裁定的争议清单；当前human_approved仍为0。质量门槛不是要求初学用户为所有专业问题背书，而是不能伪造已经签审或用AI自信分数替代依据。\n')
    add('## 8. 复现与文件\n')
    add('重建只使用已保存的原材料与裁定，不发起模型或词典请求：\n')
    add('```powershell\npython -X utf8 scripts/p6c3/seal_blind_reviews.py\npython -X utf8 scripts/p6c3/build_quality_review.py\npython -X utf8 scripts/p6c3/validate.py\npython -X utf8 -m unittest discover -s test/p6c3 -p "test_*.py" -v\npython -X utf8 scripts/p6c3/write_report.py\n```\n')
    add('私有source-only输入包由`prepare_review.py`创建并与封存哈希绑定；已有包不覆盖。重建提案本身需要真实独立审查，不能由组装脚本生成模板替代。输出四文件为`independent_quality_review.json`、`QUALITY_GATE_REPORT.md`、`REVISED_CANDIDATES.json`、`RULES_V4.md`；附封存盲审、选择台账、前后哈希、证据观察、测试记录。\n')
    add('## 9. 逐词对照台账（90词，非人工通过名单）\n')
    for role,title in [('target_major','原Major42词'),('stratified_audit','其余分层48词')]:
        add('### '+title+'\n')
        add('| 词头 | 旧严重度/风险 | 本轮主状态 | 对照理由 |\n|---|---|---|---|')
        for r in sorted((r for r in review['records'] if r['selection']['role']==role), key=lambda r:r['headword']):
            a=r['adjudication']; sel=r['selection']
            add(f"| {r['headword']} | {sel['prior_severity']} / {sel['prior_risk']} | {LABELS[a['disposition']]} | {cell(a['reason'])} |")
        add('')
    add('完成P6-C.3后停止：未开始剩余4,832词，也未正式发布修订。\n')
    (OUT/'QUALITY_GATE_REPORT.md').write_text('\n'.join(lines),encoding='utf-8')
    print('QUALITY_GATE_REPORT.md written; decision B; 90 per-word adjudications.')


if __name__ == '__main__':
    main()
