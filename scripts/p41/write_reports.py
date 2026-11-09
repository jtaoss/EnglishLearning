"""Summarize completed native P4.1 evidence without publishing personal rows."""
import csv
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/p41'


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8-sig'))


def text(name, value):
    (OUT / name).write_text(value, encoding='utf-8')


warm = read('build/reports/p41/trial.json')
cold = read('build/reports/p41/trial.json.cold.json')
assert warm['status'] == cold['status'] == 'PASS'
assert warm['pid'] != cold['pid']
assert warm['tts_sample_count'] == 18 and warm['human_sample_count'] == 6
assert len(warm['playbacks']) == 24
assert all(r['native_completed'] for r in warm['playbacks'])
assert not warm['http_requests'] and not cold['http_requests']
assert all(read('docs/p41/personal-preservation.json')['formal_tables_equal_before_after'].values())
vocab = {r['entry_id']: r for r in csv.DictReader(open(ROOT / 'assets/vocabulary/reviewed500.csv', encoding='utf-8-sig'))}
samples = []
for r in warm['playbacks']:
    entry = vocab[r['entry_id']]
    samples.append({**r, 'current_part_of_speech': entry['part_of_speech'],
                    'current_stress_hint': entry['stress'], 'current_example': entry['example_en']})
with open(OUT / 'playback-samples.csv', 'w', encoding='utf-8-sig', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=list(samples[0]))
    writer.writeheader()
    writer.writerows(samples)
context_count = sum(r['context_completed'] for r in samples)
acceptance = {k: warm[k] for k in [
    'status', 'pid', 'created_utc', 'word_count', 'tts_sample_count', 'human_sample_count',
    'voice', 'locale', 'http_requests', 'meaning_only_without_listening',
    'formal_personal_database_opened', 'real_events_uploaded', 'human_hearing_confirmation',
]}
acceptance.update(cold_restart=cold, context_playbacks=context_count,
                  isolated_meaning_records=3, isolated_pronunciation_records=2,
                  application_code_changed=False, version='0.7.0+10',
                  initial_attempt='One playback wait timed out before per-word diagnostic logging; word and root cause not captured. After adding diagnostics, all 24 completed. No playback implementation change.',
                  residual_issue='Monitor transient playback stalls during trial; do not infer acoustic correctness from native completion.')
text('acceptance.json', json.dumps(acceptance, ensure_ascii=False, indent=2) + '\n')

focus = {
    'object': '本卡名词，首音节重读；听例句时别套用动词读法',
    'increase': '本卡动词，后音节重读；注意与名词区别',
    'address': '本卡美式名词首重读；英式读法有差异',
    'use': '本卡动词词尾浊辅音；与名词区分',
    'separate': '本卡形容词结尾轻读；与动词区分',
    'beloved': '形容词两/三音节均有依据；本卡列三音节，名词另看语境',
    'elementary': 'men 主重读；五音节与压缩读法',
    'database': '首音节主重读；data 开头元音变体',
    'resume': '本卡动词，两音节后重读；与下一词区分',
    'résumé': '求职名词，三音节首重读；重音符号不去掉合并 ID',
    'read': '本卡现在时；过去时同拼写有另一元音',
    'lead': '本卡动词；不要选金属名词的元音',
    'overhaul': '本卡按名词首重读练习；动词末重读',
    'combat': '当前提示为名词首重读；动词/口音有变体',
    'fifteen': '单独报数后重读；和 fifty 区分，例句节奏可变',
    'interesting': '首重读；三/四音节差异无需机械判错',
    'convenience': '第二音节主重读，检查多音节衔接',
    'texture': '首重读；ture 作为整体认读，检查词尾',
}
table = '\n'.join(f"| {r['word']} | {focus[r['word']]} | {'已播单词及例句' if r['context_completed'] else '已播单词'} | 待用户听辨 |"
                  for r in samples if r['source_type'] == 'local_tts')
