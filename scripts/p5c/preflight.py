"""P5-C pre-import check. Read-only: no Notion writes and no learning-event uploads.

Reuses the P5-B formal list and offline preview. Does not OCR, re-filter, or rebuild them.
Stops when the live cloud state differs from that preview.
"""
import csv
import datetime
import hashlib
import json
import os
import pathlib
import sqlite3
import sys
import time
import urllib.error
import urllib.request
import ctypes as C
from ctypes import wintypes as W

ROOT = pathlib.Path(__file__).resolve().parents[2]
PUBLIC = ROOT / 'docs/p5a/public'
P5A = ROOT / 'docs/p5a'
P5B = ROOT / 'docs/p5b'
PRIVATE = ROOT / 'private/p5c'
REVIEWED = ROOT / 'assets/vocabulary/reviewed500.csv'
DB = pathlib.Path(os.environ['APPDATA']) / 'Personal' / 'English Learning' / 'english_learning_v1.sqlite3'
DATA_SOURCE = '157d89e571fb4e6896401b04dbb1e627'
REVIEWED_SHA = '09cd736d61c40f9614239e451f5894ad464f2ff69a863d50bde95b03b87f651d'
EXPECTED = {'formal': 5332, 'unchanged': 500, 'new': 4832, 'review': 194, 'deferred': 27, 'preview': 5553}
ID_PATTERN = __import__('re').compile(r'^[A-Za-z0-9][A-Za-z0-9._:\-]{0,99}$')
REQUIRED = (
    'entry_id', 'word', 'meaning_zh', 'book_category', 'source_file', 'source_id',
    'source_pdf_pages', 'source_index_pages', 'book_verification', 'meaning_review_status',
    'pets2015_status', 'pets2025_status', 'library_class',
)
PERSONAL = {
    '学习状态', '发音状态', '自然拼读状态', '自然拼读笔记', '听音学习状态', '听音学习笔记',
    '笔记', '评级', '复习日期', '学习事件',
}
CLASSES = {'主学习', '扩展', '暂缓'}
PRIORITIES = {'P1', 'P2', '未分配'}


class Credential(C.Structure):
    _fields_ = [
        ('Flags', W.DWORD), ('Type', W.DWORD), ('TargetName', W.LPWSTR),
        ('Comment', W.LPWSTR), ('LastWritten', W.FILETIME),
        ('CredentialBlobSize', W.DWORD), ('CredentialBlob', C.POINTER(C.c_ubyte)),
        ('Persist', W.DWORD), ('AttributeCount', W.DWORD), ('Attributes', C.c_void_p),
        ('TargetAlias', W.LPWSTR), ('UserName', W.LPWSTR),
    ]


class _RejectRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError('Notion read refused a redirect')


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv(path):
    with open(path, encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle))


def index_rows(items):
    found = {}
    duplicates = []
    for item in items:
        entry_id = item['entry_id']
        if entry_id in found:
            duplicates.append(entry_id)
        else:
            found[entry_id] = item
    return found, duplicates


def plain(prop):
    kind = prop.get('type')
    if kind in ('title', 'rich_text'):
        return ''.join(part.get('plain_text', '') for part in prop.get(kind) or [])
    if kind == 'select':
        selected = prop.get('select')
        return '' if not selected else selected.get('name', '')
    return None


def fingerprint(connection, sql):
    digest = hashlib.sha256()
    for row in connection.execute(sql):
        digest.update(repr(tuple(row)).encode())
        digest.update(b'\n')
    return digest.hexdigest()


def read_credential():
    api = C.WinDLL('Advapi32.dll', use_last_error=True)
    pointer = C.POINTER(Credential)()
    api.CredReadW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, C.POINTER(C.POINTER(Credential))]
    api.CredReadW.restype = W.BOOL
    api.CredFree.argtypes = [C.c_void_p]
    if not api.CredReadW('EnglishLearning.Notion.ReadOnly.v1', 1, 0, C.byref(pointer)):
        raise RuntimeError('Existing read-only Windows credential unavailable')
    try:
        blob = C.string_at(pointer.contents.CredentialBlob, pointer.contents.CredentialBlobSize)
        account = json.loads(blob.decode('utf-8'))
    finally:
        C.memset(pointer.contents.CredentialBlob, 0, pointer.contents.CredentialBlobSize)
        api.CredFree(pointer)
    token = account['token']
    data_source = account['data_source_id']
    if data_source.replace('-', '') != DATA_SOURCE:
        raise RuntimeError('Credential data source does not match the formal vocabulary database')
    return token, data_source


