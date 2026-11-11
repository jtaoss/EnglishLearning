"""P5-C.5 read-only Notion audit.

Reads the formal vocabulary with the existing read-only credential.
Backs up the personal SQLite and does not modify it.
Does not write, archive, or delete Notion pages.
Writes a private apply payload only when the cloud matches the accepted
5,332-word list and the single known blank page.
"""
import datetime
import hashlib
import json
import pathlib
import re
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request

import preflight

ROOT = pathlib.Path(__file__).resolve().parents[2]
FORMAL = ROOT / 'docs/p5a/public/formal_learning_vocabulary.csv'
REVIEWED = ROOT / 'assets/vocabulary/reviewed500.csv'
MAPPING = ROOT / 'docs/p5a/public/field_mapping.csv'
BLANK = '414cd5b5-d6b9-80db-ac03-d94e99d65e61'
SOURCE = '157d89e5-71fb-4e68-9640-1b04dbb1e627'
COLUMNS = (
    'entry_id', 'word', 'meaning_zh', 'book_category', 'source_file', 'source_id',
    'source_pdf_pages', 'source_index_pages', 'book_verification', 'meaning_review_status',
    'pets2015_status', 'pets2025_status', 'library_class', 'part_of_speech', 'usage_note',
    'lexical_sources', 'example_en', 'example_zh', 'learning_priority', 'selection_reason',
    'phonics_note', 'syllables', 'stress', 'reading_review_status', 'audio_status',
    'audio_source', 'audio_license', 'pets2015_evidence', 'pets2015_match_method',
)
SELECTS = {
    'book_category', 'book_verification', 'pets2015_status', 'pets2025_status',
    'library_class', 'learning_priority',
}
PETS2015 = {'已收录', '未直接列出', '待核实'}


class RejectRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise RuntimeError('Notion redirect rejected')


def read_rows(path):
    rows, duplicates = preflight.index_rows(preflight.read_csv(path))
    if duplicates:
        raise RuntimeError(f'{path.name} has duplicate stable IDs')
    return rows


def property_text(prop):
    kind = prop.get('type')
    if kind in ('title', 'rich_text'):
        parts = []
        for part in prop.get(kind) or []:
            text = part.get('plain_text')
            if text is None and isinstance(part.get('text'), dict):
                text = part['text'].get('content')
            parts.append(text or '')
        return ''.join(parts).strip()
    if kind == 'select':
        selected = prop.get('select') or {}
        return (selected.get('name') or '').strip()
    return None


def backup_personal(stamp_dir):
    source = preflight.DB
    record = {
        'path': str(source),
        'present': source.exists(),
        'sidecars': sorted(path.name for path in source.parent.glob(source.name + '-*')) if source.parent.exists() else [],
    }
    if not source.exists():
        return record
    destination = stamp_dir / 'english_learning_v1.sqlite3'
    reader = sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)
    writer = sqlite3.connect(destination)
    try:
        reader.execute('PRAGMA busy_timeout = 5000')
        reader.backup(writer)
    finally:
        writer.close()
        reader.close()
    with preflight.open_ro(destination) as connection:
        counts = preflight.table_counts(connection)
        vocab_ids = [row[0] for row in connection.execute('SELECT entry_id FROM vocabulary ORDER BY entry_id')]
        progress = preflight.learning_counts(connection) if 'learning_progress' in counts else []
        due = connection.execute('SELECT COUNT(*) FROM learning_progress WHERE due_utc IS NOT NULL').fetchone()[0] if 'learning_progress' in counts else None
        reviewed = connection.execute("SELECT COUNT(*) FROM learning_progress WHERE status<>'untested' OR pronunciation_status<>'未测试'").fetchone()[0] if 'learning_progress' in counts else None
        record.update({
            'bytes': source.stat().st_size,
            'sha256': preflight.sha256(destination),
            'source_sha256': preflight.sha256(source),
            'user_version': connection.execute('PRAGMA user_version').fetchone()[0],
            'integrity': connection.execute('PRAGMA integrity_check').fetchone()[0],
            'foreign_key_issues': len(connection.execute('PRAGMA foreign_key_check').fetchall()),
            'tables': counts,
            'unique_ids': len(set(vocab_ids)),
            'learning_progress_groups': progress,
            'rated_or_pronunciation_rows': reviewed,
            'review_dates': due,
            'fingerprints': {
                'learning_progress': preflight.fingerprint(connection, 'SELECT entry_id, status, pronunciation_status, review_count, last_reviewed_utc, due_utc FROM learning_progress ORDER BY entry_id'),
                'review_events': preflight.fingerprint(connection, 'SELECT event_id, entry_id, grade, reviewed_utc, due_utc FROM review_events ORDER BY event_id') if 'review_events' in counts else None,
                'pronunciation_progress': preflight.fingerprint(connection, 'SELECT entry_id, status, assessed_utc, audio_asset_id FROM pronunciation_progress ORDER BY entry_id') if 'pronunciation_progress' in counts else None,
                'pronunciation_events': preflight.fingerprint(connection, 'SELECT attempt_id, entry_id, status, audio_asset_id, assessed_utc FROM pronunciation_events ORDER BY attempt_id') if 'pronunciation_events' in counts else None,
            },
            'entry_ids': vocab_ids,
        })
    return record


