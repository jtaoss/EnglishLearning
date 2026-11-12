# EnglishLearning · P6-C AI 核心释义提炼试点报告

日期：2026-11-12（Asia/Shanghai）。基线：main `c105a0f`；应用版本保持 `0.7.0+10`。

**交付状态：100词的AI提炼、结构/来源验证和隔离UI已完成；真人内容复核尚未完成。全部输出仍为隔离草稿，未发布为正式词库内容。本轮到试点为止。**

## 1. 以实际代码与CSV核对的数据现状

正式输入：[formal_learning_vocabulary.csv](../p5a/public/formal_learning_vocabulary.csv)，5,332行、5,332个唯一稳定ID、29列。文件为5,376,339字节，SHA-256 `508007c44f272f71df0ed918f17c006b263a1320fef1ada48e411a6aed3ba619`。主学习4,259，扩展1,073；本清单没有暂缓词。`meaning_zh` 和 `part_of_speech` 均无空值。

| 数据维度 | 实际字段/形式 |
|---|---|
| 标识 | `entry_id`，客户端 `VocabularyEntry.id`；本轮附加输出名为 `stable_id`，值原样沿用 |
| 词头、中文 | `word`、`meaning_zh`，均为字符串；原文有中文分号、逗号和显式词性标签混排 |
| 词性 | `part_of_speech`，如 `名词；动词；形容词`；其排列不保证与中文解释排列一一对应 |
| 原书词频分类 | `book_category`：高频951、基础1,780、中频586、低频576、偶考1,439；这是词头分类，不是词义频率 |
| 其他字段 | 原书文件/页码/核验、两个PETS年份归属、学习优先级、例句、读音、许可等；29字段全量快照存入每条附加记录 |

`VocabularyEntry` 把内容保存在不可变 `Map<String,String>`，`meaning` 直接读取 `meaning_zh`。CSV解析器区分词头大小写，限制5,332词/8MB；必需13列，另有16列可选内容，本正式文件包含全部29列。2025官方归属仍为“待核实”。`meaning_review_status` 本就区分AI来源对照与个人确认，不能据此声称原文已由真人终审。

当前正式释义展示位于 [review_page.dart](../../lib/features/review/review_page.dart) 与 [review_session_page.dart](../../lib/features/review/review_session_page.dart)，揭晓后显示 `entry.meaning` 和例句。本轮没有替换这两处。

本地由 [SqliteLearningRepository](../../lib/core/storage/sqlite_learning_repository.dart) 通过后台isolate串行执行操作。正式schema仍为v3，词库内容、词义进度/事件、发音进度/事件分别存储；副本事件迁移受隔离许可限制。词义评级仍为掌握+7天、眼熟+1天、遗忘+10分钟。

[NotionSyncService](../../lib/integrations/notion/notion_sync_service.dart) 每100个已批准ID分组查询并处理分页。全部验证完成后一次事务写入本地内容和同步水位，首次/扩容走全量核对；不会把个人进度映射成词库字段。本轮只阅读这些代码，没有请求Notion。

README和早期交接文件中的500词状态不作为本轮数据依据。这里的5,332是正式CSV及已提交的同步范围，**没有通过打开当前个人SQLite来重新证明本机已下载词数**。

## 2. 使用的模型、提示词与系统边界

- 生成/语义校订者：Codex当前AI会话。执行环境没有提供可核实的后端模型ID和精确快照，因此 `generation.backend_model_id`、`backend_snapshot` 明确为null，未冒充某个API型号。
- 管线版本：`codex-session/p6c-semantic-v2`；提示词版本：`p6c-prompt-2`，全文在 [PROMPT_V2.md](p6c/PROMPT_V2.md)，SHA-256随输出保存。
- [semantic_decisions.py](../../scripts/p6c/semantic_decisions.py) 保存100个明确的逐词AI决定，包括分层、理由、说明及风险。没有“取前两条就是核心”的回退规则。
- [build_core_pilot.py](../../scripts/p6c/build_core_pilot.py) 只装配并重放这些决定；重新运行不代表再次调用模型。本轮未发起外部模型API请求，不能由此推断Codex会话费用为零。
- 这是离线试点管线，尚不是可以自动推理任意新词的生产服务。后续API适配、真人终审和发布门禁只在方案中描述，没有自动实施。

