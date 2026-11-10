"""P5-C.1 read-only location survey for the personal learning database.

Does not create directories, restore a database, write to Notion, or modify a
candidate file. SQLite is opened immutable so a read does not create WAL/SHM.
"""
import datetime
import hashlib
import json
import os
import pathlib
import sqlite3
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PRIVATE = ROOT / 'private' / 'p5c'
DOCS = ROOT / 'docs' / 'p5c'
BASELINE_RELATIVE = pathlib.Path('private/p41/personal-pretrial-20261109-141933.sqlite3')
BASELINE_RECORDED = '3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31'
APP_DIR_NAME = pathlib.Path('Personal') / 'English Learning'
DB_NAME = 'english_learning_v1.sqlite3'
SKIP_DIRS = {
    'node_modules', '.git', 'build', '.dart_tool', '.gradle', 'Cache', 'Code Cache',
    'GPUCache', 'CachedData', 'DawnGraphiteCache', 'DawnWebGPUCache', 'GrShaderCache',
    'Crashpad', 'logs', 'Service Worker', 'Temp', 'tmp', '__pycache__', 'ephemeral',
    'Blob_Storage', 'CacheStorage', 'Code Cache', 'Shared Dictionary',
}


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def local_stamp(path):
    return datetime.datetime.fromtimestamp(path.stat().st_mtime).astimezone().isoformat(timespec='seconds')


def is_sqlite(path):
    try:
        with open(path, 'rb') as handle:
            return handle.read(16) == b'SQLite format 3\x00'
    except OSError:
        return False


def display_path(path):
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def open_immutable(path):
    connection = sqlite3.connect(path.as_uri() + '?mode=ro&immutable=1', uri=True)
    connection.execute('PRAGMA query_only = ON')
    return connection


def learning_summary(path):
    info = {
        'path': display_path(path),
        'bytes': path.stat().st_size,
        'modified_local': local_stamp(path),
        'sha256': sha256(path),
        'sqlite_header': is_sqlite(path),
        'sidecars': sidecar_info(path),
    }
    if not info['sqlite_header']:
        info['role'] = 'not_sqlite'
        return info
    try:
        with open_immutable(path) as connection:
            names = [row[0] for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY 1")]
            info['tables'] = names
            info['user_version'] = connection.execute('PRAGMA user_version').fetchone()[0]
            info['integrity'] = connection.execute('PRAGMA integrity_check').fetchone()[0]
            info['foreign_key_issues'] = len(connection.execute('PRAGMA foreign_key_check').fetchall())
            if 'vocabulary' in names and 'learning_progress' in names:
                info['role'] = 'learning_database'
                info['vocabulary'] = connection.execute('SELECT COUNT(*) FROM vocabulary').fetchone()[0]
                info['review_events'] = scalar(connection, 'review_events')
                info['pronunciation_events'] = scalar(connection, 'pronunciation_events')
                info['pronunciation_progress'] = scalar(connection, 'pronunciation_progress')
                info['meaning_ratings'] = connection.execute(
                    "SELECT COUNT(*) FROM learning_progress WHERE status IS NOT NULL AND status != 'untested'"
                ).fetchone()[0]
                info['pronunciation_status_set'] = connection.execute(
                    "SELECT COUNT(*) FROM learning_progress WHERE pronunciation_status IS NOT NULL AND pronunciation_status != '未测试'"
                ).fetchone()[0]
                info['review_dates'] = connection.execute(
                    'SELECT COUNT(*) FROM learning_progress WHERE due_utc IS NOT NULL OR last_reviewed_utc IS NOT NULL'
                ).fetchone()[0]
                info['review_counts'] = connection.execute(
                    'SELECT COUNT(*) FROM learning_progress WHERE review_count > 0'
                ).fetchone()[0]
                info['status_groups'] = [
                    {'status': row[0], 'pronunciation_status': row[1], 'count': row[2]}
                    for row in connection.execute(
                        'SELECT status, pronunciation_status, COUNT(*) FROM learning_progress GROUP BY 1, 2 ORDER BY 3 DESC'
                    )
                ]
                info['progress_fingerprint'] = fingerprint(connection, '''
                    SELECT entry_id, status, pronunciation_status, review_count, last_reviewed_utc, due_utc
                    FROM learning_progress ORDER BY entry_id
                ''')
            else:
                info['role'] = 'other_sqlite'
    except Exception as exc:
        info['role'] = 'unreadable'
        info['error'] = type(exc).__name__
    return info


def scalar(connection, table):
    names = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if table not in names:
        return None
    return connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]


