# P5-C.1 个人数据库定位

版本保持 0.7.0+10。调查时间 2026-11-10T10:35:29+08:00。本轮没有恢复数据库，没有创建空库，没有写入 Notion，没有上传学习事件。

## 程序实际路径

Windows 正式库由 `getApplicationSupportDirectory()` 加上固定文件名 `english_learning_v1.sqlite3` 决定。`path_provider_windows` 2.3.0 读取正在运行的 exe 版本资源：公司名 `Personal`，产品名 `English Learning`，再拼到 Roaming AppData。公司名和产品名自基线提交 `e07c9da` 起没有改过。

因此直接启动已构建的 Windows 程序时，正式库路径是：

`%APPDATA%\Personal\English Learning\english_learning_v1.sqlite3`

当前解析为 `C:\Users\Administrator\AppData\Roaming\Personal\English Learning\english_learning_v1.sqlite3`。调查没有启动程序。path_provider 在首次解析时会创建尚不存在的目录，所以这次没有调用它。

同一规则下的备用位置也已查看：没有公司名时会落到 `%APPDATA%\English Learning`；没有产品名时会落到 exe 文件名 `english_learning`。LocalAppData、LocalLow、VirtualStore 和名称里含 English 或 Personal 的 MSIX LocalCache 均已列入检查。

## 已构建程序与快捷方式

- `build\windows\x64\runner\Debug\english_learning.exe`：CompanyName `Personal`，ProductName `English Learning`，文件版本 `0.7.0+10`。
- `build\windows\x64\runner\Release\english_learning.exe`：CompanyName `Personal`，ProductName `English Learning`，文件版本 `0.7.0+10`。
- 当前用户桌面、公共桌面和开始菜单里没有名称或目标匹配 English Learning 的快捷方式。

## 预期位置

- `C:\Users\Administrator\AppData\Roaming\Personal\English Learning\english_learning_v1.sqlite3`：不存在。
- `C:\Users\Administrator\AppData\Roaming\English Learning\english_learning_v1.sqlite3`：不存在。
- `C:\Users\Administrator\AppData\Roaming\english_learning\english_learning_v1.sqlite3`：不存在。
- `C:\Users\Administrator\AppData\Local\Personal\English Learning\english_learning_v1.sqlite3`：不存在。
- `C:\Users\Administrator\AppData\Local\VirtualStore\Roaming\Personal\English Learning\english_learning_v1.sqlite3`：不存在。
- `C:\Users\Administrator\AppData\LocalLow\Personal\English Learning\english_learning_v1.sqlite3`：不存在。

## 已知试用前快照

- 路径 `private\p41\personal-pretrial-20261109-141933.sqlite3`。
- 修改时间 2026-11-09T14:19:33+08:00。
- SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31`，与 2026-11-09 14:19:33 记录一致。
- schema user_version 3，integrity `ok`，外键问题 0。
- 词条 500，词义事件 0，发音事件 0。
- 非未测试词义评级 0，已写复习日期 0，发音进度 0。

## 候选与备份

### `C:\Users\Administrator\AppData\Local\Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Roaming\Personal\English Learning\english_learning_v1.sqlite3`

- 角色：学习状态与试用前快照相同，文件字节不同。
- 修改时间 2026-11-09T13:59:10+08:00，大小 1327104 字节。
- SHA-256 `13e7287e8c6da07fa7888ecfa66244ed25821f68c74b75b14f764c5c6db9a061`。
- schema 3，integrity `ok`，外键问题 0。
- 词条 500，词义事件 0，发音事件 0。
- 非未测试词义评级 0，已写复习日期 0，复习次数大于 0 的行 0，发音进度 0。
- 学习记录分组：[{"status": "untested", "pronunciation_status": "未测试", "count": 500}]。
- 学习进度指纹与试用前快照相同。

### `private\p3\personal-before-cloud-import.sqlite3`

- 角色：更早的空学习库，词条数为 0。
- 修改时间 2026-11-09T13:06:58+08:00，大小 73728 字节。
- SHA-256 `84c55b3c216bef53d344da915ecca7257c5ab5815e58bb9cc23c4a7563fcbbdb`。
- schema 3，integrity `ok`，外键问题 0。
- 词条 0，词义事件 0，发音事件 0。
- 非未测试词义评级 0，已写复习日期 0，复习次数大于 0 的行 0，发音进度 0。
- 学习记录分组：[]。
- 学习进度指纹与试用前快照不同。

### `private\p4\personal-before-direct-135030.sqlite3`

- 角色：学习状态与试用前快照相同，文件字节不同。
- 修改时间 2026-11-09T13:50:30+08:00，大小 1159168 字节。
- SHA-256 `3af145954bfc6f42b7dd82d0be6b3ae72ceba03381b1e37974276850ffedf02c`。
- schema 3，integrity `ok`，外键问题 0。
- 词条 500，词义事件 0，发音事件 0。
- 非未测试词义评级 0，已写复习日期 0，复习次数大于 0 的行 0，发音进度 0。
- 学习记录分组：[{"status": "untested", "pronunciation_status": "未测试", "count": 500}]。
- 学习进度指纹与试用前快照相同。

### `private\p41\personal-pretrial-20261109-141933.sqlite3`

- 角色：字节与试用前快照相同。
- 修改时间 2026-11-09T14:19:33+08:00，大小 1327104 字节。
- SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31`。
- schema 3，integrity `ok`，外键问题 0。
- 词条 500，词义事件 0，发音事件 0。
- 非未测试词义评级 0，已写复习日期 0，复习次数大于 0 的行 0，发音进度 0。
- 学习记录分组：[{"status": "untested", "pronunciation_status": "未测试", "count": 500}]。
- 学习进度指纹与试用前快照相同。

