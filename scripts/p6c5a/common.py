"""Isolated700 scope review utilities. No database connections or Notion API."""
import collections
import copy
import csv
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/p6/p6c5a'
BASE=ROOT/'docs/p6/p6c5/core_meanings_5332_candidates.json'
FORMAL=ROOT/'docs/p5a/public/formal_learning_vocabulary.csv'
RULES=OUT/'RULES_V5_SCOPE_GUARD.md'
LAYERS=('core_meanings','extended_meanings','other_meanings')
RELATIONS=('语义等价','合理概括','范围收窄','范围扩大','语义不匹配','无法确定')

def now():return dt.datetime.now(dt.timezone.utc).isoformat()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def canonical(x):return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def require(ok,message):
    if not ok:raise ValueError(message)
def save(p,x):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);tmp=p.with_suffix(p.suffix+'.tmp')
    tmp.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');os.replace(tmp,p)
def once(p,x):
    if Path(p).exists():require(read(p)==x,'Immutable checkpoint drift: '+str(p))
    else:save(p,x)
def old_common():
    spec=importlib.util.spec_from_file_location('p6c5_read_only_common',ROOT/'scripts/p6c5/common.py')
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def protected():
    result=old_common().protected()
    for folder in ['docs/p6/p6c5','scripts/p6c5','test/p6c5']:
        for p in (ROOT/folder).rglob('*'):
            if p.is_file() and '__pycache__' not in p.parts:result[p.relative_to(ROOT).as_posix()]={'sha256':sha(p),'bytes':p.stat().st_size}
    return result
def verify_protection():
    before=read(OUT/'PRESERVATION.json')['files'];after=protected()
    drift=[p for p in set(before)|set(after) if before.get(p)!=after.get(p)]
    require(not drift,'Protected source/checkpoint/DB drift: '+','.join(drift[:10]))
    return {'unchanged':True,'checked_files':len(before),'changed':[],'method':'hashes and DB side-file metadata only; no SQL','utc':now()}
def verify_frozen():
    m=read(OUT/'RUN_MANIFEST.json')
    for p,h in m['files'].items():require(sha(ROOT/p)==h,'Frozen V5/input/prompt/code drift: '+p)
    return m
def gid(g):return g.get('sense_group_id',g.get('review_group_id'))
def baseline():return read(BASE)['records']
def working():return read(OUT/'working700.json')['records']
def evidence():return read(OUT/'evidence700.json')['headwords']

def packet(r,refs,include_candidate=True):
    result={'id':r['stable_id'],'word':r['headword'],'source_pos':r['part_of_speech'],
      'raw':r['original_meaning_zh'],'source_usage_note':r['source_fields'].get('usage_note',''),
      'senses':r['original_meanings'],'evidence':refs}
    if include_candidate:
        result['groups']=[{'id':gid(g),'layer':k,'pos':g['part_of_speech'],'text':g['display_zh'],
          'source_ids':g['source_sense_ids'],'note':g.get('usage_note',''),'evidence_ids':g['evidence_ids']}
          for k in LAYERS for g in r[k]]
        result['held']=[{'source_id':h['source_sense_id'],'reason':h.get('reason',h.get('note','evidence pending'))} for h in r['reserved_original_items']]
        result['reason']=r.get('selection_reason','')
        result['unadopted_external_candidates']=[{k:a[k] for k in ('part_of_speech','evidence_ids') if k in a}|{'text':a.get('meaning_zh',a.get('display_zh',''))} for a in r['dictionary_additions']]
    return result
