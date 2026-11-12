# EnglishLearning · P6-C.1 核心释义独立质量复核报告

日期：2026-11-12（Asia/Shanghai）。本轮仅复查现有100词，生成独立附加版本；原P6-C结果、正式CSV及个人数据库保持不变。

**100词均已完成本轮证据驱动的AI资料复核。33词建议调整分层或展示，15词保留原分层但另列补充候选，52词保留并补上逐义证据/教学说明。这不是33词被判错，也不是人类裁定的准确率。**

## 1. 输入、Git状态与独立性

首先检查到Git为 `main...origin/main`，已有上一轮6个tracked修改及多项未跟踪P6-C成果。没有stash、回滚或覆盖它们；仓库无 `.codegraph/`，按项目约定直接阅读文件。此次只新增 `docs/p6/p6c1/`、`scripts/p6c1/` 与本报告。

已读取原[P6-C报告](P6C_CORE_MEANINGS_PILOT_REPORT.md)、[100词JSON](p6c/core_meanings_pilot.json)、[复核工作表](p6c/REVIEW_WORKSHEET.md)，并与正式CSV逐条核对稳定ID、词头、词性、中文及29字段源哈希。

当前文件实际为：100条、100个唯一ID；旧高风险48、旧standard 52；人工台账100条pending、0条approved。正式CSV仍是5,332词，SHA-256 `508007c44f272f71df0ed918f17c006b263a1320fef1ada48e411a6aed3ba619`。没有把上轮报告数字未经验证地当作事实，也没有把用户未提出修改计为人工签审。

原提炼JSON的逐字节冻结副本为 [input_p6c_snapshot.json](p6c1/input_p6c_snapshot.json)，SHA-256 `46e2dd5e572a76789e3c81439708fbfd77373dc0865c08469f7275a601607851`。原文的263个文本解释片段全部保留。这些片段不等于263个经过语言学确定的英语词义。

复核版本为 `p6c1-independent-ai-review-1`。独立性指**独立文件、独立规则和逐义证据映射**：未重跑原提炼器作自证。仍是同一Codex AI会话，已见过原稿，属于非盲审；不冒充第二个独立模型或人类审稿人。精确后端模型ID未暴露，因此不捏造模型快照。

## 2. 证据来源与局限

本轮从项目合法的 [WordNet 3.1参考](p6c/wordnet_evidence.json) 中逐个挑选与中文解释有关的synset，替代旧稿“挂全部同词性义项”的粗粒度引用。引用267个相关synset，另有19条正规词典网页观察，共286个证据条目，见 [evidence_catalog.json](p6c1/evidence_catalog.json)。WordNet文本按 [现有许可](../../assets/vocabulary/WORDNET_3_1_LICENSE.txt) 保留来源。

网络补证采用Cambridge和Collins。若干Cambridge直接读取返回403，已如实记录；使用搜索工具返回的公开索引摘要进行有限补证，不声称看过当日完整页面，不绕过限制或批量抓取。Collins的abstract和flush实际直接读取成功。只保存短篇原创中文概述和URL，没有复制大量受版权保护的定义或例句。

关键判断的证据示例：

