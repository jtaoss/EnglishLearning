"""Export derived P5-A results for GitHub without raw ledger or personal data.

The complete local audit/Notion payloads remain ignored. This export contains
content, editorial decisions and a read-only import summary, never credentials.
"""
import csv
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
DATA = ROOT / 'docs/p5a'
OUT = DATA / 'public'
OUT.mkdir(parents=True, exist_ok=True)


def rows(path):
    with open(path, encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def write(name, records, fields):
    with open(OUT / name, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction='ignore')
        w.writeheader()
        w.writerows(records)


content_fields = list(rows(ROOT / 'assets/vocabulary/reviewed500.csv')[0])
audit_fields = ['processing_status', 'recommend_keep', 'selection_method',
                'selection_confidence', 'quality_status', 'blocking_issues',
                'source_verification_method', 'book_category_status',
                'book_category_evidence', 'pets2015_reference_status',
                'pets2025_verification_status', 'phonics_resource_status',
                'pronunciation_resource_status', 'ai_model', 'ai_reason',
                'ai_confidence', 'evidence_source', 'content_license', 'head_change_note']
for name, expected_count in [('selected_vocabulary.csv', 5331),
                             ('deferred_vocabulary.csv', 27), ('manual_review.csv', 194)]:
    records = rows(DATA / name)
    assert len(records) == expected_count
    write(name, records, content_fields + audit_fields)
formal = rows(DATA / 'formal_learning_vocabulary.csv')
assert len(formal) == len({r['entry_id'] for r in formal}) == 5332
write('formal_learning_vocabulary.csv', formal, content_fields)
preview = rows(DATA / 'notion_import_preview.csv')
assert len(preview) == 5553
write('notion_import_preview.csv', preview,
      ['entry_id', 'word', 'action', 'processing_status', 'candidate_scope', 'changed_fields', 'personal_fields_policy'])
write('field_mapping.csv', rows(DATA / 'field_mapping.csv'),
      ['csv_field', 'notion_property', 'notion_type', 'policy'])
stats = json.loads((DATA / 'statistics.json').read_text(encoding='utf-8'))
stats = {k: v for k, v in stats.items() if k not in
         {'live_snapshot_fetched_utc', 'connector_projection_field_differences', 'dataset_sources_sha256'}}
(OUT / 'statistics.json').write_text(json.dumps(stats, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
validation = json.loads((DATA / 'validation.json').read_text(encoding='utf-8'))
(OUT / 'validation.json').write_text(json.dumps(validation, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
report = '''# P5-A 公开交付摘要

当前软件版本 **0.7.0+10**。正式 Notion 与 Windows SQLite 仍保留原有 **500** 词；本轮只处理数据，没有新增软件功能或正式云端写入。

## 数量与结果

**5,552 = 5,331 正式入选 + 27 暂缓学习 + 194 待人工核实。** 三种状态互斥，每个原始 ID 都有处理状态。另保留此前恢复的 texture，它不在原 5,552 台账内，因此合并建议库为 **5,332** 词。

|原书分类|候选|正式入选|暂缓|待核实|
|---|---:|---:|---:|---:|
|高频|977|951|0|26|
|中频|635|586|0|49|
|基础|1,795|1,780|0|15|
|低频|670|576|0|94|
|偶考|1,475|1,438|27|10|
|补充|0|0|0|0|

原书高频、中频、基础 3,407 词全部建议保留，其中 90 词仅因质量待核实，未因 AI 评分被暂缓。补充分区在既有输入中的数量为 0，不表示教材没有补充词，也不宣称输入覆盖了教材所有附录。

选择性用途判断共 1,145 词，AI 建议保留 1,116、后置 27、待核实 2；最终正式名单中 1,059 词来自 AI 用途建议，其余受来源质量门槛约束。所有 AI 判断标为主观学习次序建议，没有虚构语料词频、官方考试频率或精确模型型号。

2015 官方附录明确词形匹配 3,962、未直接列出 1,590；未直接列出不等于考试不考。2025 归属均待核实。原书考研分类与 PETS 状态分别保存，大小写敏感匹配，May/may、March/march、resume/résumé 保持不同 ID。

## 可公开的数据

- [正式入选词库](selected_vocabulary.csv)：5,331 条，保留稳定 ID、词性、独立编写或有许可参考的释义、来源、PETS、学习优先级与质量状态。
- [暂缓词库](deferred_vocabulary.csv)：27 条，源记录不删除。
- [待核实词库](manual_review.csv)：194 条；其中 177 条需核对原书正文词头，另外 17 条涉及大小写、语法或语域。拟用释义不能当作已确认内容导入。
- [合并内容库](formal_learning_vocabulary.csv)：5,332 条，包括原有 500 与台账外 texture。
- [Notion 导入摘要](notion_import_preview.csv)：新增 4,832、更新 0、原有 500 保持不变；另跳过 194 待核实及 27 暂缓。此公开文件不包含正式写入载荷或私有云端快照。
- [字段映射](field_mapping.csv)、[统计](statistics.json)、[数据验证](validation.json)。

这些是派生的筛选和编辑结果，导出时删除原始台账 original_ 字段及历史个人投影；原始候选 CSV、完整原始字段审计台账、教材 PDF、正式 SQLite、Notion 原始快照、凭据和本地交付 ZIP 均不进入 Git。

## 质量与证据层级

复用既有 OCR、稳定 ID、分类页码和 P4.1 修正，没有重新 OCR。原有 500 的 29 个内容字段及全部个人 SQLite 表保持不变。

5,053 个新候选完成逐词语义检查：2,144 个使用许可 COW 概念词元形成草稿，另 2,909 个独立编写释义及词性并分批保存。累计记录 639 个有来源草稿的改写、2,909 个新释义字段，最终 5,036 个通过会话自检、17 个保留语义待核实；来源与大小写等问题叠加后为 194 个待人工核实词。**会话自检不是教师终审，也不是每词均经多家词典独立核验。**

许可依据、来源和编辑检查点见 [许可](../licenses/)、[用途判断](../value_batches/)、[语义批次](../content_batches/)、[独立补义批次](../extended_content_batches/)、[有据修正](../quality_resolutions.json) 与 [第二轮修正](../semantic_second_pass.json)。WordNet/COW 义项是线索，检索次序不能作为课程优先级或常用义证明。中文释义独立整理，不批量复制商业词典释义或例句。

对 he/at 的元素符号错配、常用介词/代词标签及 coronavirus 家族义等高风险项核对了出版社语法资料或官方来源，保留修正前后记录。renaissance、whatsoever、dumb、handicap、lame、dwarf、rape、idiot、queer、irrespective、gay、cock、used、except、while、both、several 仍需语义、语域或大小写审定；bible 的大小写问题同时归入来源待核实组，未重复计数。

原先待核实的 406 个新词仅作现有 PDF 文本层补查，229 个得到同页行首完整词形支持，177 个仍待核实。原 PDF 的 xref 解析警告已记录，文本匹配未冒充图像终审。

沿用现有六个合法真人录音，其余 5,326 词允许复用已安装的 Windows 本地 TTS；本轮未声称全量试听。4,832 个新增词的逐词拼读、音节、重音和例句未建设，状态如实保留。不显示音标或中文谐音，不伪造拼读规律；缺录音不阻塞词义入选。

## 导入与验证边界

正式 Notion schema 和全部 500 条已只读核对，29 个映射内容字段与已有 500 包一致。按稳定 ID 的离线预演首次新增 4,832、重复时新增 0/更新 0，另以纯模拟行检查内容更新不会修改个人字段。**这不是正式远端写入验收；本轮实际内容写入 0、事件上传 0。**

数量守恒、原始字段本地保留、稳定 ID、现有 500 内容、个人 SQLite 全表、无个人字段的载荷、select 映射及两次确定性重建均通过。原教材、原有 500 包、Windows Release 与原 Flutter Starter 的 417 个文件哈希一致。

当前软件 CSV 入口限 500 词 / 1 MB，Notion 同步范围仍为现有 500 词。**完整建议库尚不能直接替换现有应用资源或宣称已完成大词库 Windows 验收。** 194 词需核实；未来正式导入仍需更新只读基线、稳定 ID 幂等执行器、用户明确写入授权及另行授权的客户端容量接入。本轮不继续开发或执行正式写入。

## 重建

处理脚本见 [scripts/p5a](../../../scripts/p5a/)。已有本机私有原始输入与许可缓存时运行：

```powershell
python -X utf8 scripts/p5a/build_delivery.py
python -X utf8 scripts/p5a/write_reports.py
python -X utf8 scripts/p5a/validate_delivery.py --check-rebuild
python -X utf8 scripts/p5a/export_public.py
```

离线构建复用保存的判断，不自动调用模型；没有私有原始输入的新机器不能仅靠公开仓库重建完整原始审计。不要对未逐词检查的新数据直接使用 approve。

参考：[2015 PETS 官方附录](https://pets.neea.edu.cn/res/Home/2507/7186495d90963d37a36afccbfb505cc9.pdf)、[WordNet 许可](https://wordnet.princeton.edu/license-and-commercial-use)、[COW 许可](https://github.com/omwn/omw-data/blob/main/wns/cow/LICENSE)。原有音频许可见 [署名](../../../assets/pronunciation/ATTRIBUTION.md)。
'''
(OUT / 'REPORT.md').write_text(report, encoding='utf-8')
print(json.dumps({'export': 'docs/p5a/public', 'selected': 5331, 'deferred': 27, 'manual': 194, 'formal': 5332, 'raw_ledger_included': False, 'personal_data_included': False}, ensure_ascii=False))
