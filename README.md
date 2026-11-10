# EnglishLearning

个人英语学习软件，当前源码版本 **0.7.0+10（500 词实际学习）**。目前仅开发 Windows；P5-A 只建设完整词库数据，正式客户端仍为 500 词。Android 开发、构建和真机测试暂停，保留跨平台工程。Notion 保存云端主词库，SQLite 支持本地离线学习，无自建服务器。

**Notion 与本机正式 SQLite 均为 500 词**，真实只读直连已恢复；完整、重复及增量同步均通过，个人状态不重置。6 词优先真人录音，其余可用 Windows 本地 TTS；来源类型分别保存。34 个不同难度词的原生学习及独立进程恢复已通过，正式个人库没有写入这些测试评级。真实学习事件上传仍须单独批准。最新 [P4 验收报告](docs/p4/REPORT.md)；P3 [扩容历史](docs/p3/NOTION_IMPORT_STATISTICS.json) 保留。

换设备或继续开发，请先阅读 **[设备迁移与开发接续](docs/DEVICE_HANDOFF.md)**。

**P4.1 个人试用准备已完成**：版本仍为 0.7.0+10，500 词内容不变；texture 已补齐原书映射，质量标记已分级，18 个 TTS 词及 6 段真人资源完成原生播放检查，个人听辨待确认。见 [P4.1 交付记录](docs/p41/REPORT.md) 与 [7 天试用清单](docs/p41/PERSONAL_TRIAL.md)。正式 SQLite 已备份并完成独立恢复演练，测试评级未写入个人库。

**P5-A 数据审阅已完成**：5,552 候选分为 5,331 入选、27 暂缓、194 待核实；另保留台账外的既有 texture，合并建议库 5,332 词。只读 Notion 预览为新增 4,832、更新 0、原有 500 不变；未正式写入。见 [P5-A 公开报告与派生词库](docs/p5a/public/REPORT.md)。原始台账、完整本地审计包和私有云端快照继续留本机。

**P5-B 客户端容量已放开，云端尚未写入**：本地 CSV 导入上限改为正式库 5,332 词 / 8 MB。Windows 随包的 Notion 同步范围仍是已验收的 500 词，界面仍只提供 100／200／500。194 个待核实词没有并入正式库。见 [P5-B 报告](docs/p5b/REPORT.md)。

**P5-C 正式导入已暂停**：先完成 10 个试写词，云端达到 510；随后授权的 4,822 词只完成一部分。最近一次只读核对是 1,054 页、1,053 个唯一稳定 ID，已核对 553，还有 4,277 个未发送。`pollution` 和 `highlight` 待对账，一张无稳定 ID 的空白页来源未确定。194 个待核实词和 27 个暂缓词没有导入，个人 SQLite 未改。见 [P5-C.4C.1 恢复调查](docs/p5c/P5C4C_RECOVERY_AUDIT.md)。不要自动续跑。

## 已有功能

- 100 个已核验词头及原有稳定 ID；来源、原书分类、PETS-3 2015 与 2025 状态分别保存。2025 官方归属保持待核实。
- 隐藏释义，查看答案后选择掌握／眼熟／遗忘；SQLite 保存记录，按 7 天／1 天／10 分钟安排基础复习。
- 六词自主认读、自然拼读提示、重音、合法真人音频、离线缓存和独立发音自评；不使用 IPA 或中文谐音。
- 500 词内容包保留既有 100 个 ID，新增 400 个 ID 均来自原候选台账；支持逐词认读、音节/重音、例句、无音频自评、词库搜索和到期入口。现有 6 份音频继续使用，其余明确待补充。
- Windows 可选择已验收的 100／200／500 词同步规模，分组读取后整批事务提交；扩容强制完整核对。缺失批次、重复 ID 或网络错误不提交部分内容。
- Notion → SQLite 手动增量只读同步，重复同步去重，内容更新不覆盖个人评级及复习日期。
- 缺少真人资源时可播放系统本地 TTS，支持重播及例句语境核对；完整播完才允许相应发音自评，停止/失败不记完成，词义学习可独立进行。此备用不等于真人或官方标准音频。
- Windows 使用系统凭据管理器；Android 使用系统 Keystore 加密存储，凭据不随源码或安装包分发。
- Windows 保留 CSV 导入；Android 只提供 Notion 词库同步及离线复习，不提供手动 CSV 导入／导出。

