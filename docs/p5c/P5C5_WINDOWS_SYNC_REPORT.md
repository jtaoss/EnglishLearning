# P5-C.5 Windows 全量词库同步

版本保持 0.7.0+10。核对时间 2026-11-11 22:54，同步完成于同日 23:17。结论：**正式词库已只读同步到本机个人 SQLite，重复同步不改学习记录。**

本轮只使用现有只读凭据读取正式数据源 `157d89e5-71fb-4e68-9640-1b04dbb1e627`。没有创建、修改、归档或删除 Notion 页面，没有使用写入凭据，没有上传学习事件，没有打开学习事件库。空白页保持原样。SQLite schema 仍是 user_version 3，背词日程没有改。

## 同步前后的词条数量

| 位置 | 同步前 | 同步后 |
|---|---|---|
| Notion 页面 | 5,333 | 5,333，未改 |
| Notion 有效唯一稳定 ID | 5,332 | 5,332，未改 |
| 本机正式个人库 | 文件不存在 | 5,332 |

正式路径是 `C:\Users\admin\AppData\Roaming\Personal\English Learning\english_learning_v1.sqlite3`。同步前该文件不存在，文档里的 Administrator 路径、备用应用目录和 `private/p41` 试用前快照也不存在。因此没有一份可以备份的现成个人库，也没有可以沿用的词义评级、发音评级或复习日期。同步没有补造这些记录。

只读检查写在 `private/p5c/backups/p5c5-20261111-225259/audit_summary.json`。当时应用没有运行。

## 5,332 个稳定 ID 对账

只读分页共 55 次请求：1 次数据源结构，54 次查询。前 53 页各 100 条且 `has_more` 为真，最后一页 33 条且 `has_more` 为假。没有提前停止，也没有把不完整结果当成完成。

| 口径 | 数量 |
|---|---|
| 页面 | 5,333 |
| 唯一页面 | 5,333 |
| 有效唯一稳定 ID | 5,332 |
| 与正式清单相同的 ID | 5,332 |
| 清单中缺失 | 0 |
| 清单外的非空 ID | 0 |
| 重复稳定 ID | 0 |
| 原 500 词缺失 | 0 |

正式清单 `docs/p5a/public/formal_learning_vocabulary.csv` 当前是 LF，SHA-256 为 `508007c44f272f71df0ed918f17c006b263a1320fef1ada48e411a6aed3ba619`。同一内容换成 CRLF 后是 P5-C 记录过的 `9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb`。两边是同一份 5,332 行。

先前待对账的 `pollution`（`SG25-de2c2dcff9ee`）和 `highlight`（`SG25-dc2c5be187f6`）都在这 5,332 个 ID 里，29 个内容字段与清单一致。

主学习 4,259，扩展 1,073，暂缓 0。

## 29 个内容字段

对照的是客户端读取的 29 个字段：`entry_id`、`word`、`meaning_zh`、`book_category`、`source_file`、`source_id`、`source_pdf_pages`、`source_index_pages`、`book_verification`、`meaning_review_status`、`pets2015_status`、`pets2025_status`、`library_class`、`part_of_speech`、`usage_note`、`lexical_sources`、`example_en`、`example_zh`、`learning_priority`、`selection_reason`、`phonics_note`、`syllables`、`stress`、`reading_review_status`、`audio_status`、`audio_source`、`audio_license`、`pets2015_evidence`、`pets2015_match_method`。

5,332 个 ID 的这 29 个字段全部一致，差异 0。字段类型与 `field_mapping.csv` 一致。没有字段被截断。个人评级、复习日期、发音自评和学习事件没有进入同步内容。

最大一页响应 1,398,128 字节。按客户端方式精确查询旧样本前 100 个 ID，返回 100 条，`has_more` 为假，ID 完全一致，响应 1,485,884 字节，低于客户端 2 MB 上限。空白页不在这次结果里。

## 空白页隔离

