# P1-B 最小实现与数据兼容

版本 0.2.0+3，仍共用 Windows/Android 的 Flutter 页面、会话规则、缓存校验与 SQLite 代码。

## 模块与流程

features/pronunciation 下保留小型模块：content/catalog 读取固定、可审计的资源清单；services 组合依赖；cache 仅复制已授权的随包资源；player 封装原生插件；session 负责自主认读、播放状态和自评；两个页面负责词表与练习。

用户从现有词库进入“6 词发音练习”，或从词卡进入“自主认读与听音”。未匹配资源的词显示未配置音频，不影响词义学习。清单只按已有稳定 ID 关联，词头也必须一致，不自动插入或重新导入词库。

先显示英文；确认已自主认读后才显示提示并允许播放。完整的原生结束事件到达后才允许自评。“停止”、页面退出、后台、加载或播放失败都不被当成完成。单个会话只允许一个在途播放，晚到事件用会话代次隔离；每次原生播放单独创建播放器，退出后释放。自评保存期间禁止第二次写入；同一次尝试 ID 在 SQLite 中唯一，失败重试也不追加重复事件。

## 依赖选择

选择 audioplayers 6.8.1，Windows 使用其官方认可的 audioplayers_windows 4.4.1，Android 使用 audioplayers_android 5.3.0。它提供单文件、本地路径播放和结束事件，覆盖本轮需求，不添加后台播放、录音、识别或自动评分。

与之比较，just_audio 0.10.6 的核心包还需要另外选择 Windows 实现；本轮不需要其序列或无缝播放能力，因此没有同时引入两套播放器。

- [audioplayers 官方使用文档](https://github.com/bluefireteam/audioplayers/blob/main/getting_started.md)
- [Windows 插件要求](https://pub.dev/packages/audioplayers_windows)
- [just_audio 平台说明](https://pub.dev/packages/just_audio)

crypto 3.0.7 原已在锁文件中，仅提升为显式依赖用于 SHA-256；没有升级已有包。Windows CMake 最低版本与策略从 3.14 调整到 3.15，遵循该插件对 CMP0091 的要求；未修改 Flutter Starter、Flutter SDK 或系统安全设置。soundfile 与 pycaw 仅装在本机 D:/DevCache/EnglishLearningAudioTools，供资源转换和验收使用，不随 Flutter 应用引入 Python 依赖。

## SQLite v1 → v2

数据库文件名仍为 english_learning_v1.sqlite3。启动时事务新增以下两张表，旧三张表不做内容更新：

- pronunciation_progress：entry_id 主键及外键、个人自评 status、assessed_utc、audio_asset_id。
- pronunciation_events：attempt_id 唯一键、entry_id 外键、status、audio_asset_id、assessed_utc。

状态为 needsPractice / familiar / confident，界面对应“再练习／基本会读／能独立认读”。没有记录时为未测试。旧 learning_progress.pronunciation_status 原值保留；没有新自评时只读展示旧值，不猜测映射。词义 status、review_count、last_reviewed_utc、due_utc 以及 review_events 不受发音自评写入影响。

跨版本测试保存旧三表全部行，再迁移、保存发音、关闭重开，逐行比较保持一致。未知/较新版本仍报错，不删除重建数据库。个人数据库仅做本次启动必需的表迁移，没有写入验收评分或重新导入词条。

## 离线与缓存

只有清单中缓存许可为真的资源才能使用；只从本地随包 WAV 复制，不抓取 source_url。每次使用核对完整 SHA-256；缓存丢失或损坏时从合法随包原件重建，原件缺失或校验失败时明确报错。临时文件不用于播放。

本机首次原生试用发现，Codex 宿主对 Roaming 的文件系统重定向使同目录逻辑路径 rename 返回 Windows 错误 17。已用独立 Python 文件操作对照证明：逻辑别名失败，解析后的实际目录成功。缓存因此先解析目录重定向并缩短缓存文件名；少数提供者仍返回跨盘错误时，复制后校验才返回可播放位置。未改动 SQLite 的既有目录选择，不能因修缓存而另建一套个人学习库。证据见 evidence/cache-rename-environment.json。

缓存路径属于当前启动上下文的应用支持目录。当前桌面宿主会解析到其 MSIX LocalCache；不能把这一上下文下的路径推测成用户从其他宿主启动时的固定物理路径。本轮没有跨上下文迁移或删除个人数据。
