"""Read-only preflight for an exact approved content preview. Never writes Notion."""
import argparse
import json
import pathlib

from prepare import MAPPING, PERSONAL, ROOT, digest

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--batch',type=int,choices=[200,500],required=True)
parser.add_argument('--snapshot',type=pathlib.Path,required=True,
    help='Fresh complete Notion read-only export, never credentials')
parser.add_argument('--approved-sha',default='',help='Exact preview hash explicitly approved by the user')
args=parser.parse_args()
preview=json.loads((ROOT/f'private/p3/notion-preview-{args.batch}.json').read_text(encoding='utf-8'))
saved_hash=preview.pop('sha256')
assert digest(preview)==saved_hash, 'Preview changed after hashing'
assert preview['mode']=='PREVIEW_ONLY_NOT_EXECUTED'
if args.approved_sha:
    assert args.approved_sha==saved_hash, 'Approval does not match this preview'
snapshot=json.loads(args.snapshot.read_text(encoding='utf-8'))
assert snapshot.get('has_more') is False, 'Snapshot is incomplete'
rows=snapshot['results']; by_id={r['词条ID']:r for r in rows}
assert len(by_id)==len(rows)==preview['expected_before'], 'Unexpected count or duplicate stable IDs'
assert len({r['单词'] for r in rows})==len(rows), 'Duplicate exact word keys'
allowed=set(MAPPING.values())|{'数据版本','数据哈希','导入批次'}
create_ids=set()
for creation in preview['creates']:
    entry=creation['entry_id']; props=creation['properties']
    assert entry not in by_id and entry not in create_ids, 'Create would duplicate an existing ID'
    assert props['词条ID']==entry and props['PETS3 2025收录状态']=='待核实'
    assert set(props)<=allowed and not PERSONAL.intersection(props), 'Unapproved property write'
    create_ids.add(entry)
for update in preview['updates']:
    actual=by_id[update['entry_id']]
    actual_hash=digest({name:actual.get(name) for name in [*MAPPING.values(),'数据版本','数据哈希']})
    assert actual_hash==update['precondition_hash'], 'Cloud content changed; regenerate and reapprove preview'
    assert update['page_url']==actual['url'], 'Stable ID page mapping changed'
    assert set(update['after'])<=allowed and not PERSONAL.intersection(update['after'])
    assert all((actual.get(name) or '')==(value or '') for name,value in update['before'].items()), 'Before values changed'
assert len(rows)+len(create_ids)==args.batch
print(json.dumps({'preflight':'PASS','target':args.batch,'cloud_before':len(rows),
    'creates':len(create_ids),'updates':len(preview['updates']),'deletes':0,
    'preview_sha256':saved_hash,'approval_hash_supplied':bool(args.approved_sha),
    'remote_writes_performed':0},ensure_ascii=False,indent=2))
