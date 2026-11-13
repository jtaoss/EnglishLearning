# EnglishLearning P6-C.2：500词核心中文释义隔离试点

日期：2026-11-13（Asia/Shanghai）。输入Git为main `3c234c6`；应用版本仍0.7.0+10。本轮不提交Git、不连接Notion、不打开SQLite、不发布正式UI。

## 1. 实际交付

**已形成恰好500个不同正式稳定ID：原100词 + 新400词，缺失0、生成失败0。** 原100词优先采用P6-C.1独立复核的proposed_layers，同时完整嵌入原提炼与复核记录，没有重生成或改写旧成果。继承的33词分层/展示建议、263个原文片段、26条补充候选（22词）、4个原文暂存片段及0人工签审均保持。

主文件：[core_meanings_500.json](core_meanings_500.json)。统计：[QUALITY_METRICS.json](QUALITY_METRICS.json)。高风险逐词表：[HIGH_RISK_REVIEW.md](HIGH_RISK_REVIEW.md)。全部500词待签审队列：[HUMAN_REVIEW_QUEUE.json](HUMAN_REVIEW_QUEUE.json)。

**本轮的“原文”是正式CSV的meaning_zh及29字段源快照，不声称是商业教材PDF逐字中文，也不声称这些既有AI整理释义已获教师确认。** 原文片段按文本位置切出，片段不自动等于真实英语义项。

## 2. 选择范围与分类证据

正式CSV实际5,332词。排除旧100 ID，再按已核验原书分类：高频→基础/简单→中频→低频→偶考→其他；同类按正文PDF页最小值、稳定ID排序。候选来源与分类交叉核对既有P5-A审计证据，没有重新OCR、没有根据词头或AI感觉猜词频。剩余高频词已足够，因此新增400全为高频；没有为了制造类别均衡而跳过用户学习顺序。

|分类|合并500|本轮新增400|
|---|---:|---:|
|高频词|429|400|
|基础词|45|0|
|中频词|10|0|
|低频词|7|0|
|偶考词|9|0|

选择表 [selection_400.json](selection_400.json) 保存完整源值、source_hash、原文字区间和分类依据。旧100顺序保留，新400按选择顺序追加。issue、charge、address、concern未入本500；present在原100；account、conduct、maintain、approach在新400。未因示例要求添加其他词头。

## 3. 核心组与原文守恒

|指标|原100|新400|合并500|
|---|---:|---:|---:|
|原中文文本片段|263|953|1216|
|首次记忆核心组（不含来源外候选）|139|549|688|
|原文疑点暂存片段|4|21|25|
|词典补充候选|26|29|55|

**A：平均原中文片段数 = 1,216 ÷ 500 = 2.432。B：首次记忆核心组平均数 = 688 ÷ 500 = 1.376。** 展示单元相对原片段数量少约43.42%，但两个指标单位不同，不能报告为准确率、实际词义减少或记忆效果提升。

所有1,216片段均在核心、扩展、其他或疑点保留区恰好映射一次。25个疑点片段仍完整保存，不通过悄悄删原义制造压缩。55条来源外候选不计入当前B；未来接纳重要候选时，首次记忆负担可能增加。

没有硬卡1–3组：原get保持4组；operation、apply、application、appreciate、account等保留多个重要入口。不同词性不合并。近义显示允许压缩，相关但不同的子用法保留原文与区别；例如agent标为角色框架并列，benefit的及物/不及物方向已经拆开。

## 4. 自动审查结果

### 结构层

校验500唯一正式ID、旧100/新400互斥、源词头大小写、词性、29字段哈希、全文与Unicode片段区间、来源映射守恒、非空组、去重、证据所属词头/词性、来源外候选不冒充原文以及人工状态分离。结构通过；没有用结构PASS宣称语义绝对正确。

### 新400的AI语义层

400词均有明确逐词判断，保存在scripts/p6c2/review_01.tsv至review_08.tsv，没有为缺记录自动填“通过”模板。生成与语义判断都来自本次Codex会话，并不假称每词另发了一次API请求。

|问题等级|新400词的首要审阅事项数量|
|---|---:|
|Critical|0|
|Major|42|
|Minor|55|
|Info|303|

这些是AI提出的审阅事项，不是经过人工裁定的错误数。Major涉及原短释范围、重要用法缺口或首稿修订。原100不重复做等级映射，保持上轮结论，不能为了凑总数把它们自动算成Info。

新400有34词发生候选层级、展示或证据修订，其中28词涉及实际分组/展示，余6仅证据调整；前后差异在 [review_revisions.json](review_revisions.json)。原100已有33词分层/展示建议，未重复生成。本轮新增加29条词典候选，涉及24词；加上旧26条，共55条、46词。候选独立列dictionary_additions，source_sense_ids为空，自动升级核心数0。

### 高风险资料复核层

新400采用较保守规则，多个语义/词性组、原文不明确、证据缺口历史或来源外候选均列优先，因此294词是高风险优先项；原100沿用原48词，总342。该数不是错误数，且旧新风险规则不同，不应直接比较错误率。逐词观察、证据引用和限度均保存，原100直接继承C.1而不重复。

**独立性必须说明：本轮是同一Codex会话的非盲、来源优先重新核对，不是第二个独立模型，也不是真人审核。独立模型/API复核未执行，明确记为not_run。** 实际可访问的词典证据用于重新判断，而不是运行原生成器充当复核。例如：

