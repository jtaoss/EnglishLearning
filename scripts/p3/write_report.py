"""Summarize observed P3 outputs and logs; pending acceptance remains pending."""
import json
import pathlib
import re

root=pathlib.Path(__file__).resolve().parents[2]
private=root/'private/p3'
stats=json.loads((root/'docs/p3/selection-statistics.json').read_text(encoding='utf-8'))
preview200=json.loads((private/'notion-preview-200.json').read_text(encoding='utf-8'))
preview500=json.loads((private/'notion-preview-500.json').read_text(encoding='utf-8'))
def log(name):
    path=private/name
    return path.read_text(encoding='utf-8-sig',errors='replace') if path.exists() else ''
tests=log('tests-final.log')
match=re.search(r'\+(\d+): All tests passed!',tests)
count=int(match[1]) if match else None
analysis='通过' if 'No issues found!' in log('analyze-final.log') else '待检查日志'
native=root/'build/reports/p3-native/native-report.json'
cold=root/'build/reports/p3-native/cold-report.json'
native_state='原生与独立进程冷启动均通过，见 build/reports/p3-native 下两个报告' if native.exists() and cold.exists() else '原生流程已通过，独立进程冷启动待验收' if native.exists() else '待 Windows 原生验收；未计作通过'
builds={}
for mode in ['debug','release']:
    text=log(f'windows-{mode}-final.log')
    builds[mode]='通过' if ('Built build' in text or 'Built ' in text) and '.exe' in text else '待完成'
starter=json.loads((private/'starter-verification.json').read_text(encoding='utf-8')) if (private/'starter-verification.json').exists() else {}
category_table='\n'.join(f'| {name} | {stats["raw_category_counts"].get(name,0)} | {stats["selected_category_counts"].get(name,0)} |' for name in ['高频词','中频词','基础词','低频词','偶考词','补充词'])
class_changes='、'.join(r['word'] for r in stats['existing_class_changes'])
cloud_path=root/'docs/p3/NOTION_IMPORT_STATISTICS.json'
cloud=json.loads(cloud_path.read_text(encoding='utf-8')) if cloud_path.exists() else {'cloud_words':100,'batches':{}}
cloud_count=cloud['cloud_words']
cloud_conclusion=(f'**Notion 已扩至 {cloud_count} 词，直接读回的 29 个内容字段与数据哈希一致。** '
    '真实 Notion 连接器快照经 CSV 导入 Windows SQLite，重复导入与独立进程恢复已验证；应用内直连增量同步因用户暂未配置只读密钥，仍待验收。'
    if cloud_count>100 else '**Notion 仍为 100 词，尚未写入扩容。**')
