# 发音覆盖与本地备用

| 类型 | 覆盖 | 本轮原生播放验证 |
|---|---:|---:|
| 已授权社区真人录音 | 6 | 6 |
| 缺真人录音、可使用本地 TTS | 494 | 28 |

本机语音：**Microsoft Zira Desktop - English (United States)（en-US）**。SAPI 使用已安装的 Microsoft Desktop 语音，只在本机实时播放；不使用云语音、不下载或打包语音引擎、不导出合成音频。其他电脑若未安装适用英语语音，会显示不可用并保留词义学习。

原生实现依据 [Microsoft SAPI 文档](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms717065(v=vs.85))：异步 Speak、状态查询与停止。应用只在 native 完成且没有错误后启用发音评级；停止、超时或输出失败均不算完成。取消和旧请求按尝试 ID 隔离。再次练习需要重新完整听音。

播放策略：有合法真人资源时优先使用原有真人播放；否则提供明确标识的系统 TTS。多音词可额外播放原例句获得语境，页面不会展示 IPA 或中文谐音。

状态使用现有 `pronunciation_progress.audio_asset_id` 和事件字段保存，schema 不变：

- `commons-…`：已有授权真人音频。
- `windows-tts:sapi:en-US:…`：Windows 合成语音核对。
- `self-reading:…`：仅自主认读，未作听音核对。

词卡重开可看到上次来源类型；三类记录不会混称真人录音。发音自评是用户练习记录，不是自动识音/自动评分；TTS 发音也不作为官方或人工标准。

## 6 份真人资源复核

| 单词 | 作者 | 许可 | 文件页 |
|---|---|---|---|
| big | Dvortygirl | CC BY-SA 3.0 | [来源](https://commons.wikimedia.org/wiki/File:En-us-big.ogg) |
| tree | Dvortygirl | CC BY-SA 3.0 | [来源](https://commons.wikimedia.org/wiki/File:En-us-tree.ogg) |
| side | Dvortygirl | CC BY-SA 3.0 | [来源](https://commons.wikimedia.org/wiki/File:En-us-side.ogg) |
| carry | Dvortygirl | Public domain (PD-self) | [来源](https://commons.wikimedia.org/wiki/File:En-us-carry.ogg) |
| notice | Dvortygirl | CC BY-SA 3.0 | [来源](https://commons.wikimedia.org/wiki/File:En-us-notice.ogg) |
| autumn | Muke Tever (Muke) | Public domain (PD-self) | [来源](https://commons.wikimedia.org/wiki/File:En-us-autumn.ogg) |

2026-11-09 核对 Wikimedia 原文件页的作者/许可，并核对随包 WAV 的 SHA-256。既有 Ogg→PCM WAV 转换及署名/CC BY-SA 许可文本保留，没有新增下载或商业词典音频抓取。逐文件信息见 audio-audit.json 与 assets/pronunciation/ATTRIBUTION.md。

**验证边界：**34 词的本地播放完整结束、来源、音节/重音提示已检查；没有获得用户或教师的逐词听辨确认。语音设备报告完成不等于证明现实扬声器可听见，也不保证多义词的每一种读法。对 resume/résumé、read/lead、overhaul 等优先使用例句和词性提示，并留待本人抽听。
