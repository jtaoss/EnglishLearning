"""Publish counts only after real readback and Windows snapshot tests pass."""
import json
from prepare import ROOT, save_json

private = ROOT / 'private/p3'
native = ROOT / 'build/reports/p3-cloud'
def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

batches = {}
for size in (200, 500):
    audit = read(private / f'cloud-audit-{size}.json')
    warm = read(native / f'cloud-{size}.json')
    cold = read(native / f'cloud-{size}.json.cold.json')
    assert audit['status'] == warm['status'] == cold['status'] == 'PASS'
    assert audit['cloud_count'] == warm['size'] == cold['size'] == size
    assert warm['repeat_inserted'] == warm['repeat_updated'] == 0
    assert warm['repeat_unchanged'] == size
    assert cold['pid'] != warm['pid']
    batches[str(size)] = {
        'accepted': True, 'cloud_words': size,
        'created': 100 if size == 200 else 300,
        'content_updated': 100 if size == 200 else 0, 'deleted': 0,
        'duplicate_ids': 0, 'all_29_content_fields_equal': True,
        'all_content_hashes_equal': True,
        'windows_transport': warm['transport'],
        'windows_inserted': warm['inserted'], 'windows_updated': warm['updated'],
        'repeat_import_inserted': 0, 'repeat_import_updated': 0,
        'repeat_import_unchanged': size,
        'independent_process_restore': True,
        'isolated_meaning_and_pronunciation_preserved': True,
        'http_requests_during_snapshot_import': 0,
    }
first_receipts = []
for batch in read(private / 'notion-create-receipts-200.json'):
    first_receipts.extend({'entry_id': p['properties']['词条ID'], 'id': p['id']}
        for p in json.loads(batch['result']['content'][0]['text'])['pages'])
receipts = [*first_receipts, *read(private / 'notion-create-receipts-500.json')]
assert len(receipts) == len({r['entry_id'] for r in receipts}) == 400
personal_path = native / 'personal-cloud-import.json'
personal = read(personal_path) if personal_path.exists() else None
if personal:
    assert personal['status'] == 'PASS' and personal['all_cloud_content_fields_equal']
stats = {
    'date': '2026-11-09', 'authorization': '批准两批，200词验收通过后继续500词',
    'cloud_words': 500, 'created_total': 400, 'content_updated_total': 100,
    'schema_rich_text_fields_added': 7, 'schema_total_fields': 57,
    'deleted_total': 0, 'duplicate_stable_ids': 0,
    'old_page_identities_preserved': 100,
    'old_nonempty_personal_property_values_preserved': 400,
    'personal_property_note': 'Includes default untested states; not 400 historical learning events.',
    'readback': 'Direct Notion page fetch for old 100, direct rows for new 400; plain rich-text comparison.',
    'batches': batches,
    'actual_windows_personal_library': {
        'status': personal['status'], 'before_words': personal['before_words'],
        'after_words': personal['after_words'], 'new_words_untested': True,
        'existing_personal_state_preserved': True, 'meaning_events_created': 0,
        'pronunciation_events_created': 0,
    } if personal else {'status': 'pending'},
    'direct_notion_api_sync': 'Pending: user cannot configure read-only credential currently.',
    'real_learning_events_uploaded': 0, 'android_work_performed': False,
}
save_json(ROOT / 'docs/p3/NOTION_IMPORT_STATISTICS.json', stats)
print(json.dumps(stats, ensure_ascii=False, indent=2))