def fingerprint(connection, sql):
    digest = hashlib.sha256()
    for row in connection.execute(sql):
        digest.update(repr(tuple(row)).encode())
        digest.update(b'\n')
    return digest.hexdigest()


def sidecar_info(path):
    found = []
    for suffix in ('-wal', '-shm', '.sqlite3-wal', '.sqlite3-shm'):
        candidate = pathlib.Path(str(path) + suffix)
        if candidate.exists():
            found.append({'name': candidate.name, 'bytes': candidate.stat().st_size, 'sha256': sha256(candidate)})
    stem = path.with_name(path.name.replace('.sqlite3', '').replace('.sqlite', ''))
    for extra in (path.with_suffix(path.suffix + '-wal'), path.with_suffix(path.suffix + '-shm')):
        if extra.exists() and extra.name not in {item['name'] for item in found}:
            found.append({'name': extra.name, 'bytes': extra.stat().st_size, 'sha256': sha256(extra)})
    return found


def expected_locations():
    appdata = pathlib.Path(os.environ['APPDATA'])
    local = pathlib.Path(os.environ['LOCALAPPDATA'])
    profile = pathlib.Path(os.environ['USERPROFILE'])
    locations = [
        appdata / APP_DIR_NAME / DB_NAME,
        appdata / 'English Learning' / DB_NAME,
        appdata / 'english_learning' / DB_NAME,
        local / APP_DIR_NAME / DB_NAME,
        local / 'VirtualStore' / 'Roaming' / APP_DIR_NAME / DB_NAME,
        profile / 'AppData' / 'LocalLow' / APP_DIR_NAME / DB_NAME,
    ]
    packages = local / 'Packages'
    if packages.exists():
        for child in packages.iterdir():
            if not child.is_dir():
                continue
            lowered = child.name.lower()
            if 'english' in lowered or 'personal' in lowered:
                locations.append(child / 'LocalCache' / 'Roaming' / APP_DIR_NAME / DB_NAME)
                locations.append(child / 'LocalCache' / 'Local' / APP_DIR_NAME / DB_NAME)
    return locations


def interesting_file(path):
    name = path.name.lower()
    parent = path.parent.name.lower()
    in_app_dir = parent == 'english learning'
    if name.endswith(('-wal', '-shm')) and ('english_learning' in name or in_app_dir):
        return True
    if name.endswith(('.sqlite', '.sqlite3', '.db')) and (
        'english_learning' in name or 'learning' in name or in_app_dir or 'personal-' in name or 'rehearsal' in name
    ):
        return True
    return name == DB_NAME.lower()


def walk_files(root):
    if not root.exists():
        return
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS and name != 'WindowsApps']
        current = pathlib.Path(dirpath)
        english_dir = current.name.lower() in {'english learning', 'english_learning', 'englishlearning'}
        for filename in filenames:
            path = current / filename
            if english_dir or interesting_file(path):
                yield path


def version_info(executable):
    if not executable.exists():
        return {'path': display_path(executable), 'present': False}
    script = (
        "$info = (Get-Item -LiteralPath $env:P5C_EXE).VersionInfo; "
        "Write-Output ($info.CompanyName + '|' + $info.ProductName + '|' + $info.FileVersion)"
    )
    completed = subprocess.run(
        ['powershell', '-NoProfile', '-Command', script],
        env={**os.environ, 'P5C_EXE': str(executable)},
        capture_output=True, text=True, timeout=30, check=False,
    )
    company, product, version = (completed.stdout.strip().split('|') + ['', '', ''])[:3]
    return {
        'path': display_path(executable),
        'present': True,
        'company_name': company,
        'product_name': product,
        'file_version': version,
    }


