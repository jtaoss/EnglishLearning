"""Audit a complete cloud snapshot against the reviewed prefix and prior rows."""
import argparse
import collections
import json
import re
import string

from prepare import CORE, EXTRA, MAPPING, PERSONAL, ROOT, digest, read_csv, save_json, write_csv

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--batch', type=int, choices=[200, 500], required=True)
parser.add_argument('--snapshot', required=True)
parser.add_argument('--before', required=True)
args = parser.parse_args()
snapshot = json.loads((ROOT / args.snapshot).read_text(encoding='utf-8'))
before = json.loads((ROOT / args.before).read_text(encoding='utf-8'))
def plain(value):
    if not isinstance(value, str):
        return value
    value = re.sub(r'\[([^\]]*)\]\([^\s]*\)', r'\1', value)
    return re.sub(r'\\([' + re.escape(string.punctuation) + r'])', r'\1', value)

if snapshot.get('evidence_kind', '').startswith('Direct Notion rows'):
    snapshot['results'] = [{k: plain(v) for k, v in r.items()} for r in snapshot['results']]
assert snapshot['has_more'] is False, 'Incomplete snapshot'
rows = snapshot['results']
by_id = {r['词条ID']: r for r in rows}
expected = read_csv(ROOT / 'assets/vocabulary/reviewed500.csv')[:args.batch]
assert len(by_id) == len(rows) == args.batch, 'Count or duplicate ID failure'
assert set(by_id) == {r['entry_id'] for r in expected}, 'Unexpected stable IDs'
assert len({r['单词'] for r in rows}) == args.batch, 'Duplicate head'
for row in expected:
    cloud = by_id[row['entry_id']]
    for field in CORE + EXTRA:
        assert (cloud.get(MAPPING[field]) or '') == row[field], (row['word'], field)
    assert cloud['数据哈希'] == digest({k: row[k] for k in CORE + EXTRA})
    assert cloud['数据版本'] == 'p3-20261109-v1'
    assert row['pets2025_status'] == '待核实'
    assert row['library_class'] in {'主学习', '扩展'}
allowed = set(MAPPING.values()) | {'数据版本', '数据哈希', '导入批次'}
metadata = {'createdTime', 'lastEditedTime'}
personal_values = 0
for old in before['results']:
    after = by_id[old['词条ID']]
    for name, value in old.items():
        if name == 'id' and 'id' not in after:
            assert value.replace('-', '') in after['url'], 'Page identity changed'
        elif name == 'url':
            assert re.search(r'[a-f0-9]{32}', after['url']).group() == re.search(r'[a-f0-9]{32}', value).group(), 'Page URL changed'
        elif name not in allowed | metadata:
            assert (after.get(name) or '') == (value or ''), (old['词条ID'], name, 'unapproved change')
        if name in PERSONAL and value not in (None, ''):
            personal_values += 1
report = {
    'status': 'PASS', 'batch': args.batch, 'cloud_count': len(rows),
    'unique_stable_ids': len(by_id), 'duplicate_ids': 0, 'duplicate_heads': 0,
    'content_fields_compared': len(MAPPING), 'content_matches': args.batch,
    'data_hash_matches': args.batch, 'old_pages_preserved': len(before['results']),
    'old_personal_nonempty_values_preserved': personal_values,
    'unapproved_property_changes': 0, 'all_selected_learnable': True,
    'priority_counts': dict(collections.Counter(r['学习优先级'] for r in rows)),
    'pets2025_all_pending': True, 'source': snapshot.get('evidence_kind', 'Notion MCP SQL readback'),
    'windows_direct_api_sync': 'pending credential configuration',
}
export = ROOT / f'private/p3/notion-cloud-{args.batch}.csv'
write_csv(export, [{field: by_id[r['entry_id']].get(MAPPING[field]) or ''
    for field in CORE + EXTRA} for r in expected], CORE + EXTRA)
report['actual_cloud_content_csv'] = str(export.relative_to(ROOT))
report['transport'] = 'Notion connector direct rows to CSV; no simulated Notion API pages'
save_json(ROOT / f'private/p3/cloud-audit-{args.batch}.json', report)
print(json.dumps(report, ensure_ascii=False, indent=2))
