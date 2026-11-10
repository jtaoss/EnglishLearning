"""P5-C.3 final read-only preflight. No Notion writes and no SQLite changes."""
import datetime
import json
import pathlib
import sys

import preflight
import restore_personal_db as restore

FORMAL_SHA = '9965dab5fdc1d3008ae8b687d21dce18839fe0137f43579e800a180be24025eb'
SNAPSHOT_SHA = restore.EXPECTED_SHA
PROGRESS_FP = restore.P5C1_FINGERPRINT
ROOT = preflight.ROOT
BACKUPS = [
    ROOT / 'docs/p5a/public/formal_learning_vocabulary.csv',
    ROOT / 'private/p5c/backups/20261110-095221/formal_learning_vocabulary.csv',
    ROOT / 'private/p5c/backups/20261110-095221/notion_import_preview.csv',
    ROOT / 'private/p41/personal-pretrial-20261109-141933.sqlite3',
    ROOT / 'private/p5c/backups/20261110-095221/personal-pretrial-20261109-141933.sqlite3',
    restore.AUTHORIZED_TARGET,
]


def file_record(path):
    record = {'path': str(path), 'exists': path.exists()}
    if not path.exists():
        return record
    record['sha256'] = preflight.sha256(path)
    if path.suffix == '.sqlite3':
        info = restore.inspect_db(path)
        record['integrity'] = info['integrity']
        record['user_version'] = info['user_version']
        record['vocabulary'] = info['vocabulary']
        record['readable'] = info['integrity'] == 'ok'
    else:
        record['readable'] = True
    return record


