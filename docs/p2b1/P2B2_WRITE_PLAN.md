# P2-B2 正式新事件试写建议（未执行，待用户明确确认）

本轮只准备结构与方案，不创建正式事件库、不授权正式写集成、不上传真实新事件或历史。`FORMAL_EVENT_SCHEMA.sql` 是可审查的 Notion 结构草案，不是已存在数据库的证明。P2-A 模拟库及其 24 条记录继续独立。

## 正式目标与字段

建议名称“EnglishLearning · 正式学习事件（1～3 条试写）”，作为私有顶层数据库，独立于词库、P2-A 库和状态快照库。初期一条 Notion 页面代表一条不可变事件。Event ID 使用本地已经保存的 UUID，不在上传时重生成；Word ID 沿用现有稳定 ID。

| 字段 | 类型及规则 |
|---|---|
| Event ID | Title；设备内已持久化 UUID；Notion 文本本身不保证唯一 |
| Word ID | Text；必须属于现有核验词条，不用词头替代身份 |
| Learning Type / Grade | 类型为 meaning/pronunciation；词义保留 mastered/familiar/forgotten；发音保留 needsPractice/familiar/confident |
| Occurred At UTC | 来自新学习操作的实际时间，不用上传时间或旧最终评级推算 |
| Device ID / Sequence | 明确属于真实设备的持久身份和单调序号；不能复用隔离副本设备身份 |
| Schema / Algorithm Version | 事件格式与复习算法/自评规则版本 |
| Origin | 仅 new_learning_event；拒绝 simulation_test、history_state_snapshot 及 P2-A 模拟批次 |
| Payload Hash | 规范化后的载荷校验，回传键顺序不影响校验 |
| Pilot Batch / Client Version | 独立试写批次与程序版本，便于限定 1～3 条范围 |

历史状态快照保存在本地迁移审计区，不进入事件待上传队列。旧版本实际已记录的 review_events / pronunciation_events 保留原表，本阶段不批量回填或回写。未来若需历史云端归档，应单独授权、定义来源与缺失字段，不能按最终评级补造事件。

## 权限与启动门槛

1. 用户先明确确认：允许创建独立正式事件库，并试写 **1～3 条确认后新产生的真实事件**。本轮指令尚不构成这一步确认。
2. 另建仅 Read content + Insert content 的正式事件集成，只授权正式事件库；不扩展词库只读集成，也不使用 P2-A 写密钥。
3. 初期不授予 Update content、删除、评论、用户信息或代理权限。没有现有事件或词条覆盖接口。
4. 新凭据放到独立 Windows 凭据管理器键；不接收聊天密钥，不用环境变量/Dart define/日志/普通配置文件保存。
5. 先完成真实个人库再备份、校验和非破坏迁移验收。B1 的副本功能不会自动迁移正式库，也不会自动把隔离数据库替换为正式库。

官方权限依据：[Read 与 Insert 能力](https://developers.notion.com/reference/capabilities)。这是本项目拟定的最小范围，不代表本轮已授权。

## 1～3 条新事件方案

先指定最多 3 个现有稳定 Word ID，用户本人在新版完成新的学习操作。第一条只选一种学习类型，确认本地“评级/日期 + 事件 + outbox”事务完成，再上传。先按 Event ID 查询；创建成功后核对全部字段、唯一性及本地评级不变。重复同步、新进程重启并对账通过后，再由用户选择是否增加第二、第三条，可覆盖另一学习类型。

只允许本地白名单中的这 1～3 个 Event ID、Origin=new_learning_event、本试写批次及确认后时间窗。历史事件、隔离副本事件、模拟库记录和状态快照一律不在范围内。不要把设备当前最终状态改写成“历史学习事件”。

发生创建超时、连接断开、5xx 或确认失败时保留 sending/uncertain，先查询并核对。查不到不自动重新创建；查询也失败时继续离线保留本地数据。重复 ID 或内容差异进入人工复核，不采用“最后写入覆盖”。限流按 Retry-After 持久等待，不连点重试。参考 [Notion 限流](https://developers.notion.com/reference/request-limits)与[分页截断标记](https://developers.notion.com/reference/query-a-data-source)。

## 通过条件与停止条件

通过条件：1～3 个本地 ID 对应相同数量的唯一云端页面；完整载荷一致；重复/重启不新建；原 100 词、词义/发音状态及复习日期完整；无敏感日志。

若出现不明写入查不到、同 ID 多页面、哈希不一致、错库授权或迁移校验失败，停止新写入并保留所有事件、回执、备份及审计，不删除云端页面凑数量。回滚软件不会撤销远端创建，恢复备份也不能直接丢弃待对账的事件身份。

本阶段不开放多设备冲突合并、Android、历史批量回写、自动归档或自建后端。是否进入正式试写由用户在查阅 B1 报告后另行明确决定。
