"""P5-C.2 restore the verified pretrial snapshot to the formal Windows database.

The script refuses to run unless the Release executable's version resource still
resolves to the authorized Roaming path, the target is absent, and the source
hash matches. It does not write to Notion or modify any other database.
"""
import csv
import datetime
import hashlib
import json
import os
import pathlib
import sqlite3
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'private' / 'p41' / 'personal-pretrial-20261109-141933.sqlite3'
REVIEWED = ROOT / 'assets' / 'vocabulary' / 'reviewed500.csv'
RELEASE_EXE = ROOT / 'build' / 'windows' / 'x64' / 'runner' / 'Release' / 'english_learning.exe'
DEBUG_EXE = ROOT / 'build' / 'windows' / 'x64' / 'runner' / 'Debug' / 'english_learning.exe'
EXPECTED_SHA = '3c1ed2c1d1338f3cf5ee98122eedfdf00479a913c206480d1578863dce1a4e31'
AUTHORIZED_TARGET = pathlib.Path(
    r'C:\Users\Administrator\AppData\Roaming\Personal\English Learning\english_learning_v1.sqlite3'
)
P5C1_FINGERPRINT = 'bb776ed996b0e7ab692fc69ebb8ef6c565b2453e4856452884e453827e996f6d'
PRIVATE = ROOT / 'private' / 'p5c'
DOCS = ROOT / 'docs' / 'p5c'


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def sanitize(value):
    if value is None:
        return None
    cleaned = value.replace('<', '_').replace('>', '_').replace(':', '_').replace('"', '_')
    cleaned = cleaned.replace('/', '_').replace('\\', '_').replace('|', '_').replace('?', '_').replace('*', '_')
    cleaned = cleaned.rstrip(' ').rstrip('.')
    return cleaned or None


def version_info(executable):
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
    return {'company': company, 'product': product, 'file_version': version, 'present': executable.exists()}


def roaming_appdata():
    script = "[Environment]::GetFolderPath('ApplicationData')"
    completed = subprocess.run(
        ['powershell', '-NoProfile', '-Command', script],
        capture_output=True, text=True, timeout=30, check=False,
    )
    return pathlib.Path(completed.stdout.strip())


def resolved_database(executable):
    info = version_info(executable)
    company = sanitize(info['company'])
    product = sanitize(info['product']) or executable.stem
    relative = pathlib.Path(company) / product if company else pathlib.Path(product)
    return roaming_appdata() / relative / 'english_learning_v1.sqlite3', info


def running_processes():
    script = r'''
Get-CimInstance Win32_Process | Where-Object {
  $_.Name -eq 'english_learning.exe' -or
  $_.Name -eq 'flutter_tester.exe' -or
  ($_.CommandLine -and $_.CommandLine -match 'EnglishLearning-main' -and $_.Name -match 'dart|flutter')
} | ForEach-Object { Write-Output ($_.ProcessId.ToString() + '|' + $_.Name) }
'''
    completed = subprocess.run(
        ['powershell', '-NoProfile', '-Command', script],
        capture_output=True, text=True, timeout=30, check=False,
    )
    return [line.strip() for line in completed.stdout.splitlines() if line.strip()]


def fingerprint(connection, sql):
    digest = hashlib.sha256()
    for row in connection.execute(sql):
        digest.update(repr(tuple(row)).encode())
        digest.update(b'\n')
    return digest.hexdigest()


def open_ro(path):
    connection = sqlite3.connect(path.as_uri() + '?mode=ro&immutable=1', uri=True)
    connection.execute('PRAGMA query_only = ON')
    return connection


