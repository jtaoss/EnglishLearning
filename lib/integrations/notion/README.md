# Notion Windows 只读同步（P1-C）

P3：Windows 可选 100／200／500 词范围，按最多 100 个 ID 一组查询并分页，全部结果校验后才调用一次 `applyNotionBatch`。首次、手动全量或本地关联数量不足时完整核对，防止扩大范围遗漏旧时间戳的词。新增内容字段在旧 schema 中可缺省，已存在但类型不符仍拒绝；个人学习字段不映射到词库内容。Android 本轮暂停，保留原 100 词读取适配。公开读取客户端仍无正式事件写入接口；批量内容写入预览见 docs/p3，未获批准前不执行。

Notion 是云端词库和学习记录中心，SQLite 提供离线工作副本；不部署自建服务器。

NotionReadApi 封装官方 HTTPS 读取、限流、超时和固定错误；NotionFields 校验并映射已核验的 100 个稳定 ID；NotionSyncService 完成分页后通过 NotionSyncStore 一次事务更新内容和水位。NotionSyncController/Page 提供 Windows 手动同步与安全配置入口。通用 HTTP 依赖、主题、路由和错误处理继续沿用。

词库内容按 Notion 来源及稳定词条 ID 更新；个人状态与内容使用独立变更路径。回写前检查 ID 与页面一对一映射，零条/多条先报告冲突，不盲目创建。Notion 普通文本字段本身不提供唯一约束。

个人只读集成凭据在程序内输入，WindowsNotionCredentials 通过 runner 的 CredWriteW / CredReadW 存入当前 Windows 用户的凭据管理器；没有普通文件后备。Android 本轮暂停，只保留平台无关的接口和已有配置。此方案用于个人软件。

客户端没有创建/更新 Notion 页面的方法；不回写学习记录，不删除本地词条。API 版本固定 2026-03-11。字段、事务、权限及验收证据见 docs/p1c/NOTION_SCHEMA.md、SYNC_DESIGN.md、NOTION_AUTH_SETUP.md 和 P1C_REPORT.md。
