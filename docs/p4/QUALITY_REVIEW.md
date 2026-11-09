# 词库质量异常与来源核验

500 词只读审计完成；结构阻断 0。自动筛查得到 **94 条提示，涉及 72 词**，主要是多读音、大小写/重音符号、WordNet 词性覆盖差异和语境限定。这些是复核提示，不等于同样数量的错误。

已对 17 个高风险词逐项对照词典/官方参考并保留结论：[review-before-after.csv](review-before-after.csv)。内容前后均相同，未批量覆盖原释义或云端字段。其余提示详见 [quality-flags.csv](quality-flags.csv)。

- `overhaul`：名词首重读、动词末重读；原提示及名词例句一致，保留。[Cambridge](https://dictionary.cambridge.org/dictionary/english/overhaul)
- `combat`：原名词首重读成立；美式动词也有首重读变体，不能机械套用“动词必末重读”。[Cambridge](https://dictionary.cambridge.org/dictionary/english/combat)
- `resume` / `résumé`：继续的动词与求职简历的名词保留独立 ID、词性和读法。[Cambridge](https://dictionary.cambridge.org/us/dictionary/english/resume)
- `lead` / `read`：原卡分别限定带领的动词和现在时阅读；保留语境提示，建议例句 TTS。[Cambridge lead](https://dictionary.cambridge.org/dictionary/english/lead)、[Collins read](https://www.collinsdictionary.com/us/dictionary/english/read)
- `outside`：初始审计错误地只取 CMU 首个重读位置，造成一条假警报；已修正审计器，保留原词。CMU 本条含两个重读位置，仍需结合副词/介词语境。[Cambridge](https://dictionary.cambridge.org/dictionary/english/outside)
- `percent`、`vegetarian`、`why`：词典支持原卡相关词性；WordNet 覆盖差异不是删改依据。[percent](https://dictionary.cambridge.org/dictionary/english/percent)、[vegetarian](https://dictionary.cambridge.org/dictionary/english/vegetarian)、[why](https://dictionary.cambridge.org/dictionary/english/why)
- `yes`：肯定答复义保留；副词/感叹词标签在词典体系间不同，仍列语法标签统一待复核。[Cambridge](https://dictionary.cambridge.org/dictionary/learner-english/yes)
- `oriental`：原卡已有不推荐称人的提示，保留阅读识别用途。[Oxford](https://www.oxfordlearnersdictionaries.com/definition/english/oriental_1)
- `texture`：词义/名词与词典一致；这是既有审计恢复词，当前5552台账没有同形/同ID直接映射。既有来源 PDF642 对应书内631，落在偶考分区；原始映射证据仍待补齐，不删除词条或伪造台账对应。[Cambridge](https://dictionary.cambridge.org/dictionary/english/texture)

原书分类与原台账直接对应 499 词，另 1 个 texture 如上留证据缺口。PETS-3 2015 明确词形匹配473；2025全部待核实。原始台账未删、未重新OCR。所有义项的完整人工终审仍未完成，个人确认字段未自动提升。