提炼先区分词性和语义，再判断近义表达能否合组。核心通常1–2组，但 `present`、`major`、`light`、`get`、`hold` 各有3组，以免机械截断重要义项。其余义项没有删除。考研分类、WordNet顺序和义项数量都不被用来证明某义项更常用或属于PETS官方重点。

## 3. 证据和可追溯结构

每词均有要求的13个字段：`stable_id`、`headword`、`part_of_speech`、`core_meanings`、`extended_meanings`、`other_meanings`、`core_explanation`、`usage_example`、`selection_reason`、`confidence`、`review_required`、`model_version`、`source_hash`。另保留原始中文、29字段输入快照、解释片段、风险、提示词版本、决定哈希和证据引用。

`source_hash` 对29个CSV字段的完整快照计算：键排序、UTF-8、JSON紧凑序列化、保留Unicode，再SHA-256。`decision_hash` 对该词附加结果计算，不包含自身。人工台账同时绑定两个哈希；源数据或分层/说明变化时旧签审不能继续使用。

原文的263个解释片段均保留 `source_sense_id`、原文词性依据和Python Unicode字符区间 `[start,end)`。这些片段只是可校验的文字单位，不意味着每个逗号或分号就是不同语义。归组由明确的逐词AI决定完成。每个片段在三个层级中恰好归属一次；同样的“冲洗”可分别来自名词和动词，按片段ID追踪，不靠中文字符串去重。

所有义组的 `origin=formal_gloss`。本轮 `model_added_senses=[]`，没有补写新义项；例句仅原样保留正式字段，标记 `formal_example_unmodified`。解释说明是AI教学改述，不能当作新词典义项。

另外实际取得 [Princeton WordNet 3.1 词典归档](https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz)，只把选定100词的英文词义保存到 [wordnet_evidence.json](p6c/wordnet_evidence.json)。遵守已有 [WordNet许可](../../assets/vocabulary/WORDNET_3_1_LICENSE.txt)，没有抓取商业词典或重新OCR。100词均能找到英文参考。归档哈希与英文synset ID已保存。

**证据局限**：义组上的WordNet引用是词头/词性参考集合，不是逐个中文解释的人工双语对应证明；不提供实测语料词频，也不证明PETS考查重点。原书信息只读取正式CSV已有字段，没有打开原始PDF复核。`knock`、翻译边界及全部教学排序仍需人工判断。

`confidence` 采用保守的AI编辑自评档位0.55/0.68/0.80，反映词性/翻译不确定性和复杂度。不是API logprob、校准概率、准确率或签审依据。

## 4. 100词样本选择与结果

沿用已有100个ID，修改抽样说明而未更换样本。五组互斥，交集0、各20词、共100个唯一ID。完整逐词结果在 [core_meanings_pilot.json](p6c/core_meanings_pilot.json)，便于阅读的全量对照在 [REVIEW_WORKSHEET.md](p6c/REVIEW_WORKSHEET.md)。

| 组别 | 数量 | 选择依据及限制 |
|---|---:|---|
| 简单词 | 20 | 基础词、单词性、单一未标号解释；候选388，按ID等距取样。是可复现代理，不宣称测得零基础难度 |
| 常见多义词 | 20 | AI逐词识别的既有多义样本，如bank、run、get、case；不是由分号数自动判定，常用性无独立语料验证 |
| 复杂词性 | 20 | 词性至少2种，候选1,394；优先词性数量多、显式标签多的词 |
| 考研高频词 | 20 | 正式高频分类且单词性，候选702；扣除前组后按原书页码排列等距选择 |
| 随机正式词 | 20 | 扣除前80词，按SHA256(`p6c-pilot-1:`+ID)排序取样；确定性伪随机，无人工挑换 |

组选择顺序为复杂词性、多义、高频、简单、随机，详见 [selection.json](p6c/selection.json)。没有组别不足或重复补位。单词性且至少3个分号解释的候选有1,148条，但该指标不能证明真正多义，因此没有直接把该池前20条当作多义词。

### 多义词与错误合并处理示例

