# Windows 只读同步设计

客户端直接访问 https://api.notion.com，固定 Notion-Version: 2026-03-11。仅实现 GET /v1/data_sources/{id} 与 POST /v1/data_sources/{id}/query；后者是读取查询，不是页面写入。HTTP 禁止重定向，不接受可配置的服务器地址。复用 Starter 中已经锁定的 http、crypto、csv 依赖，没有增加 Flutter 包或升级依赖。

NotionReadApi 负责带认证的限量读取、超时和安全错误。原通用 ApiClient 继续保留；它没有认证头、流式大小限制和 Notion Retry-After 语义，因此不强行改变它的既有调用行为。新适配器不记录请求头、请求体、响应体、原生异常文本或密钥。

NotionCredentials 是平台边界。Windows runner 通过一个固定 method channel 调用当前用户的 CredWriteW / CredReadW / CredDeleteW，目标名 EnglishLearning.Notion.ReadOnly.v1，持久化为 CRED_PERSIST_LOCAL_MACHINE。没有普通文件、SharedPreferences、SQLite 或 Dart define 形式的密钥后备。调试验收使用独立且受限的 Test 命名空间，不覆盖真实凭据；Release 禁用测试命名空间。Android 配置与业务代码保留，本轮不实现 Android 凭据适配，不构建或测试 Android。

同步过程：读取安全凭据与本轮 100 ID 范围 → 读取并校验数据源结构 → 分页查询 → 校验每个字段、已核验词头、两个 PETS 年份、重复页和重复 ID → 一个 SQLite 事务内更新词条、来源页面映射和时间水位。任一分页失败或冲突均不提交部分词条，不推进水位。

首次需要完整返回 100 个词；重复同步以 last_edited_time 为依据，查询水位前两分钟及之后的改动，涵盖时间精度、边界并列和短时延迟。用实际返回的最大远端时间推进水位，不用本机时间跳过未读内容。零改动不推进水位。内容按规范字段顺序序列化并校验哈希；即使哈希未变，也核对本地内容，避免 CSV 更新之后误跳过云端内容。

网络请求最多每页 100 条、10 页，每个响应 2 MB，实际入库上限 100 个 ID。数据源查询之间至少间隔 350 ms。429/529 遵守 Retry-After，等待不超过 10 秒时最多三次；更长等待明确提示稍后重试。5xx 最多重试三次；权限、格式、重定向错误不盲目重试。所有错误均为固定、可理解的文字，本地词库保持可用。

SQLite 文件名 english_learning_v1.sqlite3 保持不变，schema v2 原地迁移至 v3，仅新增：

| 表 | 用途 |
|---|---|
| notion_sync_state | source_id 主键、远端水位 UTC、本机成功时间 UTC |
| notion_word_links | source_id + entry_id 联合主键、源 page_id、内容 SHA-256、远端修改 UTC；同一数据源内页面唯一 |

沿用 CSV 的内容 upsert，只有新词才创建默认未测试的 learning_progress。已有 learning_progress、review_events、pronunciation_progress、pronunciation_events 不被同步更新。同步位置在提交时比较旧水位，拒绝过期并发批次；同步按钮在操作期间禁用。一个稳定 ID 不自动改绑到另一个数据源或重建页面。

这是手动触发的增量拉取，不是后台订阅或双向同步。Notion 查询不提供本实现依赖的强一致快照；长时间并发改动、长期索引延迟可使用“重新核对 100 词”完整复核。重建、归档或删除的源页不会删除本地记录，需要人工确认。更换同步范围、远端删除策略及学习记录回写留到后续阶段。

验收明确区分三类证据：单元/组件测试中的模拟 HTTP；真实 Windows 运行时回放授权连接导出的 100 词内容（API 元数据和时间戳明确为合成）；用户独立凭据完成后的真实 Notion API 直连。前两类不能冒充第三类。
