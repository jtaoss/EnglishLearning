# P1-C Notion 数据结构

目标数据库：[英语词库 · 2015参考筛选试导入（100词）](https://www.notion.so/0351820ea5c1428ba25a454b7de32773)。数据库 ID 为 `0351820e-a5c1-428b-a25a-454b7de32773`，数据源 ID 为 `157d89e5-71fb-4e68-9640-1b04dbb1e627`。

复用原有 100 个页面，未创建另一套词库。客户端仅同步 assets/vocabulary/verified100.csv 限定的既有 100 个稳定 ID，保留大小写及特殊词头，不导入全量 5,552 词。

| Notion 属性 | 类型 | SQLite content_json 字段 |
|---|---|---|
| 词条ID | 文本 | entry_id；既有稳定主键 |
| 单词 | 标题 | word；须与已核验样本一致 |
| 中文词义 | 文本 | meaning_zh |
| 原书分类 | 选择 | book_category；不重新推断词频 |
| 来源文件 | 文本 | source_file |
| 来源ID | 文本 | source_id |
| 原书PDF页码 | 文本 | source_pdf_pages |
| 索引PDF页码 | 文本 | source_index_pages |
| 原书核验状态 | 选择 | book_verification；须已核验 |
| 释义复核说明 | 文本，本轮新增 | meaning_review_status；保留 AI 对照与个人确认的区别 |
| PETS3 2015收录状态 | 选择 | pets2015_status；已收录/未直接列出/待核实 |
| PETS3 2025收录状态 | 选择 | pets2025_status；本轮必须待核实 |
| 学习词库分类 | 选择 | library_class；主学习/扩展/暂缓 |
| 词性 | 文本 | part_of_speech |
| 用法说明 | 文本，本轮新增 | usage_note |
| 释义来源 | 文本，本轮新增 | lexical_sources |

本轮只新增三个文本属性，未改原属性类型、选项或视图。原“词义整理状态”继续保留“独立编写待复核”，不将 AI 对照当成人工认证。原数据版本、哈希、筛选理由、AI 评分及历史批次原样保留；客户端根据实际映射字段重新计算自己的 SHA-256。

Notion 中的学习状态、发音状态、自然拼读状态、听音学习状态、笔记和原创例句均不属于本轮同步映射。它们未被本轮云端更新覆盖。SQLite 新词使用数据库默认值“未测试”，不从 Notion 复制个人学习历史。

Notion 文本属性没有唯一约束。导入前检查完整 100 条，客户端在分页、稳定 ID、词头、源页面映射和 SQLite 主键层面分别检查冲突，拒绝整批写入。云端归档/删除不会触发本地删除。

云端整理先更新 big、tree、autumn、percent、there 五词并读取核验，再更新其余 95 词。更新中文释义及词性/复核说明/用法/来源共五个属性，56 条释义从此前版本作澄清；其余属性保留。完整前后快照、五词验证及 100 词一致性结果位于 evidence/，可导入 CSV 为 verified100_notion.csv。
