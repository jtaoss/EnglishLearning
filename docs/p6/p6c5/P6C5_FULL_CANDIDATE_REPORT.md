# P6-C.5 全量核心中文释义候选报告

结论 **C：存在系统性质量问题，停止后续处理**。全量目标未完成。实际合并候选 700/5,332（复用600 + 本轮新生成100）；剩余 4632 未生成。首批结构检查可通过，语义放行未通过，所有结果隔离保存。

## 输入、分组与冻结

按实际稳定ID核对A=原500、B=独立盲测100、C=其余4732，互不重叠，无重复/额外ID。旧600的所有原文快照与正式29字段一致。

V4.1规则哈希：`0c94b56ac7bcef28dd3ccda29995ec3d61ade284c6ed95734418f2db87771dbe`。正式清单哈希：`9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb`。执行配置与提示词文件哈希见 RUN_MANIFEST.json，规则从未静默替换。

## 复用与生成

A复用C4独立回归候选；B复用C4盲测经保守处置候选。C2/C3/C4原文件完整保留，每条带来源文件哈希及源记录/候选哈希。旧48个历史风险继续待审。management人员义与clause语法上位概念没有自动采用。

48个计划批次中保存了 1 个结构检查点，语义门槛通过 0 批；实际新生成 100 词。第2批及以后未启动。每100词为检查点；成功原始输出不可覆盖，失败不填模板、不换未经验证模型。

实际冻结模型：`deepseek-flash`，thinking=enabled，effort=low。官方文档标注快照 `DeepSeek-V4.1-Flash-1017`，API未返回精确部署快照，不能视为逐请求快照证明。

预检失败、证据补充与最终模型采用过程见PREFLIGHT_ADJUDICATION.json；预检费用包含在实际API统计内，不隐藏失败或声称旧600重新生成。

## 停止原因与证据裁定

冻结的停止标准是同批出现至少2个同因、经证据裁定的Major。首批ritual与extend满足该条件；本轮只提独立修订，不改变冻结规则后继续扩量。