batch200='已执行并验收（真实云端快照→CSV→Windows）' if cloud.get('batches',{}).get('200',{}).get('accepted') else '待完成'
batch500='已执行并验收（真实云端快照→CSV→Windows）' if cloud.get('batches',{}).get('500',{}).get('accepted') else '须先验收 200'
report=f'''# P3 词库扩容与 Windows 学习闭环报告

日期：2026-11-09。源码从实际 0.5.0+8 推进至 **0.6.0+9**；未回退到消息中提及的旧版本 0.4.1+7。

## 当前结论

已完成 500 词本地内容包、100→200→500 扩容代码、完整词卡认读/词义学习流程和自动化验证。{cloud_conclusion} Android 暂停，现有工程保留；未上传真实个人学习事件。

## P3-A：筛选及词头质量

原有审计 ZIP 与 5,552 条候选记录直接复用，未重新 OCR、未删除原始记录。按已目视核对的原书目录 PDF10，书内 1–284 页为高频，285–440 中频，441–588 低频，589–639 偶考，640–700 基础，701–715 补充。页码相对 PDF 偏移沿用原审计。

| 原书分类 | 原候选台账 | 本批 500 |
|---|---:|---:|
{category_table}

高频/中频/基础 **{stats['mandatory_retained']} 条全部保留为候选**。结合 2015 明确词形参考及本批实用性选择，共 {stats['screened_candidate_retained']} 条保留候选；这不表示它们已完成释义与发音内容终审。其他条目保留原记录和暂缓理由，不宣称无价值或官方未收录。原台账未覆盖补充词分区，未凭空补造其记录。

本批保持原 100 个既有 ID；新增 400 个 ID 完整沿用候选台账，不重新生成。新增 400 词均有原审计的正文同页词头支持。初选中仅有索引证据的 live、cheese、story、tool、general、almost、personal、progress、red、wonderful 已退出本批；替换为 learn、class、street、table、give、also、people、public、right、warm。原始条目和内容草稿留在 private/p3，后续仍可复核。

## P3-B：内容与来源

- 500 词均有词性、常用中文义、来源、学习优先级、自然例句/译文、逐词拼读提示、音节、主重音及音频许可状态；不使用国际音标或中文谐音。
- 400 词新增释义/例句独立编写并作 AI 语义复核。现有 100 词保留原释义复核状态；为使词性读法与例句一致，combat、overhaul、limitation 的例句纳入变更预览。
- 所有 500 词的手工字母分块/音节数/主重音与 CMUdict 至少一个美式变体匹配。多读音、功能词弱读和词性重音另有说明；此检查不等于自动发音评分或个人确认。
- 2015 官方附录明确词形匹配 **{stats['pets2015_matches']} 词**；其余标记“未直接列出”，不作官方排除结论。2025 **500 词全部待核实**。原书考研词频与 PETS 参考状态分字段保存。
- 6 词沿用已有合法录音，494 词标记待补充；没有抓取或伪造商业词典音频。缺少录音时仍可学习词义和保存自主认读自评。

参考来自 [教育考试院公开的 2015 大纲 PDF]({stats['official_2015_url']})（前言 2015年3月；附录四主表及明确附表词形），[CMUdict](https://github.com/cmusphinx/cmudict) 与 [WordNet 3.1](https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz)。许可见 assets/vocabulary/P3_ATTRIBUTION.md 及随包文本。商业原书、完整台账和云端快照不进入公开资源包。

## P3-C：Notion 审计与授权执行

执行前真实读取 100 词，重复稳定 ID 为 0；100 个 ID/词头与本地旧样本一致。原数据源已有个人状态和个人拼读笔记，**不复用这些字段存放词库内容**。用户明确批准两批、200 验收后继续 500；已新增 7 个独立 rich_text 内容字段：拼读提示、音节说明、重音说明、拼读复核说明、音频许可状态、标准音频来源、标准音频许可。

| 批次 | 执行前应有 | 新增 | 既有内容更新 | 删除 | 已执行 |
|---|---:|---:|---:|---:|---|
| 扩至 200 | 100 | 100 | 100 | 0 | {batch200} |
| 扩至 500 | 200 | 300 | 0 | 0 | {batch500} |

首批更新包括上述内容字段、独立例句、参考证据、数据版本/哈希，以及 9 个“暂缓→扩展”的内容分类调整：{class_changes}。不写入个人词义/发音/自然拼读/听音状态、次数、复习日期或历史事件。分类调整理由逐词列在预览中。

- 首批完整清单：`private/p3/notion-preview-200.html`、对应 JSON 和 `preview-200.csv`。
- 首批审批哈希：`{preview200['sha256']}`。
- 第二批：`private/p3/notion-preview-500.html`，哈希 `{preview500['sha256']}`。
- 字段变更：`docs/p3/NOTION_SCHEMA_PREVIEW.sql`，经批准已执行。

写入前已重新读取 schema/全部 ID，并核对批准的精确预览哈希与内容前置条件；已存在 ID 不新建。首批先完成真实云端 200 词内容/优先级及 Windows SQLite 验收，再执行第二批。实际统计见 `NOTION_IMPORT_STATISTICS.json`，逐次回执与含个人状态的原始快照仅留 private/p3。

Notion SQL 与部分 rows 结果在写后曾返回旧的 100 词字段；最终对旧 100 页逐页 fetch，对新增 400 页直接 rows 读取，按已核验字段还原 rich_text 的 Markdown 转义并逐项比对，未把缓存旧值冒充当前内容。云端只读连接器导出的 CSV 来自这些真实读回值，没有构造 page/edit-time 元数据模拟 API。应用内直连 Notion 的分页/增量读取仍需用户日后安全配置只读密钥后单独实测。

本机正式学习库导入前另存 SQLite 安全备份，执行前为 0 词，执行后为 500 词；再次导入新增 0、更新 0、未变 500。新词均未测试，未创造任何词义/发音历史事件。隔离验收中的保留评级只存在隔离测试库，未复制到正式个人库。

## P3-D：Windows 实现与测试

首页自动取得主学习及扩展词的未测试/到期队列；词库支持英文搜索和惰性列表。词卡隐藏答案，允许先自主认读，再查看提示/音节/重音；已有合法录音可完整播放及重播，随后独立自评。揭示词义后可看例句并独立评词义。两类评级分别安排 10 分钟/1 天/7 天复习，发音日期由原有状态与时间计算，正式 schema 继续 v3。

Notion 按最多 100 个 ID 分组并分页，所有分组成功后一次事务提交。扩容强制完整核对，避免新范围中的旧时间戳词遗漏；旧 100 词字段结构兼容。同步内容不会改个人记录，无网络时学习读写不依赖 Notion。

| 检查 | 本轮实际结果 |
|---|---|
| Dart 静态分析 | {analysis} |
| 单元/组件自动化 | {f'{count} 项全部通过' if count else '待检查实际测试日志'} |
| 100→200→500、重复导入、磁盘重开及状态不变 | 自动化通过 |
| 500 个词逐一记录词义评级 | 自动化通过，均可学习 |
| 发音自评独立到期与重复尝试去重 | 自动化通过 |
| 分组分页同步、失败整批回滚、重复同步 | 使用合成 API 页面自动化通过；不冒充真实 Notion 验收 |
| 真实 Notion 快照→CSV→Windows SQLite | 200/500 分阶段执行，见 NOTION_IMPORT_STATISTICS.json；与应用内直连 API 区分 |
| 无音频完整词卡流程、500 词搜索和隐藏答案 | 组件测试通过 |
| Windows Debug | {builds['debug']} |
| Windows Release | {builds['release']} |
| 正常 Release 程序 500 词首页/词卡 | 新进程实际检查隐藏答案、自主认读、拼读/音节/重音、无音频提示、中文义和自然例句；未写个人评级，见 RELEASE_UI_ACCEPTANCE.json |
| Windows 原生/离线/播放/重开 | {native_state} |

新增原生 P3 规格仍由统一 integration_test/app_acceptance_test.dart 注册，显式参数启用；报告输出到 build/reports/p3-native，不打开正式个人库。原始 Starter 三个目录共 {starter.get('files_checked','待核对')} 个源文件哈希核对，变更 {len(starter.get('changed',[]))}；Android 原始工程、pubspec.lock 与原 100 词资产均未改动。

本机 AllSigned 策略阻止未签名 scripts/verify.ps1 执行，因此按其对应原生命令逐项验证；未修改执行策略。日志保存在 private/p3。未执行 Android 构建/设备验收。

## P3-E：事件同步与恢复准备

保留 P2-A 的模拟事件隔离、P2-B1 的副本迁移/outbox/inbox、事件 ID 与载荷哈希、sending/uncertain 对账及重启恢复规则；原有自动化继续通过。正式库不自动升级为副本，不启用真实上传开关。不从最终评级倒推历史事件。发音保存重试保留同一次尝试身份与时间，避免重复事件或日期漂移。

正式事件字段还须区分“自主认读”与“完整听过合法录音后的自评”，不将 self-reading 来源包装成听音事件。旧模拟载荷没有该依据字段，正式适配前需要在副本验证；具体字段和恢复门槛见 [EVENT_READINESS.md](EVENT_READINESS.md)。

正式事件库实施前仍需：单独明确授权、独立事件集成权限、正式个人库备份/校验、最多 1–3 个授权后新事件白名单、重复/超时/重启对账验收。失败保留本地事实与回执，不删除云端事件凑数。该准备不阻塞本地背词。

## 剩余问题及下一道门槛

1. Windows 应用内直连 Notion 的真实增量同步尚未验收：用户目前无法配置只读密钥。已使用现有 CSV 路径完成真实云端内容转入本地；不将此等同于直连 API 验收。
2. 双向学习事件同步仍未启用，真实事件上传未授权。原有最终评级未转成虚构历史事件。
3. 494 词标准录音待合法来源补充；词义、例句与逐词读法仍保留 AI 复核/待个人确认区别。
4. 超出本批的候选仍需内容质量核验；暂缓候选没有删除。补充词分区缺少原台账记录，不能宣称全书已覆盖。
5. 本目录是源码副本，没有 .git 元数据；未执行提交或发布。完整 5,552 台账与个人记录保留私有。

复现内容：`python scripts/p3/prepare.py`、`python scripts/p3/render_preview.py`。输入/输出及恢复门槛见 scripts/p3/README.md。筛选统计与资源哈希见 selection-statistics.json。
'''
(root/'docs/p3/REPORT.md').write_text(report,encoding='utf-8')
print(f'Report updated: tests={count}, analysis={analysis}, builds={builds}, native={native.exists()}')
