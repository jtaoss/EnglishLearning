# P5-B 报告

日期：2026-11-09。版本号保持 **0.7.0+10**。修改前基线是已干净提交的 `b832e88`（`feat: publish Windows 500-word learning and P5-A vocabulary review`）。本轮没有调用 Notion，没有写入云端，没有上传学习事件，没有打开正式个人 SQLite，也没有进入 P5-C。

## 修改文件

- `lib/features/vocabulary/vocabulary_csv.dart`：导入上限从 500 词 / 1 MB 改为正式库 5332 词 / 8 MB。
- `lib/features/vocabulary/vocabulary_import_source.dart`：文件选择使用同一个字节上限。
- `lib/core/storage/sqlite_learning_repository.dart`：Notion 批次入库使用同一个词条上限。
- `lib/main.dart` 未改。Windows 随包同步范围仍是 `assets/vocabulary/reviewed500.csv`。
- `lib/integrations/notion/notion_sync_page.dart` 未改。界面仍只提供已验收的 100／200／500。
- `test/p1a/csv_test.dart`、`test/p1a1/import_quality_test.dart`：回归断言改为新上限。
- `test/p5b/formal_library_test.dart`：隔离库与同步测试。
- `scripts/p5b/build_preview.py`：只读公开表，生成预览。
- `docs/p5b/notion_import_preview.csv`、`docs/p5b/diff_summary.json`、`docs/p5b/manual_review_disposition.csv`。
- `README.md`、`docs/DEVICE_HANDOFF.md`、两个模块 README、`.gitignore`：记录本阶段边界，并允许公开 P5-B 文档进入版本库。

没有改 Android，没有改 Flutter Starter，没有新增学习功能或界面结构。

## 最终词库统计

| 项目 | 数量 |
|---|---:|
| 原候选 | 5,552 |
| 正式入选 | 5,331 |
| 暂缓 | 27 |
| 待人工核实 | 194 |
| 台账外 texture | 1 |
| 正式学习库 | 5,332 |
| 其中主学习 / 扩展 / 暂缓 | 4,259 / 1,073 / 0 |
| 与现有 500 词重叠 | 500 |
| 重叠词的 29 个内容字段差异 | 0 |
| 稳定 ID 重复 | 0 |
| 词头重复 | 0 |
| 本轮新升入正式库 | 0 |
| 云端写入 | 0 |

5,331 + 27 + 194 = 5,552。正式库 = 5,331 + texture。大小写独立的 May/may、March/march 仍保留。2025 归属仍全部是“待核实”。

## 194 个待核实词

全部保持 **仍待人工核实**，没有编造确认，没有并入正式库。逐条记录在 [manual_review_disposition.csv](manual_review_disposition.csv)。

本机没有 `E:\desktop\2025考研英语词汇闪过.pdf`，仓库里也没有 `private/p5a` 的补查缓存。因此没有重跑文本层核对，也没有做整本 OCR。结论沿用 P5-A 已经保存的来源状态。

| 处理 | 数量 | 依据 |
|---|---:|---|
| 正文词头仍待核实 | 177 | 原书核验状态为“待核验”；来源方法为“仍待正文词头人工核实” |
| 词头已有既有来源记录，但释义、语域或大小写仍须人工定 | 17 | 原书核验状态为“已核验”，阻塞原因不是缺词头 |

177 个按原书分类：低频 93、中频 49、高频 25、基础 8、偶考 2。`bible` 在这一组，同时保留“大小写及圣经/权威著作义需核对”，没有用词网大小写折叠定义它。

17 个没有提升：

| 词 | 已有来源记录 | 仍待核实的原因 |
|---|---|---|
| renaissance | 索引原图已核对 | 小写复兴义与专名文艺复兴需区分 |
| used | 索引原图已核对 | “用过的/二手的”与 be used to 需分开 |
| whatsoever | 文本层行首词头，非图像终审 | 限定词/代词标签和语境 |
| idiot | 文本层行首词头，非图像终审 | 侮辱性及过时标签不能当作中性称人释义 |
| dumb、handicap、lame、dwarf、rape、queer、gay、cock | 同页正文标题同形 | 语域、贬义或粗俗义需人工定范围 |
| irrespective | 同页正文标题同形 | 固定结构 irrespective of 与词性 |
| except、while、both、several | 同页正文标题同形 | 常用词性或结构没有被现有释义覆盖 |

这些已有记录只说明词头曾经被核对过，不能把拟用释义写成已确认内容。

## 5,332 词隔离测试

临时数据库在系统临时目录，文件名不是正式个人库。测试结束后删除。正式个人库没有被打开。

