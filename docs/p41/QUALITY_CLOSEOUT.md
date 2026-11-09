# P4.1 词库质量收尾

2026-11-09，沿用 **0.7.0+10** 的 500 词内容和正式学习模块。本轮不改释义、词性、拼读字段或稳定 ID，不向 Notion 写入内容或真实学习事件。

## 标记分级与处理

原始 [P4 quality-flags.csv](../p4/quality-flags.csv) 保留原样，SHA-256 为 `013cdf6d7eb0da6fec849ec20a272645e2be9545db20306f26951952e2d3ba58`。94 条标记涉及 72 个不同词，不表示有 94 个错误。

| 类型 | 标记数 | 处理 |
|---|---:|---|
| 已证实错误释义 | 0 | 未取得足以更改释义的反证，不批量覆盖 |
| 词性歧义 | 47 | 6 条 WordNet 覆盖差异，41 条语境读法风险；保留当前词性及提示 |
| 自然拼读提示错误候选 | 39 | 37 条多读法、2 条多重读位置；未证实为提示错误，列听辨待确认 |
| 数据来源问题 | 1 | texture 补充映射证据已完成，关闭本项缺证 |
| 普通警告 | 7 | 6 条大小写/重音符号去重风险，1 条 oriental 语域风险；保留警示 |

优先级按误学影响而非仅按自动规则命名：P1 为词性会改变读音、语域或来源的重点项，共 20 条、14 词；P2 为一般变体和词典覆盖差异，共 68 条；P3 为已有独立 ID 保护的词形警告，共 6 条。texture 的 P1 已补证，其余 P1 不等于已证实错误。逐条原始标记、分级、决定和证据见 [quality-triage.csv](quality-triage.csv)。

## 有依据的复核

共 26 词保留逐字段前后对照：17 词沿用 P4 出版社词典/官方材料核验记录并对照现卡，新增 9 词本轮查询词典；texture 本轮另核原书。每条含原值、现值、依据与核验方式，见 [review-before-after.csv](review-before-after.csv)。这属于 agent 依据对照，**不冒充用户或教师终审**。

- object 当前名词首重读，increase 当前动词后重读；[object](https://dictionary.cambridge.org/pronunciation/english/object)、[increase](https://dictionary.cambridge.org/us/pronunciation/english/increase) 的出版社词典读法支持现卡。
- use 当前动词词尾浊辅音，separate 当前形容词结尾轻读；不能把另一词性的读法当成本卡答案。[use](https://dictionary.cambridge.org/pronunciation/english/use)、[separate](https://dictionary.cambridge.org/pronunciation/english/separate)。
- address 的名词美式首重读有据；beloved 形容词存在两/三音节变体，现卡列三音节并说明所用读法，未据另一合法变体强改。[address](https://dictionary.cambridge.org/pronunciation/english/address)、[beloved](https://dictionary.cambridge.org/pronunciation/english/beloved)。
- elementary 的 men 重读、fifteen 单独报数末音节主重读、interesting 首重读及三/四音节变体与词典对照保留。[elementary](https://dictionary.cambridge.org/pronunciation/english/elementary)、[fifteen](https://dictionary.cambridge.org/pronunciation/english/fifteen)、[interesting](https://dictionary.cambridge.org/dictionary/english/interesting)。
- resume/résumé 保留两个 ID；lead/read 保留本卡词性/时态限定；overhaul 明确本次名词练习，不能将动词末重读套到名词。[resume/résumé](https://dictionary.cambridge.org/pronunciation/english/resume)、[lead](https://dictionary.cambridge.org/pronunciation/english/lead)、[overhaul](https://dictionary.cambridge.org/pronunciation/english/overhaul)。read 和其他历史依据逐项见对照表。
- WordNet 没覆盖某词性不构成判错。yes 的副词/感叹词标签统一、might 的语法标签精细化保留人工决定；不据此覆盖正常词义。oriental 称人风险的原警示及物品例句继续保留。

## texture 的补充映射

稳定 ID `28171f83-01fb-5cf2-943d-ee61b96942c5` 不变。旧快照已经记录从 **R4983** 恢复 texture。原排除行混合为 `n t/599 texture/631`，清洗仅处理了前面的跨栏碎片；不能因为该行被排除，就认为第二个有效词没有原书出处。

本轮用已有文本层和页面图像交叉核对：索引 PDF **766** 明确列 `texture/631`；正文 PDF **642** 有 texture、名词标注及页脚 **631**；目录 PDF **10** 显示偶考词从 **589** 开始、基础词从 **640** 开始，所以 631 属于**偶考词**。未重新 OCR。

只新增 [texture-mapping.json](texture-mapping.json) 补充台账，保存 R4983 原行、旧状态“待补证”与新状态“补充映射已核验”、文件校验值及本机证据路径。**R4983 的 599/610 属于被排除碎片，不作为 texture 页码。**原 5,552 台账与排除行不改写，原“本轮恢复”历史不改成虚构的原台账直接命中。

原 PDF SHA-256：`5e4501eb7237e59ddbc6a2ba0d83bfc3874c963ded439e6394b711afd2ba192a`。页面图像及已有文本摘取只放在本机 `private/p41/`，不随安装包或公开文档发布原书内容。

## 完整性和边界

500 词必填字段齐全、稳定 ID 无重复。PETS-3 2025 的 500 条状态仍为“待核实”，原书考研分类不解释成 PETS-3 词频。500 词结构检查和 26 词依据复核不代表所有中文义项、例句或发音均已由教师逐词终审。

词库 CSV SHA-256 保持 `09cd736d61c40f9614239e451f5894ad464f2ff69a863d50bde95b03b87f651d`。前后内容变化 **0**；唯一状态变化为本报告中的 texture 补证台账。历史 P4 审计不覆盖，Notion/SQLite 不需要为了该侧录证据重新导入。复核脚本为 `scripts/p41/audit.py`，只读正式数据，报告见 [quality-summary.json](quality-summary.json)。
