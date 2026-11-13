# P6-C.5a 范围失败分析

实际基线为600词复用+100词新生成=700，不是已完成5332；剩余4632不处理。旧C5结论、原700、失败记录与检查点未覆盖。四项旧问题为2 Major+2 Minor；本轮只有这四词的语义/注释修订进入独立工作快照，复用600词内容全部不变。

## 生成器与检查器根因

| 项目 | 原文与旧目标 | 定位 | 隔离修复及状态 |
|---|---|---|---|
| ritual | s001名词仪式 → 宗教仪式的规定程序；s002惯常程序、s003形容词仪式的另存 | C核心子义选择+D限制性表述；不是原文解析丢片段。生成器已报Minor scope_gap，却用已限定展示视作可接受；E在风险处置/升级上不足，并非完全没检出。C5外部二审/父级裁定实际发现Major并停止 | 仪式；礼仪程序（宗教或非宗教）。[Collins](https://www.collinsdictionary.com/dictionary/english/ritual)及WN宽义支持。惯常行为/形容词仍独立，已知Major修复点通过新审查，未签审 |
| extend | s001伸展 → 只解释身体；原证据已有桌腿/布料/天线。s003空间/时间延伸不能替代s001主动展开 | C子义选择+D对象收窄+E把source ID出现误当用途覆盖。A解析与原文字符完整 | 伸展；展开（肢体或物体），注明可伸展物体与非排他例子；WN v01371528/v02058913及[Collins](https://www.collinsdictionary.com/dictionary/english/extend)支持。s002变宽保留held，未声称全词已核完 |
| scholar | 学习者；学者；文人未丢，选择理由却称最常用 | D无依据频率措辞+E理由字段检查遗漏；不是语义合并错误 | 仅改为AI教学选择，两模型仍漏报旧措辞，通用频率告警补检；不伪造客观频率 |
| contact | 源联系；接触、逐片段POSnull；旧动词注释使某物与另一物接触，绑定WN只描述直接接触 | D注释与具体引用方向不齐；E未逐引用核对。不能据WN局部条目断言整词不存在使动义 | 中性直接接触注释与WN一致。[完整Collins](https://www.collinsdictionary.com/dictionary/english/contact)American verb7/9确有使之接触；旧Minor保留但细化为引证精度，不把它伪造成语义负例 |

四项均没有发现原始片段解析损坏；不通过修改原文掩盖生成器限制。B分组不是两项范围Major的直接主因，F为C/D/E叠加。修订复用C5已有独立建议，建立V5快照并实际复核，没有为新措辞另做无必要生成。前后完整字段差异在revised_candidates.json中。

## 通用保护与自身缺陷

V4偏重源ID守恒、词性和引证存在，缺少同一源片段内部剩余范围、所有层级并集与反例检查。V5固定为先来源范围、再英语证据、最后候选；语义等价/合理概括/收窄/扩大/不匹配/不确定六类显式映射。减少同义展示不等于减少来源用途；不以字符串包含证明覆盖。

本轮发现自己的输入封包遗漏四词修订新增的两个已有出版社引用。原误报保留在calibration_after.json；EVIDENCE_RECONCILIATION.json明确复制真实已有观察后，另建reconciled_inputs并重审，不改冻结规则或旧结果。模型捏造引用ID、大小写级别、同值字段别名及缺失证明字段分开记录，未当语义成功。

## pursue 的真实状态

旧C5首响应与一次结构修复都回显输入，没有合格二审结果，状态仍review_incomplete_after_bounded_attempts。新查[Collins](https://www.collinsdictionary.com/dictionary/english/pursue)分别支持追求目标、追赶与从事活动；本轮Pro也实际返回审阅，但其moderate级别不合枚举，关于寻找/追求的判断与等价映射存在张力。新证据和新结果分开保存，未解除待对账、未将再次请求成功等同语义正确。

## 回归的新发现与边界

29个至少一次被模型提Major的词逐个证据裁定：新增确认范围Major 2（determine、sensitive），引证/映射Minor 6；其余21继续待核或否定该项错误断言。这里确认指父级AI对实际证据的裁定，不是人工签审。未逐项裁定的其他Minor/Info继续保留为提案。细节见PARENT_EVIDENCE_ADJUDICATION.json。

determine原决定被注释限为主动作选择，未覆盖因素决定结果，[出版社定义](https://www.collinsdictionary.com/dictionary/english/determine)与WN v00702806直接支持遗漏用途。sensitive原敏感的仅物理/机密两域；体察他人不是自己容易被冒犯，[出版社定义](https://www.collinsdictionary.com/dictionary/english/sensitive)证实独立非物理用途缺口。两个候选未在本轮擅自改写，已隔离，故不放行下一批。

相反，abstract/tender等显示文本并无只限某例的措辞，少挂一个synset是证据覆盖不足，不能自动升级为删除含义Major。held不是完整覆盖，但正确保留待核也不是新的静默删义。原POSnull未改、推荐组POS另记，检查器不能据此谎称源字段被覆盖。详见测试报告的误报分解。
