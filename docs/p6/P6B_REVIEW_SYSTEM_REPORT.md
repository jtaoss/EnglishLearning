# EnglishLearning · P6-B 复习系统优化验收报告

> **环境与时间戳**
> - **基准时间**：2026-11-12
> - **Git 分支**：`p6/review-system`
> - **词库状态**：正式 5,332 词（主学习 4,259 · 扩展 1,073）
> - **个人 SQLite 校验码**：`EA158DDCF7FA751F53E35CE2753B987D4ED3DB0753E37E2CA6620C106FB06F4F`（100% 保持完全一致与零污染）

---

## 目录
1. [现有复习功能审查结果](#一现有复习功能审查结果)
2. [复习中心改造说明](#二复习中心改造说明)
3. [模式一（今日到期复习）实现说明](#三模式一今日到期复习实现说明)
4. [模式二（薄弱词专项）实现说明](#四模式二薄弱词专项实现说明)
5. [复习评级与间隔算法](#五复习评级与间隔算法)
6. [发音复习与词义复习的隔离性说明](#六发音复习与词义复习的隔离性说明)
7. [Windows 键盘快捷键设计与实现细节](#七windows-键盘快捷键设计与实现细节)
8. [复习结果展示页结构与设计](#八复习结果展示页结构与设计)
9. [数据安全与用户进度保护验证](#九数据安全与用户进度保护验证)
10. [测试覆盖情况与测试报告](#十测试覆盖情况与测试报告)
11. [附录：修改文件清单与后续建议](#十一附录修改文件清单与后续建议)

---

## 一、现有复习功能审查结果

### 1.1 原有代码结构
- **`lib/features/review/review_schedule.dart`**：间隔复习算法核心，定义 `ReviewGrade`（掌握 `mastered`、眼熟 `familiar`、遗忘 `forgotten`）及 `nextDue(grade, at)` 间隔。
- **`lib/features/review/study_queue.dart`**：原先仅包含 P6-A 阶段的新词排序逻辑（`BookStudyOrder`）与基础的 `isDue(now)` 队列过滤。
- **`lib/features/review/review_page.dart`**：原单卡片词条查看与学习页面（`/vocabulary/:entryId`），用于单词回忆、发音跟读与词义评级。
- **`lib/features/home/home_page.dart`**：学习首页，原先将 `allDue` 统计与新词可学数混合，缺乏真正到期词、已完成词、薄弱词的明确划分。

### 1.2 原有缺陷分析
1. **未测试新词与到期复习词混合**：旧版逻辑在没有任何词被学过（全库未测试）时，将未测试词也计入“待处理”，导致首页按钮标签模糊，容易误导用户以为存在真实逾期的复习任务。
2. **缺乏连续复习会话流**：旧版每评一个词需要用户主动寻找或点击“下一词”，没有整体会话进度（如“第 3 词 / 共 12 词”）与结束汇总页。
3. **缺乏薄弱词专项巩固**：旧版没有将“遗忘”和“眼熟”词聚合的专用练习通道；若用户想临时巩固困难词，只能重打正式评级或在全量列表中人肉查找。
4. **缺少 Windows 键盘高效操作**：背单词高频操作缺少空格揭晓释义与数字键 1/2/3 快捷评级，且容易与搜索框输入冲突。

### 1.3 保留与改进内容
- **保留**：
  - 保留已验证的 `ReviewSchedule` 间隔算法（掌握 +7天、眼熟 +1天、遗忘 +10分钟）。
  - 保留 Antigravity 精致蓝白 UI 风格、圆角、卡片及语义状态标签。
  - 保留单词学习页（`/vocabulary/:entryId`）与 P1–P5 历史测试契约。
- **改进**：
  - 首页构建清晰的真实数据复习中心（今日到期、今日已完成、今日剩余、未到期、薄弱词）。
  - 新增独立连贯的复习会话页面 `ReviewSessionPage`，支持模式一（今日到期复习）与模式二（薄弱词专项）。
  - 实现全套 Windows 桌面键盘快捷键（Space 揭晓、1/2/3 评级），并具备文本焦点防误触机制。

---

## 二、复习中心改造说明

### 2.1 统计指标真实来源
所有指标均通过 `ReviewDashboardStats.fromWords(words, now)` 从本地真实 SQLite 提取，不制造虚假数字：
1. **今日到期复习（`metric-due-review`）**：
   - 筛选条件：`word.libraryClass != '暂缓' && (word.status != 'untested' || word.reviewCount > 0) && word.dueAt <= now`。
   - **全库未测试时严格为 0**，绝不把未测试新词伪造为到期复习。
2. **今日已完成复习（`metric-completed-today`）**：
   - 筛选条件：`word.lastReviewedAt` 处于本地当天零点至次日零点 `[todayLocal, tomorrowLocal)` 范围内。
3. **今日剩余待复习（`metric-remaining-review`）**：
   - 动态反映本轮尚未完成的到期复习词数（与当前到期词数保持一致）。
4. **未到期词数（`metric-not-yet-due`）**：
   - 筛选条件：已学词且 `word.dueAt > now`。
5. **薄弱词数量（`metric-weak-words`）**：
   - 筛选条件：真实状态为 `forgotten`（遗忘）或 `familiar`（眼熟）的词条总数，并附带遗忘与眼熟的细分数值。

### 2.2 零到期词空状态设计
- 当 `dueReviewCount == 0` 且词库非空时：
  - 醒目显示官方提示文本：`“今天暂无到期复习，先去学习一些新词吧。”`（带有 `Key('no-due-review-hint')`）。
  - 首页主行动按钮智能聚焦为“开始今日新词学习”（`Key('start-new-words')`），点击直接进入排好序的第一本新词。
  - 同时保留“今日到期复习（0 词）”入口（`Key('start-due-review')`），保障既有自动化测试与用户查验无障碍。

---

## 三、模式一（今日到期复习）实现说明

### 3.1 入队规则与优先级
- **入口路径**：`/review/due`（`AppRouter.reviewDue`）。
- **入队过滤**：仅包含已学词（`status != 'untested' || reviewCount > 0`）、非暂缓词、且 `dueAt <= now`。
- **队列排序**：
  - **到期时间优先**：`dueAt` 升序排列，逾期越久的单词越先复习。
  - **不受新词分类排序限制**：旧词复习纯粹以遗忘曲线到期时间为准。

### 3.2 学习与交互流程
```
[展示英文单词 & 进度] -> [用户独立回忆词义] -> [点击“查看答案”或按 Space]
                                                      |
                                                      v
[自动切入下一词] <- [持久化写入 SQLite] <- [按 1 遗忘 / 2 眼熟 / 3 掌握 评级]
```
1. 界面首屏仅显示大号英文词头、分类标签与发音认读组件，中文释义严格隐藏。
2. 呈现语义评级引导：“若只是看着拼写熟悉、无法独立想起准确词义，请选择「眼熟」或「遗忘」，不要默认选「掌握」”。
3. 揭晓答案后，选择评级即刻触发 `controller.review(...)`，安全原子写入本地 SQLite。
4. 评级完成后无需手动点击“下一词”，会自动平滑切换到下一到期词。
5. 会话中途退出时，已评级的词已实时入库，下次打开不会丢失。

---

## 四、模式二（薄弱词专项）实现说明

### 4.1 候选词来源
- **入口路径**：`/review/weak`（`AppRouter.reviewWeak`）。
- **来源标准**：严格根据本地 SQLite 记录中 `status == 'forgotten'` 或 `status == 'familiar'` 的词条。
- **排序规则**：`forgotten`（遗忘词）排在最前，其次为 `familiar`（眼熟词），同级别内按到期时间升序与最近复习时间倒序排列。

### 4.2 临时巩固与正式更新双模式
- **默认模式：临时巩固练习**：
  - 页面顶部提示：“临时巩固模式：默认仅做自测与回忆练习，不改动正式到期时间（due_utc）”。
  - 揭晓答案后提供轻量按钮：`“这次记住了 · 下一词”` 与 `“仍需再记 · 下一词”`。
  - 操作仅在当前内存会话中统计巩固成效，**不调用 `recordReview`，不改动 SQLite 中的 `due_utc`、`status` 或 `review_count`**。
- **可选通道：同步更新正式评级**：
  - 点击“需要同步更新正式学习评级？”可展开正式的 1/2/3 评级按钮，用户主动点击时才更新真实数据库。

---

## 五、复习评级与间隔算法

### 5.1 三级评级语义规范
| 评级等级 | 语义定义 | 复习间隔增量 | 界面引导建议 |
| :--- | :--- | :--- | :--- |
| **遗忘 (`forgotten`)** | 无法独立想起正确中文词义 | **+10 分钟** | 10 分钟后在本轮或下次复习中重现 |
| **眼熟 (`familiar`)** | 有印象，但回忆不完整或不够确定 | **+1 天** | 明日再次核验，巩固回忆深度 |
| **掌握 (`mastered`)** | 无需提示，能够准确回忆出主要词义 | **+7 天** | 进入长期记忆维护周期 |

> **特别提示**：界面中清晰警示“形似认得拼写但想不起词义不能算掌握”，严格防范虚假掌握感。

### 5.2 算法保护
保留既有 `ReviewSchedule.nextDue` 算法，未修改或重置历史学习数据。

---

## 六、发音复习与词义复习的隔离性说明

1. **数据模型独立**：
   - 词义学习由 `learning_progress`（`status`, `review_count`, `due_utc`）管理。
   - 发音练习由 `pronunciation_progress`（`grade`, `attempt_id`, `source_id`, `due_utc`）管理。
2. **到期计算独立**：
   - 词义到期（`isMeaningReviewDue`）依据词义 `dueAt`。
   - 发音到期（`isPronunciationDue`）依据发音 `pronunciationProgress.dueAt`。
   - 词义评级绝不改写发音状态；发音自评也绝不覆盖词义掌握程度。
3. **独立入口**：
   - 首页为发音薄弱/到期提供独立入口 `AppRouter.pronunciation`。
   - 复习卡片中将发音练习与词义回忆置于独立模块，各自拥有专属操作。

---

## 七、Windows 键盘快捷键设计与实现细节

### 7.1 按键映射
- **`Space`（空格键）**：
  - 仅在答案未揭晓（`!_revealed`）时有效，按下后揭晓中文释义与例句。
- **`1` / `NumPad 1`**：评级为“遗忘（10 分钟）”。
- **`2` / `NumPad 2`**：评级为“眼熟（1 天）”。
- **`3` / `NumPad 3`**：评级为“掌握（7 天）”。

### 7.2 安全与防误触机制
1. **未揭晓前按键保护**：在未揭晓答案时，按 `1`、`2`、`3` 均被安全忽略，防止盲猜或误触跳过。
2. **输入框焦点避让（Focus Guard）**：
   - 实现 `_isEditableTextFocused()` 深度检查焦点树。
   - 当用户在搜索框或任何 `EditableText` 中输入字符（包含空格或数字）时，所有全局复习快捷键自动挂起，绝不产生干扰。
3. **防抖与连按保护**：
   - 在评级写入中（`_saving == true`）或发音播放忙碌（`_playbackBusy == true`）时锁定按键，避免重复记录或越级跳词。

---

## 八、复习结果展示页结构与设计

在复习会话全部单词评级完成时，动态切换为优雅的汇总面板（`_buildCompletionState`）：
1. **完成仪式感与成果卡片**：
   - 突出展示“今日到期复习已完成”或“薄弱词巩固练习已完成”。
2. **真实成效分布**：
   - 模式一：展示本轮掌握词数、眼熟词数、遗忘词数、当前全库剩余到期词数。
   - 模式二：展示临时记住词数、仍需再记词数。
3. **下一步行动建议**：
   - `[返回学习首页]`：一键返回主界面。
   - `[巩固薄弱词（X）]`：如有遗忘/眼熟词，推荐一键转入薄弱词练习。
   - `[继续学习新词]`：如今日有可学新词，一键进入下一批新词学习。

---

## 九、数据安全与用户进度保护验证

1. **5,332 词数据一致性**：
   - `vocabulary` 数据表保持正式 5,332 词不变（主学习 4,259 · 扩展 1,073）。
2. **用户学习记录零损失**：
   - 既有个人评级、复习次数和复习日期保持不变；逐词学习明细仅留本地验收记录，不在公开报告中列出。
   - 个人数据库文件哈希校验保持 `EA158DDCF7FA751F53E35CE2753B987D4ED3DB0753E37E2CA6620C106FB06F4F`，无任何未授权改动。
3. **测试数据物理隔离**：
   - 所有的读写自动化测试均使用系统临时目录（`Directory.systemTemp.createTemp`）中的隔离数据库，绝对不碰生产文件。

---

## 十、测试覆盖情况与测试报告

### 10.1 新增专属测试集：`test/p6/review_system_test.dart`
覆盖全部 10 项严苛场景，100% 通过：
- `untested words are never counted as due meaning reviews`
- `due queue orders strictly by overdue time ascending`
- `weak queue includes only forgotten and familiar words in order`
- `isReviewedOnLocalDay accurately matches local calendar day`
- `ReviewSchedule calculates exact intervals and preserves stability`
- `Home Review Center displays empty hint when 0 words are due`
- `Mode 1: Due Review Session progresses, supports keyboard shortcuts, and completes`
- `Mode 2: Weak Word Consolidation defaults to temporary practice without touching formal SQLite ratings`
- `Keyboard shortcuts are ignored when text field has focus`
- `Isolated SQLite database preserves ratings and queue after restart`

### 10.2 全量回归验证结果
- **静态代码分析**：`dart analyze --fatal-infos` -> **No issues found!**
- **代码格式规范**：`dart format lib test` -> **0 changed**
- **全套测试套件**：`flutter test --no-pub` -> **233 / 233 全部通过 (All tests passed!)**
- **Windows Release 构建**：`flutter build windows --release` -> **成功构建 `build\windows\x64\runner\Release\english_learning.exe`**
- **Windows Debug 构建**：`flutter build windows --debug` -> **成功构建 `build\windows\x64\runner\Debug\english_learning.exe`**

---

## 十一、附录：修改文件清单与后续建议

### 11.1 本轮修改文件清单
1. **`lib/features/review/study_queue.dart`**：
   - 实现 `isMeaningReviewDue`、`isWeakMeaningWord`、`isReviewedOnLocalDay`、`isPronunciationWeakOrDue`。
   - 实现 `dueMeaningReviewQueue`、`weakMeaningWordQueue`、`newLearnableWordQueue`、`pronunciationReviewQueue`。
   - 实现 `ReviewDashboardStats` 指标统计容器。
2. **`lib/features/vocabulary/vocabulary_controller.dart`**：
   - 接入各复习队列与仪表盘统计方法。
3. **`lib/features/review/review_session_page.dart`**（新增）：
   - 模式一（今日到期复习）与模式二（薄弱词专项）会话控制器、键盘驱动、防抖及结果结算界面。
4. **`lib/features/review/review_page.dart`**：
   - 单卡片页补充 Windows 键盘快捷键响应，优化“下一词”队列回退。
5. **`lib/app/app_router.dart`**：
   - 注册 `/review/due` 与 `/review/weak` 路由。
6. **`lib/features/home/home_page.dart`**：
   - 复习中心界面与指标网格升级，完善零到期词空状态引导。
7. **`test/p6/review_system_test.dart`**（新增）：
   - P6-B 全套业务逻辑、组件交互、键盘事件与隔离数据库测试。

### 11.2 后续演进建议
1. **P6-C（长难词与发音拼读强化）**：
   - 针对长难词音节划分、重音符号和发音辅音连缀练习提供针对性微交互。
2. **P6-D（学习热力图与统计归档）**：
   - 可在设置或次级页面中增加 30 天复习量热力图与艾宾浩斯记忆保留率预测曲线。