def inspect_db(path):
    with open_ro(path) as connection:
        tables = [row[0] for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY 1")]
        ids = [row[0] for row in connection.execute('SELECT entry_id FROM vocabulary ORDER BY entry_id')]
        words = [row[0] for row in connection.execute('SELECT word_key FROM vocabulary')]
        info = {
            'user_version': connection.execute('PRAGMA user_version').fetchone()[0],
            'integrity': connection.execute('PRAGMA integrity_check').fetchone()[0],
            'foreign_key_issues': len(connection.execute('PRAGMA foreign_key_check').fetchall()),
            'journal_mode': connection.execute('PRAGMA journal_mode').fetchone()[0],
            'tables': tables,
            'vocabulary': len(ids),
            'unique_ids': len(set(ids)),
            'duplicate_word_keys': len(words) - len(set(words)),
            'review_events': connection.execute('SELECT COUNT(*) FROM review_events').fetchone()[0],
            'pronunciation_events': connection.execute('SELECT COUNT(*) FROM pronunciation_events').fetchone()[0],
            'pronunciation_progress': connection.execute('SELECT COUNT(*) FROM pronunciation_progress').fetchone()[0],
            'meaning_ratings': connection.execute(
                "SELECT COUNT(*) FROM learning_progress WHERE status != 'untested'"
            ).fetchone()[0],
            'pronunciation_status_set': connection.execute(
                "SELECT COUNT(*) FROM learning_progress WHERE pronunciation_status != '未测试'"
            ).fetchone()[0],
            'review_dates': connection.execute(
                'SELECT COUNT(*) FROM learning_progress WHERE due_utc IS NOT NULL OR last_reviewed_utc IS NOT NULL'
            ).fetchone()[0],
            'review_counts': connection.execute(
                'SELECT COUNT(*) FROM learning_progress WHERE review_count > 0'
            ).fetchone()[0],
            'notion_links': connection.execute('SELECT COUNT(*) FROM notion_word_links').fetchone()[0],
            'progress_fingerprint': fingerprint(connection, '''
                SELECT entry_id, status, pronunciation_status, review_count, last_reviewed_utc, due_utc
                FROM learning_progress ORDER BY entry_id
            '''),
            'content_fingerprint': fingerprint(connection, '''
                SELECT entry_id, word, word_key, library_class, content_json
                FROM vocabulary ORDER BY entry_id
            '''),
            'ids': ids,
        }
        content = {
            row[0]: json.loads(row[1])
            for row in connection.execute('SELECT entry_id, content_json FROM vocabulary')
        }
    info['content'] = content
    return info


def reviewed_rows():
    with REVIEWED.open(encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle))


def sidecars(path):
    found = []
    for suffix in ('-wal', '-shm'):
        candidate = pathlib.Path(str(path) + suffix)
        if candidate.exists():
            found.append(str(candidate))
    return found


def fail(report, reason):
    report['stopped'] = reason
    report['restored'] = False
    write_outputs(report)
    print(json.dumps({'restored': False, 'stopped': reason}, ensure_ascii=False))
    return 2


