# P5-C.2 个人数据库恢复

版本保持 0.7.0+10。时间 2026-11-10T11:48:35+08:00。结果：**恢复完成，正式程序已读到 500 词且未改学习记录**。

本轮只恢复指定的本地 SQLite 快照。没有写入 Notion，没有上传学习事件，没有导入 CSV，没有修改其他候选数据库。

## 路径核对

- Roaming 目录 `C:\Users\Administrator\AppData\Roaming`。
- Release 版本资源：公司名 `Personal`，产品名 `English Learning`，文件版本 `0.7.0+10`。
- 由该版本资源解析出的正式库：`C:\Users\Administrator\AppData\Roaming\Personal\English Learning\english_learning_v1.sqlite3`。
- 授权目标：`C:\Users\Administrator\AppData\Roaming\Personal\English Learning\english_learning_v1.sqlite3`。
- 两者一致：是。

## 源快照

- SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31`，与预期一致。
- integrity `ok`，外键问题 0，schema 3。
- 词条 500，唯一 ID 500，词义事件 0，发音事件 0。
- 非未测试评级 0，复习日期 0，发音进度 0。
- 学习进度指纹与 P5-C.1一致。

## 恢复结果

- 正式文件存在：是。
- 恢复后 integrity `ok`，外键问题 0，schema 3。
- 词条 500，唯一 ID 500，词义事件 0，发音事件 0。
- 非未测试评级 0，复习日期 0。
- 与源快照的内容和学习指纹一致：是。
- 正式库 WAL/SHM：[]。

## Windows 读取验证

Release 程序 english_learning.exe 直接启动，没有通过 flutter run。窗口显示“本地 500 词 · 可学习未测试 / 到期 500 词”。没有点击复习、词库、CSV 或 Notion 同步。关闭后正式库 SHA-256 仍与源快照相同，没有 WAL/SHM。

## 异常与后续

没有未处理的恢复异常。脚本进程第一次替换正式路径时遇到暂时的 PermissionError，当时临时库已经校验通过且正式路径仍是空的；随后把同一临时文件原子移动到位。正式文件字节与源快照一致。

重新进行 P5-C 正式导入预检的条件：本地正式库已恢复，应用读取验证通过。可以另行做一次只读导入预检。本轮没有重跑预检，也没有执行 Notion 批量写入。