| 词 | 优先记忆 | 其他重要处理 |
|---|---|---|
| light | 名词光、名词灯、形容词轻的，3组 | 光与发光器物不是同义词；明亮的、点燃仍保留 |
| double | 形容词双倍的、动词使加倍 | 成双的与数量翻倍不同；两倍、加倍地、替身均保留 |
| present | 名词礼物、形容词当前的/在场的，分别成组 | 现在、呈交、展示另列；呈交和展示不强并 |
| bank | 银行、河岸，2组 | 不以“核心限两项”或无证据的频率假设压掉河岸 |
| mean | 动词意味着、打算，2组 | 吝啬的、平均的、平均数分别保留词性与语义 |
| get | 得到、变得、到达，3组 | 理解仍可见；不暗中增加原文未收录的其他用法 |
| aisle | 过道/狭长通道近义组 | 林中小径留其他层；WordNet `wn31:n:02697041`确有树林狭长通道义，不能判为凭空捏造 |

## 5. 七项质量检查、问题统计与人工状态

已对100词分别写出AI编辑检查意见，见 [semantic_audit.json](p6c/semantic_audit.json)。以下是**AI发现或待核对问题**，不是经真人裁定的错误率。

| 检查维度 | 本轮结果与实际限制 |
|---|---|
| 重要义遗漏 | 原文263/263片段保留；run/get/chair单列“原始词义清单不完整”局限。不能据文字覆盖证明涵盖完整英语词典的重要义 |
| 罕见义排首 | 没有语料频率金标准，不能报告罕见义准确率；shot、aisle、notify、correlate有明确排序修订记录，61词排序仍未由语料验证 |
| 词性混淆 | 输出不跨明确原文词性合组；knock的2个解释缺逐义标签，保持“待核实”，未猜配 |
| 凭空增义 | 结构验证没有新增原文以外的义项；这不等于确认原文所有中文翻译正确。obvious/engage/notify共3词有翻译边界疑问 |
| 不同语义误合并 | 对旧草稿11词的合并提出AI问题并在v2拆开；仍待真人裁定。18词保留近义归组，也需人工确认边界 |
| 来源追溯 | 100词源快照及哈希一致；263片段区间及单次归属通过；词典引用不冒充逐义翻译证明 |
| 初学/PETS-3适用性 | 100词有具体教学说明和理由；尚无人类学习效果测试，不标记“官方考试重点” |

11个AI疑似过度合并已拆开的词：**double、back、present、slack、model、light、tender、minor、extension、chop、consumption**。拆分前的实际义组保存在 [draft_v1_findings.json](p6c/draft_v1_findings.json)。同文件保留couple、correlate两个负对照：旧草稿本就分开，未误报为旧合并错误。

48词列入高风险人工清单，其余52词也待签审。风险包括复杂多义/词性、翻译边界、疑似过度合并和语用敏感等，标签可以重叠，不能相加当作独立错误数。

需要优先确认的疑义：

| 词 | 待确认问题与现有处理 |
|---|---|
| knock | 原文同时列名/动词但中文未逐义标注。WordNet有敲击声音名词 `wn31:n:07400970` 和敲门动词 `wn31:v:01417121`，仍不能据此替原书猜配 |
| notify | “通知”有 `wn31:v:00875364` 对应；“使注意”容易被理解为吸引注意，保留原文并待双语核对 |
| engage | “从事/从事于”接近；“实行”范围可能太宽，保留其他层。参考 `wn31:v:02380222` 不证明任意“实行”搭配成立 |
| obvious | “明显/明明白白”与“无疑”存在确定性边界，后者单列扩展义，待人工核对 |
| parallel | 原文“与……相似或并行”本身并列语义，保留并标记，待人工进一步拆分而不是冒充纯同义组 |
| cripple | 具体残疾与功能瘫痪分别保留；涉及人的用词和例句适用性待人工判断 |
| aisle、shot、present、light、get等 | 中文排序和核心组数量属于教学建议，未获得语料频率或PETS官方排序证据 |

**人工复核真实状态：0词通过，100词pending。** [human_review.json](p6c/human_review.json) 的reviewer、reviewed_at均为空；已经提出真人复核请求，但不把AI自查写成人工审核。独立真人审核是本试点尚未完成的内容验收项。任何未来签审必须覆盖当前source_hash与decision_hash，保留具体意见；不能仅凭confidence通过。

## 6. 隔离UI试点