def read_cloud():
    token, data_source = preflight.read_credential()
    if data_source != SOURCE:
        del token
        raise RuntimeError('Read-only credential points at a different data source')
    opener = urllib.request.build_opener(RejectRedirect)
    calls = []
    sizes = []

    def request(suffix, body=None):
        if suffix not in ('', '/query'):
            raise RuntimeError('Blocked non-read Notion path')
        method = 'GET' if body is None else 'POST'
        path = f'/v1/data_sources/{data_source}{suffix}'
        payload = None
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
                    raw = response.read()
                payload = json.loads(raw.decode('utf-8'))
                sizes.append(len(raw))
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
        calls.append({'method': method, 'path_kind': 'schema' if suffix == '' else 'query', 'read_only': True})
        if payload.get('request_status') not in (None, 'success'):
            raise RuntimeError('Notion query incomplete')
        return payload

    try:
        schema = request('')
        pages = []
        page_lengths = []
        cursor = None
        while True:
            if page_lengths:
                time.sleep(0.35)
            body = {'page_size': 100}
            if cursor:
                body['start_cursor'] = cursor
            result = request('/query', body)
            batch = result.get('results') or []
            page_lengths.append(len(batch))
            pages.extend(batch)
            print(f'read page {len(page_lengths)} rows {len(batch)} has_more {bool(result.get("has_more"))}', file=sys.stderr)
            if not result.get('has_more'):
                break
            cursor = result.get('next_cursor')
            if not cursor:
                raise RuntimeError('Notion pagination stopped without a cursor')
            if len(page_lengths) >= 80:
                raise RuntimeError('Notion pagination exceeded 80 pages')
    finally:
        del token
    return schema, pages, calls, page_lengths, sizes


