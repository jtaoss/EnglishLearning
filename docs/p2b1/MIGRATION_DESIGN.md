# P2-B1 隔离副本迁移与事件协议

正式入口保持 schema v3，新增 `SqliteLearningRepository.openIsolatedCopy` 供本轮验收。没有自动迁移用户库、正式事件上传入口、生产事件凭据或真实 Notion 写网关。

## 文件与入口保护

真实文件在关闭应用后以 SQLite `mode=ro` 打开，通过 backup API 生成独立备份并逐表比较。记录原文件前后 SHA-256、备份 SHA-256、完整性和外键检查。副本由该备份复制到 `docs/p2b1/private/`，私有目录不进入交付包。

副本入口要求 `.copy-permit.json` 明确标记 role=isolated_learning_copy、simulation_only=true、实际副本路径及受保护原路径；解析符号链接并检查文件身份，拒绝原路径或别名指向原文件。每次副本操作重查标记。它用于防止误操作，不是抵抗本机恶意代码的权限隔离。默认正式入口拒绝 v4，正式启动路径未切到副本。

## 迁移事务与旧数据

整个 v1/v2/v3 → v4 迁移在一个 BEGIN IMMEDIATE 中完成，复用原 v2/v3 DDL，嵌套步骤用 savepoint。任一步失败回滚表、记录和 PRAGMA user_version。v4 重复打开不重建快照、不重置设备身份或序号。

原有 vocabulary、learning_progress、review_events、pronunciation_progress、pronunciation_events、notion_sync_state、notion_word_links 在 v3 副本中逐行保留。v1/v2 只补原先版本尚未拥有的基础表，不根据现有评级填充旧事件。

新增 `migration_state_snapshots`，每词保存迁移时已持久化的原状态与 provenance=history_state_snapshot。captured_utc 是实际迁移时间；没有实际学习时间时保持空，不把 captured_utc 当学习发生时间。review_count 即使与留存事件数量不同也按原值保留，不补造缺失事件。已存在的旧 review_events / pronunciation_events 留在原表，不回填 outbox。

## 新事件与学习事务

| 新表 | 作用 |
|---|---|
| copy_journal_meta | 持久设备 UUID、单调序号、simulation_only、全队列限流等待时间 |
| learning_journal | UUID Event ID、action_key、Word ID、学习类型、精确评级、发生时间、设备/序号、格式/算法版本、来源、规范载荷和哈希 |
| journal_outbox | 事件外键、pending/sending/uncertain/synced/conflict、回执、等待时间和固定错误分类 |
| migration_state_snapshots | 历史状态快照；不作为学习事件上传 |
| journal_inbox | 云端回传证据及哈希，matched/requires_review/quarantined；不投影到评级表 |

同一短事务同时写入词义或发音状态、对应原事件表、新学习日记、outbox 和设备序号。词义和发音各有独立事件类型，不互相覆盖。队列 INSERT 失败时整个学习事务回滚，避免“评分已保存但队列缺失”。网络调用在事务外；断网不会阻止本地提交。

新事件 UUID 在本地提交时确定，不在上传或重启时重生成。词义 action_key 支持同一操作重放幂等；同 key 不同内容报错。发音沿用既有 attempt_id 去重，不改音频/自然拼读实现。哈希按字段名排序，远端 JSON 键顺序不同不被误判为内容差异。

来源严格区分：本轮在副本上发生的操作全部为 simulation_test；历史为 history_state_snapshot 或原表真实记录；未来 new_learning_event 仅在用户确认和 P2-B2 正式迁移后启用。当前表约束只允许 simulation_test。默认正式库拒绝日记/inbox 接口；P2-A 模拟表也不会导入正式库。

## 回传与恢复策略

本轮 `CopyJournalCloud` 是隔离协议契约；自动化使用内存模拟，Windows 原生测试使用私有目录中的磁盘模拟云端。**没有发出新的 Notion 创建/修改请求，不将模拟通过说成正式 API 试写通过。**P2-A 真实 API 的 24 条既有结果不能替代 P2-B2 的正式网关和授权验收。

上传前查询相同 Event ID；唯一且完整哈希一致才确认。发送前持久化 sending。超时、响应丢失或本地确认失败后保留身份，先查询；结果不明且查不到时停留 uncertain，不盲目重建。重复 ID 或内容不同列为 conflict，不覆盖任何评级。

下载分页先完整暂存，再一次事务写 inbox；缺页、重复游标或 incomplete 标记拒绝提交该批 inbox。新回传事件、评级不同或来源不符只保存为复核/隔离证据，不改词义评级、发音状态、复习日期或已有事件。没有多设备冲突合并，也不承诺“严格恰好一次”。

模拟限流保留 Retry-After 对应时间，跨重启生效并阻止整队列请求。写入单实例保护与 Windows 文件锁约束同路径的单写入者；跨设备和不同副本的互斥尚未实现。

正式 Notion 结构、最小授权和 1～3 条新事件方案见 `P2B2_WRITE_PLAN.md`、`FORMAL_EVENT_SCHEMA.sql`；回滚见 `ROLLBACK_PLAN.md`。
