# P6-C.1 独立质量复核资料

只复核现有100词；旧P6-C、正式CSV、SQLite和Notion均不改。人工确认没有增加。

- [复核报告](../P6C1_INDEPENDENT_REVIEW_REPORT.md)：结论、证据局限、问题分类及验证。
- [100词对照表](REVIEW_COMPARISON.md)：原文、建议三层、保留疑点、来源外候选和逐词理由。
- [结构化独立结果](independent_review.json)：100词、八项检查、逐义证据、原决定及新决定哈希。
- [证据目录](evidence_catalog.json)：具体WordNet义项与19条词典网页观察；403/搜索摘要局限如实记录。
- [后续规则v3](RULES_V3.md)：语义区别与记忆展示分别建模，新增内容不冒充原文。
- [原输入冻结副本](input_p6c_snapshot.json)：输入角色，字节与旧提炼JSON相同，不是新生成结果。
- [保护清单](preservation_manifest.json)、[验证结果](validation_results.json)。

状态：29词调整分层/显示；4词修订并保留原文歧义或语境项；15词保留分层但加补充候选；52词保留并补证据说明。标签有交叉，不是裁定错误率。共26个补充候选，仍为独立建议。

这些文件不兼容旧UI的数据加载schema，没有替换或接入应用；不要直接导入正式数据库。