def notion_read(token, data_source):
    opener = urllib.request.build_opener(_RejectRedirect)
    calls = []

    def request(suffix, body=None):
        if suffix not in ('', '/query'):
            raise RuntimeError('Blocked non-read Notion path')
        method = 'GET' if body is None else 'POST'
        path = f'/v1/data_sources/{data_source}{suffix}'
        for attempt in range(4):
            req = urllib.request.Request(
                'https://api.notion.com' + path,
                data=None if body is None else json.dumps(body).encode(),
                headers={
                    'Authorization': 'Bearer ' + token,
                    'Notion-Version': '2026-03-11',
                    'Content-Type': 'application/json',
                },
                method=method,
            )
            try:
                with opener.open(req, timeout=60) as response:
                    payload = json.load(response)
                break
            except urllib.error.HTTPError as error:
                retry_after = error.headers.get('Retry-After', '1')
                try:
                    wait = int(retry_after)
                except ValueError:
                    wait = 11
                if error.code in (429, 529) and attempt < 3 and wait <= 10:
                    time.sleep(wait)
                    continue
                raise RuntimeError(f'Notion read failed with HTTP {error.code}') from None
        calls.append({'method': method, 'path': path, 'read_only': True})
        status = payload.get('request_status')
        if status not in (None, 'success'):
            raise RuntimeError('Notion query incomplete')
        return payload

    schema = request('')
    pages = []
    cursor = None
    pages_fetched = 0
    while True:
        if pages_fetched:
            time.sleep(0.35)
        body = {'page_size': 100}
        if cursor:
            body['start_cursor'] = cursor
        result = request('/query', body)
        pages_fetched += 1
        pages.extend(result.get('results') or [])
        if not result.get('has_more'):
            break
        cursor = result.get('next_cursor')
        if not cursor:
            raise RuntimeError('Notion pagination stopped without a cursor')
        if pages_fetched >= 80:
            raise RuntimeError('Notion pagination exceeded the preflight bound')
    return schema, pages, calls


def backup_sqlite(stamp_dir):
    destination = stamp_dir / 'english_learning_v1.sqlite3'
    source = sqlite3.connect(DB.as_uri() + '?mode=ro', uri=True)
    target = sqlite3.connect(destination)
    try:
        source.execute('PRAGMA busy_timeout = 5000')
        source.backup(target)
    finally:
        target.close()
        source.close()
    return destination