def audit(schema, pages, formal, reviewed, mapping):
    stops = []
    blank = []
    cloud = {}
    seen_pages = set()
    classes = {}
    for page in pages:
        page_id = page.get('id') or ''
        if page_id in seen_pages:
            stops.append({'kind': 'duplicate_page', 'page_id': page_id})
        seen_pages.add(page_id)
        parent = ((page.get('parent') or {}).get('data_source_id') or '')
        archived = bool(page.get('archived') or page.get('is_archived') or page.get('in_trash'))
        properties = page.get('properties') or {}
        values = {}
        truncated = []
        type_errors = []
        for field, spec in mapping.items():
            prop = properties.get(spec['notion_property'])
            if not isinstance(prop, dict):
                type_errors.append(spec['notion_property'])
                continue
            if prop.get('type') != spec['notion_type']:
                type_errors.append(spec['notion_property'])
            if prop.get('has_more') is True:
                truncated.append(spec['notion_property'])
            values[field] = property_text(prop)
        entry_id = values.get('entry_id') or ''
        word = values.get('word') or ''
        if page_id == BLANK:
            blank.append({
                'page_id': page_id,
                'entry_id_empty': entry_id == '',
                'word_empty': word == '',
                'archived': archived,
                'parent_matches': parent == SOURCE,
                'library_class': values.get('library_class') or '',
            })
            continue
        if archived or parent != SOURCE or page.get('object') != 'page':
            stops.append({'kind': 'invalid_page', 'page_id': page_id})
            continue
        if not entry_id:
            stops.append({'kind': 'unexpected_blank_page', 'page_id': page_id})
            continue
        if entry_id in cloud:
            stops.append({'kind': 'duplicate_entry_id', 'entry_id': entry_id})
            continue
        if type_errors or truncated or any(values[field] is None for field in mapping):
            stops.append({'kind': 'field_shape', 'entry_id': entry_id, 'types': type_errors[:8], 'truncated': truncated[:8]})
            continue
        edited = page.get('last_edited_time') or ''
        if not re.search(r'(Z|[+-]\d{2}:\d{2})$', edited):
            stops.append({'kind': 'edited_time', 'entry_id': entry_id})
        cloud[entry_id] = {
            'page_id': page_id,
            'edited': edited,
            'fields': {field: values[field] or '' for field in COLUMNS},
        }
        classes[values.get('library_class') or ''] = classes.get(values.get('library_class') or '', 0) + 1
    if len(blank) != 1:
        stops.append({'kind': 'known_blank_page_count', 'count': len(blank)})
    elif not blank[0]['entry_id_empty'] or not blank[0]['word_empty'] or blank[0]['archived'] or not blank[0]['parent_matches']:
        stops.append({'kind': 'known_blank_page_shape', 'detail': blank[0]})
    missing = sorted(set(formal) - set(cloud))
    extra = sorted(set(cloud) - set(formal))
    if missing or extra or len(cloud) != 5332:
        stops.append({'kind': 'id_set', 'cloud': len(cloud), 'missing': len(missing), 'extra': len(extra), 'missing_sample': missing[:10], 'extra_sample': extra[:10]})
    diffs = []
    for entry_id, row in cloud.items():
        expected = formal.get(entry_id)
        if expected is None:
            continue
        fields = [field for field in COLUMNS if (row['fields'].get(field) or '') != (expected.get(field) or '').strip()]
        if fields:
            diffs.append({'entry_id': entry_id, 'word': expected.get('word'), 'fields': fields})
        if row['fields'].get('pets2015_status') not in PETS2015:
            stops.append({'kind': 'pets2015', 'entry_id': entry_id})
        if len(diffs) >= 20:
            break
    if diffs:
        stops.append({'kind': 'content_mismatch', 'samples': diffs})
    reviewed_missing = sorted(set(reviewed) - set(cloud))
    return {
        'pages': len(pages),
        'unique_pages': len(seen_pages),
        'valid_ids': len(cloud),
        'blank_pages': blank,
        'classes': classes,
        'reviewed500_missing': len(reviewed_missing),
        'stops': stops,
        'cloud': cloud,
    }


