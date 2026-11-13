# P6-C.3 核心释义质量门槛报告

核验日期：2026-11-13。产物仅为隔离 AI 候选；未发布、未执行全量处理。

## 1. 结论：B，先修正规则并在现有500词验证，再扩容

**暂不直接进入剩余4,832词处理。** 42项旧Major全部复查，另抽48词；补充样本发现1项当前候选的重要用法遗漏和1项原文覆盖缺口。两者都还没有正式采用解决方案。原文片段全部覆盖并不能证明英语用法覆盖完整。

- **不选A**：`import` 的贸易动词未明确保留，`management` 的人员义在原材料与现有分层均未表达；不能只看压缩率或旧风险标签放行。
- **选择B**：问题集中于“原片段一次分配”与“原文之外重要用法检查”；已有局部修订和V4规则，可以在现有500内验证。
- **不选C**：本轮没有证据证明整套核心提炼方法整体失效，也未确认批量错译、原文丢失或稳定ID损坏。90词不是全500的重新盲审，更不能据此断言全库无缺陷。

## 2. 实际输入与审查范围

已读取C2的500词JSON、试点报告、高风险报告、质量指标，以及C1 RULES_V3。结构以实际文件为准。正式词库为5,332词；旧100与新400均保留。

| 项目 | 数量 | 含义 |
|---|---:|---|
| 既有数据集 | 500 | 原100+新增400，均未改写 |
| 定向复查 | 42 | 新增400中全部旧Major标记，不等于42个确认错误 |
| 额外分层抽检 | 48 | 新400非Major抽40，旧100 standard抽8 |
| 源先行盲审总数 | 90 | 90个不同正式稳定ID，两个任务各45且不相交 |
| 本轮审查原文片段 | 221 | 保持全部完整文本及映射 |
| 本轮没有重新语义审查 | 410 | 保持旧状态，不自动通过 |
| 本轮修订候选 | 3 | import、management、indicate；新文件，不覆盖旧500 |

固定配额内按SHA256(`p6c3:分层:stable_id`)排序，不按置信度挑词。旧100子样本覆盖其standard池中可用的原书分类。原书分类只用于抽样记录，不推断义项频率。

| 分层 | 池大小 | 抽取 |
|---|---:|---:|
| new_Info_standard | 102 | 12 |
| new_Info_high | 201 | 12 |
| new_Minor_high | 51 | 12 |
| new_Minor_standard | 4 | 4 |
| old_standard | 52 | 8 |

本轮90词原书分类：高频词 84；中频词 1；低频词 2；偶考词 1；基础词 2。分类不是英语义项的使用频率证据。

## 3. 独立性、证据与局限

两组审查使用fresh fork-none上下文，配置模型为`gpt-6-astra`。先给原词头、词性、原始中文和未按旧结论筛选的合法WordNet3.1定义，不给旧核心/风险/Major标签/旧评审意见；每15词保存检查点，45词提案封存哈希后才由父上下文对照旧候选。封存后没有回填旧结论。父上下文裁定不是第三次盲审。

**未完成可证明不同后端身份的跨模型验证**：原生成后端ID未暴露；复核配置名不能证明它必然不同于原后端。新上下文盲审真实完成，但不同后端模型分歧数记为`null`。两个45词任务没有同词重叠，也不能计算同词双审者一致率。

原文件的项目版本标签也原样记录：旧100词`model_version=p6c1-independent-ai-review-1`、`prompt_version=p6c-prompt-2 + p6c1-RULES_V3`；新400词`model_version=codex-session/p6c2-semantic-v4`、`prompt_version=p6c2-rules-v4`。这些是项目标签，不是可证明的后端模型身份。本轮`P6C3/RULES_V4`是基于C1 RULES_V3增补的质量标准，与C2自身的`p6c2-rules-v4`标签分开。

WordNet3.1使用项目已有许可；逐定义原文、归属词头和哈希均已校验。出版社网页只保存自写的短中文观察与URL，不复制整页/商业例句。共记录17次403：两审者各8次，父上下文reference页1次；均未把失败页当成功证据，使用已许可WordNet和可访问出版社作替代，未绕过。记录见`publisher_observations.json`及审查JSON。

