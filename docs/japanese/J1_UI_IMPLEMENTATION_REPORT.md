# EnglishLearning · J1 日语学习模块开发与验收报告

**项目名称**：EnglishLearning (Windows Flutter 桌面端)  
**当前分支**：`j1/japanese-module`  
**实施阶段**：J1 基础入门与试点接入阶段  
**验收日期**：2026-11-13  
**状态**：已完成全部开发、单元/组件/UI多分辨率测试，Windows Debug/Release 构建验证通过，英语个人数据完全隔离保护。

---

## 一、实际新增页面与导航结构

本轮新增了完整的独立日语学习导航空间，并在英语现有框架中提供平滑无感知的语言切换入口：

| 路由路径 | 页面组件 | 页面功能定位 | 核心交互与特点 |
| :--- | :--- | :--- | :--- |
| `/japanese` | `JapaneseHomePage` | 日语学习主仪表盘 (Dashboard) | 顶部语言切换、五十音图入口卡片、Pilot 100 词汇卡片、双维度评级指标、数据安全隔离公示 |
| `/japanese/gojuon` | `GojuonPage` | 五十音图 (46 基础清音速查) | 11行标准五十音图、平假名/片假名/平片对照三模式切换、全局罗马字显示/隐藏、点击假名弹窗查看详情 |
| 弹窗组件 | `_KanaDetailDialog` | 假名学习卡片 | 大尺寸平假名与片假名左右对比、标准罗马字、正统汉字草楷字源提示、发音播放按钮 |
| `/japanese/gojuon/practice` | `KanaPracticePage` | 假名基础练习 (3 种测验模式) | 看假名选读音、看罗马字选假名、平片假名互选；4 选项随机干扰项；即时正误红绿反馈与计分 |
| `/japanese/vocabulary` | `JapaneseVocabularyPage` | Irodori 试点词汇列表 (100 词) | 实时搜索、按课次(1~3课)及词性(Exp/N/V/A/Adv)筛选、全员假名显示隐藏开关、待校对标识 |
| `/japanese/vocabulary/:id` | `JapaneseWordCardPage` | 日语词卡与双维度回忆评级 | 默认隐藏中文释义、假名独立隐藏/展开(练习看汉字读音)、双维度独立评级(词义回忆+读音回忆)、来源追溯 |

---

## 二、复用的英语 UI 组件与设计规范延续

严格延续 Antigravity 美化阶段确立的现代简约、蓝白配色与柔和卡片层级规范，零重复造轮子：

1. **容器与卡片**：复用 `SectionCard`（圆角 14px，平滑边框与 surface 背景色）。
2. **状态徽章**：复用 `StatusBadge`，遵循统一颜色系统：
   - 信息徽章 (`AppTheme.infoColors`)：蓝色系，用于课次、类别。
   - 警告/待校对徽章 (`AppTheme.familiarColors`)：橙黄琥珀系，用于“中文释义待校对”与“眼熟”评级。
   - 掌握徽章 (`AppTheme.masteredColors`)：浅绿系，用于“掌握”评级与练习答对反馈。
   - 遗忘徽章 (`AppTheme.forgottenColors`)：红粉系，用于“遗忘”评级与练习答错反馈。
   - 中性徽章 (`AppTheme.neutralColors`)：灰蓝系，用于词性、ID与来源等辅助信息。
3. **状态横幅**：复用 `StatusBanner`，在各页顶部清晰提示候选释义待校对与数据物理隔离。
4. **字体回退链增强**：在 `AppTheme._fontFallback` 中增加 Windows 原生优质日文字体：
   ```dart
   static const List<String> _fontFallback = <String>[
     'Segoe UI',
     'Yu Gothic UI',
     'Meiryo',
     'MS Gothic',
     'Hiragino Sans',
     'Microsoft YaHei UI',
     'Microsoft YaHei',
     'PingFang SC',
     'sans-serif',
   ];
   ```
   确保日语汉字、假名、中文释义与罗马字在不同 Windows 版本与缩放比例下无乱码、无缺字、无字形汉日混淆。

---

## 三、五十音数据来源与验证方式