| 判断 | 支持证据 | 能支持与不能支持的范围 |
|---|---|---|
| notify不另教为吸引注意 | WordNet `v:00875364`；[Cambridge notify](https://dictionary.cambridge.org/dictionary/english/notify) | 支持通知/告知；不据词典未列出便断言任何句子绝不能转述为使注意 |
| couple不限于已婚夫妇 | WordNet `n:08005299`；[Cambridge couple](https://dictionary.cambridge.org/dictionary/english/couple) | 支持伴侣范围更宽；夫妇仍是有效子集，不是捏造义 |
| chop可并列显示但子义不能抹平 | WordNet `v:01259737`、`v:01260655`；[Cambridge chop](https://dictionary.cambridge.org/dictionary/english/chop) | 砍与切成块有词义区别；并列在一个记忆单元是教学建议，不是宣称完全同义 |
| abstract提取不是虚构义 | [Collins abstract](https://www.collinsdictionary.com/dictionary/english/abstract) | 有正式取出/提取语境；不据此提高首次学习优先级 |
| reverse倒车不是词性错误 | [Cambridge Learner’s reverse](https://dictionary.cambridge.org/dictionary/learner-english/reverse) | 支持驾驶车辆后退；原文另一个名词倒退指向仍未确定 |
| flush名词冲水需另证 | [Collins flush](https://www.collinsdictionary.com/dictionary/english/flush) | 动词冲马桶后明确列可数名词用法，不仅靠WordNet的广义水流推断 |
| priority缺少具体优先事项 | [Cambridge priority](https://dictionary.cambridge.org/us/dictionary/english/priority?topic=important-and-essential-things) | 证明该用法存在；不是PETS官方高频证明 |

所有记录包含来源名称、URL/本地路径、义项ID、词性/定义或短概述及对应结论。局限也保留：例如garbage所选WordNet定义偏厨房食物垃圾，不能拿窄定义去否定中文垃圾的宽泛日常用法。

没有使用原书PDF的新页码、重新OCR、未取得的语料命中数或精确考试概率。`illustrative_collocations` 是本轮编写的教学搭配/例示，不冒充真实语料例句或使用频次。PETS-3适用性只是依据阅读、交际、表达场景作出的教学判断。

## 3. 逐词结论与分布

完整结果：[independent_review.json](p6c1/independent_review.json)；便于查看的100词对照：[REVIEW_COMPARISON.md](p6c1/REVIEW_COMPARISON.md)。每词有八项检查、首次记忆理由、搭配例示、逐义证据、修订层级、原文疑点及来源外候选。

| 复核结论 | 旧高风险 | 旧standard | 总数 |
|---|---:|---:|---:|
| 原分层保留，补证据和说明 | 16 | 36 | 52 |
| 调整层级/措辞/显示 | 17 | 12 | 29 |
| 原分层保留，另列补充候选 | 11 | 4 | 15 |
| 修订并保留原文歧义/语境项 | 4 | 0 | 4 |
| 合计 | 48 | 52 | 100 |

旧standard的52词也全部复核，其中12词调整显示/语境、4词有补充候选，不能因为旧风险低就略过。表中“原分层保留”的52与旧standard的52只是总数恰好相同，不是同一组词。

问题标签可重叠，统计的是AI提出的审阅事项而非裁定错误：教学优先级调整8词、语境/译义范围10词、原文独立义或意图不明4词、相关子义展示优化5词、冗长近义中文显示4词、词性推荐1词、参考覆盖局限1词。另有22词的26个补充候选。

原词范围内的核心显示单元从141变为139，仅少2个。**没有把显示单元变少当作质量指标**：有的词应减少重复，有的词应增加重要入口，例如get补上已有原义理解，核心保留4组。

## 4. 明确修订与保留的区别

### 4.1 译义、语境和词性

- **notify**：优先通知/告知，并给出宾语与介词结构；原使注意完整保留在暂存区，不作为独立“吸引注意”义教学。
- **engage**：从事与从事于压缩显示为从事/参与活动，说明engage in。实行单独暂存，不能泛化成任意实行政策；聘用、吸引兴趣作为来源外候选。
- **obvious**：核心为明显/显而易见。无疑的可属于特定句子的中文转述，放语境备注而不是另造一个“确定无疑”义项。[词典依据](https://dictionary.cambridge.org/dictionary/english/obvious)。
- **knock**：推荐动词敲/撞击，有英语动词义支持；原中文没有逐义词性标签的事实不变。名词敲击声/一次敲击另列候选，不能谎称已查清原书排列。[参考](https://dictionary.cambridge.org/dictionary/english/knock?topic=sounds-made-by-objects-movement-or-impact)。
- **quarter**：裸地区收窄显示为城镇的区，不扩大成任意地域；25分硬币候选明确美国/加拿大货币语境。
- **carve**：切开补上切肉等场景，避免理解为任意打开物体；英语参考实际含切肉例示。
- **tone**：先学交际语气；声音品质、音高/声调与色调分场景，不把音色都误当音高。[参考](https://dictionary.cambridge.org/dictionary/english/tone)。
- **payment**：报酬只是支付款项的一种语境；支付行为之外的钱款义另列候选，不把所有payment都译成劳动报酬。[参考](https://dictionary.cambridge.org/dictionary/english/payment)。

### 4.2 近义压缩与不同用法并列

imitate显示模仿/仿效，remarkable不重复列值得注意和值得注目，obesity显示肥胖（症），ability减少能耐等中文显示负担；每处原文仍能通过原片段ID找到。

chop、consumption、extension、minor、correlate使用 `distinct_uses_explicitly_preserved`：**只在记忆展示层并列，下层仍保存各自原文、证据和差别**。如消费商品/服务与消耗资源不是处处等义；相关与使相互关联保留及物/不及物方向。不能反过来把旧稿的分组一概说成词典错误。

major三个词性仍分开；bank银行/河岸、miss错过/想念、light光/灯/轻的仍保留独立入口。用户举的issue、charge、address是审查原则示例，不在原100名单，本轮没有给这些词生成结果。

### 4.3 4个保留项没有被删掉

| 词 | 原文片段 | 当前处理 |
|---|---|---|
| notify | 使注意 | 暂存；不支持作为另一个吸引注意义独立背诵 |
| engage | 实行 | 暂存；中文搭配范围不明 |
| reverse | 倒退（名词） | 暂存；尚不能确认原书指挫折、逆转还是别的用法 |
| obvious | 无疑的 | 只作为语境中文转述保留，不列独立英语义 |

259个原文片段在建议三层中，另4个在暂存/语境区；冻结快照与新文件保留完整原中文。暂存不等于删除，更不等于把疑点认证成“少见义”。

## 5. 重要用法缺口

22词有26个词典支持的补充候选。它们带有独立来源、建议层级及 `origin=dictionary_evidenced_AI_addition_candidate_not_in_formal_gloss`；`source_sense_ids=[]`，不混入原义项，也未写回任何正式字段。

| 示例 | 候选 | 原表为什么不足 |
|---|---|---|
| run | 运转/运行；运行程序/执行 | 跑和经营不能完整表达机器/程序用法 |
| chair | 主持会议；主席/主持人 | 椅子这个名词不能覆盖这些用法 |
| priority | 优先事项 | 抽象优先地位与具体应先办的事不同 |
| couple | 一对伴侣；a couple of的两个/少数几个 | 夫妇只是伴侣的子集，数量表达也需上下文 |
| model | 型号 | 模型、模特、典范不能代替产品型号 |
| subject | 主语 | 主题、学科和对象不等于语法主语 |
| light | 浅色的 | 轻的与明亮的都不是颜色浅 |
| well | 对话中的嗯/那么/好吧 | 不是副词好地，也不是形容词健康 |

这些是限定于已选100词的教学补充建议，不是要求把每部词典的所有义项都搬进来。原义项全覆盖不等于完整词义覆盖；候选个数也不等于正式词库中已确认的缺失数。未做学习者记忆效果实验，不报告准确率或背诵效率提升百分比。

## 6. 后续规则改进

完整规则在 [RULES_V3.md](p6c1/RULES_V3.md)。主要变化：

1. 原文片段、英语语义、记忆展示单元分开建模，消除“逗号=多义”和“放一起=完全同义”两种误解。
2. 先查词性/搭配/语境及重要缺口，再决定优先层；不机械限两组，也不以减少字数作唯一目标。
3. 每个解释有具体证据与支持关系；不再用整套同词性词义集合冒充逐义验证。
4. 不确定译义进入显式保留区，不自动降到其他层装成罕见但正确的释义。
5. 新词义候选与原文改述分开标记，绑定输入/父决定/复核版本哈希；不把词性推荐说成原书已核实。
6. 教学先后是建议，词典编码/义项顺序/考研词头分类均不证明PETS义项频率。confidence不能代替证据或签审。

## 7. 验证与保护

[preservation_manifest.json](p6c1/preservation_manifest.json) 对原P6-C成果、相关代码、正式CSV/样本以及已知个人SQLite和sidecar共36个路径做前后字节哈希和元数据比对，全部不变。仅按已知路径检查，不扫描磁盘、不打开SQLite连接。原JSON冻结副本与原文件逐字节相同。

- 100个原ID范围、稳定ID/词头/词性/原中文与正式源哈希核对通过。
- 263个原解释全部追溯；每项在三层或保留区恰好归属一次；26个新增候选没有冒用原文片段ID。
- 286条证据引用可解析，检查所属词头；不存在编造synset ID或把别的单词来源挪作证明。
- 13项Python测试通过，包含删除原义及其追溯、错误词性、跨词引用、假引用、增义伪装原文、丢失子义、范围扩到101词和假人工签审等损坏注入。
- 确定性重建 `--check` 和原文件保护检查通过。复核JSON等校验结果见 [validation_results.json](p6c1/validation_results.json)。

这些测试验证结构/来源一致性，不验证中文译义达到人工金标准。没有修改Flutter应用、UI入口或原测试，本轮不重复构建应用。原有工作区修改完整保留，没有Git提交/推送，没有Notion访问/写入、学习事件上传、正式数据库操作或全库模型处理。人工确认仍为0。

## 8. 使用与重现

此版本是独立审查资料，**不能直接当作旧UI所需的P6-C JSON替换文件**，也没有接入正式学习页。

```powershell
& 'C:/Users/admin/AppData/Local/Programs/Python/Python314/python.exe' -X utf8 scripts/p6c1/build_review.py --check
& 'C:/Users/admin/AppData/Local/Programs/Python/Python314/python.exe' -X utf8 scripts/p6c1/validate_review.py
& 'C:/Users/admin/AppData/Local/Programs/Python/Python314/python.exe' -X utf8 -m unittest discover -s scripts/p6c1 -p 'test_*.py' -v
& 'C:/Users/admin/AppData/Local/Programs/Python/Python314/python.exe' -X utf8 scripts/p6c1/freeze_inputs.py
```

正常重建和校验不联网、不调用模型API。`freeze_inputs.py --freeze` 只在全新审查目录创建输入和保护基线，已有快照使用排他创建，禁止覆盖。源文件变化时应建立新的审查版本，不把本版偷偷重绑为已通过。
