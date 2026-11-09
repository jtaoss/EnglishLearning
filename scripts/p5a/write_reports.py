"""Render the P5-A data report and human review index from persisted outputs."""
import csv
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/p5a'
S = json.loads((OUT / 'statistics.json').read_text(encoding='utf-8'))


def rows(name):
    with open(OUT / name, encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def cell(text):
    return str(text).replace('|', '\\|').replace('\n', ' ')


manual = rows('manual_review.csv')
deferred = rows('deferred_vocabulary.csv')
source_pending = [r for r in manual if '原书正文词头仍待核实' in r['blocking_issues']]
other_pending = [r for r in manual if r not in source_pending]
category_table = '\n'.join(
    f"|{cat}|{sum(counts.values())}|{counts.get('正式入选', 0)}|{counts.get('暂缓学习', 0)}|{counts.get('待人工核实', 0)}|"
    for cat, counts in S['category_dispositions'].items())
other_table = '\n'.join(f"|{r['word']}|{cell(r['blocking_issues'])}|" for r in other_pending)
defer_words = '、'.join(r['word'] for r in deferred)
report = f'''# EnglishLearning P5-A 全量筛选与质量报告

日期：2026-11-09。应用版本保持 **0.7.0+10**。本阶段只产出本地数据、审计记录及只读导入预览；正式 Notion 和 Windows SQLite 仍为原有 500 词。

## 1. 交付结论与数量守恒

**5,552 个候选词全部有明确、互斥的处理状态：5,331 正式入选 + 27 暂缓学习 + 194 待人工核实 = 5,552。** 全部处理指台账覆盖完整，并非全部经过教师终审或全部可以立即导入。

已验收的 texture 是此前从异常源记录恢复的词，不在这份 5,552 台账内。本轮另行完整保留它。因此：原候选入选 5,331 + 恢复保留 1 = 合并正式建议库 **5,332**；其中原有正式 500 个 ID 和内容全部保留，预计新增 **4,832**，预计更新 **0**，保持不变 **500**。texture 不重复计入 5,552 数量守恒。

|统计项目|数量|
|---|---:|
|原始候选总数 / 大小写敏感唯一词头|5,552 / 5,552|
|正式入选（原候选范围）|5,331|
|暂缓学习 / 待人工核实|27 / 194|
|AI 用途筛选实际入选|1,059|
|2015 官方附录明确词形匹配 / 未明确列出|3,962 / 1,590|
|2025 归属待核实|5,552（另保留 texture 的待核实状态）|
|现有 Notion 词条|500|
|预计新增 / 更新 / 保持不变|4,832 / 0 / 500|
|重复稳定 ID / 重复完整词头 / ID 冲突|0 / 0 / 0|
|大小写或重音符号相关组|3 组，6 个独立词条|
|带异常或提示的条目|492（含普通警告，不等于 492 个已证实错误）|

|原书分类|候选|正式入选|暂缓|待人工核实|
|---|---:|---:|---:|---:|
{category_table}
|合计|5,552|5,331|27|194|

高频、中频、基础词共 **3,407** 个全部建议保留；其中 90 个因质量证据不足暂列待核实，没有因 AI 低分被暂缓。原书目录分区为高频书内 1–284、中频 285–440、低频 441–588、偶考 589–639、基础 640–700、补充 701–715。原始台账在补充分区的输入数量为 0；这不表示原书没有补充词，也不宣称这份既有台账覆盖了教材所有附录。未扩展输入范围、未重新 OCR。

## 2. 文件与数据边界

|文件|内容及用途|
|---|---|
|[selected_vocabulary.csv](selected_vocabulary.csv)|5,331 个原候选入选条目，含完整审计字段|
|[deferred_vocabulary.csv](deferred_vocabulary.csv)|27 个后置学习条目，不删除源记录|
|[manual_review.csv](manual_review.csv)|194 个未达到正式门槛的条目；拟用释义不能当已确认内容导入|
|[all_candidates_audit.csv](all_candidates_audit.csv)|全部 5,552 个候选，原始 13 字段逐值保留在 original_ 列|
|[original_candidates.csv](original_candidates.csv)|原始候选台账逐字节副本|
|[notion_import_preview.csv](notion_import_preview.csv)|5,553 行预览，包含 texture；新增、保持不变、暂缓和待核实明确分开|
|[formal_learning_vocabulary.csv](formal_learning_vocabulary.csv)|5,332 条合并内容数据，仅用于数据审阅及未来接入准备|
|[retained_supplemental.csv](retained_supplemental.csv)|台账外的既有 texture 1 条|
|[preserved_existing500.csv](preserved_existing500.csv)|当前 500 词的 29 个内容字段原样保留|
|[meaning_before_after.csv](meaning_before_after.csv)|新候选草稿的原值、拟定值、依据与检查状态；不修改原有 500 词|
|[quality_anomalies.csv](quality_anomalies.csv)|所有阻塞项及警告；同一词可有多项，不用于数量守恒|
|[manual_review_guide.md](manual_review_guide.md)|194 词的逐词处理指引及页码索引|
|[field_mapping.csv](field_mapping.csv)|38 个内容与来源映射；个人学习字段不在写入范围|
|[stable_id_conflicts.csv](stable_id_conflicts.csv)|只有表头：未发现稳定 ID 冲突|
|[statistics.json](statistics.json)、[independent_validation.json](independent_validation.json)|机器可读统计与独立校验结果|

CSV 使用 UTF-8 BOM 和标准引号转义。`processing_status` 是唯一的三分处理状态；分类、优先级、PETS 标签及 AI 建议均是附加维度。原始 ID 从未重算。May/may、March/march、resume/résumé 分别保留独立 ID。原台账 Leap 沿用现有 500 词已验收的 leap 及同一 ID，变化单列 [head_normalizations.csv](head_normalizations.csv)，未对全库小写化。

texture 复用 [P4.1 已有证据](../p41/texture-mapping.json)：索引 PDF 766、正文 PDF 642 对应书内 631，目录 PDF 10 的偶考分区。没有重复执行已有图像核验。

## 3. 筛选方法与 AI 判断

优先顺序为既有验收内容、原书必留规则、2015 官方附录明确词形，之后才使用主观用途建议。低频、偶考中需要主观评估的 **1,145** 个条目分 5 批保存：建议保留 1,116、暂缓 27、待核实 2。建议保留中仍受来源/内容门槛约束，最终由 AI 建议进入正式名单的为 1,059 个。不同筛选机制不能相加当作新的总数。

每条 AI 判断保留模型标记、建议、P2 学习优先级、逐词理由、置信度及可追溯的 WordNet 概念线索；未核实词降低置信度。模型标记为“Codex 当前会话；精确运行型号未公开”，没有虚构外部模型调用或型号。此处的适用性、较专门或可后置均是 **AI 学习次序建议**，没有采用可量化语料频率，也不冒充官方考试频率。

首轮用途理由有时引用许可词网的第一个义项，可能过窄。合并前将已复核的常用中文义与概念域用于说明用途，并在 [selection_reason_refinements.csv](selection_reason_refinements.csv) 保留首轮及最终理由。该转换是审计说明整理，不是新词频打分。不可把 WordNet 的检索次序理解成课程优先级或中文常用义证明。

暂缓的 27 词为：{defer_words}。各自依据见暂缓 CSV 和原始批次。它们仍在原始台账内，不表示无价值、错误词或官方考试不考。

## 4. 释义、词性与来源质量

对 5,053 个非既有词条逐词检查了中文常用义与词性：2,144 个由许可 COW 概念词元形成草稿并核对；另 2,909 个逐词独立编写简洁释义和词性，分 15 批保存。累计 639 个有既存来源草稿的条目记录了改写，2,909 个记录了空值到新释义的添加。上述计数含尚待核实的草稿，不能当作正式入选数。最终语义状态 5,036 个通过本轮会话自检、17 个保留语义待核实；再叠加原书来源和专名问题形成 194 条人工清单。

检查重点为错配、词性、常用多义与中文自然程度，例如修正 emperor 只匹配某种蛾类、fireman 的不自然词元及 agony 的错误义项等草稿；为 sanction、principal、bank、contract、wind 等保留常用多义与词性。没有批量照抄商业词典释义或例句。没有修改现有 500 词的任何释义。

高风险的 he / at 被词网大小写折叠误配为元素符号，已剔除错误概念依据；依据出版社语法资料独立补成代词/介词。另对 despite、unlike、every、someone、another、whatever、but 的常用词性，以及 intercourse 的现代/旧式用法、coronavirus 的病毒家族含义进行有据修正，保存于 [quality_resolutions.json](quality_resolutions.json)。依据分别为 [Cambridge he](https://dictionary.cambridge.org/dictionary/english/he?topic=personal-pronouns)、[Cambridge at](https://dictionary.cambridge.org/grammar/british-grammar/at)、[Cambridge but](https://dictionary.cambridge.org/grammar/british-grammar/but)、[Cambridge intercourse](https://dictionary.cambridge.org/dictionary/english/intercourse) 与 [NIH coronavirus](https://health.nih.gov/health-topics-a-z/coronaviruses)，逐条链接保留在修正记录内。仅作核验后独立编写，没有保存其受保护的长段释义。

最后又对 intelligence、security、generation、foundation、occupation、invest、revenue、division、deliver、robust、peculiar、gender、impressive、feasible、viable、exotic 16 个新草稿检查常用义完整性、POS 和中文自然程度，保存 [第二轮前后差异](semantic_second_pass_diffs.csv) 与 [依据](semantic_second_pass.json)。例如 revenue 不等同毛利，已纠正。

许可来源为 [Princeton WordNet 3.0](https://wordnet.princeton.edu/license-and-commercial-use) 与 [Chinese Open WordNet](https://github.com/omwn/omw-data/blob/main/wns/cow/LICENSE)，保留作者、版权及免责声明于 [licenses](licenses/)。COW 采用其附带的 WordNet 式许可，不误标为通用 CC BY 许可。原始许可数据和哈希缓存在本机 private/p5a/sources。词网命中只是词义线索，不等于官方教学解释；词网缺失也不自动判为拼写错误。

**质量限度：会话逐词检查不是教师终审，也不是每条均有两家词典独立核验。** 不能仅凭自动测试 PASS 宣称所有中文义项绝无遗漏。所有新增义项均保留方法和依据层级，未声称人工教师或 PETS 官方认证。

## 5. 仍需人工处理

177 个条目仍需对照原书正文词头，不能只依页码归类当作来源已确认。仅对原来待核实且不在已有 500 验收范围的 406 条做现有 PDF 文本层补查，229 条获得同页行首完整词形支持，177 条未获得；原 PDF 存在 xref 解析警告，新匹配明确标为文本辅助支持，未冒充图像终审。未重新 OCR，未重复检查已有充分证据的条目。其待核实分类为按既有索引页码暂定位，源分类证据不足状态保留。

另有以下 17 条无上述来源阻塞，但需语义、语域或大小写审定。bible 同时有来源及大小写疑点，已包含在前述 177 条内，不重复计数。

|词头|待处理问题|
|---|---|
{other_table}

全部 194 条的 ID、原始词头、索引/正文页码、拟用释义、当前依据和阻塞原因在 [人工复核清单](manual_review.csv)；其中的拟用值不进入新增 Notion 载荷。人工核实后应新增有日期/依据的修正记录，再离线重建与重新审阅差异，不直接修改原始台账。

## 6. PETS-3 状态

复用合法取得的 [2015 年 PETS-3 官方附录](https://pets.neea.edu.cn/res/Home/2507/7186495d90963d37a36afccbfb505cc9.pdf) 和原有提取缓存。仅匹配附录明确列出的大小写敏感词形及印刷形式展开；不任意词干化或全局转小写。3,962 个明确匹配、1,590 个未直接列出。未直接列出不表示衍生词不在学习范围或考试不会考。

审计列 `pets2015_reference_status` 为“已收录/未收录”，其中“未收录”严格指未匹配到明确印刷词形；既有 Notion 兼容列 `pets2015_status` 仍采用“已收录/未直接列出”，不改 schema、不覆盖已有 500 内容。2025 全部“待核实”，未用 2015 版推定 2025 归属。原书考研分类不作为 PETS 词频。

## 7. 发音和自然拼读的真实状态

现有 big、tree、side、notice、carry、autumn 六个真人录音及许可原样保留，详见 [音频署名](../../assets/pronunciation/ATTRIBUTION.md)。合并 5,332 词中，6 词有现有独立真人资源，5,326 词无独立真人录音；后者允许复用已有 Windows 本地 SAPI TTS，须本机安装可用英语语音。TTS 单列为系统合成备用，不是独立标准真人录音，也不表示本轮实际试听了 5,326 词。

4,832 个新增条目的逐词拼读、音节、重音和例句留空，状态明确“未建设”；用户本阶段未要求全量拼读教学说明。没有猜造规则、显示音标、使用中文谐音或下载商业词典音频。现有 500 的已验收教学内容保持不变。缺少真人录音不阻塞词义入选。

## 8. Notion 只读预检与幂等性

本轮已读取正式 [Notion 词库](https://www.notion.so/0351820ea5c1428ba25a454b7de32773) 的 57 个属性和全部 500 条记录。直连快照时间 UTC {S['live_snapshot_fetched_utc']}。使用已有 Windows 安全凭据，Token 未写入源码、明文配置、报告或包。

连接器的查询投影与官方 API 逐字段比较存在 858 处差异，原因未确证；没有据此覆盖云端。随后使用官方 API 直接只读结果作基线，其映射的 29 个内容字段与已验收 500 包全部一致。私有原始快照及差异仅留本机，不随交付包分发。正式读取共 1 次 schema GET + 5 次分页 query POST；query POST 是只读查询，**内容写入 0、事件上传 0**。

预览为新增 4,832、更新 0、原有 500 保持不变，另跳过 194 待核实及 27 暂缓。以稳定 ID 比较，只提供必要内容差异；没有删除计划。字段映射不含学习状态、发音自评、自然拼读自评、笔记、评级、复习日期或事件。

离线副本按 ID 合并：首轮新增 4,832，第二轮新增 0、更新 0、4,832 保持不变；原来 500 的全部属性保持不变。另以纯模拟行验证“内容更新一次、重复更新不变、个人字段保留”。这证明本地计划合并幂等，**未声称已经做过正式远端写入验收**。

[notion_content_payloads.json](notion_content_payloads.json) 是属性到纯值的预览，不是可直接提交的 Notion API 请求体；未来执行器仍须按 title/rich_text/select 转成 API 类型，重新读取远端并按 ID 查找/更新。普通 Notion 界面 CSV 导入不能替代稳定 ID 幂等更新。脚本没有实现或调用正式写入。

## 9. 验证与不可变数据

`validate_delivery.py --check-rebuild` 独立检查：5,552 守恒及互斥状态、原始字段逐值保留、大小写/重音符号独立、现有 500 的全部 29 内容字段、texture 单列、必留词规则、正式必填字段、无虚构新拼读、学习展示字段无音标、载荷无个人字段、select 值符合实际 schema、文本长度、ID 无冲突、SQLite 全表内容及完整性、原始 PDF/500 包/Windows Release 哈希，以及原 Flutter Starter 的 417 个文件哈希。还连续两次重建并比较编译器输出逐字节一致。

SQLite 用 `mode=ro` 读取并与本轮前快照逐表比较：learning_progress 500、notion_sync_state 1、notion_word_links 500、pronunciation_events 0、pronunciation_progress 0、review_events 0、vocabulary 500 均不变。没有向真实个人库写入测试评级或恢复数据。

数据校验通过的范围见 [validation.json](validation.json) 和 [独立验证](independent_validation.json)。本轮没有软件代码改动、重新构建或新增背词功能，因此不重复运行已有 Windows/Flutter 功能验收；这些数据校验不代替未来完整词库客户端验收。Android、同步框架、UI、服务端及 Starter 均未开发或改动。

## 10. 可重复运行及检查点

现有工程、本机私有原始输入和缓存保留时，PowerShell 下运行：

```powershell
Set-Location E:\\desktop\\EnglishLearning-main
python -X utf8 scripts/p5a/build_delivery.py
python -X utf8 scripts/p5a/write_reports.py
python -X utf8 scripts/p5a/validate_delivery.py --check-rebuild
```

这三步离线重用现有审批记录，不连接 Notion、不读凭据、不写 SQLite。首次恢复缺失的许可参考缓存可单独运行 `fetch_lexical_sources.py`，脚本固定许可数据哈希，来源变化会停止而不会静默替换既有结论。`build_workbench.py` 从原始候选、已验收 500、2015 缓存和许可参考重建工作台；`source_followup.py` 优先使用已保存的 406 条补查缓存。

主观判断在 value_batches 5 批、初始语义检查在 content_batches 7 批、独立补义在 extended_content_batches 15 批中保存；另有 editorial.txt、extended_editorial.txt、两轮修正及前后差异。批处理脚本只整理本轮实际逐词判断的记录，不会自动调用未知模型，也不应对未检查的新数据直接执行 approve。可重复运行指确定性重建已记录决策，不表示重新生成的模型结论必然相同。

交付数据包包含本轮 CSV、报告、审计检查点、许可和 scripts/p5a；不含 Token、个人 SQLite、Notion 原始私有快照、商业教材 PDF、源录音或语音引擎。脚本重建依赖现有项目私有原始输入，不宣称 ZIP 在任意空目录即可独立重建。文件较大，均留本机，不自动上传仓库或云端。

## 11. 正式导入条件与阶段终点

**已具备 4,832 个新词的内容预览及本地幂等预检；尚不具备完整 5,552 候选一次性正式上线条件。** 194 条须核实，27 条明确后置。新增释义是可追溯的会话自检成果，仍允许后续教学使用中发现遗漏并留痕修正。

当前应用 CSV 入口仍限 500 词 / 1 MB，Notion 同步范围也是已有 500 词集合。不能把合并 5,332 词 CSV 直接替换现有应用资源或声称完整大词库已通过 Windows 学习验收；未来接入需另行授权调整容量和同步范围，本轮不开发。

未来正式写入还需新鲜只读基线、类型正确的执行器、稳定 ID 冲突复检、保留个人字段及用户明确的批量写入授权。本轮未请求或推定该授权。P5-A 到此停止：不写正式 Notion，不改真实学习记录，不上传事件，不自动开始下一阶段。
'''
(OUT / 'P5A_REPORT.md').write_text(report, encoding='utf-8')

guide = '''# P5-A 人工复核索引

以下条目不进入本轮正式新增载荷。不要在原始候选台账上直接改值。

先核对原书来源：按下表 PDF 页检查真实正文词头、大小写、索引与目录分区。已有文本层未找到不等于词条错误；不能据此猜测替换词头。确认后记录证据页及核验方法，保留原始值。

语义问题需核对可靠词典或语法来源，独立写出常用义，保留词性与多义区分。贬义、旧式或身份用法应审定语域标签，不能把侮辱义当中性释义。审核后追加修正与前后差异，再重建并审阅新增清单。2025 PETS 归属仍待核实。

|词头|稳定 ID|原书分类|正文 PDF 页|索引 PDF 页|当前阻塞|
|---|---|---|---|---|---|
'''
guide += '\n'.join('|'+ '|'.join(cell(r[k]) for k in ['word', 'entry_id', 'book_category', 'source_pdf_pages', 'source_index_pages', 'blocking_issues'])+'|' for r in manual)
(OUT / 'manual_review_guide.md').write_text(guide+'\n', encoding='utf-8')
print(json.dumps({'report_written': True, 'manual_index_rows': len(manual), 'source_pending': len(source_pending), 'other_pending': len(other_pending)}, ensure_ascii=False))