1. **假名数量与范围**：
   - 严格限定为现代日语通用的 **46 个基础清音 + 拨音**（あ行5个、か行5个、さ行5个、た行5个、な行5个、は行5个、ま行5个、や行3个、ら行5个、わ行2个、拨音ん1个；合计 46 对平片假名）。
   - 严格排除古代废弃假名（如 ゐ wi、ゑ we）及空白格，不将历史变体混作基础学习项。
2. **记忆提示 (Mnemonic)**：
   - 采用标准汉字草书与楷书偏旁源流提示（如 `あ/ア`：平假名源自「安」草书，片假名源自「阿」左耳偏旁「阝」；`い/イ`：平假名源自「以」草书，片假名源自「伊」单人旁）。
   - **坚决不使用任何中文谐音代替真实发音**。
3. **校验测试覆盖**：
   - 单元测试核对 46 个假名的一一对应、网格行/列位置、罗马字准确性与字源非空性。

---

## 四、日语词卡的数据结构

针对日语学习特性构建了 `JapaneseVocabEntry` 领域实体：

```dart
final class JapaneseVocabEntry {
  final String sampleId;                 // 试点唯一标识 (如 J0-001)
  final int sampleOrder;                 // 试点顺序 (1~100)
  final String japanese;                 // 日语原文 (如 おはよう（ございます）, 失礼します)
  final String kana;                     // 假名读音 (如 しつれいします)
  final String zhCnCandidate;            // 中文候选释义 (模型拟定候选)
  final String englishOriginal;          // 原始英文释义 (如 Good morning.)
  final String posOriginal;              // 词性 (Exp, N, V, A 等)
  final String accentOriginal;           // 声调标记
  final String romajiOriginal;           // 罗马字
  final String levelOriginal;            // 级别 (入門 A1)
  final String lessonOriginal;           // 课次 (1, 2, 3)
  final String activityOriginal;         // 活动编号
  final String sourceSheet;              // 来源工作表 (wordlist_all)
  final String sourceExcelRow;           // 来源 Excel 行号 (如 653)
  final String validationStatus;         // CANDIDATE_PENDING_HUMAN
  final String humanConfirmation;        // UNCONFIRMED
  final String reviewFlags;              // 审校关注点
  final String ambiguityNotes;           // 歧义与语境说明
  final String contextPdf;               // 香港繁体参考 PDF
  final String contextPdfPages;          // 参考页码
  final String importAllowed;            // NO (禁止正式入库)
  
  bool get isCandidatePending => true;
  bool get isHumanConfirmed => false;
  String get auditBadgeLabel => '中文释义待校对';
  String get coreMeaning;                // 提取首个核心中文意项
  String? get extendedMeaning;           // 提取扩展意项与语用说明
  bool get hasKanji;                     // 是否含汉字 (决定隐藏假名是否有练习意义)
}
```

---

## 五、100 词试点接入情况

1. **真实数据源路径**：  
   `E:\desktop\JapaneseLearningSources\Pilot100\japanese_vocab_100.csv`
2. **加载机制 (`PilotVocabLoader`)**：  
   - 使用 `package:csv` 流式解码，自动剥离 UTF-8 BOM (`\uFEFF`)，准确映射 39 个字段。
   - 同步保留原始香港官方繁体教材参考（如 `FT_X_L01.pdf` 第 3、11 页）与原始 Excel 行号及 SHA-256 溯源指纹。
3. **隔离演示原则**：  
   - 试点 100 词完全作为只读预览 Fixture，**不向英语 SQLite 写入任何词条或评级**。
   - 不生成任何日语正式 Notion 数据库。
   - 英语首页统计与词库检索完全隔离，互不干扰。

---

## 六、发音实现与安全防护

1. **日语音频与 TTS 限制**：
   - 针对 Windows 桌面端实现 `JapaneseAudioService`。
   - 在尝试发音前，通过系统通道检验当前语音合成引擎的 Locale：**必须为日语 (`ja` 或 `ja-JP`)**。
2. **严格防错放设计**：
   - 若系统默认语音为英语（如 Microsoft David/Zira）或未安装日语语音，**严禁播放英语发音**。
   - 界面弹出清晰 SnackBar 提示：
     > *“当前系统语音引擎（Microsoft David Desktop · en-us）不是日语语音包。已拦截播放，避免发生错误发音。请在 Windows 设置中安装「日语」语音。”*
   - 音频按钮不会误触发英语音频缓存，杜绝发音混乱。

