# P5-C.4C.5 highlight 单词补录

版本 0.7.0+10。执行时间 2026-11-11 15:40:00–15:41:14（UTC+8）。

Git 已推送版本是 `3dc6196`。本轮报告和此前的导入改动仍在本地工作区，没有提交。

本轮只创建了 highlight。没有再次创建 pollution，也没有创建 architect、concise、seemingly、educate、finally。没有更新、删除或归档，没有上传学习事件，没有打开个人 SQLite。

## 1. 目标与原始记录

正式数据源 `157d89e5-71fb-4e68-9640-1b04dbb1e627`。写入凭据目标是 `EnglishLearning.Notion.VocabularyWrite.v1`，数据源与正式库一致。

稳定 ID `SG25-dc2c5be187f6`，词头 highlight。29 个内容字段的 SHA-256 是 `0992268d38b2c8d91784a6b4b0c621bf1293834477d04702483fc44b6de98ed7`。正式清单 SHA-256 为 `9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb`，与检查点一致。来源文件和来源 ID 均非空，没有空的选择项。

原始待对账记录仍在审计日志中：2026-11-10 15:15:39 请求已发出，15:15:57 记为 `connection`，15:17:04 只读复核未找到页面。本轮授权记录是 `private/p5c/p5c4c5-highlight-operation.json`，关联这三条原始事件。创建前的检查点备份是 `private/p5c/p5c4c-checkpoint.pre-4c5-highlight.json`，SHA-256 `34053c7dbf38343eb99b4d452460dcd66e220ca0768dd1566b1a643ad8b921b3`。

## 2. 写入前云端

没有其他写入进程。完整分页、按稳定 ID 和按词头查询的结果与预期基线一致：

| 项目 | 写入前 |
|---|---:|
| 页面总数 | 5,327 |
| 有效唯一稳定 ID | 5,326 |
| highlight 页面 | 0 |
| 词头 highlight | 0 |
| pollution 页面 | 1，仍是 `415cd5b5-d6b9-81c6-a62a-fc85e8a14e36`，字段一致 |
| 已知空白页 | 1，签名仍是 isolated |
| 重复稳定 ID | 0 |
| 原有保护页 | 510 |

另外 5 个待对账词的检查点仍是 `pending_reconciliation`，云端都是 0 页。保护核对通过。全部前置条件满足后，才写入唯一请求机会已被占用。

## 3. 唯一一次创建

实际 Create 请求次数是 1。15:40:00 占用请求机会，15:40:01 收到成功响应，没有状态码异常。返回页面 ID `415cd5b5-d6b9-81b4-b10d-c07c9eabff4e`。没有第二次创建，也没有隐式重试。

## 4. 写入后独立核验

完整分页和按稳定 ID、按词头的查询都指向上述同一页。29 个内容字段与正式清单一致，差异字段为空。

| 项目 | 结果 |
|---|---|
| 有效唯一稳定 ID | 5,327 |
| 页面总数 | 5,328 |
| highlight 页面数 | 1 |
| 重复稳定 ID | 0 |
| 原有 5,326 个有效词条 | 仍在，保护核对通过 |
| pollution | 仍是原来那一页，字段未变 |
| 空白页 | 仍是 `414cd5b5-d6b9-80db-ac03-d94e99d65e61`，签名未变 |
| 新的无 ID 页面 | 0 |
| architect、concise、seemingly、educate、finally | 云端 0 页，检查点仍待对账 |
| 个人 SQLite | 前后都是 1,327,104 字节，SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31` |
| 学习事件、更新、删除、归档 | 0 |

两个只在创建时写入的审计计数由 4,926 变为 4,927。历史审计计数没有变化。

检查点里 highlight 现为 `verified`，页面 ID 与创建响应一致。原来的待对账日志没有删除。最终结论是成功。

剩余待对账词是 architect、concise、seemingly、educate、finally。不继续处理它们，也不启动 Windows 全量同步。