def main():
    differences = []
    lists = preflight.check_lists(differences)
    db_path = restore.AUTHORIZED_TARGET
    sqlite = {'exists': db_path.exists(), 'sidecars': restore.sidecars(db_path)}
    if not db_path.exists():
        differences.append({'kind': 'sqlite_missing'})
    else:
        info = restore.inspect_db(db_path)
        sqlite.update({key: value for key, value in info.items() if key not in {'ids', 'content'}})
        sqlite['sha256'] = restore.sha256(db_path)
        if info['integrity'] != 'ok' or info['foreign_key_issues'] or info['user_version'] != 3:
            differences.append({'kind': 'sqlite_integrity'})
        if info['vocabulary'] != 500 or info['unique_ids'] != 500:
            differences.append({'kind': 'sqlite_id_count'})
        if info['progress_fingerprint'] != PROGRESS_FP or info['meaning_ratings'] or info['review_dates'] or info['pronunciation_status_set'] or info['review_events'] or info['pronunciation_events']:
            differences.append({'kind': 'sqlite_learning_state'})
        if sqlite['sha256'] != SNAPSHOT_SHA:
            differences.append({'kind': 'sqlite_hash'})
    if lists['formal_hash'] != FORMAL_SHA:
        differences.append({'kind': 'formal_hash'})
    cloud = {'content_writes': 0, 'event_uploads': 0}
    counts = {'unchanged': 0, 'new': 0, 'update': 0}
    try:
        token, data_source = preflight.read_credential()
        try:
            schema, pages, calls = preflight.notion_read(token, data_source)
        finally:
            del token
        properties = schema.get('properties') or {}
        remote = {}
        for page in pages:
            values = {}
            types = {}
            for name, prop in (page.get('properties') or {}).items():
                types[name] = prop.get('type')
                values[name] = preflight.plain(prop)
            entry_id = values.get('词条ID') or ''
            if not entry_id or entry_id in remote:
                differences.append({'kind': 'cloud_duplicate', 'entry_id': entry_id})
                continue
            remote[entry_id] = {'values': values, 'types': types}
        content_diffs = []
        for entry_id, row in lists['formal_by_id'].items():
            item = remote.get(entry_id)
            if item is None:
                counts['new'] += 1
                continue
            changed = False
            for field in lists['content_fields']:
                spec = lists['mapping'][field]
                prop = spec['notion_property']
                if item['types'].get(prop) != spec['notion_type'] or (item['values'].get(prop) or '') != (row.get(field) or ''):
                    changed = True
                    if len(content_diffs) < 20:
                        content_diffs.append({'entry_id': entry_id, 'word': row.get('word', ''), 'property': prop})
            counts['update' if changed else 'unchanged'] += 1
        unexpected = sorted(set(remote) - set(lists['formal_by_id']))
        if unexpected:
            differences.append({'kind': 'cloud_unexpected_ids', 'entry_ids': unexpected[:20]})
        if content_diffs:
            differences.append({'kind': 'content_diff', 'count_capped': len(content_diffs), 'samples': content_diffs})
        isolated = sorted(set(remote) & (lists['review_ids'] | lists['deferred_ids']))
        if isolated:
            differences.append({'kind': 'isolated_in_cloud', 'entry_ids': isolated[:20]})
        cloud.update({
            'pages': len(pages),
            'unique_ids': len(remote),
            'properties': len(properties),
            'read_requests': len(calls),
            'api_version': '2026-03-11',
        })
    except Exception as exc:
        differences.append({'kind': 'cloud_read_failed', 'error': type(exc).__name__})
        cloud['error'] = type(exc).__name__
    backups = [file_record(path) for path in BACKUPS]
    expected = {
        str(BACKUPS[0]): FORMAL_SHA,
        str(BACKUPS[1]): FORMAL_SHA,
        str(BACKUPS[3]): SNAPSHOT_SHA,
        str(BACKUPS[4]): SNAPSHOT_SHA,
        str(BACKUPS[5]): SNAPSHOT_SHA,
    }
    for record in backups:
        if not record['exists'] or not record.get('readable'):
            differences.append({'kind': 'backup_unreadable', 'path': record['path']})
        elif record['path'] in expected and record.get('sha256') != expected[record['path']]:
            differences.append({'kind': 'backup_hash', 'path': record['path']})
    if counts != {'unchanged': 500, 'new': 4832, 'update': 0} or cloud.get('pages') != 500:
        if cloud.get('pages') is not None:
            differences.append({'kind': 'import_counts', 'counts': counts, 'pages': cloud.get('pages')})
    data_ready = not differences
    report = {
        'phase': 'P5-C.3',
        'version': '0.7.0+10',
        'checked_local': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'sqlite': sqlite,
        'formal_sha256': lists['formal_hash'],
        'formal_sha_matches_p5c': lists['formal_hash'] == FORMAL_SHA,
        'checks': lists['checks'],
        'cloud': cloud,
        'counts': counts,
        'backups': backups,
        'differences': differences,
        'content_writes': 0,
        'event_uploads': 0,
        'import_started': False,
        'data_ready': data_ready,
        'import_program': {
            'vocabulary_page_create_client': False,
            'read_sync_page_size': 100,
            'read_sync_group_size': 100,
            'read_sync_max_pages': 10,
            'read_sync_spacing_ms': 350,
            'read_sync_response_limit_bytes': 2 * 1024 * 1024,
            'rate_limit': '429/529 use Retry-After up to 10 seconds and 3 attempts; otherwise the batch stops and local data stays',
            'idempotency': 'duplicate page or stable ID rejects the batch; incomplete ID return rejects the batch before commit',
            'checkpoint_resume_for_4832_creates': False,
        },
    }
    private = ROOT / 'private' / 'p5c'
    private.mkdir(parents=True, exist_ok=True)
    (private / 'final_preflight.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    write_markdown(report)
    print(json.dumps({
        'sqlite': sqlite.get('vocabulary'),
        'cloud_pages': cloud.get('pages'),
        'counts': counts,
        'differences': len(differences),
        'data_ready': data_ready,
        'writes': 0,
    }, ensure_ascii=False))
    return 0 if data_ready else 1


def write_markdown(report):
    sqlite = report['sqlite']
    counts = report['counts']
    cloud = report['cloud']
    ready = '通过' if report['data_ready'] else '未通过'
    lines = [
        '# P5-C.3 最终只读预检',
        '',
        f"版本保持 0.7.0+10。时间 {report['checked_local']}。数据预检：**{ready}**。内容写入 0，事件上传 0。",
        '',
        '## 正式 SQLite',
        '',
        f"- 文件存在：{'是' if sqlite.get('exists') else '否'}。schema {sqlite.get('user_version', '未读')}，integrity `{sqlite.get('integrity', '未读')}`，外键问题 {sqlite.get('foreign_key_issues', '未读')}。",
        f"- 词条 {sqlite.get('vocabulary', '未读')}，唯一 ID {sqlite.get('unique_ids', '未读')}。",
        f"- 非未测试评级 {sqlite.get('meaning_ratings', '未读')}，发音状态改动 {sqlite.get('pronunciation_status_set', '未读')}，复习日期 {sqlite.get('review_dates', '未读')}。",
        f"- 词义事件 {sqlite.get('review_events', '未读')}，发音事件 {sqlite.get('pronunciation_events', '未读')}。",
        f"- SHA-256 与恢复快照{'一致' if sqlite.get('sha256') == SNAPSHOT_SHA else '不一致'}。",
        '',
        '## Notion 与导入预览',
        '',
        f"- 云端实际页数 {cloud.get('pages', '未完成')}，唯一稳定 ID {cloud.get('unique_ids', '未完成')}，读取请求 {cloud.get('read_requests', '未完成')}。",
        f"- 预计保持不变 {counts['unchanged']}，更新 {counts['update']}，新增 {counts['new']}。",
        f"- 正式清单 SHA-256 `{report['formal_sha256']}`，与 P5-C 记录{'一致' if report['formal_sha_matches_p5c'] else '不一致'}。",
        f"- 待核实 {report['checks']['review']}，暂缓 {report['checks']['deferred']}，与正式清单无交集：{'是' if not any(item['kind'].endswith('isolated') or 'review' in item['kind'] or 'deferred' in item['kind'] for item in report['differences']) else '否'}。",
        '',
        '## 差异',
        '',
        '没有 ID 或 29 个内容字段差异。' if not any(item['kind'] in {'content_diff', 'cloud_duplicate', 'cloud_unexpected_ids', 'import_counts'} for item in report['differences']) else '```json\n' + json.dumps(report['differences'], ensure_ascii=False, indent=2) + '\n```',
        '',
        '## 备份',
        '',
    ]
    for record in report['backups']:
        lines.append(f"- `{record['path']}`：{'可读' if record.get('readable') else '不可读'}，SHA-256 `{record.get('sha256', '缺失')}`。")
    lines.extend([
        '',
        '## 导入程序',
        '',
        '仓库没有词库页面创建客户端。现有 Notion 适配器只允许读取数据源和查询。只读同步按 100 个 ID 分组、每页 100 条、最多 10 页，查询间隔 350 毫秒，响应上限 2 MB。429／529 按 Retry-After 处理，超过 10 秒或重试耗尽则整批停止并保留本地数据。重复页面、重复稳定 ID 或返回不完整时拒绝整批，校验后才一次提交。',
        '',
        '4,832 个新增词的断点批次、创建结果不明时的查询对账，还没有可执行程序。事件沙盒的页面创建接口不用于正式词库。',
        '',
        '## P5-C.4',
        '',
        '数据预检已通过，仍不执行正式写入。P5-C.4 需要用户单独授权，并使用带断点、幂等、限流和异常对账的写入程序。' if report['data_ready'] else '数据预检未通过，不满足 P5-C.4。',
        '',
    ])
    out = ROOT / 'docs' / 'p5c' / 'FINAL_PREFLIGHT.md'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text('\n'.join(lines), encoding='utf-8')


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print('Final preflight failed: ' + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