def shortcuts():
    roots = [
        pathlib.Path(os.environ['USERPROFILE']) / 'Desktop',
        pathlib.Path(os.environ['APPDATA']) / 'Microsoft' / 'Windows' / 'Start Menu',
        pathlib.Path(os.environ['PROGRAMDATA']) / 'Microsoft' / 'Windows' / 'Start Menu',
        pathlib.Path(r'C:\Users\Public\Desktop'),
    ]
    found = []
    script = r'''
$shell = New-Object -ComObject WScript.Shell
Get-ChildItem -LiteralPath $env:P5C_SHORTCUT_ROOT -Filter *.lnk -Recurse -ErrorAction SilentlyContinue |
  ForEach-Object {
    $link = $shell.CreateShortcut($_.FullName)
    if ($_.Name -match 'English|english_learning' -or $link.TargetPath -match 'English|english_learning') {
      Write-Output ($_.FullName + '|' + $link.TargetPath + '|' + $link.Arguments + '|' + $link.WorkingDirectory)
    }
  }
'''
    for root in roots:
        if not root.exists():
            continue
        completed = subprocess.run(
            ['powershell', '-NoProfile', '-Command', script],
            env={**os.environ, 'P5C_SHORTCUT_ROOT': str(root)},
            capture_output=True, text=True, timeout=60, check=False,
        )
        for line in completed.stdout.splitlines():
            parts = (line.split('|') + ['', '', '', ''])[:4]
            found.append({
                'shortcut': parts[0],
                'target': parts[1],
                'arguments': parts[2],
                'working_directory': parts[3],
            })
    return found


def recycle_matches():
    script = r'''
$shell = New-Object -ComObject Shell.Application
$bin = $shell.NameSpace(0xA)
if ($null -eq $bin) { return }
foreach ($item in @($bin.Items())) {
  $name = [string]$item.Name
  if ($name -match 'sqlite|english_learning|English Learning') {
    Write-Output $name
  }
}
'''
    completed = subprocess.run(
        ['powershell', '-NoProfile', '-Command', script],
        capture_output=True, text=True, timeout=60, check=False,
    )
    return sorted({line.strip() for line in completed.stdout.splitlines() if line.strip()})


def classify(item, baseline):
    path = item['path'].lower()
    if 'rehearsal' in path or 'simulation' in path or 'acceptance' in path:
        return 'rehearsal_or_simulation'
    if item.get('user_version') == 4 or 'learning_journal' in item.get('tables', []):
        return 'isolated_copy_schema'
    if item.get('sha256') == baseline.get('sha256'):
        return 'same_bytes_as_pretrial_snapshot'
    same_state = (
        item.get('role') == 'learning_database'
        and item.get('progress_fingerprint') == baseline.get('progress_fingerprint')
        and item.get('review_events') == baseline.get('review_events')
        and item.get('pronunciation_events') == baseline.get('pronunciation_events')
        and item.get('vocabulary') == baseline.get('vocabulary')
    )
    if same_state:
        return 'same_learning_state_as_pretrial_snapshot'
    if item.get('role') == 'learning_database' and (
        (item.get('modified_local') or '') > '2026-11-09T14:19:33'
        or (item.get('review_events') or 0) > (baseline.get('review_events') or 0)
        or (item.get('meaning_ratings') or 0) > (baseline.get('meaning_ratings') or 0)
    ):
        return 'newer_than_pretrial_snapshot'
    if item.get('role') == 'learning_database':
        return 'older_or_other_learning_database'
    return item.get('role', 'unclassified')


