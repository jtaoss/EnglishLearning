# 本地词库

VocabularyCsv 兼容原 13 列 CSV，并接受 part_of_speech、usage_note、lexical_sources 三个可选字段，支持 UTF-8 BOM、引号、逗号和换行，单批最多 100 词。拒绝损坏行、重复 ID、空字段、未核验词头和本阶段不可靠的 2025 官方声明；不生成 ID 或推断官方收录。

VocabularyController 连接异步 Repository 和页面；导入按钮读取已保存的 100 词样本或用户通过系统对话框选择的 CSV。默认主学习，可查看扩展/暂缓；列表隐藏中文。

全部来源和原书分类在内容中保留，100 条词义和词性已作来源对照（AI），仍待个人确认。2025 官方归属保持待核实。
