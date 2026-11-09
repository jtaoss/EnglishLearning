# EnglishLearning 0.7.0+10：500词实际学习验收

日期：2026-11-09。Notion与Windows均保持500词。真实只读直连已恢复，500完整/重复/增量同步通过；34词原生学习和独立进程恢复通过，正式个人记录未受测试评级污染。

| 输出 | 内容 |
|---|---|
| [500词可学习性](LEARNABILITY.md) | 全量字段/身份/参考检查、逐词CSV |
| [Notion只读同步](NOTION_SYNC.md) | 凭据原因、安全保存、真实500词及个人记录保留 |
| [发音覆盖与备用](PRONUNCIATION.md) | 6真人+494本地TTS备用、来源和许可 |
| [质量异常](QUALITY_REVIEW.md) | 72词94提示、17词来源对照、前后值 |
| [Windows学习闭环](WINDOWS_ACCEPTANCE.md) | 34词原生流程、故障/复习/重开/离线验证 |
| [剩余问题与建议](REMAINING.md) | 人工听辨、全义项终审及证据缺口 |

检查：静态分析通过，191项单元/组件测试通过，Debug/Release构建通过。机器可读结果见 acceptance.json。

没有扩容到1000词、Android构建/真机开发、自建服务器、商业词典音频抓取或重新OCR。原Flutter Starter保持不变，P2-B1隔离成果保留，未上传真实学习事件。
