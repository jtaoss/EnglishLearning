# 原生测试入口

P3 Windows 500 词隔离验收仍使用统一入口。工具链就绪后执行：

```powershell
flutter test integration_test/app_acceptance_test.dart -d windows --no-pub --dart-define-from-file=config/dev.json --dart-define=P3_WINDOWS=true --dart-define=P3_REPORT_DIR=E:/desktop/EnglishLearning-main/build/reports/p3-native --plain-name="P3 Windows"
flutter test integration_test/app_acceptance_test.dart -d windows --no-pub --dart-define-from-file=config/dev.json --dart-define=P3_COLD_REPORT=E:/desktop/EnglishLearning-main/build/reports/p3-native/native-report.json --dart-define=P3_REPORT_DIR=E:/desktop/EnglishLearning-main/build/reports/p3-native --plain-name="P3 Windows cold"
```

首个规格新建隔离 SQLite、禁止 Dart HTTP、验证无音频自评及词义学习、播放既有合法音频两次并输出截图/报告。第二条命令启动独立新进程，读取前次隔离库，验证评级/日期/发音恢复、发音到期进入首页队列、历史数量不变；两个报告保存不同 PID。它们不打开个人库、不连接真实 Notion。真实 200／500 词同步须经批量写入批准后另行验收。未设置参数时明确跳过，不表示通过。Android 本轮暂停。完成集成验收后重新构建普通 Debug，避免将测试入口留在 Debug 运行目录。

当前 Flutter 3.47.7 的 DesktopLogReader 在多入口之间复用已关闭流；调查与复现见 docs/p1a1/TEST_STABILITY_INVESTIGATION.md。

所有原生用例放在 specs/*.dart，由唯一的 app_acceptance_test.dart 注册。新增规格不要命名为独立 *_test.dart，以免触发第二次原生启动。默认整目录命令：

```powershell
flutter test integration_test -d windows --no-pub
```

默认保留核心功能检查；真实系统文件选择和跨进程恢复需要显式验收参数，因此未配置时跳过，不可宣称这些项目默认已通过。完整验收记录和参数见 docs/p1a1/TESTING_RECORD.md。

系统文件选择使用真实 Windows 插件，外部 tool/drive_windows_picker.py 只操作本工程 Debug 进程的验收对话框；不替换原生文件结果。跨进程恢复读取前次验收报告，个人数据库不参与。Android 必须有实体设备才执行设备测试，不启动模拟器。

P1-B 的 pronunciation 规格会实际播放 6 个授权样本并保存隔离自评；需要有可用音频输出设备。P1B_REPORT_DIR 指定审计输出，P1B_RESTART_REPORT 指定另一个新进程读取的真实报告。发音的冷启动规格默认显式跳过。音频输出采样、离线缓存重播与完整命令见 docs/p1b/TESTING_RECORD.md。
