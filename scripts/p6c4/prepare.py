"""Freeze protocols/sources and select exactly 100 fresh IDs; no semantic output."""
import collections
import csv
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/p6/p6c4'; PRIVATE=ROOT/'private/p6c4'

def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def canonical(x):return hashlib.sha256(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def save(path,x):path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def once(path,x):
    if path.exists():assert json.loads(path.read_text(encoding='utf-8'))==x,'Immutable checkpoint drift: '+str(path)
    else:save(path,x)

def protected():
    result={}
    for folder in ['docs/p6/p6c','docs/p6/p6c1','docs/p6/p6c2','docs/p6/p6c3',
                   'scripts/p6c','scripts/p6c1','scripts/p6c2','scripts/p6c3','test/p6c2','test/p6c3']:
        for p in (ROOT/folder).rglob('*'):
            if p.is_file() and '__pycache__' not in p.parts:result[p.relative_to(ROOT).as_posix()]={'sha256':sha(p),'bytes':p.stat().st_size}
    for folder in ['docs/p5a/public','assets/vocabulary']:
        for p in (ROOT/folder).rglob('*'):
            if p.is_file():result[p.relative_to(ROOT).as_posix()]={'sha256':sha(p),'bytes':p.stat().st_size}
    for path in ['docs/p6/P6C_CORE_MEANINGS_PILOT_REPORT.md','docs/p6/P6C1_INDEPENDENT_REVIEW_REPORT.md']:
        p=ROOT/path
        if p.exists():result[path]={'sha256':sha(p),'bytes':p.stat().st_size}
    db=Path(os.environ['APPDATA'])/'Personal/English Learning/english_learning_v1.sqlite3'
    for suffix in ['','-wal','-shm','-journal']:
        p=Path(str(db)+suffix)
        result['%APPDATA%/Personal/English Learning/english_learning_v1.sqlite3'+suffix]={
            'exists':p.exists(),'sha256':sha(p) if p.exists() else None,
            'bytes':p.stat().st_size if p.exists() else None,'mtime_ns':p.stat().st_mtime_ns if p.exists() else None}
    return result

def verify_protection():
    b=read('docs/p6/p6c4/preservation.json')['before'];a=protected()
    drift=[k for k in set(a)|set(b) if a.get(k)!=b.get(k)]
    assert not drift,'Protected input drift: '+','.join(drift)
    return {'unchanged':True,'before':b,'after':a}

def atoms(row):
    text=row['meaning_zh'];poslist=row['part_of_speech'].split('；');result=[]
    label_re=re.compile(r'^(名词|动词|形容词|副词|数词|介词|连词|代词|限定词|助动词|系动词|情态动词|感叹词)[:：]')
    for seg in re.finditer(r'[^；;]+',text):
        start=seg.start()+len(seg[0])-len(seg[0].lstrip());body=seg[0].strip();label=label_re.match(body)
        pos=label[1] if label else poslist[0] if len(poslist)==1 else None
        offset=start+(label.end() if label else 0);body=body[label.end():] if label else body
        for atom in re.finditer(r'[^，,]+',body):
            gloss=atom[0].strip();a=offset+atom.start()+len(atom[0])-len(atom[0].lstrip())
            result.append({'source_sense_id':f's{len(result)+1:03d}','text':gloss,'part_of_speech':pos,
                'pos_evidence':'explicit_gloss_label' if label else 'single_pos_field' if len(poslist)==1 else 'unresolved_multi_pos',
                'start':a,'end':a+len(gloss)})
    return result

def wn_lines():
    archive=ROOT/'private/p3/wordnet31.tar.gz'
    assert sha(archive)=='3f7d8be8ef6ecc7167d39b10d66954ec734280b5bdcd57f7d9eafe429d11c22a'
    with tarfile.open(archive) as tar:
        for m in tar.getmembers():
            if Path(m.name).name not in ('data.noun','data.verb','data.adj','data.adv'):continue
            for raw in tar.extractfile(m):
                line=raw.decode().rstrip('\r\n')
                if not line or line.startswith(' '):continue
                h,g=line.split('|',1);ps=h.split();lemmas=[ps[4+i*2].split('(')[0] for i in range(int(ps[3],16))]
                yield ps,lemmas,g.strip()

def source_packet(row,refs):
    return {'stable_id':row['entry_id'],'headword':row['word'],'part_of_speech':row['part_of_speech'],
            'original_meaning_zh':row['meaning_zh'],'original_meanings':atoms(row),
            'source_hash':canonical(row),'unfiltered_wordnet_senses':refs}

def sort_pool(pool,label):return sorted(pool,key=lambda r:hashlib.sha256(('p6c4:'+label+':'+r['entry_id']).encode()).hexdigest())

def main():
    OUT.mkdir(parents=True,exist_ok=True);PRIVATE.mkdir(parents=True,exist_ok=True)
    if (OUT/'preservation.json').exists():verify_protection()
    else:save(OUT/'preservation.json',{'method':'read-only hashes and DB side-file metadata; no SQL connection',
        'before':protected(),'git_branch':subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip(),
        'git_head':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'git_status_before':subprocess.check_output(['git','status','--short'],cwd=ROOT,text=True).splitlines()})
    old=read('docs/p6/p6c2/core_meanings_500.json')['records'];oldids={r['stable_id'] for r in old}
    with (ROOT/'docs/p5a/public/formal_learning_vocabulary.csv').open(encoding='utf-8-sig',newline='') as f:formal=list(csv.DictReader(f))
    assert len(formal)==len({r['entry_id'] for r in formal})==5332
    remaining=[r for r in formal if r['entry_id'] not in oldids];assert len(remaining)==4832
    heads={r['word'] for r in remaining};stats={w:{'synsets':0,'has_domain_label':False} for w in heads}
    restricted=re.compile(r'^\((?:law|legal|medicine|medical|comput|biolog|chem|physic|astronom|linguist|grammar|military|nautical|music|mathem|geolog|botan|zoolog)',re.I)
    for ps,lemmas,g in wn_lines():
        for w in heads.intersection(lemmas):
            stats[w]['synsets']+=1;stats[w]['has_domain_label'] |= bool(restricted.match(g))
    used=set();selected=[];strata={}
    def take(label,pool,n,forced=()):
        pool=[r for r in pool if r['entry_id'] not in used]
        byhead={r['word']:r for r in pool};chosen=[byhead[w] for w in forced]
        chosenids={r['entry_id'] for r in chosen}
        chosen+=sort_pool([r for r in pool if r['entry_id'] not in chosenids],label)[:n-len(chosen)]
        assert len(chosen)==n,(label,len(pool))
        strata[label]={'available_after_previous_strata':len(pool),'selected':n,'forced_representatives':list(forced)}
        for r in chosen:used.add(r['entry_id']);selected.append((label,r))
    seeds=set('issue charge address change turn set stand bear draw drive cover check strike press pass point right still fine firm fair fit sound spring train board order record head face ground mark form match state lead matter lie rest pool kind object sentence'.split())
    take('general_polysemy_teaching_pool',[r for r in remaining if r['word'] in seeds and stats[r['word']]['synsets']>=2],20,('issue','charge','address'))
    take('multiple_source_POS',[r for r in remaining if len(r['part_of_speech'].split('；'))>=2],20)
    context=re.compile(r'（|\(|专业|法律|医学|金融|计算机|生物|物理|化学|旧称|比喻|正式|不可数|集合|复数|尊称|贬义|英式|美式|口语|俗语|语境')
    take('context_restriction_candidates',[r for r in remaining if context.search(r['meaning_zh']) or stats[r['word']]['has_domain_label']],20)
    take('simple_source_meanings',[r for r in remaining if len(r['part_of_speech'].split('；'))==1 and len(atoms(r))<=2 and 1<=stats[r['word']]['synsets']<=3],20)
    take('hash_random_remainder',remaining,20)
    assert len(used)==100 and not used.intersection(oldids)
    plan={'count':100,'strata':strata,'method':'Disjoint strata, SHA256(p6c4:stratum:stable_id) within pool; last20 fixed-hash pseudo-random remainder.',
        'limitations':'General polysemy pool is explicitly AI pedagogical selection, not measured frequency. WordNet synset counts only indicate lexical diversity; domain label presence only suggests contextual review, not frequency or restriction of every sense.',
        'records':[{'stable_id':r['entry_id'],'headword':r['word'],'stratum':label,'book_category':r['book_category'],
                    'source_hash':canonical(r),'source_fields':r,'source_wordnet_metadata':stats[r['word']]} for label,r in selected],
        'old500_ids':sorted(oldids),'historical48_ids':[r['stable_id'] for r in read('docs/p6/p6c3/independent_quality_review.json')['inherited100_pending_queue']]}
    once(OUT/'selection_100.json',plan)
    wanted={r['headword'] for r in old}|{r['word'] for label,r in selected};refs={w:[] for w in wanted}
    for ps,lemmas,g in wn_lines():
        for w in wanted.intersection(lemmas):refs[w].append({'evidence_id':f'wn31:{ps[2]}:{ps[0]}','part_of_speech':ps[2],
            'definition_en':g,'lemmas':lemmas,'source':'https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz',
            'license':'assets/vocabulary/WORDNET_3_1_LICENSE.txt'})
    once(PRIVATE/'wordnet_selected600.json',{'headwords':refs,'archive_sha256':'3f7d8be8ef6ecc7167d39b10d66954ec734280b5bdcd57f7d9eafe429d11c22a'})
    shuffled=sorted(selected,key=lambda lr:hashlib.sha256(('blind:'+lr[1]['entry_id']).encode()).hexdigest())
    for i,name in enumerate('AB'):
        packet={'protocol':'P6C4_source_only_blind_v1','rules_path':'docs/p6/p6c4/RULES_V4_REVISED.md',
                'count':50,'records':[source_packet(r,refs[r['word']]) for label,r in shuffled[i::2]]}
        once(PRIVATE/f'blind_{name}.json',packet)
    # Regression is a non-blind source/evidence-first re-evaluation; it receives
    # old candidates and the 3 proposed fixes, not fresh100 generation outputs.
    historical={r['stable_id']:r for r in read('docs/p6/p6c3/independent_quality_review.json')['inherited100_pending_queue']}
    fixes={r['stable_id']:r for r in read('docs/p6/p6c3/REVISED_CANDIDATES.json')['records']}
    for i in range(10):
        packet=[]
        for r in old[i*50:(i+1)*50]:
            packet.append({k:r[k] for k in ['stable_id','headword','source_hash','part_of_speech','original_meaning_zh','original_meanings',
                'core_meanings','extended_meanings','other_meanings','reserved_original_items','dictionary_additions','supporting_sources','core_explanation','selection_reason','risk_level']}
                |{'unfiltered_wordnet_senses':refs[r['headword']], 'historical48':historical.get(r['stable_id']), 'C3_revision_candidate':fixes.get(r['stable_id'])})
        once(PRIVATE/f'regression_{i+1:02d}.json',{'count':50,'records':packet})
    if not (OUT/'PROTOCOL_SEAL.json').exists():
        assert not (OUT/'regression_500.json').exists() and not (OUT/'blind_test_100.json').exists()
        files=[OUT/'RULES_V4_REVISED.md',OUT/'GATE_PROTOCOL.json',OUT/'selection_100.json',Path(__file__).resolve()]
        files += [PRIVATE/f'blind_{n}.json' for n in 'AB']+[PRIVATE/f'regression_{i:02d}.json' for i in range(1,11)]
        save(OUT/'PROTOCOL_SEAL.json',{'frozen_before_generation_and_review':True,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'files':{p.relative_to(ROOT).as_posix():sha(p) for p in files}})
    else:
        for p,h in read('docs/p6/p6c4/PROTOCOL_SEAL.json')['files'].items():assert sha(ROOT/p)==h,'Protocol drift: '+p
    print(json.dumps({'fresh100':100,'old500':500,'strata':strata,'historical48':len(historical),'protocol_sealed':True},ensure_ascii=False))

if __name__=='__main__':main()