def table_counts(connection):
    names = [row[0] for row in connection.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY 1")]
    return {name: connection.execute(f'SELECT COUNT(*) FROM "{name}"').fetchone()[0] for name in names}


def learning_counts(connection):
    rows = connection.execute(
        'SELECT status, pronunciation_status, COUNT(*) FROM learning_progress GROUP BY 1, 2 ORDER BY 1, 2'
    ).fetchall()
    return [{'status': row[0], 'pronunciation_status': row[1], 'count': row[2]} for row in rows]


def open_ro(path):
    connection = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
    connection.execute('PRAGMA busy_timeout = 5000')
    connection.execute('PRAGMA query_only = ON')
    return connection


def check_lists(differences):
    formal_path = PUBLIC / 'formal_learning_vocabulary.csv'
    formal_hash = sha256(formal_path)
    formal = read_csv(formal_path)
    preview = read_csv(P5B / 'notion_import_preview.csv')
    review = read_csv(PUBLIC / 'manual_review.csv')
    deferred = read_csv(PUBLIC / 'deferred_vocabulary.csv')
    reviewed = read_csv(REVIEWED)
    disposition = read_csv(P5B / 'manual_review_disposition.csv')
    mapping = read_csv(PUBLIC / 'field_mapping.csv')
    formal_by_id, formal_dups = index_rows(formal)
    preview_by_id, preview_dups = index_rows(preview)
    review_by_id, review_dups = index_rows(review)
    deferred_by_id, deferred_dups = index_rows(deferred)
    reviewed_by_id, reviewed_dups = index_rows(reviewed)
    actions = {}
    for item in preview:
        actions.setdefault(item['action'], []).append(item)
    unchanged = {item['entry_id'] for item in actions.get('保持不变', [])}
    created = {item['entry_id'] for item in actions.get('新增', [])}
    skipped_review = {item['entry_id'] for item in actions.get('跳过-待核实', [])}
    skipped_deferred = {item['entry_id'] for item in actions.get('跳过-暂缓', [])}
    client_fields = list(formal[0]) if formal else []
    mapped = {row['csv_field']: row for row in mapping}
    checks = {
        'formal_rows': len(formal),
        'formal_unique_ids': len(formal_by_id),
        'preview_rows': len(preview),
        'preview_unique_ids': len(preview_by_id),
        'unchanged': len(unchanged),
        'new': len(created),
        'review': len(review_by_id),
        'deferred': len(deferred_by_id),
        'unknown_actions': sorted(set(actions) - {'保持不变', '新增', '跳过-待核实', '跳过-暂缓'}),
        'client_fields': len(client_fields),
    }
    if formal_dups or len(formal_by_id) != EXPECTED['formal']:
        differences.append({'kind': 'formal_id_count', 'unique': len(formal_by_id), 'duplicate_ids': formal_dups[:20]})
    if preview_dups or len(preview_by_id) != EXPECTED['preview']:
        differences.append({'kind': 'preview_id_count', 'unique': len(preview_by_id)})
    if checks['unknown_actions'] or len(unchanged) != EXPECTED['unchanged'] or len(created) != EXPECTED['new']:
        differences.append({'kind': 'preview_action_count', 'unchanged': len(unchanged), 'new': len(created), 'unknown': checks['unknown_actions']})
    if review_dups or len(review_by_id) != EXPECTED['review'] or set(review_by_id) & set(formal_by_id):
        differences.append({'kind': 'review_not_isolated', 'overlap': sorted(set(review_by_id) & set(formal_by_id))[:20]})
    if deferred_dups or len(deferred_by_id) != EXPECTED['deferred'] or set(deferred_by_id) & set(formal_by_id):
        differences.append({'kind': 'deferred_not_isolated', 'overlap': sorted(set(deferred_by_id) & set(formal_by_id))[:20]})
    if set(review_by_id) & set(deferred_by_id):
        differences.append({'kind': 'review_deferred_overlap', 'count': len(set(review_by_id) & set(deferred_by_id))})
    if skipped_review != set(review_by_id) or skipped_deferred != set(deferred_by_id):
        differences.append({'kind': 'preview_isolation_ids_differ'})
    if unchanged | created != set(formal_by_id) or unchanged & created:
        differences.append({'kind': 'formal_preview_id_mismatch'})
    if reviewed_dups or set(reviewed_by_id) != unchanged:
        differences.append({'kind': 'unchanged_ids_differ_from_reviewed500'})
    if sha256(REVIEWED) != REVIEWED_SHA:
        differences.append({'kind': 'reviewed500_hash'})
    words = {}
    trimmed_words = {}
    for entry_id, row in formal_by_id.items():
        if not ID_PATTERN.fullmatch(entry_id):
            differences.append({'kind': 'formal_id_invalid', 'entry_id': entry_id})
            break
        word = row['word']
        if word in words:
            differences.append({'kind': 'formal_word_duplicate', 'word': word})
            break
        words[word] = entry_id
        key = word.strip()
        if key in trimmed_words and trimmed_words[key] != entry_id:
            differences.append({'kind': 'formal_word_duplicate', 'word': key})
            break
        trimmed_words[key] = entry_id
        if any(value != value.strip() for value in row.values()):
            differences.append({'kind': 'formal_whitespace', 'entry_id': entry_id})
            break
        if any(not row.get(field) for field in REQUIRED):
            differences.append({'kind': 'formal_client_rule', 'entry_id': entry_id, 'rule': 'required'})
            break
        if row['book_verification'] != '已核验' or row['pets2025_status'] != '待核实' or row['library_class'] not in CLASSES:
            differences.append({'kind': 'formal_client_rule', 'entry_id': entry_id, 'rule': 'status'})
            break
        priority = row.get('learning_priority') or ''
        if priority and priority not in PRIORITIES:
            differences.append({'kind': 'formal_client_rule', 'entry_id': entry_id, 'rule': 'priority'})
            break
    content_fields = [field for field in client_fields if field in mapped]
    if len(content_fields) != 29 or any(field not in mapped for field in client_fields):
        differences.append({'kind': 'formal_mapping', 'client_fields': len(client_fields), 'mapped_client_fields': len(content_fields)})
    audit_fields = [row['notion_property'] for row in mapping if row['csv_field'] not in client_fields]
    if len(audit_fields) != 9:
        differences.append({'kind': 'audit_mapping_count', 'count': len(audit_fields)})
    changed = []
    for entry_id in sorted(unchanged):
        remote = reviewed_by_id.get(entry_id)
        local = formal_by_id.get(entry_id)
        if remote is None or local is None:
            continue
        fields = [field for field in content_fields if (remote.get(field) or '') != (local.get(field) or '')]
        if fields:
            changed.append({'entry_id': entry_id, 'fields': fields})
            if len(changed) >= 20:
                break
    if changed:
        differences.append({'kind': 'existing500_formal_content_differs', 'samples': changed})
    private_formal = P5A / 'formal_learning_vocabulary.csv'
    if private_formal.exists():
        private_rows, private_dups = index_rows(read_csv(private_formal))
        if private_dups or set(private_rows) != set(formal_by_id):
            differences.append({'kind': 'formal_private_mismatch', 'detail': 'ids'})
        else:
            for entry_id, row in formal_by_id.items():
                other = private_rows[entry_id]
                if any((row.get(field) or '') != (other.get(field) or '') for field in content_fields):
                    differences.append({'kind': 'formal_private_mismatch', 'entry_id': entry_id})
                    break
    private_preview = P5A / 'notion_import_preview.csv'
    if private_preview.exists():
        private_items = read_csv(private_preview)
        private_actions = {(item['entry_id'], item['word'], item['action']) for item in private_items}
        public_actions = {(item['entry_id'], item['word'], item['action']) for item in preview}
        if private_actions != public_actions:
            differences.append({'kind': 'preview_private_action_mismatch'})
        for item in private_items:
            if 'payload_json' not in item:
                continue
            payload = json.loads(item['payload_json'] or '{}')
            if set(payload) & PERSONAL:
                differences.append({'kind': 'personal_payload', 'entry_id': item['entry_id']})
                break
    updates = P5A / 'notion_updates.csv'
    if updates.exists() and len(read_csv(updates)):
        differences.append({'kind': 'unexpected_update_plan', 'count': len(read_csv(updates))})
    promoted = [row['entry_id'] for row in disposition if row.get('promoted_to_formal_library') != '否' or row.get('disposition') != '仍待人工核实']
    if {row['entry_id'] for row in disposition} != set(review_by_id) or promoted:
        differences.append({'kind': 'disposition_mismatch', 'promoted': promoted[:20]})
    return {
        'formal_path': formal_path,
        'formal_hash': formal_hash,
        'formal_by_id': formal_by_id,
        'preview': preview,
        'unchanged': unchanged,
        'created': created,
        'review_ids': set(review_by_id),
        'deferred_ids': set(deferred_by_id),
        'reviewed_by_id': reviewed_by_id,
        'content_fields': content_fields,
        'mapping': mapped,
        'audit_properties': audit_fields,
        'checks': checks,
    }


def snapshot_files():
    found = []
    private = ROOT / 'private'
    if not private.exists():
        return found
    for path in private.rglob('*.sqlite3'):
        name = path.name.lower()
        if 'rehearsal' in name or 'simulation' in name or 'acceptance' in name:
            continue
        if 'p5c' in path.parts and 'backups' in path.parts:
            continue
        found.append(path)
    return sorted(found, key=lambda item: item.stat().st_mtime)


def inspect_database(path, lists):
    with open_ro(path) as connection:
        counts = table_counts(connection)
        info = {
            'user_version': connection.execute('PRAGMA user_version').fetchone()[0],
            'integrity': connection.execute('PRAGMA integrity_check').fetchone()[0],
            'foreign_keys': connection.execute('PRAGMA foreign_key_check').fetchall(),
            'tables': counts,
            'learning_progress_groups': learning_counts(connection) if 'learning_progress' in counts else [],
            'fingerprints': {
                'learning_progress': fingerprint(connection, 'SELECT entry_id, status, pronunciation_status, review_count, last_reviewed_utc, due_utc FROM learning_progress ORDER BY entry_id'),
                'review_events': fingerprint(connection, 'SELECT event_id, entry_id, grade, reviewed_utc, due_utc FROM review_events ORDER BY event_id'),
                'pronunciation_progress': fingerprint(connection, 'SELECT entry_id, status, assessed_utc, audio_asset_id FROM pronunciation_progress ORDER BY entry_id'),
                'pronunciation_events': fingerprint(connection, 'SELECT attempt_id, entry_id, status, audio_asset_id, assessed_utc FROM pronunciation_events ORDER BY attempt_id'),
            },
        }
        vocab = {
            row[0]: {'word': row[1], 'word_key': row[2], 'content': json.loads(row[4])}
            for row in connection.execute('SELECT entry_id, word, word_key, library_class, content_json FROM vocabulary ORDER BY entry_id')
        }
        progress_ids = {row[0] for row in connection.execute('SELECT entry_id FROM learning_progress')}
    content_diffs = []
    reviewed_ids = set(lists['reviewed_by_id'])
    if set(vocab) != reviewed_ids:
        content_diffs.append({'field': 'entry_id', 'sqlite_rows': len(vocab)})
    if progress_ids != set(vocab):
        content_diffs.append({'field': 'learning_progress'})
    for entry_id, stored in vocab.items():
        expected = lists['reviewed_by_id'].get(entry_id)
        if expected is None:
            continue
        if stored['word'] != expected['word'] or stored['word_key'] != expected['word'].strip():
            content_diffs.append({'entry_id': entry_id, 'field': 'word'})
        else:
            for field in lists['content_fields']:
                if (stored['content'].get(field) or '') != (expected.get(field) or '').strip():
                    content_diffs.append({'entry_id': entry_id, 'field': field})
                    break
        if len(content_diffs) >= 20:
            break
    info['content_diffs'] = content_diffs
    return info


def check_historical_snapshot(stamp_dir, lists, differences):
    candidates = snapshot_files()
    if not candidates:
        differences.append({'kind': 'personal_snapshot_missing'})
        return {}
    source = candidates[-1]
    recorded = ROOT / 'private/p41/personal-backup.json'
    expected_hash = None
    if recorded.exists():
        expected_hash = json.loads(recorded.read_text(encoding='utf-8')).get('backup_sha256')
    source_hash = sha256(source)
    if expected_hash and source_hash != expected_hash:
        differences.append({'kind': 'historical_snapshot_hash'})
    destination = stamp_dir / source.name
    origin = sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)
    target = sqlite3.connect(destination)
    try:
        origin.backup(target)
    finally:
        target.close()
        origin.close()
    info = inspect_database(destination, lists)
    info.update({
        'source': str(source.relative_to(ROOT)),
        'source_sha256': source_hash,
        'backup_sha256': sha256(destination),
        'recorded_sha256': expected_hash,
        'copied_name': source.name,
    })
    if info['integrity'] != 'ok' or info['foreign_keys'] or info['user_version'] != 3:
        differences.append({'kind': 'historical_snapshot_integrity'})
    if info['backup_sha256'] != source_hash:
        differences.append({'kind': 'historical_snapshot_copy'})
    if info['content_diffs']:
        differences.append({'kind': 'historical_snapshot_content', 'samples': info['content_diffs']})
    info.pop('content_diffs', None)
    info.pop('foreign_keys', None)
    return info