### `private\p5c\backups\20261110-095221\personal-pretrial-20261109-141933.sqlite3`

- 角色：字节与试用前快照相同。
- 修改时间 2026-11-10T09:52:21+08:00，大小 1327104 字节。
- SHA-256 `3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31`。
- schema 3，integrity `ok`，外键问题 0。
- 词条 500，词义事件 0，发音事件 0。
- 非未测试词义评级 0，已写复习日期 0，复习次数大于 0 的行 0，发音进度 0。
- 学习记录分组：[{"status": "untested", "pronunciation_status": "未测试", "count": 500}]。
- 学习进度指纹与试用前快照相同。

### `private\p41\restore-rehearsal.sqlite3`

- 角色：恢复演练副本，不是正式库。
- 修改时间 2026-11-09T14:38:52+08:00，大小 1327104 字节。
- SHA-256 `bb476bd7a08d4b7764efc2a8ff24076ec15ea2526043283d37c92885f2b1689a`。
- schema 3，integrity `ok`，外键问题 0。
- 词条 500，词义事件 0，发音事件 0。
- 非未测试词义评级 0，已写复习日期 0，复习次数大于 0 的行 0，发音进度 0。
- 学习记录分组：[{"status": "untested", "pronunciation_status": "未测试", "count": 500}]。
- 学习进度指纹与试用前快照相同。

## 回收站名称匹配

- 回收站里没有名称匹配 sqlite、english_learning 或 English Learning 的项目。

## 判断

直接启动当前 Debug 或 Release 程序时使用的正式路径上，数据库、WAL 和 SHM 都不存在，`Personal\English Learning` 目录也不存在。

Codex 宿主的 MSIX 重定向目录里还有一份同名库。它的学习进度指纹与试用前快照相同，文件时间更早，没有 WAL/SHM，也不能代替已经缺失的正式路径文件。

因此目前不能把任何候选自动恢复成当前个人库。试用前快照可以恢复出当时的 500 个未测试词条和 0 条学习事件，但不能证明 14:19:33 之后没有学习记录。文件消失时间无法从剩余目录时间得知，缺失观察最早记录在 2026-11-10 09:44 的导入前检查。这段时间里如果曾经把评级写入正式路径且没有另存，那些记录现在不在已找到的文件中。

在确认恢复方案之前不要启动 English Learning。程序打开缺失的正式库时会创建新的空数据库。

## 建议的恢复方案

等待确认前不执行，也不要启动程序。建议目标只恢复直接启动所用的正式路径 `%APPDATA%\Personal\English Learning\english_learning_v1.sqlite3`，来源使用哈希已核对的 14:19:33 试用前快照。操作是先确认没有 English Learning 进程，再用 SQLite backup API 把快照复制到该路径；该路径目前没有文件，所以不会覆盖现有个人库。回滚是关闭程序后删除这次新放入的文件，使目录回到调查时的缺失状态。

不使用 `restore-rehearsal.sqlite3`、P3/P4 旧备份、P5-C 备份副本或 schema v4 隔离副本。Codex LocalCache 里的同名文件保持原样，不覆盖，也不把它复制成正式库；它的学习状态相同但文件更早。

如果 14:19:33 之后确实背过词，应先提供另一份更新备份或接受这段记录无法找回，再执行上述恢复。

## 进入正式导入前仍需完成

- 确认正式个人库已放回实际应用支持目录，或明确接受试用前快照作为恢复来源。
- 只读复核恢复后的 schema、500 个稳定 ID、评级和复习日期，并与快照指纹一致。
- 保留这次恢复前“正式路径为空”的证据，以便回滚。
- 再取得明确授权后才允许 Notion 批量写入。194 个待核实词和 27 个暂缓词继续排除。
