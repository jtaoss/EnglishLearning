# P4.1 Windows 试用准备验收

日期 2026-11-09；版本 0.7.0+10。应用学习/同步/播放代码没有修改，仅新增隔离验收规格和报告，不重复开发已有模块。

| 检查 | 本轮证据 |
|---|---|
| 正常 Release 学习入口 | 已观察正式窗口本地 500 词，首页“开始今日学习 / 到期复习”可见；词库默认主学习范围 486、总数仍 500，扩展词另有范围 |
| 答案保密 | 24 词原生界面初始、认读提示后、播放后均无中文释义或双语例句；答案前词义评级禁用；正常 Release 的 about 卡同样隐藏答案 |
| 发音播放 | 18 个系统 TTS、6 个真人录音全部完整播放；12 个 TTS 例句播放；Zira Desktop en-US；逐词见 playback-samples.csv |
| 词义与发音独立 | object：眼熟/再练习；increase：遗忘/能独立认读；发音保存后词义仍未测试，之后词义保存不改发音 |
| 只评词义 | about 未确认认读、未播放直接揭示答案，保存遗忘，发音仍未测试 |
| 真正新进程恢复 | warm PID **7880** → cold PID **20460**；3 份词义、2 份发音记录、时间及来源逐值一致 |
| 到期优先 | 隔离时钟推进 8 天，3 个有评级的到期项排在 497 个新词前；未改系统时间 |
| 离线 | 两阶段拒绝 Dart HTTP，实际请求 0；音频及 TTS 使用本机资源 |
| 正式个人库保护 | 正式库未用于上述评级；备份前后 7 表逐值一致，500 词/500 链接，真实事件新增 0 |
| 备份恢复演练 | SQLite backup API，integrity_check=ok；恢复到新私有文件并重新打开，全部表一致；未替换正式库 |
| 静态分析 | `dart analyze --fatal-infos`：No issues found |
| 原 Starter | 417 文件哈希相同；没有操作 Android |

详细机器结果见 [acceptance.json](acceptance.json)、[playback-samples.csv](playback-samples.csv) 和 [personal-preservation.json](personal-preservation.json)。完整原生运行日志只保留在 `private/p41/native-warm.log` 与 `native-cold.log`；测试 SQLite 路径在本机 `build/reports/p41/trial.json`，不进入正式库或安装包。

首次原生检查有一次等待播放超时，当时测试未记录具体词头。添加逐词诊断后重跑 24 词全部通过；未修改播放实现，根因未证实。试用时若复现，请记录词头、声卡/输出设备及界面提示。失败不应记为发音练习完成；P4 原有中断/失败门槛测试仍保留。

本轮没有更改应用模块，沿用 P4 已通过的 191 项单元/组件测试及 Debug/Release 验收；本轮新增的两项 Windows 原生检查均通过，不将旧测试冒称为本轮重新执行。集成测试会覆盖 Debug 启动入口，结束后重新构建 `lib/main.dart` 的正常 Debug，正式 Release 包仍为原 0.7.0+10。没有新增安装包或扩大词库。

Notion 的 500 词只读直连/重复同步沿用 [P4 验收](../p4/NOTION_SYNC.md)，本轮 CSV 内容和云端均未改动，没有为了证据侧录再次同步个人库。真实使用第 6 天按清单核对一次状态保留。人工听辨、7 天实际学习记录尚待用户完成，不能用隔离评级代替。
