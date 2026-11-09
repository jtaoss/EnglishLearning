"""Render acceptance reports from observed native results; no credentials read."""
import collections
import json
import pathlib
import re
import sys

ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/p3'))
from prepare import write_csv, save_json
out=ROOT/'docs/p4'; private=ROOT/'private/p4'; native=ROOT/'build/reports/p4'
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
quality=read(out/'quality-summary.json'); audio=read(out/'audio-audit.json')
warm=read(native/'learning.json'); cold=read(native/'learning.json.cold.json')
live=read(native/'notion-live.json'); personal=read(native/'notion-personal.json')
assert all(x['status']=='PASS' for x in [warm,cold,live,personal])
assert warm['sample_count']==cold['sample_count']==34 and warm['pid']!=cold['pid']
assert cold['due_reviews_before_466_new_words'] is True
assert quality['structural_blockers']==0 and quality['vocabulary_content_changes']==0
tests=(private/'tests.log').read_text(encoding='utf-8-sig')
match=re.search(r'\+(\d+): All tests passed!',tests); assert match
assert 'No issues found!' in (private/'analyze.log').read_text(encoding='utf-8-sig')
builds={mode:'PASS' if 'Built ' in (private/f'windows-{mode}.log').read_text(encoding='utf-8-sig') else 'PENDING' for mode in ['debug','release']}
assert all(v=='PASS' for v in builds.values())
write_csv(out/'learning-samples.csv',warm['samples'],list(warm['samples'][0]))
categories=dict(collections.Counter(r['category'] for r in warm['samples']))
summary={'version':'0.7.0+10','date':'2026-11-09','vocabulary_count':500,'vocabulary_content_changes':0,
    'static_analysis':'PASS','unit_widget_tests_passed':int(match[1]),'windows_builds':builds,
    'native_sample_count':34,'native_categories':categories,'human_recording_samples':6,'local_tts_samples':28,
    'cold_process_restore':'PASS','overdue_34_before_466_new_after_restart':True,
    'notion_actual_500_full_repeat_incremental':'PASS','formal_personal_tables_preserved':True,
    'human_recordings':6,'local_tts_fallback_candidates':494,'installed_tts_voice':warm['voice'],
    'tts_subjective_human_review':'not confirmed; native completion and source/stress references checked',
    'quality_structural_blockers':0,'quality_words_flagged':quality['words_flagged_for_review'],
    'individual_high_risk_source_checks':quality['individually_source_checked_high_risk'],
    'real_personal_events_created':0,'real_learning_events_uploaded':0,'production_sqlite_schema':3,
    'android_build_or_device_work':False,'starter_changed':False,'ocr_performed':False,
    'vocabulary_sha256':quality['source_vocabulary_sha256']}
release_ui=out/'release-ui.json'
if release_ui.exists():
    summary['normal_release_ui']=read(release_ui)['status']
save_json(out/'acceptance.json',summary)