已知页面 `414cd5b5-d6b9-80db-ac03-d94e99d65e61` 恰好出现一次。它属于正式数据源，未归档，不在垃圾箱，单词和稳定 ID 都是空的，学习词库分类是「主学习」。它被排除，没有删除或修改。

没有第二张空稳定 ID 的页面，也没有归档页、父级不匹配的页面或重复页面。个人库的 5,332 条 Notion 关联里没有这张空白页。

## 个人学习记录

正式个人库是新建的。5,332 个词都是未测试，发音状态都是「未测试」，复习日期 0，词义事件 0，发音进度 0，发音事件 0。原 500 个稳定 ID 都在其中，同样没有评级和复习日期。这是缺失记录下的真实状态，不是从旧词条补写的学习历史。

隔离库先完成同一批同步，再人为写入四条学习记录并重复同步、关闭后重开。四条都还在：

| 词 | 稳定 ID | 同步后仍在的状态 |
|---|---|---|
| challenge | `SG25-2dd00bd77e02` | 词义掌握，发音能独立认读 |
| advanced | `SG25-d21f85ea3816` | 词义眼熟 |
| convenience | `SG25-d7ae368c1499` | 词义遗忘 |
| ambiguous | `SG25-6a651134eb4b` | 词义眼熟；这是 500 词之外的新词 |

隔离库仍有 4 条词义事件和 1 条发音事件。其余 5,328 个词保持未测试。这些评级只留在隔离库，没有写入正式个人库。

正式库 integrity `ok`，外键问题 0，schema 3。目录里只有 `english_learning_v1.sqlite3`，没有 WAL、SHM，也没有事件库。

## 重复同步与冷启动

隔离库第一次同步：新增 5,332，更新 0，未变 0。写入上述学习记录后再次同步：新增 0，更新 0，未变 5,332。关闭并重新打开后，词数、分类、评级和事件数不变。

正式库第一次同步：新增 5,332，更新 0，未变 0。立即再次同步：新增 0，更新 0，未变 5,332。关闭并重新打开后仍是 5,332 个未测试词、0 条事件。

之后启动 Release 程序。它打开了这份个人库，文件 SHA-256 仍是 `da9a72fcc186871ee35df048100f8acf40f3651bfb0aed2246102a9f6444b643`，没有产生 WAL。程序随后关闭。词库在本地文件中，不依赖当次网络请求。

搜索、筛选和学习走现有界面测试：正式词库可以搜到单词且默认不显示释义，扩展筛选为 1,073，学习卡片在揭开释义前不显示词义，评级可以保存。这次没有在正式个人库里点击评分，所以没有新增真实学习记录。打包窗口当时停在锁屏后面，没有做一次可见的点击验收。

## 客户端范围

Windows 正式同步范围改为 5,332。`verified100.csv` 和 `reviewed500.csv` 都还在资源里。5,332 的顺序把旧版 500 词放在前面，因此 100 仍是原来的 100 词，500 仍是原来的 500 词，完整范围才是 5,332。非 Windows 范围仍是 100 词样本。同步页可以选择 100、200、500 和 5,332，Windows 默认是 5,332。同步仍然只读，内容更新不改已有评级和复习日期。

## Windows 构建与测试

| 检查 | 结果 |
|---|---|
| `dart format --set-exit-if-changed` | 通过，126 个文件无格式差异 |
| `flutter analyze --fatal-infos` | 无问题 |
| `flutter test` | 200 项通过 |
| 已核对载荷的隔离库和正式库同步 | 单独运行通过 |
| Windows Debug | 42.6 秒，`english_learning.exe` 1,251,840 字节 |
| Windows Release | 55.4 秒，`english_learning.exe` 146,432 字节 |

没有构建 Android。

## 本轮没有做的事

没有向 Notion 写入，没有处理空白页，没有上传真实学习事件，没有开发 Android，没有新增背词功能，没有批量修改释义，没有下载或生成音频，没有重新 OCR，没有修改 Flutter Starter。

P5-C.5 到此停止，不进入下一阶段。
