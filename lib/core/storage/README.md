# SQLite 本地适配

LearningRepository 是页面与持久化之间的边界。SqliteLearningRepository 在后台 isolate 串行执行任务，每项任务独立打开并关闭连接，不跨 isolate 传递原生句柄。

schema v1 的 vocabulary、learning_progress、review_events 原地保留；v2 新增 pronunciation_progress、pronunciation_events。迁移及评分使用事务，发音自评不写入旧的三张表。PronunciationStore 以独立接口提供发音数据，旧 pronunciation_status 字段在没有新自评时仍可读，不做猜测映射。较新/未知 schema 明确报错，保留文件，不删除重建。平台路径在 app/open_learning_repository.dart，Windows/Android 都使用应用支持目录；数据库文件名保持 english_learning_v1.sqlite3。

schema v3 新增 notion_sync_state 与 notion_word_links，记录只读词库同步的远端水位、成功时间、页面映射与内容哈希。同步内容和水位同一事务提交，复用 CSV 的 upsert，已有个人进度/事件不被同步覆盖。大小写保留，May/may 等不同词条不能合并。Android 本轮暂停，原配置保留。