Android 的历史授权及隔离验收记录保留，本轮不继续手机同步、构建或设备测试。隔离测试数据不能当作正常应用的个人记录。

P2-A 只允许独立模拟事件库；P2-B1 只在个人数据库副本验证迁移与事件事务。**P2-B2 真实学习事件试写尚未授权**，当前不自动上传真实学习记录、不做多设备冲突合并。

## 恢复开发环境

已验收环境为 Flutter **3.47.7**、Dart **3.13.5**。先使用相同版本恢复，保留 `pubspec.lock`，不以 `pub upgrade` 代替安装。

```powershell
git clone https://github.com/jtaoss/EnglishLearning.git
cd EnglishLearning
flutter doctor -v
flutter pub get --enforce-lockfile
dart analyze --fatal-infos
flutter test --no-pub
flutter run -d windows --dart-define-from-file=config/dev.json
```

三套非敏感配置在 `config/dev.json`、`staging.json`、`prod.json`。启动和构建都必须选择配置文件；默认启动缺少 `APP_ENV` 会显示配置错误页。

Windows 需要 Visual Studio 的 C++ 桌面工作负载、MSVC、CMake 和 Windows SDK，以及可创建插件符号链接的权限。Android 使用 JDK 21、SDK 36、NDK **28.2.13676358**；SDK 许可由用户阅读和接受，不自动输入 yes。

```powershell
flutter build windows --debug --no-pub --dart-define-from-file=config/dev.json
flutter build windows --release --no-pub --dart-define-from-file=config/prod.json
flutter build apk --debug --no-pub --dart-define-from-file=config/dev.json
```

可选工具：`scripts/bootstrap.ps1` 恢复锁文件，`scripts/verify.ps1` 检查配置、格式、分析和测试，`scripts/build_android_debug.ps1` 临时选择 SDK／Gradle 缓存而不改变全局设置。

## 验证范围

0.5.0 阶段已有 179 项单元／组件测试、Windows Debug／Release、Android Debug APK 和实体 Android 的隔离学习／音频验收。真实手机 Notion 下载与物理断网检查仍待补验。

仓库测试使用固定的公开样本和合成 Notion 元数据，不依赖原电脑的审计目录、Notion Token 或个人数据库。原始审计及备份留在旧设备本地，未上传公开仓库。

原生测试使用 `integration_test/app_acceptance_test.dart` 统一入口。跨进程、真实云端和设备测试需要显式验收参数；跳过不等于通过。不要在同一工程并行启动 Windows 和 Android 原生测试，避免共享生成文件互相干扰。

## 数据和资源

GitHub 提交与 Release 不包含个人 SQLite、系统凭据、签名密钥、原始商业词书 PDF、完整 5,552 词台账或机器缓存。换设备的个人记录须通过本地备份私下迁移；新设备重新安全配置 Notion 凭据。

六份音频的作者、来源、缓存与再分发许可见 [ATTRIBUTION](assets/pronunciation/ATTRIBUTION.md) 和随附许可文本；不是 PETS 官方录音。WordNet 许可见 [WORDNET_3_1_LICENSE.txt](assets/vocabulary/WORDNET_3_1_LICENSE.txt)。中文释义独立整理，保留 AI 对照与个人确认的区别，不冒充官方释义。

[模块边界](docs/ARCHITECTURE.md) · [Notion 字段](docs/p1c/NOTION_SCHEMA.md) · [只读同步设计](docs/p1c/SYNC_DESIGN.md) · [事件副本设计](docs/p2b1/MIGRATION_DESIGN.md)