def write(name,text): (out/name).write_text(text.strip()+'\n',encoding='utf-8')
write('LEARNABILITY.md',f'''# 500 词可学习性检查

2026-11-09，Windows 0.7.0+10。保持既有 500 个稳定 ID，不扩容、不改词库内容。

- 500 词所需词头/词性/中文义/拼读/音节/重音/例句/来源/参考状态均存在；重复 ID、重复精确词头为 0，结构阻断为 0。
- CMUdict 音节及所标重读位置对照 500/500；多重读位置和变体另列风险，不把这种对照视为语音质量认证。
- PETS-3 2015 明确印刷词形匹配 473；2025 全部待核实。原书分类与 PETS 参考状态独立，不推断 PETS 词频。
- 6 词优先真人录音；494 词可调用本机已安装的英语 TTS。未安装适用语音或播放失败时，可继续词义复习。
- 原有逐词评级自动化覆盖 500 词；本轮又实际在原生窗口对 34 个词完成学习流程，详见 WINDOWS_ACCEPTANCE.md。

完整逐词检查为 [learnability-500.csv](learnability-500.csv)。内容包 SHA-256 前后相同：`{quality['source_vocabulary_sha256']}`。

这不是对 500 词所有义项的人工终审；个人确认状态保持原样。异常筛查、逐项来源对照与待确认项见 QUALITY_REVIEW.md。
''')
write('NOTION_SYNC.md','''# Notion 只读直连结果

状态：真实 API 验收通过。复用 P1-C 的 Windows Credential Manager、NotionReadApi、分组分页及 SQLite 事务；未新建同步框架或服务器。

本轮开始时，同一 Windows 账户下没有 `EnglishLearning.Notion.ReadOnly.v1` 条目；P3 记录也显示本机未完成安全配置。当前证据支持“此环境未保存配置”，不能据此断言旧设备凭据被程序删除。连接器授权不等于桌面应用的 WinCred 配置。

用户将已有密钥放入剪贴板，代理只把它粘贴到软件隐藏框并点击安全保存；输入框随后清空。没有读取/显示剪贴板原文，没有将 Token 写入普通文件、源码、日志、参数或程序包。

| 实际检查 | 结果 |
|---|---|
| 真实 Notion 500 词完整读取 | 新增 0、更新 0、未变 500 |
| 再次完整核对 | 新增 0、更新 0、未变 500 |
| 真实增量重复读取 | 新增 0、更新 0；500 个关联保留 |
| 29 个词库内容字段逐项比对 | 全部一致 |
| 隔离库中 34 词的词义/发音/日期/来源 | 全部保留 |
| 正式个人 SQLite 完整及重复增量同步 | 500 词一致；四张学习/事件表逐行不变 |
| 真实学习事件上传 | 0；接口未启用 |

正式同步前已另存 SQLite 备份，仅含本地数据，不含系统凭据。正式库仍为 schema v3；没有把测试评级或 P2-B1 副本迁入正式库。

读请求只使用官方 HTTPS 数据源读取及 query 端点。后台集成权限未通过受限的浏览器界面重新复核；本轮未创建、扩权或轮换密钥，也未尝试任何写入端点。

原生证据：`build/reports/p4/notion-live.json`、`notion-personal.json`。含隔离库路径的完整记录留在本机 build/private，不随发行包分发。
''')
links='\n'.join(f"| {a['word']} | {a['author']} | {a['license']} | [来源]({a['source_url']}) |" for a in audio['recordings'])
write('PRONUNCIATION.md',f'''# 发音覆盖与本地备用

| 类型 | 覆盖 | 本轮原生播放验证 |
|---|---:|---:|
| 已授权社区真人录音 | 6 | 6 |
| 缺真人录音、可使用本地 TTS | 494 | 28 |

本机语音：**{warm['voice']}（en-US）**。SAPI 使用已安装的 Microsoft Desktop 语音，只在本机实时播放；不使用云语音、不下载或打包语音引擎、不导出合成音频。其他电脑若未安装适用英语语音，会显示不可用并保留词义学习。

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
{links}

2026-11-09 核对 Wikimedia 原文件页的作者/许可，并核对随包 WAV 的 SHA-256。既有 Ogg→PCM WAV 转换及署名/CC BY-SA 许可文本保留，没有新增下载或商业词典音频抓取。逐文件信息见 audio-audit.json 与 assets/pronunciation/ATTRIBUTION.md。

**验证边界：**34 词的本地播放完整结束、来源、音节/重音提示已检查；没有获得用户或教师的逐词听辨确认。语音设备报告完成不等于证明现实扬声器可听见，也不保证多义词的每一种读法。对 resume/résumé、read/lead、overhaul 等优先使用例句和词性提示，并留待本人抽听。
''')
write('QUALITY_REVIEW.md',f'''# 词库质量异常与来源核验

500 词只读审计完成；结构阻断 0。自动筛查得到 **{quality['review_flags']} 条提示，涉及 {quality['words_flagged_for_review']} 词**，主要是多读音、大小写/重音符号、WordNet 词性覆盖差异和语境限定。这些是复核提示，不等于同样数量的错误。

已对 {quality['individually_source_checked_high_risk']} 个高风险词逐项对照词典/官方参考并保留结论：[review-before-after.csv](review-before-after.csv)。内容前后均相同，未批量覆盖原释义或云端字段。其余提示详见 [quality-flags.csv](quality-flags.csv)。

- `overhaul`：名词首重读、动词末重读；原提示及名词例句一致，保留。[Cambridge](https://dictionary.cambridge.org/dictionary/english/overhaul)
- `combat`：原名词首重读成立；美式动词也有首重读变体，不能机械套用“动词必末重读”。[Cambridge](https://dictionary.cambridge.org/dictionary/english/combat)
- `resume` / `résumé`：继续的动词与求职简历的名词保留独立 ID、词性和读法。[Cambridge](https://dictionary.cambridge.org/us/dictionary/english/resume)
- `lead` / `read`：原卡分别限定带领的动词和现在时阅读；保留语境提示，建议例句 TTS。[Cambridge lead](https://dictionary.cambridge.org/dictionary/english/lead)、[Collins read](https://www.collinsdictionary.com/us/dictionary/english/read)
- `outside`：初始审计错误地只取 CMU 首个重读位置，造成一条假警报；已修正审计器，保留原词。CMU 本条含两个重读位置，仍需结合副词/介词语境。[Cambridge](https://dictionary.cambridge.org/dictionary/english/outside)
- `percent`、`vegetarian`、`why`：词典支持原卡相关词性；WordNet 覆盖差异不是删改依据。[percent](https://dictionary.cambridge.org/dictionary/english/percent)、[vegetarian](https://dictionary.cambridge.org/dictionary/english/vegetarian)、[why](https://dictionary.cambridge.org/dictionary/english/why)
- `yes`：肯定答复义保留；副词/感叹词标签在词典体系间不同，仍列语法标签统一待复核。[Cambridge](https://dictionary.cambridge.org/dictionary/learner-english/yes)
- `oriental`：原卡已有不推荐称人的提示，保留阅读识别用途。[Oxford](https://www.oxfordlearnersdictionaries.com/definition/english/oriental_1)
- `texture`：词义/名词与词典一致；这是既有审计恢复词，当前5552台账没有同形/同ID直接映射。既有来源 PDF642 对应书内631，落在偶考分区；原始映射证据仍待补齐，不删除词条或伪造台账对应。[Cambridge](https://dictionary.cambridge.org/dictionary/english/texture)

原书分类与原台账直接对应 499 词，另 1 个 texture 如上留证据缺口。PETS-3 2015 明确词形匹配473；2025全部待核实。原始台账未删、未重新OCR。所有义项的完整人工终审仍未完成，个人确认字段未自动提升。
''')
write('WINDOWS_ACCEPTANCE.md',f'''# Windows 实际学习闭环验收

状态：原生 Debug 隔离学习及独立新进程恢复通过。版本 0.7.0+10；{int(match[1])} 项单元/组件测试通过，静态分析通过；Debug/Release 构建均通过。

原生隔离库内保留完整 500 词，实际操作 **34 个不同词条**，分类：{categories}。6 个真人录音、28 个 TTS；包含多音节、重音变体、大小写及带重音符号词。逐词结果见 [learning-samples.csv](learning-samples.csv)。

每词实际执行：英文且答案隐藏→自主认读确认→真人/TTS完整播放→独立发音自评→确认词义仍未评级→揭示中文及自然例句→独立词义评级→下一词再次隐藏答案。另检查真人及 TTS 重播，read/lead/resume/overhaul 的例句核对。未从是否听音推断词义掌握。

| 检查 | 证据 |
|---|---|
| 连续学习及下一词 | 34次词卡评级及跳转；下一词答案隐藏 |
| 词义与发音独立 | 每词发音保存后词义仍未测试；随后词义保存不改发音 |
| 眼熟不等于掌握 | familiar 单独状态及1天复习，未自动转 mastered |
| 可仅做词义 | TTS失败/未完成时仍可揭示答案并评级；组件测试 |
| 停止/失败不算发音完成 | TTS故障、停止、重试及再次练习门槛组件测试 |
| 到期优先 | 到期词在新词前；下一词优先取已到期复习，再维持当前词库的新词范围 |
| 断网 | 学习测试拒绝所有 Dart HTTP，实际请求0；本机音频/SAPI可用 |
| 重复导入 | 500未变，无新增/更新 |
| 进程关闭重开 | warm PID {warm['pid']}、cold PID {cold['pid']}；34份评级、复习日期、来源恢复，推进时钟后34个到期词排在466个新词之前 |
| 真实Notion重复同步 | 500字段一致；隔离34记录及正式个人学习表均保留 |

隔离学习库包含测试评级；正式个人库没有写入这些评级，正式同步前后学习事件新增0、真实事件上传0。P2-B1隔离代码及成果保留，正式schema仍v3。

最终正常 Release 新进程已观察：500词及安全连接恢复、默认500范围、完整核对新增0/更新0/未变500；about词卡隐藏中文，TTS明确标注系统合成且实际完整播放后启用评级。检查中未保存正式个人评级，见release-ui.json。原生播放完成不代替用户对实际扬声器和口音的主观听辨。
''')
write('REMAINING.md','''# 尚未解决的问题及下一阶段

1. 494词仍缺真人录音，本机TTS是备用核对来源。其他电脑须有可用的已安装英语Desktop语音；未自动下载安装系统语音或改安全设置。
2. TTS的多义词读音及口音质量仍需本人/教师抽听确认。已提供原例句核对，未宣称完成真人听辨或自动发音评分。
3. 72词的94条复核提示已导出，17词完成逐项来源对照；全部义项的完整人工终审、yes标签体系和texture原台账对应证据仍待继续。未自动覆盖任何释义、稳定ID或个人确认状态。
4. Notion后台集成权限未在受限浏览器界面复核。本轮复用用户提供的现有只读配置，只调用读取端点，没有创建、扩权或轮换密钥。
5. 正式学习事件回写仍未授权，继续保持关闭。不把最终评级倒推成历史事件，不把隔离测试库当成个人库。

建议先用当前500词实际学习一周，记录高风险词的读法/释义问题；随后逐条审阅复核清单，并按合法许可补充真人资源。无须先扩容、开发Android或部署后端。
''')
write('REPORT.md',f'''# EnglishLearning 0.7.0+10：500词实际学习验收

日期：2026-11-09。Notion与Windows均保持500词。真实只读直连已恢复，500完整/重复/增量同步通过；34词原生学习和独立进程恢复通过，正式个人记录未受测试评级污染。

| 输出 | 内容 |
|---|---|
| [500词可学习性](LEARNABILITY.md) | 全量字段/身份/参考检查、逐词CSV |
| [Notion只读同步](NOTION_SYNC.md) | 凭据原因、安全保存、真实500词及个人记录保留 |
| [发音覆盖与备用](PRONUNCIATION.md) | 6真人+494本地TTS备用、来源和许可 |
| [质量异常](QUALITY_REVIEW.md) | 72词94提示、17词来源对照、前后值 |
| [Windows学习闭环](WINDOWS_ACCEPTANCE.md) | 34词原生流程、故障/复习/重开/离线验证 |
| [剩余问题与建议](REMAINING.md) | 人工听辨、全义项终审及证据缺口 |

检查：静态分析通过，{int(match[1])}项单元/组件测试通过，Debug/Release构建通过。机器可读结果见 acceptance.json。

没有扩容到1000词、Android构建/真机开发、自建服务器、商业词典音频抓取或重新OCR。原Flutter Starter保持不变，P2-B1隔离成果保留，未上传真实学习事件。
''')
print(json.dumps(summary,ensure_ascii=False,indent=2))