| 词 | 已确认级别 | 实际问题及待确认修订 |
|---|---|---|
| ritual | Major | 源“仪式”被限成宗教程序，普通正式仪式未在该源用法的层级/暂存中覆盖。候选修订撤去宗教专有限制；[Collins](https://www.collinsdictionary.com/dictionary/english/ritual)同时涵盖宗教与其他仪式。 |
| extend | Major | 源“伸展”被限成身体部位，已提供WordNet中的折叠桌腿、布料、天线等主动展开对象未覆盖。修订放宽为肢体或可伸展物体；[Collins](https://www.collinsdictionary.com/dictionary/english/extend)与具体WN证据支持该范围。 |
| scholar | Minor | 选择理由无义项频率证据却写“最常用”；修订只改为AI教学建议。 |
| contact | Minor | 接触动词注释误加“使某物……”使动方向，所引WN证明直接接触状态/动作；修订注释。 |

新确认2 Major +2 Minor，Critical确认0。未把全部模型标签当错误：render仍证据待核；restore为逐片段引证范围待核；attach情感用途为外部候选建议，未自动计确认Major。详见PARENT_ADJUDICATION.json、REVISED_CANDIDATES.json。4词独立修订均未覆盖封存生成结果或替换活动合并候选。

低风险池14词，固定哈希抽2词（spouse、persuade），先给原文与证据、不提供生成答案。未确认漏报错误；persuade合一组或按信念/行动分两组是教学差异。目标二审88词，实际完成87；pursue原响应回显输入，唯一允许的修复仍不符合契约，明确保留审查失败，不再重试。

## 质量统计（实际700词）

| 指标 | 数量 |
|---|---:|
| 实际候选 | 700 |
| 原文片段总数 | 1702 |
| A 原始片段平均数 | 2.431429 |
| B 首次核心义组平均数 | 1.541429 |
| 核心义组最大数 | 5 |
| 超过3组词数 | 8 |
| 无可靠核心/证据不足 | 0 |
| 词典补充候选 | 224 |
| 保留的独立词典观察 | 126 |
| 需要人工复核 | 688 |
| 风险隔离词 | 24 |
| 历史48待审 | 48 |
| 新词定向二审 | 85 |
| 低风险source-first抽检 | 2 |
| 二审失败词数 | 1 |
| 纯教学偏好词数（新增批） | 50 |
| 人工签审 | 0 |

### 分组统计（新模型仅处理C中的100词）

```json
{
  "A_original500": {
    "record_count": 500,
    "original_fragments": 1216,
    "original_fragment_mean": 2.432,
    "core_groups": 693,
    "core_group_mean": 1.386
  },
  "B_blind100": {
    "record_count": 100,
    "original_fragments": 237,
    "original_fragment_mean": 2.37,
    "core_groups": 178,
    "core_group_mean": 1.78
  },
  "C_new4732": {
    "record_count": 100,
    "original_fragments": 249,
    "original_fragment_mean": 2.49,
    "core_groups": 208,
    "core_group_mean": 2.08
  }
}
```

### 处理状态

```json
{
  "AI_processed_needs_human_review": 674,
  "confirmed_problem_revision_pending": 13,
  "AI_processed_no_obvious_risk": 12,
  "processing_failed_or_evidence_insufficient": 1
}
```

### 原书分类

```json
{
  "高频词": 541,
  "中频词": 19,
  "低频词": 13,
  "偶考词": 32,
  "基础词": 95
}
```

### 自动AI风险标记（不是确认错误）

```json
{
  "Info": 1071,
  "Minor": 63,
  "Major": 23
}
```

### 二审提出问题（未经逐条证据裁定不算确认错误）

```json
{
  "Major": 5,
  "Info": 45,
  "Minor": 12
}
```

### 历史证据支持问题

```json
{
  "Minor": 2,
  "Major": 7
}
```

### 本轮新增证据支持问题

```json
{
  "Major": 2,
  "Minor": 2
}
```

上述候选均值分母为实际700词。正式5332原文片段平均数为 2.243623（只读解析原文，不代表生成）；全5332核心组均值不可计算（null）。未处理4632词不填模板。

压缩数字只描述展示，不证明学习效果、释义准确率或官方考试义项频率。源外新义全部独立存放，未自动升级核心。所有已生成/复用词的原文片段、Unicode位置、一对多拆解说明保留。

## 独立性、失败与成本

本轮生成请求与返回为deepseek-flash，二审请求与返回为deepseek-v4-pro；不同模型标识及官方文档版本均有记录，提供方内部实际权重/统计独立性无法自行验证。二审采用无历史API上下文，低风险样本不提供生成答案，定向二审收到候选。AI意见与证据支持错误分别存储。

保存的实际API响应：151。实际用量：`{"prompt_tokens": 535392, "completion_tokens": 715388, "total_tokens": 1250780, "prompt_cache_hit_tokens": 273664, "prompt_cache_miss_tokens": 261728, "reasoning_tokens": 633801}`。实际账单费用不可获得（null）；按官方缓存/峰谷价格估算USD范围：[1.1031, 2.206199]，不是实际扣费。

API费用估算仅含实际DeepSeek请求，按各请求返回模型分别计价，包含失败/未采用的预检与重试。当前Codex父会话的用量及费用不可获取，均为null。历史48仍为high待审，不将它们重新评为48个Major；新增Info台账提醒不解除原high风险。

失败记录：`["batch_001_STOP.json", "generation_001_02_structure.json", "generation_001_06_structure.json", "generation_001_33_structure.json", "generation_001_36_structure.json", "review_001_14_structure.json", "review_001_63_structure.json"]`。成功输出原样缓存，重跑整合不会重新调用模型。

## 安全、测试与后续门槛

正式5332原文、旧500及盲测100文件、个人SQLite及其旁文件均仅做哈希读取；脚本不建立SQL连接、不请求Notion、不上传事件、不改UI/日语模块/数据库路径。

自动化验证结果见VALIDATION_RESULTS.json、TEST_EXECUTION.json和REPRODUCIBILITY.json。数据契约通过不等于全量数量验收或语义放行；full5332_count_passed=false。旧证据未全部内嵌lemma列表，旧暂存可仅引用ID，验证器采用原许可词头证据目录与完整原文表核对，没有改写旧成果。

输出文件名按任务保留core_meanings_5332_candidates.json，内部record_count=700、generation_complete=false、missing_ids=4632条。风险台账覆盖实际700词，不能称已审完5332。

下一阶段先修正模型执行中的通用范围覆盖检查，使用本批100词及旧600回归验证，再评估是否恢复剩余4632词；当前不建议直接继续全量或进入正式发布审核。停止后没有新的模型调用。

## 实际测试执行

Python唯一测试 37 项，Dart/Flutter唯一契约测试 20 项通过；新增测试文件静态分析无问题。重复整合字节一致。数量验收未通过，语义结论仍为C。

| 检查 | 结果 |
|---|---|
| `python -X utf8 scripts/p6c5/validate.py` | exit 0；700条数据契约通过；full5332_count_passed=false，semantic_quality_gate_passed=false |
| `python -X utf8 -m unittest discover -s test/p6c5 -p test_*.py -v` | exit 0；20项；最终700词快照、原文保护、无假签审、停止后禁止模型调用及独立修订契约 |
| `python -X utf8 -m unittest discover -s test/p6c4 -p test_*.py -v` | exit 0；17项；旧600不变与历史风险/门槛回归 |
| `flutter test --no-pub --reporter expanded test/p6c2/core_meanings_500_contract_test.dart test/p6c3/core_quality_review_contract_test.dart test/p6c4/v4_isolated_contract_test.dart test/p6c5/full_candidates_contract_test.dart` | exit 0；20项；C2/C3/C4/C5数据契约 |
| `flutter test --no-pub --reporter expanded test/p6c5/full_candidates_contract_test.dart` | exit 0；最终700条快照5项复验；不重复计唯一测试数 |
| `dart analyze test/p6c5/full_candidates_contract_test.dart` | exit 0；No issues found |