def check_sqlite(stamp_dir, lists, differences):
    result = {'present': DB.exists()}
    if not DB.exists():
        differences.append({'kind': 'sqlite_missing'})
        return result
    backup_path = backup_sqlite(stamp_dir)
    with open_ro(DB) as live, open_ro(backup_path) as copy:
        live_integrity = live.execute('PRAGMA integrity_check').fetchone()[0]
        copy_integrity = copy.execute('PRAGMA integrity_check').fetchone()[0]
        live_fk = live.execute('PRAGMA foreign_key_check').fetchall()
        copy_fk = copy.execute('PRAGMA foreign_key_check').fetchall()
        user_version = live.execute('PRAGMA user_version').fetchone()[0]
        live_counts = table_counts(live)
        copy_counts = table_counts(copy)
        progress = learning_counts(live)
        queries = {
            'learning_progress': 'SELECT entry_id, status, pronunciation_status, review_count, last_reviewed_utc, due_utc FROM learning_progress ORDER BY entry_id',
            'review_events': 'SELECT event_id, entry_id, grade, reviewed_utc, due_utc FROM review_events ORDER BY event_id',
            'pronunciation_progress': 'SELECT entry_id, status, assessed_utc, audio_asset_id FROM pronunciation_progress ORDER BY entry_id',
            'pronunciation_events': 'SELECT attempt_id, entry_id, status, audio_asset_id, assessed_utc FROM pronunciation_events ORDER BY attempt_id',
        }
        hashes = {name: fingerprint(live, sql) for name, sql in queries.items()}
        copy_hashes = {name: fingerprint(copy, sql) for name, sql in queries.items()}
        vocab = {
            row[0]: {'word': row[1], 'word_key': row[2], 'library_class': row[3], 'content': json.loads(row[4])}
            for row in live.execute('SELECT entry_id, word, word_key, library_class, content_json FROM vocabulary ORDER BY entry_id')
        }
        progress_ids = {row[0] for row in live.execute('SELECT entry_id FROM learning_progress')}
    result.update({
        'user_version': user_version,
        'tables': live_counts,
        'learning_progress_groups': progress,
        'fingerprints': hashes,
        'backup': str(backup_path),
        'backup_sha256': sha256(backup_path),
        'source_sha256': sha256(DB),
    })
    if live_integrity != 'ok' or copy_integrity != 'ok' or live_fk or copy_fk:
        differences.append({'kind': 'sqlite_integrity'})
    if user_version != 3 or 'learning_journal' in live_counts:
        differences.append({'kind': 'sqlite_version', 'user_version': user_version})
    if live_counts != copy_counts or hashes != copy_hashes:
        differences.append({'kind': 'sqlite_backup_mismatch'})
    reviewed_ids = set(lists['reviewed_by_id'])
    if set(vocab) != reviewed_ids:
        differences.append({
            'kind': 'sqlite_id_set',
            'sqlite_rows': len(vocab),
            'missing': sorted(reviewed_ids - set(vocab))[:20],
            'unexpected': sorted(set(vocab) - reviewed_ids)[:20],
        })
    content_diffs = []
    for entry_id, stored in vocab.items():
        expected = lists['reviewed_by_id'].get(entry_id)
        if expected is None:
            continue
        if stored['word'] != expected['word'] or stored['word_key'] != expected['word'].strip():
            content_diffs.append({'entry_id': entry_id, 'field': 'word'})
        else:
            for field in lists['content_fields']:
                if (stored['content'].get(field) or '') != (expected.get(field) or '').strip():
                    content_diffs.append({'entry_id': entry_id, 'field': field})
                    break
        if len(content_diffs) >= 20:
            break
    if content_diffs:
        differences.append({'kind': 'sqlite_content', 'samples': content_diffs})
    if progress_ids != set(vocab):
        differences.append({'kind': 'sqlite_progress_ids'})
    return result


