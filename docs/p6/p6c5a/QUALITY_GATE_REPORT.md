# P6-C.5a 质量门槛结论

**B：仍有未解决问题，需要继续修正规则与逐词覆盖；不恢复批处理。** 本轮范围修复与700词验证已完成，不新增第701词，不发布，不处理剩余4632词。新范围保护有检出价值，尚不足以作为自动放行门槛。

## 固定门槛结果

验证前门槛哈希`16ba4cbbffcff3a49b8b36bd616cfe32d75c890b68ffb166a5533e65a5bb4ebd`；规则哈希`dfd139af49e5af3b321a587de6115364125e99fea4bb8b1f68c9d07314585950`。执行期间没有静默变更。固定原文/原700/留出集合及提示词哈希见RUN_MANIFEST.json。

| 检查 | 实际结果 |
|---|---|
| 700 ID/1702原义映射与600词内容保护 | 通过 |
| 四个旧修复点重现、证据对照与独立候选 | 通过；contact旧标签按新证据细化 |
| ritual/extend修复后无新增扩大/词性错误 | 已知修复点通过；extend变宽仍待核 |
| 无新增已确认Critical | 本轮未确认Critical；不等于证明不存在 |
| 无重复未解决确认Major | 未通过：determine、sensitive仍有具体范围缺口 |
| 至少20词源先留出与同因系统性检查 | 数量通过22；24全做候选比较，determine发现Major，2个盲审失败仍隔离 |
| 历史48与pursue未决保持 | 通过 |
| 原文/旧700/检查点/个人库/正式代码保护 | 通过：638个受保护文件 |
| 测试与幂等重放 | 见TEST_EXECUTION.json、REPRODUCIBILITY.json；技术通过不放行语义 |

不满足A：determine与sensitive仍有经实际源文、候选与词典对照确认的范围Major，不能因四个旧问题已修复就放行；引证覆盖/交叉映射6项Minor也待核。判C的固定系统性证据门槛未被证明：22份可用源先留出中没有至少2词确认同因Major，全700只确认2项剩余同因Major；其他Major提案有来源/POS/held或证据链误报，不能为达到数量而全算实错。两个剩余问题表明范围收窄仍会出现，B不等于否认风险或证明策略普遍可靠。

## 已完成与未决

- ritual恢复宗教/非宗教仪式范围；extend恢复肢体/可伸展物体范围，变宽仍held。两者在修前重现、修后实际审查，无覆盖旧700。scholar去掉无频率依据措辞；contact中性注释与WN相符，完整出版社条目支持整词的使动义，历史Minor只细化解释。
- 600旧词语义内容不变；新100完整249条源义检查；合计700个唯一ID、1702条原义映射。每条保留原POS/原文位置/目标层/上下文/关系/证据/残余疑点。字面守恒不冒充语义正确。
- 24固定留出、22源先提案、24候选对照；constitute/determine源先结构/ID失败未重映射，后续返回也未补称盲审完成。determine为留出确认Major；abstract为引证覆盖Minor，其他边界问题继续隔离。
- pursue旧二审失败和待对账保留；新词典证据与新Pro响应存在不合枚举/范围判断张力，未设通过。历史48和clause/management等旧隔离仍在。
- 本轮没有全量重新生成700词；只有四个已有修订在独立V5快照中验证。其余风险保留原候选并增加审阅/映射，不伪造V5重新生成成功。

历史48（全部继续原风险、待人工）：parallel, brief, quarter, present, consumption, extension, reverse, obvious, volume, double, engage, division, tone, abstract, fake, minor, rear, resolution, chop, cripple, slack, notify, void, tender, aisle, knock, miss, hold, yard, bank, bill, back, date, course, subject, term, close, get, keep, mean, raise, run, case, light, model, shot, major, well。

## 实际模型、失败与费用

首审请求/返回deepseek-flash；Pro源先盲提案与二审请求/返回deepseek-v4-pro，均为无旧会话历史的独立API上下文。不同模型标识确有返回，提供方实际权重/统计独立性无法证明；父级证据裁定仍为AI，没有人工签审。官方文档版本记录为DeepSeek-V4.1-Flash-1017 / DeepSeek-V4-Pro-0813，不伪装逐请求权重快照。

实际保存API响应253，含未采用与一次结构修复：`{"prompt_tokens": 1472759, "completion_tokens": 2446773, "total_tokens": 3919532, "prompt_cache_hit_tokens": 509056, "prompt_cache_miss_tokens": 963703}`。每请求usage、实际返回模型、请求/响应哈希保留，推理全文/密钥不保存。实际账单费用不可取得，null；按[提供方峰谷/缓存价格](https://api-docs.deepseek.com/quick_start/pricing/)估算USD 2.694708～5.389416，不是扣费账单。父级Codex用量/成本不可获取，null。

原始整块严格验收未完成行、一次结构修复、真实行对账、两条源先失败及所有引用/枚举异常均保留在api、reviews、failures和COLLECTED_*，没有无限重试、替换模型或模板填词。首审规范通过699/700，二审规范通过119/124，其余有真实语义响应但不作规范通过。

## 交付与下一步条件

六份要求文件齐备：SCOPE_FAILURE_ANALYSIS.md、RULES_V5_SCOPE_GUARD.md、SCOPE_GUARD_TEST_REPORT.md、revised_candidates.json、regression_700.json、QUALITY_GATE_REPORT.md。另有冻结门槛、真实API/盲审/对账/证据/指标/测试/保护清单，脚本均在scripts/p6c5a。

后续只建议在现有700内处理determine/sensitive的剩余范围、补核引证/源POS/held边界，校准误报与scholar类理由漏报，再用同一固定门槛复验。不能通过关检查或把所有中文联想都补核心解决；也不能靠多一轮模型认可清历史风险。本轮结束，不执行这些后续任务，不恢复4632、不写Notion/SQLite或学习记录、不改正式UI/日语/数据库路径。