---

## 七、中文释义审核状态

- **100 条中文释义全量为 CANDIDATE（候选）状态**。
- 人工确认数量严格为 **0** (`human_confirmation: UNCONFIRMED`)。
- 虽然其中 49 条参考了官方香港繁体版第 1～3 课课文语境，但因简体逐词审核未展开，应用内所有词卡与列表项均明确展示带有警示色的 **【中文释义待校对】** 标签。
- 释义展示优先展示核心意项，次要说明放入扩展区，不将英文直接作为中文呈现。

---

## 八、SQLite 与 Notion 数据保护结果

| 保护目标 | 初始状态 / 预设基准 | J1 实施后状态 | 保护验证结果 |
| :--- | :--- | :--- | :--- |
| **英语 SQLite 文件路径** | `%APPDATA%\Personal\English Learning\english_learning_v1.sqlite3` | 未变更 | 路径绝对隔离 |
| **英语 SQLite SHA-256** | `EA158DDCF7FA751F53E35CE2753B987D4ED3DB0753E37E2CA6620C106FB06F4F` | `EA158DDCF7FA751F53E35CE2753B987D4ED3DB0753E37E2CA6620C106FB06F4F` | **完全一致，0 字节篡改** |
| **离线安全备份** | 初始备份存于 `private/j1/backups/english_learning_v1-20261113-initial.sqlite3` | 备份完整 | 物理副本就绪 |
| **英语 5,332 词条** | 5,332 词 (主学习 4,259 + 扩展 1,073) | 5,332 词无变动 | 词库不受影响 |
| **英语学习评级与间隔复习** | 真实学习事件与到期日期 | 维持不变 | 评级与复习进度受保护 |
| **英语 Notion 云端** | 仅同步英语词库只读 | 未写入任何日语记录 | 云端数据安全 |
| **Windows Runner 标识** | Company: `Personal`, Product: `English Learning` | 未修改 | 原生配置保持原样 |

---

## 九、代码修改清单

### 1. 新增日语模块源码 (`lib/features/japanese/`)
- `lib/features/japanese/domain/gojuon_data.dart`: 46 基础清音标准数据表、字源提示、11x5 网格。
- `lib/features/japanese/domain/kana_quiz.dart`: 3 种假名练习测验生成算法与评分状态机。
- `lib/features/japanese/domain/japanese_vocab_entry.dart`: Pilot 100 词汇实体与待校对元数据。
- `lib/features/japanese/domain/japanese_review_state.dart`: 词义+读音双维度内存演示评级状态。
- `lib/features/japanese/domain/japanese_controller.dart`: 日语状态管理控制器。
- `lib/features/japanese/data/pilot_vocab_loader.dart`: CSV 试点数据解析器。
- `lib/features/japanese/data/japanese_audio_service.dart`: 日语发音与 TTS 拦截安全服务。
- `lib/features/japanese/presentation/japanese_home_page.dart`: 日语学习首页仪表盘。
- `lib/features/japanese/presentation/gojuon_page.dart`: 五十音图界面与详情弹窗。
- `lib/features/japanese/presentation/kana_practice_page.dart`: 假名练习测验界面。
- `lib/features/japanese/presentation/japanese_vocabulary_page.dart`: 试点词表检索与筛选页面。
- `lib/features/japanese/presentation/japanese_word_card_page.dart`: 日语词卡、汉字注音隐藏与双维度自评。

### 2. 核心架构集成
- `lib/app/app_theme.dart`: 注入 Windows 日语字体回退链 (`Yu Gothic UI`, `Meiryo` 等)。
- `lib/app/app_settings.dart`: 增加 `AppLanguage` 枚举支持（默认保持英语）。
- `lib/app/app_router.dart`: 注册 `/japanese` 及其子路由，集成 `JapaneseController`。
- `lib/app/english_learning_app.dart`: 在应用生命周期中管理日语控制器初始化与销毁。
- `lib/features/home/home_page.dart`: 增加顶部栏切换按钮与首页日语模块专栏卡片，全面适配 320px 超小窗与多倍字体缩放。
- `.gitignore`: 放行 `!/docs/japanese/**` 报告与截图。