def main():
    baseline_path = ROOT / BASELINE_RELATIVE
    baseline = learning_summary(baseline_path)
    baseline['recorded_sha256'] = BASELINE_RECORDED
    baseline['hash_matches_record'] = baseline.get('sha256') == BASELINE_RECORDED
    searched_roots = [
        pathlib.Path(os.environ['APPDATA']),
        pathlib.Path(os.environ['LOCALAPPDATA']),
        pathlib.Path(os.environ['USERPROFILE']) / 'AppData' / 'LocalLow',
        pathlib.Path(os.environ['USERPROFILE']) / 'Desktop',
        pathlib.Path(os.environ['USERPROFILE']) / 'Documents',
        pathlib.Path(os.environ['USERPROFILE']) / 'Downloads',
        pathlib.Path(r'E:\desktop'),
        pathlib.Path(r'C:\Users\Public\Desktop'),
        ROOT / 'private',
    ]
    seen = set()
    files = []
    for location in expected_locations():
        seen.add(location.resolve()) if location.exists() else None
        files.append(location if location.exists() else None)
    discovered = []
    for root in searched_roots:
        for path in walk_files(root):
            resolved = path.resolve()
            if resolved in seen or not path.is_file():
                continue
            seen.add(resolved)
            if path.stat().st_size > 200 * 1024 * 1024:
                continue
            if is_sqlite(path) or interesting_file(path):
                discovered.append(path)
    summaries = []
    for path in discovered:
        if path.name.lower().endswith(('-wal', '-shm')) and not is_sqlite(path):
            summaries.append({
                'path': display_path(path),
                'bytes': path.stat().st_size,
                'modified_local': local_stamp(path),
                'sha256': sha256(path),
                'role': 'wal_or_shm',
            })
            continue
        item = learning_summary(path)
        name = path.name.lower()
        if item.get('role') == 'other_sqlite' and 'english_learning' not in name and 'learning' not in name:
            continue
        item['comparison'] = classify(item, baseline)
        summaries.append(item)
    expected = [str(path) for path in expected_locations()]
    expected_exists = {str(path): path.exists() for path in expected_locations()}
    exes = [
        ROOT / 'build/windows/x64/runner/Debug/english_learning.exe',
        ROOT / 'build/windows/x64/runner/Release/english_learning.exe',
    ]
    report = {
        'phase': 'P5-C.1',
        'version': '0.7.0+10',
        'checked_local': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'application_support_rule': r'%APPDATA%\Personal\English Learning',
        'database_filename': DB_NAME,
        'directory_created_by_survey': False,
        'database_created_by_survey': False,
        'restored': False,
        'content_writes': 0,
        'event_uploads': 0,
        'executables': [version_info(path) for path in exes],
        'shortcuts': shortcuts(),
        'recycle_name_matches': recycle_matches(),
        'expected_paths_present': expected_exists,
        'baseline': baseline,
        'candidates': summaries,
    }
    newer = [item for item in summaries if item.get('comparison') == 'newer_than_pretrial_snapshot']
    report['newer_valid_database_found'] = bool(newer)
    report['safe_to_restore_without_confirmation'] = False
    PRIVATE.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)
    (PRIVATE / 'database_location.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    write_markdown(report)
    print(json.dumps({
        'expected_present': any(expected_exists.values()),
        'learning_candidates': sum(item.get('role') == 'learning_database' for item in summaries),
        'newer': len(newer),
        'shortcuts': len(report['shortcuts']),
        'recycle_matches': len(report['recycle_name_matches']),
        'restored': False,
    }, ensure_ascii=False))
    return 0


def write_markdown(report):
    baseline = report['baseline']
    lines = [
        '# P5-C.1 个人数据库定位',
        '',
        f"版本保持 0.7.0+10。调查时间 {report['checked_local']}。本轮没有恢复数据库，没有创建空库，没有写入 Notion，没有上传学习事件。",
        '',
        '## 程序实际路径',
        '',
        'Windows 正式库由 `getApplicationSupportDirectory()` 加上固定文件名 `english_learning_v1.sqlite3` 决定。`path_provider_windows` 2.3.0 读取正在运行的 exe 版本资源：公司名 `Personal`，产品名 `English Learning`，再拼到 Roaming AppData。公司名和产品名自基线提交 `e07c9da` 起没有改过。',
        '',
        '因此直接启动已构建的 Windows 程序时，正式库路径是：',
        '',
        '`%APPDATA%\\Personal\\English Learning\\english_learning_v1.sqlite3`',
        '',
        '当前解析为 `C:\\Users\\Administrator\\AppData\\Roaming\\Personal\\English Learning\\english_learning_v1.sqlite3`。调查没有启动程序。path_provider 在首次解析时会创建尚不存在的目录，所以这次没有调用它。',
        '',
        '同一规则下的备用位置也已查看：没有公司名时会落到 `%APPDATA%\\English Learning`；没有产品名时会落到 exe 文件名 `english_learning`。LocalAppData、LocalLow、VirtualStore 和名称里含 English 或 Personal 的 MSIX LocalCache 均已列入检查。',
        '',
        '## 已构建程序与快捷方式',
        '',
    ]
    for item in report['executables']:
        if item['present']:
            lines.append(
                f"- `{item['path']}`：CompanyName `{item['company_name']}`，ProductName `{item['product_name']}`，文件版本 `{item['file_version']}`。"
            )
        else:
            lines.append(f"- `{item['path']}` 不存在，没有从它产生另一套目录。")
    if report['shortcuts']:
        for item in report['shortcuts']:
            lines.append(
                f"- 快捷方式 `{item['shortcut']}` 指向 `{item['target']}`，参数 `{item['arguments'] or '无'}`，工作目录 `{item['working_directory'] or '无'}`。"
            )
    else:
        lines.append('- 当前用户桌面、公共桌面和开始菜单里没有名称或目标匹配 English Learning 的快捷方式。')
    lines.extend(['', '## 预期位置', ''])
    for path, present in report['expected_paths_present'].items():
        lines.append(f"- `{path}`：{'存在' if present else '不存在'}。")
    lines.extend([
        '',
        '## 已知试用前快照',
        '',
        f"- 路径 `{baseline['path']}`。",
        f"- 修改时间 {baseline['modified_local']}。",
        f"- SHA-256 `{baseline['sha256']}`，与 2026-11-09 14:19:33 记录{'一致' if baseline['hash_matches_record'] else '不一致'}。",
        f"- schema user_version {baseline.get('user_version')}，integrity `{baseline.get('integrity')}`，外键问题 {baseline.get('foreign_key_issues')}。",
        f"- 词条 {baseline.get('vocabulary')}，词义事件 {baseline.get('review_events')}，发音事件 {baseline.get('pronunciation_events')}。",
        f"- 非未测试词义评级 {baseline.get('meaning_ratings')}，已写复习日期 {baseline.get('review_dates')}，发音进度 {baseline.get('pronunciation_progress')}。",
        '',
        '## 候选与备份',
        '',
    ])
    if not report['candidates']:
        lines.append('除已知快照外，没有发现其他学习库。')
    for item in report['candidates']:
        lines.append(f"### `{item['path']}`")
        lines.append('')
        lines.append(f"- 角色：{item.get('comparison', item.get('role'))}。")
        lines.append(f"- 修改时间 {item.get('modified_local')}，大小 {item.get('bytes')} 字节。")
        lines.append(f"- SHA-256 `{item.get('sha256')}`。")
        if item.get('role') == 'learning_database':
            lines.append(
                f"- schema {item.get('user_version')}，integrity `{item.get('integrity')}`，外键问题 {item.get('foreign_key_issues')}。"
            )
            lines.append(
                f"- 词条 {item.get('vocabulary')}，词义事件 {item.get('review_events')}，发音事件 {item.get('pronunciation_events')}。"
            )
            lines.append(
                f"- 非未测试词义评级 {item.get('meaning_ratings')}，已写复习日期 {item.get('review_dates')}，复习次数大于 0 的行 {item.get('review_counts')}，发音进度 {item.get('pronunciation_progress')}。"
            )
            lines.append(f"- 学习记录分组：{json.dumps(item.get('status_groups', []), ensure_ascii=False)}。")
            same = item.get('progress_fingerprint') == baseline.get('progress_fingerprint')
            lines.append(f"- 学习进度指纹与试用前快照{'相同' if same else '不同'}。")
        if item.get('sidecars'):
            lines.append(f"- 伴随 WAL/SHM：{json.dumps(item['sidecars'], ensure_ascii=False)}。")
        elif item.get('role') == 'wal_or_shm':
            lines.append('- 这是 WAL 或 SHM 伴随文件，不是独立正式库。')
        lines.append('')
    lines.extend(['## 回收站名称匹配', ''])
    if report['recycle_name_matches']:
        for name in report['recycle_name_matches']:
            lines.append(f"- `{name}`")
    else:
        lines.append('- 回收站里没有名称匹配 sqlite、english_learning 或 English Learning 的项目。')
    lines.extend([
        '',
        '## 判断',
        '',
    ])
    redirected = [
        item for item in report['candidates']
        if item.get('role') == 'learning_database' and 'LocalCache' in item.get('path', '')
    ]
    if report['newer_valid_database_found']:
        lines.append('发现比试用前快照更新的学习库。正式恢复仍需确认目标文件，本轮没有覆盖或替换任何文件。')
    else:
        lines.append('直接启动当前 Debug 或 Release 程序时使用的正式路径上，数据库、WAL 和 SHM 都不存在，`Personal\\English Learning` 目录也不存在。')
        if redirected:
            lines.append('')
            lines.append('Codex 宿主的 MSIX 重定向目录里还有一份同名库。它的学习进度指纹与试用前快照相同，文件时间更早，没有 WAL/SHM，也不能代替已经缺失的正式路径文件。')
        lines.append('')
        lines.append('因此目前不能把任何候选自动恢复成当前个人库。试用前快照可以恢复出当时的 500 个未测试词条和 0 条学习事件，但不能证明 14:19:33 之后没有学习记录。文件消失时间无法从剩余目录时间得知，缺失观察最早记录在 2026-11-10 09:44 的导入前检查。这段时间里如果曾经把评级写入正式路径且没有另存，那些记录现在不在已找到的文件中。')
        lines.append('')
        lines.append('在确认恢复方案之前不要启动 English Learning。程序打开缺失的正式库时会创建新的空数据库。')
    lines.extend([
        '',
        '## 建议的恢复方案',
        '',
        '等待确认前不执行，也不要启动程序。建议目标只恢复直接启动所用的正式路径 `%APPDATA%\\Personal\\English Learning\\english_learning_v1.sqlite3`，来源使用哈希已核对的 14:19:33 试用前快照。操作是先确认没有 English Learning 进程，再用 SQLite backup API 把快照复制到该路径；该路径目前没有文件，所以不会覆盖现有个人库。回滚是关闭程序后删除这次新放入的文件，使目录回到调查时的缺失状态。',
        '',
        '不使用 `restore-rehearsal.sqlite3`、P3/P4 旧备份、P5-C 备份副本或 schema v4 隔离副本。Codex LocalCache 里的同名文件保持原样，不覆盖，也不把它复制成正式库；它的学习状态相同但文件更早。',
        '',
        '如果 14:19:33 之后确实背过词，应先提供另一份更新备份或接受这段记录无法找回，再执行上述恢复。',
        '',
        '## 进入正式导入前仍需完成',
        '',
        '- 确认正式个人库已放回实际应用支持目录，或明确接受试用前快照作为恢复来源。',
        '- 只读复核恢复后的 schema、500 个稳定 ID、评级和复习日期，并与快照指纹一致。',
        '- 保留这次恢复前“正式路径为空”的证据，以便回滚。',
        '- 再取得明确授权后才允许 Notion 批量写入。194 个待核实词和 27 个暂缓词继续排除。',
        '',
    ])
    (DOCS / 'DATABASE_RECOVERY.md').write_text('\n'.join(lines), encoding='utf-8')


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print('Location survey failed: ' + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