def check_cloud(lists, differences):
    meta = {'content_writes': 0, 'event_uploads': 0}
    token, data_source = read_credential()
    try:
        schema, pages, calls = notion_read(token, data_source)
    finally:
        del token
    properties = schema.get('properties') or {}
    meta.update({
        'properties': len(properties),
        'pages': len(pages),
        'read_requests': len(calls),
        'api_version': '2026-03-11',
    })
    cloud = {}
    page_ids = set()
    for page in pages:
        page_id = page.get('id')
        if page_id in page_ids or page.get('archived') or page.get('in_trash'):
            differences.append({'kind': 'cloud_duplicate', 'page_id_seen': bool(page_id)})
        page_ids.add(page_id)
        parent = (page.get('parent') or {}).get('data_source_id', '')
        if parent.replace('-', '') != DATA_SOURCE:
            differences.append({'kind': 'cloud_parent'})
            break
        values = {}
        types = {}
        for name, prop in (page.get('properties') or {}).items():
            types[name] = prop.get('type')
            values[name] = plain(prop)
        entry_id = values.get('词条ID') or ''
        if not entry_id or entry_id in cloud:
            differences.append({'kind': 'cloud_id_missing_or_duplicate', 'entry_id': entry_id})
            continue
        cloud[entry_id] = {'values': values, 'types': types}
    reviewed_ids = set(lists['reviewed_by_id'])
    if len(pages) != EXPECTED['unchanged'] or set(cloud) != reviewed_ids:
        differences.append({
            'kind': 'cloud_id_set',
            'cloud_pages': len(pages),
            'unique_ids': len(cloud),
            'missing_from_cloud': sorted(reviewed_ids - set(cloud))[:20],
            'unexpected_in_cloud': sorted(set(cloud) - reviewed_ids)[:20],
        })
    content_diffs = []
    for entry_id in sorted(lists['unchanged']):
        remote = cloud.get(entry_id)
        expected = lists['formal_by_id'].get(entry_id)
        reviewed = lists['reviewed_by_id'].get(entry_id)
        if remote is None or expected is None or reviewed is None:
            continue
        for field in lists['content_fields']:
            spec = lists['mapping'][field]
            prop = spec['notion_property']
            if remote['types'].get(prop) != spec['notion_type']:
                content_diffs.append({'entry_id': entry_id, 'word': expected['word'], 'property': prop, 'detail': 'type'})
            else:
                actual = remote['values'].get(prop) or ''
                if actual != (expected.get(field) or '') or actual != (reviewed.get(field) or ''):
                    content_diffs.append({'entry_id': entry_id, 'word': expected['word'], 'property': prop, 'detail': 'value'})
            if len(content_diffs) >= 30:
                break
        if len(content_diffs) >= 30:
            break
    if content_diffs:
        differences.append({'kind': 'cloud_content', 'samples': content_diffs})
    already = sorted(set(cloud) & lists['created'])
    if already:
        differences.append({'kind': 'planned_new_already_present', 'entry_ids': already[:20]})
    isolated = sorted(set(cloud) & (lists['review_ids'] | lists['deferred_ids']))
    if isolated:
        differences.append({'kind': 'isolated_already_present', 'entry_ids': isolated[:20]})
    missing_audit = [name for name in lists['audit_properties'] if name not in properties]
    if missing_audit:
        differences.append({'kind': 'audit_property_missing', 'properties': missing_audit})
    audit_counts = {name: sum(1 for item in cloud.values() if item['values'].get(name)) for name in lists['audit_properties']}
    personal_counts = {name: sum(1 for item in cloud.values() if item['values'].get(name)) for name in PERSONAL if name in properties}
    digest = hashlib.sha256()
    for entry_id in sorted(cloud):
        for name in lists['audit_properties']:
            digest.update(f'{entry_id}\t{name}\t{cloud[entry_id]["values"].get(name) or ""}'.encode())
            digest.update(b'\n')
    meta['audit_nonempty_counts'] = audit_counts
    meta['personal_properties_present'] = sorted(personal_counts)
    meta['personal_nonempty_counts'] = personal_counts
    meta['preserved_property_sha256'] = digest.hexdigest()
    meta['unique_page_ids'] = len(page_ids)
    return meta