def write_outputs(report):
    PRIVATE.mkdir(parents=True, exist_ok=True)
    DOCS.mkdir(parents=True, exist_ok=True)
    public = {key: value for key, value in report.items() if key not in {'source_ids', 'target_ids'}}
    (PRIVATE / 'restore.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (DOCS / 'RESTORE.md').write_text(render(public), encoding='utf-8')


def render(report):
    source = report.get('source') or {}
    target = report.get('target_after') or {}
    lines = [
        '# P5-C.2 个人数据库恢复',
        '',
        f"版本保持 0.7.0+10。时间 {report['checked_local']}。结果：**{report.get('result', '未完成')}**。",
        '',
        '本轮只恢复指定的本地 SQLite 快照。没有写入 Notion，没有上传学习事件，没有导入 CSV，没有修改其他候选数据库。',
        '',
        '## 路径核对',
        '',
        f"- Roaming 目录 `{report.get('roaming_appdata', '')}`。",
        f"- Release 版本资源：公司名 `{report.get('release_version', {}).get('company', '')}`，产品名 `{report.get('release_version', {}).get('product', '')}`，文件版本 `{report.get('release_version', {}).get('file_version', '')}`。",
        f"- 由该版本资源解析出的正式库：`{report.get('resolved_target', '')}`。",
        f"- 授权目标：`{report.get('authorized_target', '')}`。",
        f"- 两者一致：{'是' if report.get('target_matches_authorized') else '否'}。",
        '',
        '## 源快照',
        '',
        f"- SHA-256 `{source.get('sha256', '')}`，与预期{'一致' if source.get('sha256') == EXPECTED_SHA else '不一致'}。",
        f"- integrity `{source.get('integrity', '')}`，外键问题 {source.get('foreign_key_issues', '')}，schema {source.get('user_version', '')}。",
        f"- 词条 {source.get('vocabulary', '')}，唯一 ID {source.get('unique_ids', '')}，词义事件 {source.get('review_events', '')}，发音事件 {source.get('pronunciation_events', '')}。",
        f"- 非未测试评级 {source.get('meaning_ratings', '')}，复习日期 {source.get('review_dates', '')}，发音进度 {source.get('pronunciation_progress', '')}。",
        f"- 学习进度指纹与 P5-C.1{'一致' if source.get('matches_p5c1_fingerprint') else '不一致'}。",
        '',
        '## 恢复结果',
        '',
        f"- 正式文件存在：{'是' if report.get('target_exists_after') else '否'}。",
        f"- 恢复后 integrity `{target.get('integrity', '未检查')}`，外键问题 {target.get('foreign_key_issues', '未检查')}，schema {target.get('user_version', '未检查')}。",
        f"- 词条 {target.get('vocabulary', '未检查')}，唯一 ID {target.get('unique_ids', '未检查')}，词义事件 {target.get('review_events', '未检查')}，发音事件 {target.get('pronunciation_events', '未检查')}。",
        f"- 非未测试评级 {target.get('meaning_ratings', '未检查')}，复习日期 {target.get('review_dates', '未检查')}。",
        f"- 与源快照的内容和学习指纹一致：{'是' if report.get('logical_match') else '否'}。",
        f"- 正式库 WAL/SHM：{json.dumps(report.get('target_sidecars', []), ensure_ascii=False)}。",
        '',
        '## Windows 读取验证',
        '',
        report.get('launch_note', '尚未启动正式程序。'),
        '',
        '## 异常与后续',
        '',
        report.get('stopped', '恢复过程没有提前停止。'),
        '',
        f"重新进行 P5-C 正式导入预检的条件：{report.get('preflight_ready', '尚未满足')}。",
        '',
    ]
    return '\n'.join(lines)


def main():
    report = {
        'phase': 'P5-C.2',
        'version': '0.7.0+10',
        'checked_local': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'authorized_target': str(AUTHORIZED_TARGET),
        'content_writes': 0,
        'event_uploads': 0,
        'notion_import': False,
        'restored': False,
    }
    processes = running_processes()
    report['running_processes'] = processes
    if processes:
        return fail(report, 'English Learning 或相关测试进程仍在运行，未恢复。')
    if not RELEASE_EXE.exists():
        return fail(report, 'Release 正式程序不存在，无法核对它实际使用的数据目录。')
    resolved, release_info = resolved_database(RELEASE_EXE)
    debug_resolved, debug_info = resolved_database(DEBUG_EXE) if DEBUG_EXE.exists() else (None, {'present': False})
    report['roaming_appdata'] = str(roaming_appdata())
    report['release_version'] = release_info
    report['debug_version'] = debug_info
    report['resolved_target'] = str(resolved)
    report['debug_resolved_target'] = str(debug_resolved) if debug_resolved else ''
    report['target_matches_authorized'] = resolved == AUTHORIZED_TARGET
    if resolved != AUTHORIZED_TARGET:
        return fail(report, '正式程序解析出的数据库路径与授权目标不同，未恢复。')
    if debug_resolved and debug_resolved != AUTHORIZED_TARGET:
        return fail(report, 'Debug 与 Release 的数据目录不一致，未恢复。')
    if AUTHORIZED_TARGET.exists() or sidecars(AUTHORIZED_TARGET):
        report['target_exists_before'] = True
        report['target_sidecars_before'] = sidecars(AUTHORIZED_TARGET)
        return fail(report, '正式目标或其 WAL/SHM 已存在，未覆盖。')
    report['target_exists_before'] = False
    codex = pathlib.Path(os.environ['LOCALAPPDATA']) / 'Packages'
    report['codex_left_untouched'] = True
    if not SOURCE.exists():
        return fail(report, '指定源快照不存在，未恢复。')
    source_hash = sha256(SOURCE)
    source = inspect_db(SOURCE)
    source['sha256'] = source_hash
    source['matches_p5c1_fingerprint'] = source['progress_fingerprint'] == P5C1_FINGERPRINT
    report['source'] = {key: value for key, value in source.items() if key not in {'ids', 'content'}}
    if source_hash != EXPECTED_SHA:
        return fail(report, '源快照 SHA-256 与预期不一致，未恢复。')
    if source['integrity'] != 'ok' or source['foreign_key_issues'] or source['user_version'] != 3:
        return fail(report, '源快照完整性或 schema 不符合预期，未恢复。')
    if source['vocabulary'] != 500 or source['unique_ids'] != 500 or source['duplicate_word_keys']:
        return fail(report, '源快照词条或稳定 ID 不符合预期，未恢复。')
    if source['review_events'] or source['pronunciation_events'] or source['meaning_ratings'] or source['review_dates'] or source['pronunciation_status_set'] or source['review_counts']:
        return fail(report, '源快照含有个人学习记录，与已确认的空学习状态不符，未恢复。')
    if not source['matches_p5c1_fingerprint']:
        return fail(report, '源快照学习指纹与 P5-C.1 记录不一致，未恢复。')
    reviewed = reviewed_rows()
    reviewed_ids = [row['entry_id'] for row in reviewed]
    if set(reviewed_ids) != set(source['ids']) or len(reviewed_ids) != 500:
        return fail(report, '源快照稳定 ID 与现有 500 词包不一致，未恢复。')
    for row in reviewed:
        stored = source['content'].get(row['entry_id'])
        if stored is None or any((stored.get(field) or '') != (row.get(field) or '') for field in row):
            return fail(report, '源快照词条内容与现有 500 词包不一致，未恢复。')
    temp_dir = pathlib.Path(os.environ['LOCALAPPDATA']) / 'Temp' / 'english-learning-p5c2'
    temp_dir.mkdir(parents=True, exist_ok=True)
    temp_path = temp_dir / 'english_learning_v1.sqlite3.restore-tmp'
    if temp_path.exists():
        temp_path.unlink()
    for suffix in ('-wal', '-shm'):
        leftover = pathlib.Path(str(temp_path) + suffix)
        if leftover.exists():
            leftover.unlink()
    source_connection = sqlite3.connect(SOURCE.as_uri() + '?mode=ro', uri=True)
    temp_connection = sqlite3.connect(temp_path)
    try:
        source_connection.backup(temp_connection)
        temp_connection.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    finally:
        temp_connection.close()
        source_connection.close()
    for suffix in ('-wal', '-shm'):
        leftover = pathlib.Path(str(temp_path) + suffix)
        if leftover.exists() and leftover.stat().st_size == 0:
            leftover.unlink()
    if sidecars(temp_path):
        report['temp_path'] = str(temp_path)
        return fail(report, '临时数据库仍有 WAL/SHM，未放入正式路径。')
    temp_info = inspect_db(temp_path)
    if temp_info['integrity'] != 'ok' or temp_info['foreign_key_issues'] or temp_info['user_version'] != 3:
        report['temp_path'] = str(temp_path)
        return fail(report, '临时数据库校验失败，未放入正式路径。')
    if temp_info['content_fingerprint'] != source['content_fingerprint'] or temp_info['progress_fingerprint'] != source['progress_fingerprint']:
        report['temp_path'] = str(temp_path)
        return fail(report, '临时数据库与源快照逻辑数据不一致，未放入正式路径。')
    if AUTHORIZED_TARGET.exists() or sidecars(AUTHORIZED_TARGET):
        report['temp_path'] = str(temp_path)
        return fail(report, '放入前正式目标已出现，未覆盖。')
    AUTHORIZED_TARGET.parent.mkdir(parents=True, exist_ok=True)
    replaced = False
    for _ in range(5):
        try:
            os.replace(temp_path, AUTHORIZED_TARGET)
            replaced = True
            break
        except PermissionError:
            import time
            time.sleep(0.5)
    if not replaced:
        report['temp_path'] = str(temp_path)
        return fail(report, '临时数据库已校验，但正式路径暂时拒绝替换，未覆盖任何已有文件。')
    report['restored'] = True
    report['target_exists_after'] = AUTHORIZED_TARGET.exists()
    report['target_sidecars'] = sidecars(AUTHORIZED_TARGET)
    target = inspect_db(AUTHORIZED_TARGET)
    report['target_after'] = {key: value for key, value in target.items() if key not in {'ids', 'content'}}
    report['logical_match'] = (
        target['content_fingerprint'] == source['content_fingerprint']
        and target['progress_fingerprint'] == source['progress_fingerprint']
        and target['vocabulary'] == 500
        and target['unique_ids'] == 500
        and target['review_events'] == 0
        and target['pronunciation_events'] == 0
        and target['meaning_ratings'] == 0
        and target['review_dates'] == 0
        and target['integrity'] == 'ok'
        and target['foreign_key_issues'] == 0
        and target['user_version'] == 3
        and not report['target_sidecars']
    )
    report['codex_unchanged_sha256'] = None
    codex_db = next(codex.glob('OpenAI.Codex_*/LocalCache/Roaming/Personal/English Learning/english_learning_v1.sqlite3'), None)
    if codex_db and codex_db.exists():
        report['codex_unchanged_sha256'] = sha256(codex_db)
        report['codex_sha_unchanged'] = report['codex_unchanged_sha256'] == '13e7287e8c6da07fa7888ecfa66244ed25821f68c74b75b14f764c5c6db9a061'
    if not report['logical_match']:
        report['result'] = '恢复后校验失败'
        if target['meaning_ratings'] == 0 and target['review_events'] == 0 and target['pronunciation_events'] == 0:
            AUTHORIZED_TARGET.unlink()
            report['rolled_back'] = True
            report['target_exists_after'] = AUTHORIZED_TARGET.exists()
            return fail(report, '恢复后的逻辑数据不一致，且没有新的学习记录，已删除本次放入的正式文件。')
        return fail(report, '恢复后的数据库与源快照不一致，且检测到学习记录，未自动删除。')
    report['result'] = '本地恢复完成，等待正式程序读取验证'
    report['preflight_ready'] = '本地库已恢复并通过只读校验。Windows 读取验证完成前，还不能开始新的导入预检。'
    report['launch_note'] = '数据库已放入正式路径。正式程序尚未启动。'
    write_outputs(report)
    print(json.dumps({
        'restored': True,
        'logical_match': True,
        'target': str(AUTHORIZED_TARGET),
        'vocabulary': target['vocabulary'],
        'events': target['review_events'] + target['pronunciation_events'],
        'codex_unchanged': report.get('codex_sha_unchanged'),
    }, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print('Restore failed: ' + type(exc).__name__, file=sys.stderr)
        traceback = __import__('traceback')
        traceback.print_exc()
        sys.exit(1)
