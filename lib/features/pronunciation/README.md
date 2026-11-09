# P1-B 自主认读与听音

P3：词卡与认读列表可覆盖当前全部本地词条，不再只显示六词。已授权录音继续走原 catalog/cache/player/session；无录音词使用 `WordReadingPractice`，先自主认读，再显示逐词提示并独立保存自评。此类事件明确使用 `self-reading:<entry_id>` 来源，不声称听过录音。发音复习间隔为再练习 10 分钟、基本会读 1 天、能独立认读 7 天；从原有状态/时间计算，无需更改正式数据库版本。以下为原六词音频实现说明。

固定六词清单按既有 entry_id 关联；不自动导入、修改词义或判断 PETS 官方归属。

- content：逐词整理的提示、重音、来源及授权；无拼写到读音自动推断器。
- cache：仅复制获准缓存的随包 WAV，完整 SHA-256 校验，不发起网络请求。解析目录重定向；跨盘 rename 失败时复制后再校验，未完成文件不能播放。
- player：audioplayers Windows/Android 原生适配；完成事件才结束 Future，停止与晚到回调隔离。
- session：自主认读 → 听音 → 完整播放 → 自评；防重播并发、防重复保存、失败重试、退出停止。
- store：独立 pronunciation_progress / pronunciation_events；v1 旧发音字段只读保留，新状态不写入词义表。
- pages：六词入口、未配置资源提示与自评页面；离开或进入后台停止音频。

所有记录是个人自评，初始未测试；不等同自动评分或官方发音认证。版权清单在 assets/pronunciation/ATTRIBUTION.md；测试和验收在 docs/p1b。