def main():
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    stamp_dir = ROOT / 'private/p5c/backups' / f'p5c5-{stamp}'
    stamp_dir.mkdir(parents=True, exist_ok=True)
    running = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq english_learning.exe', '/FO', 'CSV', '/NH'], capture_output=True, text=True, check=False)
    personal = backup_personal(stamp_dir)
    public_personal = {key: value for key, value in personal.items() if key != 'entry_ids'}
    formal = read_rows(FORMAL)
    reviewed = read_rows(REVIEWED)
    mapping_rows = preflight.read_csv(MAPPING)
    mapping = {row['csv_field']: row for row in mapping_rows if row['csv_field'] in COLUMNS}
    expected_type = lambda field: 'title' if field == 'word' else 'select' if field in SELECTS else 'rich_text'
    if set(mapping) != set(COLUMNS) or any(row['notion_type'] != expected_type(field) for field, row in mapping.items()):
        raise RuntimeError('Field mapping does not match the 29 client fields')
    schema, pages, calls, page_lengths, sizes = read_cloud()
    result = audit(schema, pages, formal, reviewed, mapping)
    cloud = result.pop('cloud')
    summary = {
        'checked_local': datetime.datetime.now().astimezone().isoformat(timespec='seconds'),
        'backup_dir': str(stamp_dir),
        'app_running': 'english_learning.exe' in running.stdout,
        'personal': public_personal,
        'formal_ids': len(formal),
        'formal_sha256': preflight.sha256(FORMAL),
        'reviewed_ids': len(reviewed),
        'schema_properties': len((schema.get('properties') or {})),
        'schema_id_matches': schema.get('id') == SOURCE,
        'read_requests': len(calls),
        'query_page_lengths': page_lengths,
        'max_response_bytes': max(sizes) if sizes else 0,
        'content_writes': 0,
        'event_uploads': 0,
        **{key: value for key, value in result.items() if key != 'stops'},
        'stop_count': len(result['stops']),
        'stops': result['stops'],
    }
    (stamp_dir / 'audit_summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    if personal.get('entry_ids') is not None:
        (stamp_dir / 'personal_entry_ids.json').write_text(json.dumps(personal['entry_ids']), encoding='utf-8')
    if not result['stops']:
        payload = {
            'source_id': SOURCE,
            'words': [
                {'page_id': cloud[entry_id]['page_id'], 'edited': cloud[entry_id]['edited'], 'fields': cloud[entry_id]['fields']}
                for entry_id in formal
            ],
        }
        destination = ROOT / 'private/p5c/p5c5-verified-payload.json'
        destination.write_text(json.dumps(payload, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
        summary['payload'] = str(destination)
        summary['payload_sha256'] = hashlib.sha256(destination.read_bytes()).hexdigest()
        summary['payload_words'] = len(payload['words'])
    print(json.dumps({key: value for key, value in summary.items() if key != 'stops'}, ensure_ascii=False, indent=2))
    if result['stops']:
        print(json.dumps(result['stops'][:8], ensure_ascii=False, indent=2))
        return 2
    return 0


def probe_client_group():
    reviewed = read_rows(REVIEWED)
    ids = list(reviewed)[:100]
    token, data_source = preflight.read_credential()
    opener = urllib.request.build_opener(RejectRedirect)
    body = {
        'page_size': 100,
        'filter': {
            'or': [
                {'property': '词条ID', 'rich_text': {'equals': entry_id}}
                for entry_id in ids
            ],
        },
    }
    req = urllib.request.Request(
        f'https://api.notion.com/v1/data_sources/{data_source}/query',
        data=json.dumps(body).encode(),
        headers={
            'Authorization': 'Bearer ' + token,
            'Notion-Version': '2026-03-11',
            'Content-Type': 'application/json',
        },
        method='POST',
    )
    del token
    with opener.open(req, timeout=60) as response:
        raw = response.read()
    payload = json.loads(raw.decode('utf-8'))
    found = []
    for page in payload.get('results') or []:
        values = {}
        for field, spec in {
            'entry_id': '词条ID',
            'word': '单词',
        }.items():
            values[field] = property_text((page.get('properties') or {}).get(spec) or {})
        found.append(values['entry_id'])
        if page.get('id') == BLANK or not values['entry_id']:
            raise RuntimeError('Client-shaped query returned a blank page')
    print(json.dumps({
        'requested': len(ids),
        'returned': len(found),
        'has_more': bool(payload.get('has_more')),
        'ids_match': set(found) == set(ids),
        'response_bytes': len(raw),
        'blank_page_included': BLANK in {page.get('id') for page in payload.get('results') or []},
        'content_writes': 0,
    }, ensure_ascii=False))


if __name__ == '__main__':
    try:
        if len(sys.argv) > 1 and sys.argv[1] == '--probe':
            probe_client_group()
        else:
            sys.exit(main())
    except Exception as error:
        print(f'audit failed: {type(error).__name__}: {error}', file=sys.stderr)
        sys.exit(1)
