# P5-C 导入前检查

版本保持 0.7.0+10。检查时间 2026-11-10T09:54:00+08:00。结论：**停止，未开始正式写入**。

本轮复用 P5-B 已固定的正式清单 `docs/p5a/public/formal_learning_vocabulary.csv` 和离线预览 `docs/p5b/notion_import_preview.csv`。没有重新 OCR，没有重新筛词，没有创建或更新 Notion 页面，没有上传学习事件。

## 清单

- 正式学习词 5332 个稳定 ID，列表行数 5332。
- 预览保持不变 500，新增 4832，待核实 194，暂缓 27。
- 待核实词和暂缓词与正式清单无交集，处理状态仍是“仍待人工核实”。
- 正式清单 SHA-256 `9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb`。
- 现有 500 词包 SHA-256 `09cd736d61c40f9614239e451f5894ad464f2ff69a863d50bde95b03b87f651d`。

## 备份

- 正式清单副本 SHA-256 `9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb`，与原文件一致。
- 学习事件没有上传。
- 正式个人库 `%APPDATA%\Personal\English Learning\english_learning_v1.sqlite3` 不存在。桌面、文档和 Roaming 应用数据目录里也没有另一份同名正式库。
- 能核到的最新个人快照是 `private\p41\personal-pretrial-20261109-141933.sqlite3`。
- 快照 SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31`，与 2026-11-09 14:19:33 试用前记录一致。
- 快照 schema user_version 3。表行数：{"learning_progress": 500, "notion_sync_state": 1, "notion_word_links": 500, "pronunciation_events": 0, "pronunciation_progress": 0, "review_events": 0, "vocabulary": 500}。
- 快照学习记录分组：[{"status": "untested", "pronunciation_status": "未测试", "count": 500}]。
- 这份快照是试用前备份。试用说明写明其后的新学习记录不在其中。正式库文件缺失，所以不能把它当成当前个人库。

## 云端对照

- 只读页数：500；唯一页面：500；属性数：57；读取请求：6。
- 内容写入 0，事件上传 0。
- 9 个审计属性非空数量：{"AI 筛选理由": 100, "筛选置信度": 100, "原记录ID": 100, "原始词头": 100, "清洗记录": 20, "原书书内页码": 100, "分类依据": 100, "原5552台账内": 100, "发音资源状态": 100}。
- 已观察到的个人属性非空数量：{"自然拼读状态": 100, "发音状态": 100, "自然拼读笔记": 0, "听音学习状态": 100, "听音学习笔记": 0, "学习状态": 100}。这些值只参与保护指纹，没有写入导入计划。

## 差异

发现差异，正式批量写入没有开始。

```json
[
  {
    "kind": "sqlite_missing"
  }
]
```
