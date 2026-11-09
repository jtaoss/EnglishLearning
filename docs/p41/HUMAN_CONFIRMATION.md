# 待人工确认清单

本轮使用 **Microsoft Zira Desktop - English (United States) / en-US** 实际完成 18 个 TTS 单词播放，其中 12 个另播现有英文例句；另完成 6 段真人资源播放。没有导出 TTS 文件或下载新商业音频。来源类型和优先策略不变。

**以下“已播放”均指原生播放器/SAPI 返回完成，不是 agent 已亲耳听辨、自动声学评分或教师确认。** 请在正式软件搜索词头，先自主读，再分别播放单词和需要的例句；记录听感即可，不必为了验收给真实词条随意选评级。

| TTS 词头 | 重点 | 技术检查 | 人工状态 |
|---|---|---|---|
| object | 本卡名词，首音节重读；听例句时别套用动词读法 | 已播单词及例句 | 待用户听辨 |
| increase | 本卡动词，后音节重读；注意与名词区别 | 已播单词及例句 | 待用户听辨 |
| address | 本卡美式名词首重读；英式读法有差异 | 已播单词及例句 | 待用户听辨 |
| use | 本卡动词词尾浊辅音；与名词区分 | 已播单词及例句 | 待用户听辨 |
| separate | 本卡形容词结尾轻读；与动词区分 | 已播单词及例句 | 待用户听辨 |
| beloved | 形容词两/三音节均有依据；本卡列三音节，名词另看语境 | 已播单词及例句 | 待用户听辨 |
| elementary | men 主重读；五音节与压缩读法 | 已播单词 | 待用户听辨 |
| database | 首音节主重读；data 开头元音变体 | 已播单词 | 待用户听辨 |
| resume | 本卡动词，两音节后重读；与下一词区分 | 已播单词及例句 | 待用户听辨 |
| résumé | 求职名词，三音节首重读；重音符号不去掉合并 ID | 已播单词及例句 | 待用户听辨 |
| read | 本卡现在时；过去时同拼写有另一元音 | 已播单词及例句 | 待用户听辨 |
| lead | 本卡动词；不要选金属名词的元音 | 已播单词及例句 | 待用户听辨 |
| overhaul | 本卡按名词首重读练习；动词末重读 | 已播单词及例句 | 待用户听辨 |
| combat | 当前提示为名词首重读；动词/口音有变体 | 已播单词及例句 | 待用户听辨 |
| fifteen | 单独报数后重读；和 fifty 区分，例句节奏可变 | 已播单词 | 待用户听辨 |
| interesting | 首重读；三/四音节差异无需机械判错 | 已播单词 | 待用户听辨 |
| convenience | 第二音节主重读，检查多音节衔接 | 已播单词 | 待用户听辨 |
| texture | 首重读；ture 作为整体认读，检查词尾 | 已播单词 | 待用户听辨 |

| 真人词头 | 作者 | 原文件页面及采用许可 | 状态 |
|---|---|---|---|
| big | Dvortygirl | [CC BY-SA 3.0](https://commons.wikimedia.org/wiki/File:En-us-big.ogg) | 已完整播放；待用户听辨 |
| tree | Dvortygirl | [CC BY-SA 3.0](https://commons.wikimedia.org/wiki/File:En-us-tree.ogg) | 已完整播放；待用户听辨 |
| side | Dvortygirl | [CC BY-SA 3.0](https://commons.wikimedia.org/wiki/File:En-us-side.ogg) | 已完整播放；待用户听辨 |
| carry | Dvortygirl | [Public domain (PD-self)](https://commons.wikimedia.org/wiki/File:En-us-carry.ogg) | 已完整播放；待用户听辨 |
| notice | Dvortygirl | [CC BY-SA 3.0](https://commons.wikimedia.org/wiki/File:En-us-notice.ogg) | 已完整播放；待用户听辨 |
| autumn | Muke Tever (Muke) | [Public domain (PD-self)](https://commons.wikimedia.org/wiki/File:En-us-autumn.ogg) | 已完整播放；待用户听辨 |

真人资源的稳定 ID/词头与 manifest、Wikimedia 文件页面相符；本地 PCM WAV 哈希、声道、采样率和时长均匹配既有审计，不重新剪辑或变速。big/tree/side/notice 采用 CC BY-SA 3.0，carry/autumn 为作者自行放入公有领域；转换说明及署名仍保留在 `assets/pronunciation/ATTRIBUTION.md`，本轮核验见 [audio-audit.json](audio-audit.json)。该技术/来源对照不能代替上表的真人口音听辨。

另外保留两个人工内容决定：**yes** 的副词/感叹词标签是否按统一语法规范整理；**oriental** 的现有不推荐称人警示是否足够清楚。两项不自动改义。其余弱读/变体词可按 [quality-triage.csv](quality-triage.csv) 在日常遇到时抽查，不需要一次性给 72 词打完发音评级。

遇到不一致，记录词头、当前词性、单词或例句、真人或 TTS、听见的差别。对照 [质量复核依据](QUALITY_CLOSEOUT.md) 后再决定修改，保留原值和证据。未确认时保持待核验；词义学习仍可继续。