audio = read('docs/p41/audio-audit.json')
human = '\n'.join(f"| {r['word']} | {r['author']} | [{r['license']}]({r['source_url']}) | 已完整播放；待用户听辨 |" for r in audio)
text('HUMAN_CONFIRMATION.md', f'''# 待人工确认清单

本轮使用 **{warm['voice']} / {warm['locale']}** 实际完成 18 个 TTS 单词播放，其中 {context_count} 个另播现有英文例句；另完成 6 段真人资源播放。没有导出 TTS 文件或下载新商业音频。来源类型和优先策略不变。

**以下“已播放”均指原生播放器/SAPI 返回完成，不是 agent 已亲耳听辨、自动声学评分或教师确认。** 请在正式软件搜索词头，先自主读，再分别播放单词和需要的例句；记录听感即可，不必为了验收给真实词条随意选评级。

| TTS 词头 | 重点 | 技术检查 | 人工状态 |
|---|---|---|---|
{table}

| 真人词头 | 作者 | 原文件页面及采用许可 | 状态 |
|---|---|---|---|
{human}

真人资源的稳定 ID/词头与 manifest、Wikimedia 文件页面相符；本地 PCM WAV 哈希、声道、采样率和时长均匹配既有审计，不重新剪辑或变速。big/tree/side/notice 采用 CC BY-SA 3.0，carry/autumn 为作者自行放入公有领域；转换说明及署名仍保留在 `assets/pronunciation/ATTRIBUTION.md`，本轮核验见 [audio-audit.json](audio-audit.json)。该技术/来源对照不能代替上表的真人口音听辨。

另外保留两个人工内容决定：**yes** 的副词/感叹词标签是否按统一语法规范整理；**oriental** 的现有不推荐称人警示是否足够清楚。两项不自动改义。其余弱读/变体词可按 [quality-triage.csv](quality-triage.csv) 在日常遇到时抽查，不需要一次性给 72 词打完发音评级。

遇到不一致，记录词头、当前词性、单词或例句、真人或 TTS、听见的差别。对照 [质量复核依据](QUALITY_CLOSEOUT.md) 后再决定修改，保留原值和证据。未确认时保持待核验；词义学习仍可继续。
''')
text('WINDOWS_TRIAL_ACCEPTANCE.md', f'''# P4.1 Windows 试用准备验收

日期 2026-11-09；版本 0.7.0+10。应用学习/同步/播放代码没有修改，仅新增隔离验收规格和报告，不重复开发已有模块。

| 检查 | 本轮证据 |
|---|---|
| 正常 Release 学习入口 | 已观察正式窗口本地 500 词，首页“开始今日学习 / 到期复习”可见；词库默认主学习范围 486、总数仍 500，扩展词另有范围 |
| 答案保密 | 24 词原生界面初始、认读提示后、播放后均无中文释义或双语例句；答案前词义评级禁用；正常 Release 的 about 卡同样隐藏答案 |
| 发音播放 | 18 个系统 TTS、6 个真人录音全部完整播放；{context_count} 个 TTS 例句播放；Zira Desktop en-US；逐词见 playback-samples.csv |
| 词义与发音独立 | object：眼熟/再练习；increase：遗忘/能独立认读；发音保存后词义仍未测试，之后词义保存不改发音 |
| 只评词义 | about 未确认认读、未播放直接揭示答案，保存遗忘，发音仍未测试 |
| 真正新进程恢复 | warm PID **{warm['pid']}** → cold PID **{cold['pid']}**；3 份词义、2 份发音记录、时间及来源逐值一致 |
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
''')
text('REPORT.md', '''# P4.1 交付记录

2026-11-09；版本保持 **0.7.0+10**，500 词不扩容。可开始 Windows 正式个人试用；发音人耳听辨及 7 天实际使用尚未代用户完成。

- [质量问题处理](QUALITY_CLOSEOUT.md)：94 条原标记/72 词已分级，26 词保留依据及前后值；未证实错误释义或拼读提示错误，未批量覆盖。
- [texture 补充映射](texture-mapping.json)：R4983 的有效第二词头、原书索引/正文/目录形成证据链；稳定 ID 和原台账保持不变。
- [待人工确认](HUMAN_CONFIRMATION.md)：18 个 TTS 样本及 6 段真人录音已实际完整播放，个人听辨仍待确认；yes 语法标签和 oriental 语域警示保留人工决定。
- [Windows 准备验收](WINDOWS_TRIAL_ACCEPTANCE.md)：隐藏答案、独立评级、仅词义学习、真正新进程恢复、到期优先和离线检查通过；一次未复现播放超时保留记录。
- [7 天个人试用说明](PERSONAL_TRIAL.md)：每天先到期后新词，建议手动 5～10 新词；备份已建立并通过独立恢复演练。

只新增核验脚本/隔离测试/文档，未更改学习模块、Notion 同步框架或内容包，未写真实学习事件。正式 SQLite 的 7 个表前后逐值相同；原 Starter 417 文件哈希一致。个人备份和原书页面证据在本机 private 目录，不随发布包分发。

下一阶段先按清单试用 7 天，收集具体词头与问题；对确认错误逐条依据修正，再决定是否需要修复功能或完善每日限额。保持 500 词范围，Android、正式事件回写及词库扩容继续暂停。
''')
print(json.dumps({'tts': 18, 'human': 6, 'context': context_count,
                  'warm_pid': warm['pid'], 'cold_pid': cold['pid']}, ensure_ascii=False))