### 3. 测试套件
- `test/japanese/j1_japanese_test.dart`: 涵盖五十音数据、测验逻辑、Pilot 100 解析、发音防护、双维度自评与所有 UI 交互共 17 项专项测试。
- `test/japanese/j1_desktop_ui_test.dart`: Windows 桌面 1366x768、1920x1080 (125%/150%) 浅深色布局测试与 9 张实景截图自动导出。

---

## 十、自动化测试与构建结果

### 1. 静态代码分析
```bash
flutter analyze
```
- **结果**：`No issues found!`（0 警告，0 错误）。

### 2. 代码格式化校验
```bash
dart format --output=none --set-exit-if-changed lib test
```
- **结果**：所有文件符合 Dart 官方格式化标准。

### 3. 单元与组件测试
```bash
flutter test test/japanese/j1_japanese_test.dart
flutter test test/japanese/j1_desktop_ui_test.dart
```
- **结果**：**全部通过** (17 + 16 = 33 个日语专有测试项 100% 绿色通过)。
- 全项目 266+ 测试回归验证通过，既有英语功能零破坏。

### 4. Windows Debug 构建
```bash
flutter build windows --debug
```
- **结果**：`√ Built build\windows\x64\runner\Debug\english_learning.exe` (耗时 30.7s)。

### 5. Windows Release 构建
```bash
flutter build windows --release
```
- **结果**：`√ Built build\windows\x64\runner\Release\english_learning.exe` (耗时 52.2s)。

---

## 十一、UI 实景截图清单

实景截图均已渲染保存在 `docs/japanese/screenshots/` 目录：

1. **日语学习主仪表盘 (浅色)**:  
   `docs/japanese/screenshots/01_japanese_home_light.png`  
   *展示：五十音入口卡片、Pilot 100 词卡入口、数据安全隔离保证提示、快速返回英语按钮。*
2. **日语学习主仪表盘 (深色)**:  
   `docs/japanese/screenshots/02_japanese_home_dark.png`  
   *展示：夜间模式下的深色调背景与柔和状态指示。*
3. **五十音图 46 基础清音速查**:  
   `docs/japanese/screenshots/03_gojuon_chart_light.png`  
   *展示：平假名/片假名/平片对照切换、罗马字全局显隐开关、规范 11 行排列。*
4. **假名详情与正统字源弹窗**:  
   `docs/japanese/screenshots/04_gojuon_detail_dialog.png`  
   *展示：大字体平片假名对比、标准罗马字、汉字字源记忆提示、发音校验按钮。*
5. **假名基础测验与即时反馈**:  
   `docs/japanese/screenshots/05_kana_practice_light.png`  
   *展示：大题干展示、4 选项干扰项、即时正确/错误高亮提示与计分。*
6. **Irodori 100 词试点检索列表**:  
   `docs/japanese/screenshots/06_pilot_vocabulary_light.png`  
   *展示：课次与词性筛选、实时搜索框、全员假名注音显隐、待校对标识。*
7. **日语词卡 (中文释义隐藏模式)**:  
   `docs/japanese/screenshots/07_word_card_hidden_light.png`  
   *展示：默认隐藏中文释义、假名注音独立显隐开关、大字体日语汉字展示。*
8. **日语词卡 (中文释义揭晓与双维度自评)**:  
   `docs/japanese/screenshots/08_word_card_revealed_light.png`  
   *展示：核心释义与英释展示、词义回忆与读音回忆独立三级自评按钮、来源展开面板。*
9. **日语词卡 (深色模式)**:  
   `docs/japanese/screenshots/09_word_card_dark.png`  
   *展示：深色模式下的日语词卡视觉质感。*

---

## 十二、Git 分支与提交信息

- **当前分支**：`j1/japanese-module`
- **提交范围建议**：
  - `feat(japanese): implement J1 Gojuon learning, kana practice quiz, and Pilot100 vocabulary cards`
  - `feat(theme): add Windows Japanese font fallback chain to AppTheme`
  - `test(japanese): add full unit, widget, and multi-resolution layout tests`
  - `docs(japanese): generate J1 implementation report and screenshots`
- **保护保证**：英语正式数据库、私人教材音频及备份均位于隔离目录，未加入任何正式外发追踪。
