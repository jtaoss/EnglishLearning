# P6-C 语义提炼提示词 v2

角色：英语学习内容编辑。读者：零基础至 PETS-3 学习者。

输入只能是 selection.json 中选定的 100 个稳定 ID 对应的正式 CSV 原文，以及本次取得的 WordNet 3.1 释义证据。不得把全库送入模型。考研 book_category 仅用于抽样，不是某义项的使用频率或 PETS 官方重点证据。WordNet 的排列、词义数量也不是语料频率证明。

对每个词逐一做语义判断：

1. 保留原始 meaning_zh 和 part_of_speech。先识别明确词性标签；没有对应标签的多词性解释保持“待核实”，不得默认取第一个词性。
2. 拆解可追溯的原文解释，再决定哪些是同义或近义表达。逗号、分号本身不能证明同义或多义。身体/方位、光/灯、数量/配对等不同概念分别保留；同一个词的名词、动词、形容词不能并入一个组。
3. 输出核心、常用扩展、其他三层。通常核心 1–2 组；多个重要义项可以超过两组，并说明原因。排序是面向学习任务的建议；不得虚构实测使用频率。
4. 所有原文解释恰好归入一个层级，并关联 source_sense_id、字符区间和逐字原文。原文有疑义时仍保存，但标为 source_sense_suspect，不能把“被保留”解释为“词典已证实”。
5. 给每个词写具体的简短记忆说明、选择理由、风险和模型自评 confidence。confidence 不是校准概率，也不是正确性或审核凭据。
6. 不新增正式释义。若提出新义项，放入 model_added_senses，标记 model_added、来源和待审核；不能混入 formal_gloss。本试点选择不添加新义项。补充词典里存在、但原文缺失的义项只记录覆盖局限，不暗中补入。
7. 标出过度合并、遗漏、罕见义在前、词性混淆、疑似虚构、来源不明和学习适用性问题。区分“旧草稿中观察到的问题”“本轮修正”“尚待人工判断”，不得把风险数量说成准确率。
8. 每条保留 stable_id、headword、part_of_speech、core_meanings、extended_meanings、other_meanings、core_explanation、usage_example、selection_reason、confidence、review_required、model_version、source_hash；附加可验证的输入快照与证据。
9. 所有结果为隔离草稿，review_required=true。另建人工复核台账，reviewer、reviewed_at、decision_hash 初始为空；AI 不得代签、不得把生成成功当成人工通过。

输出后必须校验 100 个唯一 ID、五组各 20、原文覆盖、无重复归属、词性边界、哈希和来源。结构校验只证明结构，不证明语义准确。

本次执行者：Codex 当前 AI 会话。精确后端模型 ID / 快照未由执行环境提供，不能据此声称使用了某个具体 API 型号。semantic_decisions.py 保存本会话逐词语义决定；build_core_pilot.py 只是可重复的装配与校验，不是另一次 AI 推理。
