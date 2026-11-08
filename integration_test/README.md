# 原生测试入口

当前 Flutter 3.47.7 的 DesktopLogReader 在多入口之间复用已关闭流；调查与复现见 docs/p1a1/TEST_STABILITY_INVESTIGATION.md。

所有原生用例放在 specs/*.dart，由唯一的 app_acceptance_test.dart 注册。新增规格不要命名为独立 *_test.dart，以免触发第二次原生启动。默认整目录命令：

```powershell
flutter test integration_test -d windows --no-pub
```

默认保留核心功能检查；真实系统文件选择和跨进程恢复需要显式验收参数，因此未配置时跳过，不可宣称这些项目默认已通过。完整验收记录和参数见 docs/p1a1/TESTING_RECORD.md。

系统文件选择使用真实 Windows 插件，外部 tool/drive_windows_picker.py 只操作本工程 Debug 进程的验收对话框；不替换原生文件结果。跨进程恢复读取前次验收报告，个人数据库不参与。Android 必须有实体设备才执行设备测试，不启动模拟器。

P1-B 的 pronunciation 规格会实际播放 6 个授权样本并保存隔离自评；需要有可用音频输出设备。P1B_REPORT_DIR 指定审计输出，P1B_RESTART_REPORT 指定另一个新进程读取的真实报告。发音的冷启动规格默认显式跳过。音频输出采样、离线缓存重播与完整命令见 docs/p1b/TESTING_RECORD.md。
