# P3-E：正式事件库实施准备与恢复门槛

本文件是实施准备，不是正式库已存在或真实上传已获授权的证明。`personalEventUploadEnabled` 继续为 false，正式 SQLite 继续 schema v3。

## 直接复用的边界

- `integrations/notion/events/`：P2-A 独立模拟库、稳定事件 ID、先查后建、重复 ID/哈希冲突、超时后不盲目重建、限流延期。
- `core/storage/copy_learning_journal.dart`：P2-B1 隔离副本许可证校验、schema v4、事务内事件/outbox、持久设备身份及递增序号、历史状态快照独立保存。
- `integrations/notion/journal/copy_journal_sync.dart`：单实例/跨进程锁、pending/sending/uncertain/synced/conflict、查询对账、inbox 接收与人工复核；不将远端事件自动投影为本地最终评级。
- `test/p2a/`、`test/p2b1/`：已有隔离迁移、失败回滚、重复/超时/重启/冲突验收继续作为回归门禁。本轮完整自动化中继续通过。

不新增另一套同步框架，不把隔离库或模拟设备身份替换成正式个人库。

## 正式事件结构草案

继续采用一条不可变事件对应一条 Notion 页面。保留 Event ID、Word ID、Learning Type、Grade、Occurred At UTC、Device ID、Sequence、Schema/Algorithm Version、Origin、Payload Hash、Pilot Batch 与 Client Version。事件 ID/时间在本地新学习操作中生成和保存，上传及重试时复用。

P3 发音事件须另外保留**评估依据**：有合法录音并完整听音后的自评，或尚无录音的自主认读自评。正式载荷应包括 `assessment_basis` 和 `audio_asset_id`，算法版本区分新的认读流程；不能把 `self-reading:<entry_id>` 解释为播放过录音。现有本地 pronunciation_events 已记录该来源；旧 P2-B1 模拟载荷没有这一依据字段，不能直接声称它已具备全部正式 P3 发音语义。正式适配前在副本验证载荷规范化哈希、往返与重复身份。

历史最终状态只能进入明确标记的迁移快照；不反推发生时间、次数或伪造过去事件。原 review_events / pronunciation_events 保留，不擅自批量回填云端。

## 单独授权后的最小实施顺序

1. 用户明确批准独立正式事件库与最多 1–3 个授权后新事件；词库 200/500 扩容授权不涵盖这一项。
2. 独立集成仅 Read + Insert，只授权正式事件库，凭据使用独立系统安全存储键；不扩大词库只读连接。
3. 关闭正式应用，保存正式库与待对账队列的只读备份及哈希；在隔离副本验证必要迁移、回滚和新评估依据字段。
4. 将确认后真实操作写入本地评级/时间、不可变事件和 outbox 同一事务；不使用模拟 origin、测试设备或历史快照。
5. 只处理白名单 Event ID，先查唯一性和完整载荷；成功后保存回执，重启再查不新增；通过后才考虑第二、第三条。

## 故障与恢复

| 情况 | 保留事实与下一步 |
|---|---|
| 创建超时或断网，是否写入不明 | 保留 sending/uncertain 和同一事件 ID，先查云端；查不到不自动重建 |
| 同 ID 多页面或载荷不一致 | conflict/inbox 人工核对，停止新写入，不用最后写入覆盖 |
| 429 或服务器延期 | 持久保存等待时间，按 Retry-After 恢复；不连点重试 |
| 本地迁移/事务失败 | 回滚事务，保留原文件、快照、队列和审计；不删除重建 |
| 还原备份/降级程序 | 先对账备份之后可能已创建的远端事件；不得丢弃待确认事件身份 |
| 云端不可用 | SQLite 词义学习与自主认读继续；重启恢复本地状态 |

通过标准为唯一云端页面、载荷一致、重复/重启无新增、原词库及个人评级/日期/发音状态完整。真实试写授权尚未取得，因此没有创建正式事件库或上传真实事件。
