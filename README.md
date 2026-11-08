# EnglishLearning

个人英语学习软件，当前版本 **0.5.0+8**。Windows 是主学习端，Android 是移动复习端，共用 Flutter 业务代码；Notion 保存云端词库，SQLite 支持本地离线学习，无自建服务器。

换设备或继续开发，请先阅读 **[设备迁移与开发接续](docs/DEVICE_HANDOFF.md)**。

## 已有功能

- 100 个已核验词头及原有稳定 ID；来源、原书分类、PETS-3 2015 与 2025 状态分别保存。2025 官方归属保持待核实。
- 隐藏释义，查看答案后选择掌握／眼熟／遗忘；SQLite 保存记录，按 7 天／1 天／10 分钟安排基础复习。
- 六词自主认读、自然拼读提示、重音、合法真人音频、离线缓存和独立发音自评；不使用 IPA 或中文谐音。
- Notion → SQLite 手动增量只读同步，重复同步去重，内容更新不覆盖个人评级及复习日期。
- Windows 使用系统凭据管理器；Android 使用系统 Keystore 加密存储，凭据不随源码或安装包分发。
- Windows 保留 CSV 导入；Android 只提供 Notion 词库同步及离线复习，不提供手动 CSV 导入／导出。

当前手机已独立配置只读连接；电脑端只读授权验证返回 200，但手机真实同步出现连接错误／超时，用户已选择稍后再同步，正常手机应用仍为 0 词。隔离真机测试的 100 词及模拟评级不能当作正常应用数据。

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