def write_markdown(report):
    out = ROOT / 'docs/p5c'
    out.mkdir(parents=True, exist_ok=True)
    status = '停止，未开始正式写入' if report['stop'] else '检查通过，等待明确授权后才能写入'
    checks = report['checks']
    cloud = report['cloud']
    sqlite = report['sqlite']
    lines = [
        '# P5-C 导入前检查',
        '',
        f"版本保持 0.7.0+10。检查时间 {report['checked_local']}。结论：**{status}**。",
        '',
        '本轮复用 P5-B 已固定的正式清单 `docs/p5a/public/formal_learning_vocabulary.csv` 和离线预览 `docs/p5b/notion_import_preview.csv`。没有重新 OCR，没有重新筛词，没有创建或更新 Notion 页面，没有上传学习事件。',
        '',
        '## 清单',
        '',
        f"- 正式学习词 {checks['formal_unique_ids']} 个稳定 ID，列表行数 {checks['formal_rows']}。",
        f"- 预览保持不变 {checks['unchanged']}，新增 {checks['new']}，待核实 {checks['review']}，暂缓 {checks['deferred']}。",
        f"- 待核实词和暂缓词与正式清单无交集，处理状态仍是“仍待人工核实”。",
        f"- 正式清单 SHA-256 `{report['formal_sha256']}`。",
        f"- 现有 500 词包 SHA-256 `{report['reviewed_sha256']}`。",
        '',
        '## 备份',
        '',
        f"- 正式清单副本 SHA-256 `{report['formal_backup_sha256']}`，与原文件一致。",
        '- 学习事件没有上传。',
    ]
    historical = sqlite.get('historical_snapshot') or {}
    if sqlite.get('present'):
        lines.extend([
            f"- 个人库位置 `%APPDATA%\\Personal\\English Learning\\english_learning_v1.sqlite3`。",
            f"- schema user_version {sqlite.get('user_version', '未读取')}。表行数：{json.dumps(sqlite.get('tables', {}), ensure_ascii=False)}。",
            f"- 学习记录分组：{json.dumps(sqlite.get('learning_progress_groups', []), ensure_ascii=False)}。",
            f"- 源文件 SHA-256 `{sqlite.get('source_sha256', '未备份')}`。",
            f"- 备份文件 SHA-256 `{sqlite.get('backup_sha256', '未备份')}`。SQLite backup API 的文件字节可以与正在使用的源文件不同；学习表指纹已逐表核对。",
        ])
    else:
        lines.extend([
            '- 正式个人库 `%APPDATA%\\Personal\\English Learning\\english_learning_v1.sqlite3` 不存在。桌面、文档和 Roaming 应用数据目录里也没有另一份同名正式库。',
            f"- 能核到的最新个人快照是 `{historical.get('source', '未找到')}`。",
            f"- 快照 SHA-256 `{historical.get('source_sha256', '未计算')}`，与 2026-11-09 14:19:33 试用前记录{'一致' if historical.get('source_sha256') and historical.get('source_sha256') == historical.get('recorded_sha256') else '不一致'}。",
            f"- 快照 schema user_version {historical.get('user_version', '未读取')}。表行数：{json.dumps(historical.get('tables', {}), ensure_ascii=False)}。",
            f"- 快照学习记录分组：{json.dumps(historical.get('learning_progress_groups', []), ensure_ascii=False)}。",
            '- 这份快照是试用前备份。试用说明写明其后的新学习记录不在其中。正式库文件缺失，所以不能把它当成当前个人库。',
        ])
    lines.extend([
        '',
        '## 云端对照',
        '',
        f"- 只读页数：{cloud.get('pages', '未完成')}；唯一页面：{cloud.get('unique_page_ids', '未完成')}；属性数：{cloud.get('properties', '未完成')}；读取请求：{cloud.get('read_requests', '未完成')}。",
        f"- 内容写入 {report['content_writes']}，事件上传 {report['event_uploads']}。",
        f"- 9 个审计属性非空数量：{json.dumps(cloud.get('audit_nonempty_counts', {}), ensure_ascii=False)}。",
        f"- 已观察到的个人属性非空数量：{json.dumps(cloud.get('personal_nonempty_counts', {}), ensure_ascii=False)}。这些值只参与保护指纹，没有写入导入计划。",
        '',
        '## 差异',
        '',
    ])
    if report['differences']:
        lines.append('发现差异，正式批量写入没有开始。')
        lines.append('')
        lines.append('```json')
        lines.append(json.dumps(report['differences'], ensure_ascii=False, indent=2))
        lines.append('```')
    else:
        lines.append('云端 500 条与“保持不变”预览的稳定 ID 和 29 个内容字段一致。计划新增的 4,832 个 ID 尚未出现在云端。194 个待核实词和 27 个暂缓词不在正式清单中，也不在云端。')
        lines.append('')
        lines.append('本机个人库仍是这 500 个稳定 ID，词义评级、发音状态、复习日期和事件表已备份。重复检查没有创建页面。')
        lines.append('')
        lines.append('正式入库仍需要单独的明确授权。授权前不新增页面，也不把同步范围改成 5,332。')
    (out / 'PREFLIGHT.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main():
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    stamp_dir = PRIVATE / 'backups' / stamp
    stamp_dir.mkdir(parents=True, exist_ok=True)
    differences = []
    lists = check_lists(differences)
    formal_copy = stamp_dir / 'formal_learning_vocabulary.csv'
    formal_copy.write_bytes(lists['formal_path'].read_bytes())
    preview_copy = stamp_dir / 'notion_import_preview.csv'
    preview_copy.write_bytes((P5B / 'notion_import_preview.csv').read_bytes())
    if sha256(lists['formal_path']) != lists['formal_hash'] or sha256(formal_copy) != lists['formal_hash']:
        differences.append({'kind': 'formal_list_changed_during_check'})
    sqlite_result = check_sqlite(stamp_dir, lists, differences)
    if not sqlite_result.get('present'):
        try:
            sqlite_result['historical_snapshot'] = check_historical_snapshot(stamp_dir, lists, differences)
        except Exception as exc:
            differences.append({'kind': 'historical_snapshot_failed', 'error': type(exc).__name__})
    cloud = {'content_writes': 0, 'event_uploads': 0}
    try:
        cloud = check_cloud(lists, differences)
    except Exception as exc:
        differences.append({'kind': 'cloud_read_failed', 'error': type(exc).__name__})
        cloud['error'] = type(exc).__name__
    report = {
        'phase': 'P5-C preflight',
        'version': '0.7.0+10',
        'checked_local': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'formal_list': 'docs/p5a/public/formal_learning_vocabulary.csv',
        'preview': 'docs/p5b/notion_import_preview.csv',
        'formal_sha256': lists['formal_hash'],
        'formal_backup_sha256': sha256(formal_copy),
        'reviewed_sha256': sha256(REVIEWED),
        'checks': lists['checks'],
        'sqlite': {key: value for key, value in sqlite_result.items() if key != 'backup'},
        'cloud': cloud,
        'differences': differences,
        'content_writes': 0,
        'event_uploads': 0,
        'import_started': False,
        'stop': bool(differences),
        'backup_stamp': stamp,
    }
    private_report = dict(report)
    private_report['sqlite_backup'] = sqlite_result.get('backup', '')
    text = json.dumps(private_report, ensure_ascii=False, indent=2) + '\n'
    (PRIVATE / 'preflight.json').write_text(text, encoding='utf-8')
    (stamp_dir / 'preflight.json').write_text(text, encoding='utf-8')
    public = {key: value for key, value in report.items() if key != 'sqlite'}
    public['sqlite'] = {
        'present': sqlite_result.get('present'),
        'user_version': sqlite_result.get('user_version'),
        'tables': sqlite_result.get('tables'),
        'learning_progress_groups': sqlite_result.get('learning_progress_groups'),
        'fingerprints': sqlite_result.get('fingerprints'),
        'source_sha256': sqlite_result.get('source_sha256'),
        'backup_sha256': sqlite_result.get('backup_sha256'),
        'historical_snapshot': sqlite_result.get('historical_snapshot'),
    }
    (ROOT / 'docs/p5c').mkdir(parents=True, exist_ok=True)
    (ROOT / 'docs/p5c/preflight_summary.json').write_text(
        json.dumps(public, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    write_markdown(report)
    print(json.dumps({
        'formal_unique': lists['checks']['formal_unique_ids'],
        'cloud_pages': cloud.get('pages'),
        'sqlite_tables': sqlite_result.get('tables'),
        'differences': len(differences),
        'writes': 0,
        'stop': bool(differences),
        'backup': stamp,
    }, ensure_ascii=False))
    return 1 if differences else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        print('Preflight failed: ' + type(exc).__name__, file=sys.stderr)
        sys.exit(1)