SQLite 结果：

- 导入 5,332，重复导入为 5,332 条未变化。
- `PRAGMA integrity_check` 为 ok，`foreign_key_check` 为空，`user_version` 为 3。
- `entry_id` 与 `word_key` 都是 5,332 个互异值。
- `learning_progress` 行数等于词条数。内容 JSON 不含 `status`、`due_utc`、`review_count`。
- 掌握、眼熟、遗忘三条评分在改一条释义并重新打开数据库后仍在：到期分别为 7 天、1 天、10 分钟。其余 5,329 条保持未测试。

页面行为用同一份 5,332 词驱动真实词库页和词卡。组件测试绑定不能等 SQLite isolate 完成，所以这两项使用内存仓库；落盘和重启由上面的 SQLite 测试覆盖。

- 默认主学习显示 4,259。搜索 `straightforward` 得到 1 条，列表不显示中文。
- 筛选扩展得到 1,073。未测试词仍算到期，筛选后数量不变。
- 词卡在查看答案前不显示释义，也不能评分。保存“眼熟”后状态、次数和到期时间正确。

同步使用伪造的 Notion 响应，没有真实网络：

- 按 100 个 ID 分组完整读取 5,332，首次新增 5,332；再次同步 5,332 条未变化。查询次数为 54 组 × 2 次。
- 同步之后原有“掌握”和 7 天到期仍在。
- 最后一组少返回 1 个 ID 时整批拒绝。已有 5,332 词和“遗忘”评分保留，水位和关联数仍是空。
- 只同步已验收的 500 词时，另外 4,832 个本地词不被删除，两组评分都保留，关联数为 500。

## Notion 导入预览

完整差异在 [notion_import_preview.csv](notion_import_preview.csv)，汇总在 [diff_summary.json](diff_summary.json)。这是离线比较，不是远端写入验收。

| 动作 | 数量 |
|---|---:|
| 新增 | 4,832 |
| 更新 | 0 |
| 保持不变 | 500 |
| 跳过，待核实 | 194 |
| 跳过，暂缓 | 27 |

预览不含个人状态、评级、复习日期或事件。正式库 29 个客户端字段与字段映射文件一致。映射文件里另有 9 个客户端不读取的属性：AI 筛选理由、筛选置信度、分类依据、原 5552 台账内、原书书内页码、原始词头、原记录 ID、清洗记录、发音资源状态。当前学习导入不依赖它们。

分页和限流按现有实现核对，没有放宽：

- 每组最多 100 个 ID 条件，5,332 词是 54 组。`page_size` 为 100，每组最多 10 页。按每页 100 条，一组 100 个 ID 使用 1 页。
- 每次查询前等待 350 毫秒。429／529 仍按 `retry-after` 最多重试，超过 10 秒或重试耗尽则整批停止并保留本地数据。本轮没有向 Notion 发送请求，所以没有新的在线限流测量；既有 429 测试包含在下面的 198 项里。
- 单次响应仍限制 2 MB。正式库最丰富的 100 行合计约 6.2 万字符，低于这个上限。这是离线估算，不是真实响应字节数。
- 重复 ID、重复页面或未完整返回都拒绝整批。云端没有这些页之前，如果把随包范围换成 5,332，真实同步会失败并保留本地数据。因此随包范围仍是 500。

## 自动化测试和 Windows 构建

- `dart format`：通过。
- `dart analyze --fatal-infos`：无问题。
- `flutter test --no-pub`：198 项通过，用时 51 秒。其中 P5-B 为 7 项。没有跳过的测试被写成通过。
- Windows Debug：通过，67.8 秒，产物 `build\windows\x64\runner\Debug\english_learning.exe`。配置为 `config/dev.json`。
- Windows Release：通过，60.8 秒，产物 `build\windows\x64\runner\Release\english_learning.exe`。配置为 `config/prod.json`。
- Android 构建和测试：未执行。这是本轮限制，不是通过。

## 尚未解决

- 194 个词仍待人工核实。要继续核对，需要原书 PDF 或已有补查缓存；本轮没有这些文件。
- Notion 仍是 500 词。4,832 个新增页没有创建。
- 本轮没有重新读取真实 Notion，预览对比的是仓库里的 500 词包和 P5-A 公开表。
- 随包同步范围和界面选项仍是 100／200／500。本地已经能导入 5,332 词，但在获得写入授权并完成云端导入前，不应把运行中的同步目标改成 5,332。
- 9 个审计属性客户端不读取。这不是学习阻塞项。
- Android 按本轮限制未构建、未测试。
- 真实学习事件上传仍未授权。
