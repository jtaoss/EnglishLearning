# P5-C.3 最终只读预检

版本保持 0.7.0+10。时间 2026-11-10T11:53:43+08:00。数据预检：**通过**。内容写入 0，事件上传 0。

## 正式 SQLite

- 文件存在：是。schema 3，integrity `ok`，外键问题 0。
- 词条 500，唯一 ID 500。
- 非未测试评级 0，发音状态改动 0，复习日期 0。
- 词义事件 0，发音事件 0。
- SHA-256 与恢复快照一致。

## Notion 与导入预览

- 云端实际页数 500，唯一稳定 ID 500，读取请求 6。
- 预计保持不变 500，更新 0，新增 4832。
- 正式清单 SHA-256 `9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb`，与 P5-C 记录一致。
- 待核实 194，暂缓 27，与正式清单无交集：是。

## 差异

没有 ID 或 29 个内容字段差异。

## 备份

- `E:\desktop\EnglishLearning-main\docs\p5a\public\formal_learning_vocabulary.csv`：可读，SHA-256 `9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb`。
- `E:\desktop\EnglishLearning-main\private\p5c\backups\20261110-095221\formal_learning_vocabulary.csv`：可读，SHA-256 `9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb`。
- `E:\desktop\EnglishLearning-main\private\p5c\backups\20261110-095221\notion_import_preview.csv`：可读，SHA-256 `7693ac8152a832b40d5426255cf776730b059efcf63e1dd135b76dfed2ad2cda`。
- `E:\desktop\EnglishLearning-main\private\p41\personal-pretrial-20261109-141933.sqlite3`：可读，SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31`。
- `E:\desktop\EnglishLearning-main\private\p5c\backups\20261110-095221\personal-pretrial-20261109-141933.sqlite3`：可读，SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31`。
- `C:\Users\Administrator\AppData\Roaming\Personal\English Learning\english_learning_v1.sqlite3`：可读，SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31`。

## 导入程序

仓库没有词库页面创建客户端。现有 Notion 适配器只允许读取数据源和查询。只读同步按 100 个 ID 分组、每页 100 条、最多 10 页，查询间隔 350 毫秒，响应上限 2 MB。429／529 按 Retry-After 处理，超过 10 秒或重试耗尽则整批停止并保留本地数据。重复页面、重复稳定 ID 或返回不完整时拒绝整批，校验后才一次提交。

4,832 个新增词的断点批次、创建结果不明时的查询对账，还没有可执行程序。事件沙盒的页面创建接口不用于正式词库。

## P5-C.4

数据预检已通过，仍不执行正式写入。P5-C.4 需要用户单独授权，并使用带断点、幂等、限流和异常对账的写入程序。
