# P6-A 新词学习顺序

版本 0.7.0+10。检查时间 2026-11-12。分支 `p6/word-order`。

本轮只改学习队列的排序。正式词库内容、5,332 个稳定 ID、Notion、个人 SQLite 和学习评级都没有改。

## 1. 正式数据里的原书分类

正式清单是 `docs/p5a/public/formal_learning_vocabulary.csv`。分类字段是 `book_category`。同一分组里的原书位置使用 `source_pdf_pages` 的第一个页码，然后是单词，再然后是稳定 ID。5,332 行都有稳定 ID、分类和页码，没有空分类，也没有缺页。

`基础词` 是原书目录里的“基础”一节。学习阶段按要求显示为“简单词”。没有另外编造一个简单词字段。`learning_priority` 仍是 P1 4,237、P2 1,095，只留给已到期复习的同时间次序，不参与新词排序。

| 原书字段 | 学习阶段 | 数量 | 主学习 | 扩展 |
|---|---|---:|---:|---:|
| 高频词 | 考研高频词 | 951 | 951 | 0 |
| 基础词 | 简单词 | 1,780 | 1,780 | 0 |
| 中频词 | 考研中频词 | 586 | 586 | 0 |
| 低频词 | 考研低频词 | 576 | 321 | 255 |
| 偶考词 | 偶考词 | 1,439 | 621 | 818 |
| 补充词 | 补充词 | 0 | 0 | 0 |

主学习 4,259，扩展 1,073。无法可靠分类的词条是 0。补充词在正式清单中是 0 条，没有把缺分类的词算进补充词。

## 2. 新旧排序

旧队列先按到期时间，再按 `learning_priority`，最后按单词字母序。未测试的新词没有到期时间，所以实际先学 P1，并在 P1 内按字母序。正式清单按这个旧规则排出的前 8 个新词是 April、August、Catholic、Christian、Christmas、December、Easter、February。它们分属基础词、低频词、中频词和偶考词。

新队列在截取任何一页或第一项之前，对全部可学词排序：

1. 已到期、需要复习的旧词，仍按最早的词义或发音到期时间，然后才是学习优先级、单词和稳定 ID。
2. 未测试新词按高频词、基础词、中频词、低频词、偶考词、补充词。
3. 同一分组内按原书页码、单词、稳定 ID。没有页码时排在该组末尾。正式清单没有缺页。

正式清单的新词现在从第 13 页的高频词开始：actual、advance、advanced、agent。低频词里的扩展词排在偶考词前面。暂缓词仍不进入这个队列。100、200、500 的同步前缀仍是 `reviewed500.csv` 的原顺序，没有改成词频顺序。

首页和词卡在当前项是新词时显示“当前新词阶段：……”。数量来自正式 `book_category`，界面没有写死各组人数。词卡上的“下一词”取全库剩余队列的第一项，不再停在当前词的主学习或扩展范围里。

## 3. 学习状态

排序只发生在内存队列。`recordReview` 仍只更新被评级的那一条。隔离库测试把 `SG25-high` 记为掌握后关闭再打开，掌握状态、复习次数和下次复习时间保持不变，`SG25-basic` 仍是未测试。已到期的旧词排在高频新词之前。已学但未到复习时间的词不进入新词队列。

## 4. 修改文件

相对 `main`（`f15d92f`）：

- `lib/features/review/study_queue.dart`
- `lib/features/vocabulary/vocabulary_controller.dart`
- `lib/features/review/review_page.dart`
- `lib/features/review/review_session_page.dart`
- `lib/features/home/home_page.dart`
- `lib/app/app_router.dart`
- `lib/features/vocabulary/vocabulary_page.dart`
- `lib/integrations/notion/notion_sync_controller.dart`
- `lib/ui/status_badge.dart`
- `test/p6/word_order_test.dart`
- `test/p6/review_system_test.dart`
- `test/p1d/windows_learning_test.dart`
- `test/p1a1/phone_and_due_test.dart`
- `test/p3/learning_ui_test.dart`
- `.gitignore`
- `docs/p6/P6A_WORD_ORDER_REPORT.md`

到期复习和薄弱词巩固沿用当时工作区里已经接上的会话页。首页按钮依赖这两个路由，所以和排序一起保存在本分支。没有重做 Antigravity 的页面结构，也没有改词库正文。

## 5. 测试

测试使用内存词库或系统临时目录 `english_p6_order_`，没有打开个人 SQLite。

| 检查 | 结果 |
|---|---|
| 高频新词先于简单词，简单词先于中频，中频先于低频，低频先于偶考，同组顺序稳定 | 通过 |
| 已到期旧词先于新词；未到期旧词不进入队列 | 通过 |
| 评级不因排序改变，重启后队列和状态仍在 | 通过 |
| 5,332 词按 100 词分批无重复、无遗漏 | 通过 |
| 100、200、500 历史样本前缀仍与 `reviewed500.csv` 一致 | 通过 |
| `dart format --output=none --set-exit-if-changed` | 通过，检查范围内 0 个文件需要再改写 |
| `dart analyze lib test` | 通过，No issues found |
| `flutter test --no-pub` | 通过，233 项 |
| Windows Debug | 通过，`build\windows\x64\runner\Debug\english_learning.exe` |
| Windows Release | 通过，`build\windows\x64\runner\Release\english_learning.exe` |

没有启动桌面程序做点击验收。程序启动会打开个人学习库，本轮禁止打开该文件。

## 6. 数据库

个人库路径仍是 `%APPDATA%\Personal\English Learning\english_learning_v1.sqlite3`。本轮只计算文件哈希，没有用 SQLite 打开它，也没有导入、删除或重建。

验收时文件大小 11,874,304 字节，SHA-256 `ea158ddcf7fa751f53e35ce2753b987d4ed3db0753e37e2ca6620c106fb06f4f`，最后写入时间 2026-11-12 11:52:58（UTC+8）。这个时间早于随后的测试和构建。测试结束后哈希和写入时间没有变化。

没有修改 Notion，没有上传学习事件，没有改动稳定 ID 或正式词义。

## 7. Git

当前功能在 `p6/word-order`。`main` 仍是 `f15d92f`，没有推送，也没有改写远程 main。

- `8babc40` `feat(p6a): preserve 5332-word UI adaptation and book-category new-word ordering`
- `7129cb2` `fix(p6a): take the next new word from the book-order queue`