- stewardess：Collins还列船、列车等，首稿只限飞机不当；拆清一般称谓和航空旧称，原两片段均保留。
- benefit：词网的derive a benefit和be beneficial for方向不同，拆开得益与使受益。
- adapt：使适应的使动方向改用make fit证据，自身适应另列候选。
- critical：原批评的只保留指出不足参照，审慎评价另列候选；不把两定义挂一处就说完全验证。
- account：账户、叙述、解释均保留；占整体份额另列account for候选。
- maintain：原保持类近义可压缩，但坚称、保养、供养另列候选，不把原文覆盖率100%当无重要缺口。
- approach：物理接近、处理问题、方法、接近名词保留；为业务请求而接洽另列候选。
- faculty、profitable、prior、plastic：正规词典补足词网覆盖，不能把单一词典没列出当原义不存在。

## 5. 仍需语言内容审定

人工签审仍为**0**，needs_human_review为**500**；高风险表342词优先，其余158词也未获真人签审。原文疑点共24词/25片段，其中新增20词为：candidate、accelerate、percentage、recession、accident、suicide、civilization、discovery、crucial、cultivate、occur、indicate、tangible、immigrant、committee、adopt、suppress、deprive、enquiry、reasonable。旧4词及具体原文在JSON保留区，不自行修正文书原文。

疑点区不是“已证明少见”的其他义：例如occur的碰巧、deprive的裸丧失、enquiry的审问、crucial的本质的不能直接作无条件等义教学；原文仍能完整定位。新20词的21片段和旧4片段均需解释原语境，不能以AI意见直接批量覆盖正式释义。

原文缺逐义词性时仍保留null与unresolved_multi_pos，显示中的词性是词典支持的AI教学推荐，不声称查清原作者意图。词典补充候选通常有明确来源，但教学优先级仍未获语料或真人金标准验证，不能自动变成“PETS-3官方重点释义”。

## 6. 来源、失败、版本与成本

继承 [RULES_V3](../p6c1/RULES_V3.md)，本轮工作规则为 [PROMPT_V4.md](PROMPT_V4.md)。管线标签codex-session/p6c2-semantic-v4、提示版本p6c2-rules-v4，不冒充可核实的API型号。精确后端模型ID、快照、会话token和账单金额均未暴露，字段为null。

本轮没有向外部模型API发请求，external_model_api_calls=0；400次提炼和400条语义判断指本会话保存的逐词工作记录，不是800次API调用。**实际Codex会话成本未知，不报告为0美元，也不套用别的模型单价伪算。** 单独独立模型复核not_run；不能将其写成模型调用成功或真人通过。

合法WordNet3.1缓存的SHA-256为3f7d8be8ef6ecc7167d39b10d66954ec734280b5bdcd57f7d9eafe429d11c22a，只抽取新400词头的英文义项；许可见assets/vocabulary/WORDNET_3_1_LICENSE.txt。中文决定由本会话独立编写，正式CSV已有释义仅作原文快照。

外部资料来自Cambridge、Collins、Merriam-Webster，观察和URL在 [external_evidence.json](external_evidence.json)。7次直接访问返回403，已记录；使用可访问索引文本或其他出版社有限补证，未绕过限制。索引不冒充当日完整页面。只保存短篇原创中文概述和链接，没有商业词典全文或大批例句。初稿12个空证据位均有对应出版社条目补证；这不等于每条译义获独立教师认证。

生成8批每批50，失败0；已成功检查点不会覆盖或自动重生成。构建器只装配明确决定，缺词、来源漂移或损坏会停止，不用模板补全，不无限重试。

## 7. 数据保护与复现

保护基线见 [preservation.json](preservation.json)，共50个旧成果、正式源及个人路径状态。正式CSV、原100的提炼/复核文件及相关旧代码字节一致。个人SQLite及侧文件仅计算文件哈希与元数据，没有建立SQL连接、迁移、导入或写入。学习状态、评级、复习日期和事件未操作，Notion请求0、学习事件上传0。

新增范围仅docs/p6/p6c2、scripts/p6c2和test/p6c2；没有改正式Flutter页面、日语模块或Windows数据库路径。剩余4,832词没有做提炼，不注册正式资源或路由。

可重复运行（现有本机源数据/缓存可用时）：

```powershell
python -X utf8 scripts/p6c2/prepare.py
python -X utf8 scripts/p6c2/checkpoint.py 1
# 其余批号2至8；已有检查点只比较，不覆盖
python -X utf8 scripts/p6c2/build.py
python -X utf8 scripts/p6c2/validate.py
python -X utf8 -m unittest discover -s scripts/p6c2 -p test_contract.py
python -X utf8 scripts/p6c2/write_reports.py
```

首次准备依赖本机P5-A分类审计及许可缓存；后续构建使用冻结selection/checkpoints，不会重新OCR、联网或发模型API。换设备时个人保护基线不应冒称同一机器，需独立建立新验收基线，不静默改写原记录。

## 8. 验收与下一步

[validation_results.json](validation_results.json) 记录500唯一ID、1,216片段全保留、全部原100记录相同、来源和人工状态契约通过。Python包含省略、重复、ID/大小写、原文、证据、跨词性合并及虚假人工签审等损坏测试。Dart/Flutter数据契约测试以Unicode code points解释区间，验证未来UI能解析500记录，不连接正式学习库，也不表示当前正式UI已发布本数据。

实际测试命令和退出结果见 [TEST_RESULTS.json](TEST_RESULTS.json)，未执行的检查不标通过。

**目前不建议直接扩展或发布到全量5,332词。** 先处理原文疑点、审定55条来源外候选并建立真实专家签审/质量金标准；必要时再安排不同模型盲审或学习效果试验。不能把1.376组或零Critical结构问题当成已证明适合全面上线。本轮到500词隔离数据与自动审查为止，不自动扩大或发布正式软件。