独立入口 [lib/p6c_pilot_main.dart](../../lib/p6c_pilot_main.dart)，显式开启后从指定绝对路径读取这100词JSON。不调用正式main、path_provider、学习仓库、系统凭据或同步服务。普通应用路由和pubspec资源表没有接入草稿。

沿用现有AppTheme的蓝白主色、Segoe UI/雅黑字体回退、卡片和StatusBadge。英文词头与揭晓按钮为首屏；答案揭晓前不构建释义、简短说明、例句、原文或理由，也没有藏在offstage/语义树里的中文答案。揭晓后显示优先记忆、说明、常用扩展义；其他义可展开，原文与理由通过单独的来源核对操作展示。切换单词会重置揭晓和展开状态。

试点不提供持久化评级操作，因此掌握、眼熟、遗忘的既有规则及其数据完全沿用正式应用；数字键不会在试点里写学习记录。空格可揭晓。窄屏400px、1.5倍字号布局检查通过。

可重现启动命令（只启动隔离入口）：

```powershell
flutter run --no-pub -d windows -t lib/p6c_pilot_main.dart --dart-define=P6C_ENABLE_PILOT=true --dart-define=P6C_PILOT_FILE=D:/Desktop/EnglishLearning/docs/p6/p6c/core_meanings_pilot.json
```

运行目录为项目根。换电脑时替换JSON绝对路径。UI会拒绝缺少开启参数、非绝对路径、超过4MB、条数/组别/哈希不符或非隔离草稿文件。

截图由widget测试在隔离进程渲染，并由AI查看画面（**不是人类内容签审或桌面点击验收**）：[揭晓前](p6c/ui_hidden.png)、[揭晓后](p6c/ui_revealed.png)。截图仅是UI证据。

## 7. 数据保护与验证

正式CSV及既有100/500词样本、已知个人SQLite路径及其WAL/SHM/journal共7个受保护路径均做前后字节哈希和元数据比对，见 [data_protection.json](p6c/data_protection.json)。没有打开SQLite连接；已知路径检查不代表扫描了所有宿主重定向目录，也未从文件大小推断学习状态。Notion没有任何读写请求；没有事件上传、OCR、全库模型处理、Git提交或推送。

| 验证 | 结果 |
|---|---|
| 100唯一ID、五组各20、原文覆盖、词性/引用/哈希、审核绑定 | 通过；语义正确率未测量 |
| Python防回归/损坏注入 | 12项通过；覆盖丢义及同时删除追溯、重复、错词性、新增中文、源漂移和旧审核失效 |
| UI与数据载入专测（开启截图） | 7项通过，包括无障碍语义树隐藏、切词重置、展开、键盘和窄屏 |
| 全量Flutter回归 | 240项通过、1项按设计跳过；该项为需要显式开启的本机字体截图，已在上述专测单独通过 |
| 静态分析 | `dart analyze --fatal-infos`通过，无问题 |
| 格式 | 136个Dart文件检查通过，0差异；既有P6-B测试的一处断行按formatter规范化，没有更改断言或业务规则 |
| 配置 | dev/staging/prod三份非敏感配置均通过检查 |
| Windows隔离入口Debug构建 | 通过，44秒；构建参数显式指定独立pilot入口，未运行桌面程序 |
| 正式数据保护 | 7路径的已有文件哈希、大小、修改时间与缺失sidecar状态不变 |

Windows桌面真人点击和人类语义终审未执行，不用widget或结构测试冒充。完整回归输出保留在本机 `build/p6c/flutter_full_test.log`。

本机 `build/windows/x64/runner/Debug/english_learning.exe` 此次是**隔离试点调试程序**，编译时已绑定本次JSON路径，SHA-256 `29a15f3071be8dab2c9730cb353beddd50ff69b07b15c4acb8b147dcd093ccdc`。没有重新构建或替换Release发布包。默认源码入口仍为正式 `lib/main.dart`，该Debug文件不能当作正式学习客户端分发。结构校验、测试、构建及保护结果汇总在 [validation_results.json](p6c/validation_results.json)。

## 8. 处理全部5,332词的估算成本