两项独立审查任务、六个15词检查点不等于API调用次数；实际token、计费和精确后端快照均不可见，记录为null，不估造金额或零成本。裁定仍是有词典依据的AI判断，不是人工金标准、随机准确率或学习效果实验。

## 4. 确认问题与原标记的区别

| 指标 | 数量 |
|---|---:|
| 证据支持的问题：Critical | 0 |
| 证据支持的问题：Major | 2 |
| 证据支持的问题：Minor | 1 |
| 确认的原文错译断言 | 0 |
| 当前候选重要用法遗漏 | 1 |
| 新确认原文重要用法覆盖缺口 | 1 |
| 确认词性混淆 | 0 |
| 仅教学层级/展示偏好词 | 19 |
| 盲审与旧候选分层/POS/来源划分不同 | 40 |
| 其中核心原片段集合不同 | 28 |
| 字面显示或顺序不同 | 78 |
| 尚未关闭的本轮Critical/Major | 2 |

40项分层差异、28项核心片段集合差异、78项字面/顺序差异是定位指标，不能相加或改称40/78处语义错误。19词只属教学偏好；其他“已限定、旧候选、暂存”也不因此算当前错误。未确认错译/词性混淆并不等于证明全库不存在。

### 4.1 三项实际裁定与新候选

1. **C3-001 import — Major，当前候选用法遗漏**。旧核心把“进口”只分给名词并引用进口品，动词“输入”又限定为数据；贸易动词没有显式保留。新候选让同一原片段`s001`分别对应贸易动词和名词行为，以`semantic_splits`说明这是AI用法拆解而非新增原文。数据导入后学，进口品单列候选，不升核心。WordNet `v:02351132`（从国外引入）、`v:02237504`（数据导入）、`n:03569847`（进口品）相互有别；出版社也分别支持贸易动词、名词行为与进口品。[Collins import](https://www.collinsdictionary.com/dictionary/english/import)。

2. **C3-002 management — Major，原文覆盖缺口**。原“指导/指挥/管理”及旧分层都描述管理活动，不能表达管理人员群体。WordNet `n:01135602`为活动，`n:08397896`为负责经营的一群人。新候选只新增“管理层”词典候选，旧核心/扩展不变；**不是两处原文错译中的一处**。该用法重要性是职场理解的教学裁定，存在性与概念区别有词典证据，未声称语料频率。[Collins management](https://www.collinsdictionary.com/dictionary/english/management)。

3. **C3-003 indicate — Minor，用法证据与中文范围**。旧“指出/指示”组引用指向对象和简要陈述的词典项，缺少为信号表明读法对应的引证，短显示也未排除发命令的中文歧义。新候选按对象/信号/陈述给出提示，保留原片段，`s002`的重复引用显式声明AI拆解，原`s001`继续暂存。不是判定原中文完全错误。具体WordNet引用与新旧差异见JSON。[Merriam-Webster indicate](https://www.merriam-webster.com/dictionary/indicate)。

`REVISED_CANDIDATES.json`为3词的新版本，保存完整原文、原字段、稳定ID、原/候选哈希、逐字段before/after和审查来源。`human_approved=false`、`adopted=false`。生成候选不等于问题已关闭；本轮没有把词典补充自动放入原文核心。

### 4.2 原42项Major的主处理状态（互斥，总数42）

| 主状态 | 词数 |
|---|---:|
| 前轮修正已在 | 1 |
| 旧补充候选待决 | 17 |
| 原文疑点已暂存，仍待核 | 19 |
| 教学偏好差异 | 4 |
| 确认Minor：用法证据/范围 | 1 |

该42词中本轮确认0 Critical、0 Major、1 Minor；不表示其余41词全部合格。19词的来源语境仍未解决，17词的旧补充仍待采用裁定。`benefit`的施受方向、`stewardess`的范围、`core`果核限定等已有修正不能再计旧错误；`committee`、`cultivate`的usage_note亦须一并读取。

### 4.3 抽检漏报

48词额外样本中发现2项Major，均原为`Minor/high`：import、management。它们揭示旧审查严重度没有充分反映用法覆盖风险。**不称为“2个原standard低风险漏报”**：严格standard子样本24词没有确认问题；剩余24词属于其他非Major的high风险分层。本次配额和高风险过采样不支持外推总体准确率或错误率。`nuclear`盲审Major针对未限定原文，旧候选已有核能/原子核限定，故不计新的Major；`planet`当前并未引用含九大行星的旧WordNet项，也不转计当前错误。

## 5. 保留的待审与补充候选

- 旧100词高风险/暂存 **48词** 继续待审；没有因未抽到或旧文件被继承而通过。
- 原500词宽泛high风险标签 **342词** 保留。这是旧风险标签，不是342个证实错误或342个Critical/Major。
- 具体优先待处理集合 **85个不同ID**：旧48词、所有原文暂存词、旧核心层补充建议词、本轮2个Major的并集；不是85个新错误，原因逐词见JSON。
- 原55条词典候选完整保留；其中23条/22词原建议核心层，仍未采用。盲审重新提出的26条与旧候选相同，另3条其实已在现有组/证据范围，不重复当作新缺口。
- 本轮另发现 **21条/21词** 新候选，包括management管理层；其余多为扩展或范围提示，不能全部改称重要遗漏。所有候选继续单列、无人工签审。

旧48词待审名单：double、brief、close、rear、back、void、present、major、mean、parallel、slack、model、light、well、subject、tender、reverse、fake、abstract、minor、volume、bank、run、date、yard、miss、quarter、get、term、bill、keep、shot、division、course、case、raise、hold、resolution、tone、aisle、extension、obvious、engage、knock、cripple、chop、consumption、notify。具体原因沿用原文件/选择台账，未重复生成旧审查结论。

| 新候选词 | 内容 | 状态 |
|---|---|---|
| acquisition | （企业）收购 | new_candidate；未采用 |
| appreciate | （资产等）升值 | new_candidate；未采用 |
| client | 客户端计算机 | new_candidate；未采用 |
| competition | 竞争对手（集合称呼） | new_candidate；未采用 |
| conduct | 表现，举止（conduct oneself） | new_candidate；未采用 |
| confront | 拿证据与某人当面对质 | new_candidate；未采用 |
| cycle | 自行车 | new_candidate；未采用 |
| flush | 齐平的（与某表面平齐） | new_candidate；未采用 |
| import | 进口商品；进口品 | new_candidate；未采用 |
| indeed | （独立应答，带惊讶或怀疑）真的？ | new_candidate；未采用 |
| license | 正式许可，授权 | new_candidate；未采用 |
| machinery | （机构的）运作机制 | new_candidate；未采用 |
| majority | 法定成年年龄 | new_candidate；未采用 |
| management | 管理层；经营者 | new_important_source_gap；未采用 |
| nuclear | 细胞核的 | new_candidate；未采用 |
| possess | 具有（品质、技能等） | new_scope_supplement_not_proven_error；未采用 |
| private | 不公开的，保密的 | new_candidate；未采用 |
| recession | 退去；后退 | new_candidate；未采用 |
| reference | 引文出处；参考文献 | new_candidate；未采用 |
| regular | 常客 | new_candidate；未采用 |
| suppress | 镇压（反抗、暴动等） | new_candidate；未采用 |

## 6. 验证、不可变性及共享工作区

本轮脚本不连接SQLite或Notion、不写学习状态、不下载商业音频、不运行原词书OCR、不改正式UI。字节哈希和DB side-file元数据核对英语源文件、旧100/C1、旧500/C2、正式CSV及个人数据库。原数据保持不变，修订仅另存。

| 实际检查 | 结果 |
|---|---|
| 5332正式ID、原字段canonical hash、500输入哈希 | 通过 |
| 42+48范围、90盲审记录/221片段及封存提案 | 通过 |
| 3词/8个唯一原片段、完整before/after、一对多映射注释 | 通过 |
| 原文/POS/稳定ID/旧候选状态、外部补充隔离 | 通过 |
| `python -X utf8 scripts/p6c3/validate.py` | exit 0；—项；passed; 42+48 IDs, source/evidence/provenance/revision/preservation contracts |
| `python -X utf8 -m unittest discover -s test/p6c3 -p "test_*.py" -v` | exit 0；13项；passed; includes deliberately corrupted inputs rejected and deduplicated pending queue |
| `flutter test --no-pub --reporter expanded test/p6c2/core_meanings_500_contract_test.dart test/p6c3/core_quality_review_contract_test.dart` | exit 0；9项；passed; 4 existing C2 + 5 C3 Dart JSON/source contracts |
| `dart analyze test/p6c3/core_quality_review_contract_test.dart` | exit 0；—项；No issues found |

Python共13项，包括篡改原文、错误词头引证、缺少重复映射解释、伪造人工通过、外部义挂原文ID等反例拒绝测试及待审并集校验。Dart/Flutter共9项（原C2四项+C3五项），仅验证数据解析/契约；未发布或启动正式背词UI。初次unittest同名模块导入问题已修复，最终13项通过。测试记录见`TEST_EXECUTION.json`，数据校验记录见`VALIDATION_RESULTS.json`。

共享工作区观察到别的日语/应用设置工作，当前分支为`j1/japanese-module`，HEAD `3c234c6aeeb4ce7eac2eb7367bc8bed8adb12d3d`。本轮没有切换分支、回退或改写这些文件；`preservation_check.json`单列外部变化，不以“全工作区不变”作虚假保证。保护范围内英语词库/个人数据库无变动。没有Git提交、合并或推送。

关键输入SHA256：

```text
core_meanings_500.json 78b40fc7ad3b98b7f1a1f1dcc310750da211dd5f9e5f72990d500800f5733a20
formal_learning_vocabulary.csv 9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb
```

原1,216个中文片段、688个核心展示组及平均2.432/1.376均未更改；本轮没有把压缩数字作为质量门槛。

## 7. 下一次扩容前的验收条件（本轮不执行）

1. 在现有500范围验证原片段一对多映射，确认import贸易动词不再遗漏，indicate逐用法证据与范围提示齐全。
2. 对management管理层及旧有重要补充候选作独立的采用/不采用决定；保持外部候选与原文分离，不自动升级。
3. 按V4对现有500中的其他未标记多词性/宽中文词再次分层抽检；不能把本次有目的分层抽检当随机准确率。
4. 未解决Critical或同类系统性Major不得放行；验证具体修订，不能只调低风险标签。

需保留人工/专家可裁定的争议清单；当前human_approved仍为0。质量门槛不是要求初学用户为所有专业问题背书，而是不能伪造已经签审或用AI自信分数替代依据。

## 8. 复现与文件

重建只使用已保存的原材料与裁定，不发起模型或词典请求：

```powershell
python -X utf8 scripts/p6c3/seal_blind_reviews.py
python -X utf8 scripts/p6c3/build_quality_review.py
python -X utf8 scripts/p6c3/validate.py
python -X utf8 -m unittest discover -s test/p6c3 -p "test_*.py" -v
python -X utf8 scripts/p6c3/write_report.py
```

私有source-only输入包由`prepare_review.py`创建并与封存哈希绑定；已有包不覆盖。重建提案本身需要真实独立审查，不能由组装脚本生成模板替代。输出四文件为`independent_quality_review.json`、`QUALITY_GATE_REPORT.md`、`REVISED_CANDIDATES.json`、`RULES_V4.md`；附封存盲审、选择台账、前后哈希、证据观察、测试记录。

## 9. 逐词对照台账（90词，非人工通过名单）

### 原Major42词

| 词头 | 旧严重度/风险 | 本轮主状态 | 对照理由 |
|---|---|---|---|
| accelerate | Major / high | 原文疑点已暂存，仍待核 | 加快/加速是相容改述；快进已暂存，独立审者也要求原例，不是当前核心错误。 |
| accident | Major / high | 原文疑点已暂存，仍待核 | 事故和偶然意外已分组；灾祸已暂存，未把所有灾难纳入核心。 |
| account | Major / high | 旧补充候选待决 | 账户、叙述、解释原因三项均保留；占比例已是独立补充候选，本轮没有新发现该缺口。 |
| adapt | Major / high | 旧补充候选待决 | 改编与使适应已分开；调整是否上移是教学偏好，自身适应已在补充候选中。 |
| adopt | Major / high | 原文疑点已暂存，仍待核 | 裸跟随已暂存，采用/遵循有语境说明；收养已单列候选，不重复计作新漏报。 |
| apparent | Major / high | 旧补充候选待决 | 明显/显而易见相容；表面上如此与其不同，旧候选已分离，尚未获准采用。 |
| appearance | Major / high | 旧补充候选待决 | 外貌类改述相容；出现/露面旧候选仍待处理，盲审仅建议改变其教学优先级。 |
| approach | Major / high | 教学偏好差异 | 动词接近/着手处理和名词方法/接近都保留；盲审主张四项全上核心但无义项频率证据，接洽旧候选继续分离。 |
| benefit | Major / high | 教学偏好差异 | 使受益与得益在不同组，未发生施受方向合并；盲审主张使受益上移并细分福利，不能据此算错译。 |
| candidate | Major / high | 原文疑点已暂存，仍待核 | 候补已暂存；候选人与政治竞选者分层相容，无法由词典单独查清原例中的候补。 |
| civilization | Major / high | 原文疑点已暂存，仍待核 | 文明与文明社会分组保留；教化已暂存，盲审建议限定为文明化后放其他层，尚不解除旧待核状态。 |
| committee | Major / high | 原文疑点已暂存，仍待核 | 委员会核心可靠；调查团在现有usage_note已限定受委派调查的委员会，一般考察团暂存，不能仅凭盲审把限定后的扩展判成错误。 |
| conduct | Major / high | 教学偏好差异 | 行为、组织、音乐指挥、传导保持不同词性与用法；进行活动已有范围补充候选，各动词全上核心未有频率证据。 |
| confront | Major / high | 旧补充候选待决 | 对抗有词典支持，正视处理问题是旧候选；当面对质是本轮新的独立补充候选。 |
| core | Major / high | 教学偏好差异 | 抽象核心与苹果梨等中央含籽部分已区分；果核是否上移无客观义项频率证据。 |
| critical | Major / high | 旧补充候选待决 | 关键、指出缺点和危急均区分；审慎评价旧候选保持独立，不把批评与评价混同。 |
| criticism | Major / high | 旧补充候选待决 | 批评可以保留；文学艺术评论已有候选，未把词典补充伪装成原文。 |
| crucial | Major / high | 原文疑点已暂存，仍待核 | 决定性/至关重要相容；本质的已暂存，独立审者同样缺少原例，不能自动放行。 |
| cultivate | Major / high | 原文疑点已暂存，仍待核 | 教育的现有usage_note限定修养鉴赏，磨炼暂存，农业耕作已有候选；盲审对裸原文的范围警告并非新核心错误。 |
| declare | Major / high | 旧补充候选待决 | 公开宣告类合组可保留；海关申报是旧候选，不是本轮才发现。 |
| deprive | Major / high | 原文疑点已暂存，仍待核 | 剥夺/夺去的使动方向正确；裸丧失已暂存，没有继续把及物剥夺教成不及物丧失。 |
| discovery | Major / high | 原文疑点已暂存，仍待核 | 突破性进展已暂存；独立审者建议明确发现的成果义，当前发现表述较宽，暂作语义细化建议而不直接判漏义。 |
| enquiry | Major / high | 原文疑点已暂存，仍待核 | 审问已暂存，询问/探问可保留；正式调查旧候选仍待处理。 |
| immigrant | Major / high | 原文疑点已暂存，仍待核 | 现有说明限定移入别国定居；侨民已暂存，未无条件混同国籍身份和迁入身份。 |
| indicate | Major / high | 确认Minor：用法证据/范围 | 现有指出/指示按近义合组，但所引证据只有指向对象与简要陈述，没有为指示的信号表明义提供对应引用，也未限定中文指示以排除命令读法；需补齐逐用法证据和对象提示，不声称原中文完全错误。 |
| jury | Major / high | 旧补充候选待决 | 司法陪审团准确，比赛评审团旧候选保留，两个制度不混同。 |
| legislation | Major / high | 旧补充候选待决 | 原文立法过程可保留，已制定法规是旧补充候选，过程和产物没有被自动合并。 |
| maintain | Major / high | 旧补充候选待决 | 保持状态类合组合理；坚称、保养、供养三个旧候选保留，独立审者的不同层级建议不代表新增错误。 |
| occur | Major / high | 原文疑点已暂存，仍待核 | 碰巧已暂存；存在/分布与想到的旧候选分离，发生核心未擅加偶然条件。 |
| operate | Major / high | 旧补充候选待决 | 操作与经营管理均在；设备运转和外科手术是旧候选，独立审者将手术上移仅是教学建议。 |
| percentage | Major / high | 原文疑点已暂存，仍待核 | 百分数与整体份额分层可成立；裸百分之已暂存，不能把旧疑点当已确认独立名词。 |
| physical | Major / high | 旧补充候选待决 | 身体相关核心可保留，物理学与有形物质两个旧候选仍分离，不声称原文覆盖完整。 |
| propose | Major / high | 旧补充候选待决 | 求婚旧候选保持独立；盲审的提名范围在现有提议组的WordNet证据中已有，不能重复算新缺口。 |
| reasonable | Major / high | 原文疑点已暂存，仍待核 | 判断正确的已暂存；合理的当前证据包括不过分，盲审适度建议属于现有宽义的对象提示，不算新缺口。 |
| recession | Major / high | 原文疑点已暂存，仍待核 | 当前解释已明确经济衰退，不是泛指任何衰退；经济萧条的术语程度仍暂存，后退另作扩展候选。 |
| reference | Major / high | 旧补充候选待决 | 提及、查阅与推荐信均保留；参考书旧候选和引文出处/参考文献新候选不同，后者继续单列，不自动上核心。 |
| separate | Major / high | 旧补充候选待决 | 分开/各自的形容词可保留，动词分离旧候选保持独立，不把补充自动视为原书已有。 |
| stewardess | Major / high | 前轮修正已在 | 现有女乘务员已解除仅限航空的过窄说法，并标旧式性别化称谓；盲审合组偏好不是新错译。 |
| suicide | Major / high | 原文疑点已暂存，仍待核 | 自我毁灭/自毁已经暂存，盲审以比喻语境支持是可选的后续释放建议，不自动清除原待核状态。 |
| suppose | Major / high | 旧补充候选待决 | 假定与认为两项都在；be supposed to旧结构候选保留，盲审对顺序的偏好不作为频率结论。 |
| suppress | Major / high | 原文疑点已暂存，仍待核 | 裸征服已暂存，禁止已有表达流通等限制；镇压可另列候选，不因词典有压制就放行所有征服语境。 |
| tangible | Major / high | 原文疑点已暂存，仍待核 | 有形/可触知核心可靠；明确的已暂存，盲审建议改成具体可证实有依据但不能直接称旧保守暂存为错误。 |

### 其余分层48词

| 词头 | 旧严重度/风险 | 本轮主状态 | 对照理由 |
|---|---|---|---|
| acquisition | Info / high | 教学偏好差异 | 获得与获得物已分组；独立审者建议明确习得并后移获得物，属于细化和教学顺序建议，不凭词典分义数判原展示错误。 |
| agree | inherited_not_reclassified / standard | 旧补充候选待决 | 同意核心可保留；一致相符是旧候选，不能重复声称本轮新发现。 |
| analysis | Info / standard | 本次未确认新问题（非人工通过） | 分析与拆分整体、研究组成关系的词典义相容，未发现新的词性或合义错误。 |
| appreciate | Minor / high | 教学偏好差异 | 欣赏、感激、充分意识到均区分；升值是本轮另发现的词典补充候选，不证明现有三个中文义错误。 |
| battle | Info / high | 教学偏好差异 | 战斗、为目标而斗争与动词奋力抗争均在，动词是否上移仅属教学安排。 |
| bias | Minor / high | 现有候选已限定原文范围 | 统计偏差在现有扩展显示中已有系统性偏向限定，盲审对裸原文的警告不等于候选仍有同一问题。 |
| carve | inherited_not_reclassified / standard | 现有候选已限定原文范围 | 现有扩展已写切肉，原文切开的范围警告已被限定，盲审增加熟肉/分片是更具体的教学改述。 |
| client | Minor / high | 教学偏好差异 | 主顾/客户与法律委托人均保留；委托人上移是教学选择，计算机客户端另列新候选。 |
| comparison | Info / standard | 现有候选已限定原文范围 | 现有组明确是名词，说明中已提醒中文相比不是英文动词；分开短语显示是教学偏好。 |
| competition | Info / high | 本次未确认新问题（非人工通过） | 竞争活动与比赛场次已分开；竞争对手是本轮新增补充候选，不是把旧两个核心合错。 |
| cure | Info / high | 本次未确认新问题（非人工通过） | 动词治愈与名词疗法分开，有各自词典证据。 |
| cycle | Info / high | 教学偏好差异 | 名词周期/循环与动词骑车/循环未丢失；骑车等是否首次全记属教学顺序，自行车名词另列补充。 |
| decrease | Info / high | 教学偏好差异 | 名词减少和动词降低均有有效证据，且原文对应未知已明确；展示自变/使变与两个词性全组合是有益细化，不能称原推荐词性错误。 |
| definition | inherited_not_reclassified / standard | 旧补充候选待决 | 定义/释义同义改述相容；清晰度旧候选保持分离。 |
| efficient | Info / standard | 本次未确认新问题（非人工通过） | 效率高的与节约时间、精力、开支地有效工作相容，没有错配词性。 |
| electronic | Info / standard | 教学偏好差异 | 同一电子的可覆盖设备与粒子语境；旧证据已经包含两项，分成两层是可选教学拆解，不按分组数量判错。 |
| flush | inherited_not_reclassified / standard | 教学偏好差异 | 名词红晕/一次冲水与动词脸红/冲洗都存在；核心组顺序与对象提示是教学差异，齐平形容词另作候选。 |
| forecast | Info / high | 教学偏好差异 | 预测名词、预报动词均可成立，原文逐义词性未知也已注明；不必把每个中文同义词复制到两个词性才算正确。 |
| fourteen | inherited_not_reclassified / standard | 本次未确认新问题（非人工通过） | 十四的数词用法准确，WordNet以数量概念收录不意味着应把正式词性改成名词。 |
| imply | Minor / high | 现有候选已限定原文范围 | 现有意味着已限定由此可推知，暗示单列；盲审针对裸意思是的警告已由现有改述缓解。 |
| import | Minor / high | 确认Major：当前候选漏用法 | 现有s001只标名词进口且引用进口品，s002动词输入又限定数据；没有显式保留贸易动词进口货物。原中文进口支持该动词用法，需允许同一原片段跨用法映射并校正名词行为的证据。 |
| indeed | inherited_not_reclassified / standard | 本次未确认新问题（非人工通过） | 确实/的确核心可保留；表惊讶怀疑的独立应答词典可支持，另列新补充，不冒充原文同义改述。 |
| independence | Info / standard | 本次未确认新问题（非人工通过） | 独立/自主合组相容，没有引入独立日等专名含义。 |
| justify | Minor / high | 教学偏好差异 | 证明合理和为之提供理由的辩护有共同词典支持；是否合成一组或先后教没有唯一客观答案。 |
| layer | inherited_not_reclassified / standard | 本次未确认新问题（非人工通过） | 名词层与动词分层放置分开，未将相同中文形态误当相同词性。 |
| license | Minor / high | 本次未确认新问题（非人工通过） | 许可证名词与正式授权动词已分开；许可行为名词是新候选，现有批准已有正式授权语境说明。 |
| logical | Info / high | 本次未确认新问题（非人工通过） | 合乎逻辑与具备清晰推理能力的形容词都保留，未发现足以确认当前错误的证据。 |
| machinery | Minor / standard | 现有候选已限定原文范围 | 集合称呼/通常不可数已在核心显示中；机构运作机制是新的扩展候选，不能仅凭存在另一词典义判核心机械设备错误。 |
| majority | Minor / high | 教学偏好差异 | 建议首次显示普通数量义的超过一半门槛，另说明选举制度/地区差异；现有多数并非错误译文，不能将该教学建议计作词性或错译。 |
| management | Minor / high | 确认Major：原文覆盖缺口 | 现有管理/指导/指挥均指管理活动，不能表达作为人员群体的管理层；WordNet与出版社均支持该独立商业用法。属于源释义的重要用法覆盖缺口，须单列词典候选，不能批量改写原文。 |
| master | Minor / high | 教学偏好差异 | 掌握、大师、主人、硕士均有独立保留；主人是否首次记忆属教学排序，没有词频证据判定唯一顺序。 |
| monopoly | Info / standard | 本次未确认新问题（非人工通过） | 垄断的经济与泛指独占用法均与现有词典证据相容。 |
| mysterious | Info / standard | 本次未确认新问题（非人工通过） | 神秘/难解释合组相容，未据WordNet编号推导义项频率。 |
| nuclear | Minor / high | 现有候选已限定原文范围 | 现有原子的扩展已明确限核能/原子核语境；盲审针对未限定裸原文的Major不是当前Major。核能不是全新缺口，细胞核可另列新候选。 |
| optimistic | Info / standard | 本次未确认新问题（非人工通过） | 乐观/持乐观态度合组相容，未误教为乐观主义学派的专名。 |
| parliament | Info / standard | 本次未确认新问题（非人工通过） | 国会/议会改述可保留，适用国家制度差异不构成现有释义错误。 |
| participate | Minor / standard | 本次未确认新问题（非人工通过） | 参加/参与合组相容，participate in的提示为可选用法补充。 |
| partly | Info / standard | 本次未确认新问题（非人工通过） | 部分地与并非全部或某种程度相容，没有无来源新增核心义。 |
| planet | Minor / standard | 本次未确认新问题（非人工通过） | 当前引用是围绕恒星运行的词典项，不是含九大行星的旧项；盲审发现的旧WordNet材料问题不能转记为当前候选错误。 |
| possess | Info / standard | 本次未确认新问题（非人工通过） | 拥有/持有核心相容；具有品质技能可作范围补充候选，未凭单一物产权证据声称所有抽象用法均无效。 |
| prejudice | Info / high | 本次未确认新问题（非人工通过） | 名词偏见、使偏见的动词与损害权益用法已有分开，没有把使不利错误合成态度。 |
| private | Minor / high | 教学偏好差异 | 私人的和非公共私有的核心/扩展可保留；保密用法另列候选，是否首次记忆属未有频率支持的教学取舍。 |
| proposal | Info / high | 教学偏好差异 | 提议建议与求婚均保留；求婚是否上移属教学顺序差异。 |
| red | Info / high | 本次未确认新问题（非人工通过） | 名词红色和形容词红色的均有词典支持；原文对应未知已保留，不把AI推荐说成查明了教材排序。 |
| regular | Info / high | 教学偏好差异 | 规律、定期和普通均保留，普通是否上移是教学安排；常客名词另列新候选。 |
| tomb | inherited_not_reclassified / standard | 本次未确认新问题（非人工通过） | 坟墓可保留，没有把陪葬建筑或动词用法无证据加入。 |
| transaction | Minor / standard | 现有候选已限定原文范围 | 生意在现有核心显示已限定具体交易，盲审的范围警告不能再计当前错译。 |
| transform | Info / standard | 现有候选已限定原文范围 | 现有说明限定形式性质变化且通常显著，盲审把提示放到短显示属于教学改述，不是当前含义错误。 |

完成P6-C.3后停止：未开始剩余4,832词，也未正式发布修订。