本轮未执行全库处理。费率于2026-11-12实际获取自 [OpenAI API官方价格页](https://developers.openai.com/api/docs/pricing)，参考页面哈希与费率存于 [pricing_reference.json](p6c/pricing_reference.json)。按Standard、short context、无缓存或Batch折扣计算。下列API型号只是未来预算场景，**不是本会话模型身份或质量承诺**。

假设每词1,000输入token、700输出token，以约10词小批共用提示词，模型只输出紧凑语义决定，追溯/哈希由本地装配。全库约5.332M输入、3.7324M输出。未安装对应tokenizer，因此这些是显式预算假设，不是实测token。实际应先用一批真实API响应usage校准。

| API预算型号 | 每百万输入/输出美元 | 一遍提炼 | 一遍+20%复检场景 | 两遍全量 |
|---|---:|---:|---:|---:|
| gpt-6.1-sol | 2 / 10 | $47.99 | $57.59 | $95.98 |
| gpt-6-luna | 0.10 / 0.50 | $2.40 | $2.88 | $4.80 |

计算公式：`5332 × (1000 × 输入费率 + 700 × 输出费率) / 1,000,000`。20%复检仅是预算场景，不从本次刻意分层的48%高风险比例外推全库。若输入/输出量加倍，相关成本也近似加倍。额外推理token、失败重试、人工审核、订阅/会话用量、税费和换汇不在该表内；收费token应以所选API实际usage为准。便宜的型号不等于已证明有同等质量。

## 9. 后续批量方案（未执行）

1. 先由真人完成这100词，特别是48词高风险项，建立逐义金标准，统计七类问题的真实裁定，而不是把AI标签当准确率。
2. 输入冻结：对正式CSV做只读快照、保留ID与原文；以 `(stable_id, source_hash, model_version, prompt_hash)` 做缓存/去重键，源变化只让相关记录失效。
3. 约10词一批，仅提交必要的词头、词性、已有义项与已许可参考；模型返回独立附加JSON，禁止原地SQL/Notion工具访问。先再做有限批次，不自动提交全库。
4. 本地装配片段区间和哈希；严格schema、片段覆盖、词性、引用校验失败即隔离，断点按ID恢复；同一输入/提示词已完成结果不重复付费。
5. 复检关注遗漏、错误合并、翻译/词性和排序，允许指出不足，不为达到1–2组强行删义。可选择独立模型复检，但模型一致不能替代真人裁定。
6. 人工审核状态与生成分离，签名绑定输入和决定哈希。高风险全部审核；其他条目按事先确定方案抽检。未审核保持原始释义界面回退，不发布AI层。
7. 若后续获准正式接入，另行设计版本化sidecar或独立表、按ID联结和一键关闭；保留原始meaning_zh与学习事件，不能顺带改变评级、复习日程或Notion字段。备份/迁移及发布各自验收。

本轮没有实施后续批量生成或任何正式数据迁移。

## 10. 交付索引与重现

- [100词结构化结果](p6c/core_meanings_pilot.json)、[抽样及依据](p6c/selection.json)、[逐词工作表](p6c/REVIEW_WORKSHEET.md)。
- [AI审阅统计](p6c/semantic_audit.json)、[旧稿问题及负对照](p6c/draft_v1_findings.json)、[人工台账](p6c/human_review.json)。
- [提示词](p6c/PROMPT_V2.md)、[词典证据](p6c/wordnet_evidence.json)、[费用假设及计算](p6c/cost_estimate.json)。
- [本地保护清单](p6c/data_protection.json)、[隔离UI说明](p6c/README.md)。

```powershell
& 'C:/Users/admin/AppData/Local/Programs/Python/Python314/python.exe' -X utf8 scripts/p6c/build_core_pilot.py --check
& 'C:/Users/admin/AppData/Local/Programs/Python/Python314/python.exe' -X utf8 scripts/p6c/validate_pilot.py
& 'C:/Users/admin/AppData/Local/Programs/Python/Python314/python.exe' -X utf8 -m unittest discover -s scripts/p6c -p 'test_*.py' -v
flutter test --no-pub --dart-define=P6C_CAPTURE_PREVIEW=true test/p6/core_meanings_pilot_test.dart
```

正常校验不联网，也不要求私有词书或Notion凭据。`--init-review`仅在台账不存在时使用；不要删除人工台账重建来掩盖源/决定变化。`protect_data.py`针对这次本机前后保护快照，不能将另一台设备的元数据当成已验证通过。
