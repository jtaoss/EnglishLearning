"""Freeze P6-C.2 and create source-only packets for fresh-context reviewers."""
import collections
import hashlib
import json
import pathlib
import sys
import tarfile

ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/p6/p6c3'
PRIVATE=ROOT/'private/p6c3'
sys.path.insert(0,str(ROOT/'scripts/p6c2'))
from prepare import protected_state,sha


def load(path):return json.loads((ROOT/path).read_text(encoding='utf-8-sig'))
def save(path,obj):path.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def write_once(path,obj):
    if path.exists():assert json.loads(path.read_text(encoding='utf-8'))==obj,'Frozen input drift'
    else:save(path,obj)


def state():
    s=protected_state()
    for base in ['docs/p6/p6c2','scripts/p6c2','test/p6c2']:
        for p in (ROOT/base).rglob('*'):
            if p.is_file() and '__pycache__' not in p.parts:
                s[p.relative_to(ROOT).as_posix()]={'sha256':sha(p),'bytes':p.stat().st_size}
    return s


def preservation_check():
    """Fail on English/source/DB drift; disclose concurrent out-of-scope work.

    A Japanese module is being edited independently in this shared worktree.
    Never absorb its new files into the frozen baseline or modify/restore them.
    """
    before=load('docs/p6/p6c3/preservation.json')['before']
    after=state()
    changes={k:{'before':before.get(k),'after':after.get(k)}
             for k in sorted(set(before)|set(after)) if before.get(k)!=after.get(k)}
    external={k:v for k,v in changes.items() if k.startswith('lib/features/japanese/')}
    english={k:v for k,v in changes.items() if k not in external}
    assert not english, 'Protected English/source/DB drift: '+','.join(english)
    return {'protected_English_sources_and_personal_DB_unchanged':True,
            'out_of_scope_concurrent_Japanese_changes_observed':external,
            'baseline_replaced':False,'before':before,'after':after}


def choose(pool,n,label):
    # Hash ordering inside a declared stratum; neither source-list convenience
    # nor model confidence determines inclusion.
    return sorted(pool,key=lambda r:hashlib.sha256(('p6c3:'+label+':'+r['stable_id']).encode()).hexdigest())[:n]


def main():
    OUT.mkdir(parents=True,exist_ok=True);PRIVATE.mkdir(parents=True,exist_ok=True)
    if (OUT/'preservation.json').exists():preservation_check()
    else:write_once(OUT/'preservation.json',{'method':'byte hashes and DB side-file metadata only; no SQL','before':state()})
    data=load('docs/p6/p6c2/core_meanings_500.json');rs=data['records'];new=rs[100:]
    major=[r for r in new if r['ai_semantic_review']['severity']=='Major']
    assert len(major)==42
    sample=[];strata={}
    for severity,risk,n in [('Info','standard',12),('Info','high',12),('Minor','high',12),('Minor','standard',4)]:
        pool=[r for r in new if r['ai_semantic_review']['severity']==severity and r['risk_level']==risk]
        label=f'new_{severity}_{risk}'
        take=choose(pool,n,label);assert len(take)==n
        sample.extend(take);strata[label]={'population':len(pool),'sample':n}
    old_standard=[r for r in rs[:100] if r['risk_level']=='standard' and not r['reserved_original_items']]
    # Include every available book category in the legacy low-risk sample.
    legacy=[]
    for category in sorted({r['book_category'] for r in old_standard}):
        legacy+=choose([r for r in old_standard if r['book_category']==category],1,'old_'+category)
    used={r['stable_id'] for r in legacy}
    legacy+=choose([r for r in old_standard if r['stable_id'] not in used],8-len(legacy),'old_remainder')
    assert len(legacy)==8
    sample.extend(legacy)
    strata['old_standard']={'population':len(old_standard),'sample':8}
    selected=major+sample
    assert len(selected)==len({r['stable_id'] for r in selected})==90
    old_pending=[r for r in rs[:100] if r['risk_level']=='high' or r['reserved_original_items']]
    plan={'major_count':42,'sample_count':48,'sample_new400_nonmajor':40,'sample_old100_standard':8,
        'sample_strata':strata,'selection_method':'fixed stratum quotas with SHA256(p6c3:label:stable_id) order; no confidence score filtering',
        'selected':[{'stable_id':r['stable_id'],'headword':r['headword'],'role':'target_major' if r in major else 'stratified_audit',
                     'prior_cohort':r['cohort'],'prior_risk':r['risk_level'],
                     'prior_severity':r.get('ai_semantic_review',{}).get('severity','inherited_not_reclassified')} for r in selected],
        'old_unresolved_high_or_reserved':[{'stable_id':r['stable_id'],'headword':r['headword'],
             'risk_level':r['risk_level'],'reserved_original_items':r['reserved_original_items'],
             'status':'pending_not_auto_passed'} for r in old_pending],
        'original_generator_backend':data['generation']['backend_model_id'],
        'blind_protocol':'Reviewers receive only raw formal fields, original fragments and unfiltered licensed WordNet senses, not candidate groups/severity/risk/old notes.'}
    write_once(OUT/'selection_plan.json',plan)
    heads={r['headword'] for r in selected};refs={w:[] for w in heads}
    archive=ROOT/'private/p3/wordnet31.tar.gz'
    assert sha(archive)=='3f7d8be8ef6ecc7167d39b10d66954ec734280b5bdcd57f7d9eafe429d11c22a'
    with tarfile.open(archive) as tar:
        for member in tar.getmembers():
            if pathlib.PurePosixPath(member.name).name not in ['data.noun','data.verb','data.adj','data.adv']:continue
            for raw in tar.extractfile(member):
                line=raw.decode().rstrip('\r\n')
                if not line or line.startswith(' '):continue
                h,gloss=line.split('|',1);parts=h.split()
                lemmas=[parts[4+i*2].split('(')[0] for i in range(int(parts[3],16))]
                for w in heads.intersection(lemmas):
                    refs[w].append({'evidence_id':f'wn31:{parts[2]}:{parts[0]}','part_of_speech':parts[2],
                                    'definition_en':gloss.strip(),'lemmas':lemmas,
                                    'source':'https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz',
                                    'license':'assets/vocabulary/WORDNET_3_1_LICENSE.txt'})
    shuffled=sorted(selected,key=lambda r:hashlib.sha256(('blind:'+r['stable_id']).encode()).hexdigest())
    for i,name in enumerate(['A','B']):
        subset=shuffled[i::2]
        packet={'protocol':'P6C3_source_first_blind_packet_v1','record_count':45,
            'source_note':'Original Chinese means the immutable formal CSV field, not an assertion of verbatim PDF or teacher correctness.',
            'review_rules':['Independently propose core groups before seeing any previous model proposal.',
                'WordNet order is not sense frequency; no official PETS sense ranking claims.',
                'Separate POS and important independent uses; do not force a fixed number of groups.',
                'Keep all original fragments in core/extended/other/reserved with IDs; unclear source POS stays unknown.',
                'Dictionary additions remain separate candidates, never promoted into original-derived core.',
                'A dictionary omission is not proof of invalidity; use accessible publisher evidence where needed.',
                'Only AI proposals; human_approved=false; unproven facts explicitly marked.'],
            'records':[{'stable_id':r['stable_id'],'headword':r['headword'],'part_of_speech':r['part_of_speech'],
                 'original_meaning_zh':r['original_meaning_zh'],'original_meanings':r['original_meanings'],
                 'source_hash':r['source_hash'],'unfiltered_wordnet_senses':refs[r['headword']]} for r in subset]}
        write_once(PRIVATE/f'blind_packet_{name}.json',packet)
    print(json.dumps({'major':42,'stratified':48,'blind_total':90,'old_pending_retained':len(old_pending),'strata':strata},ensure_ascii=False))


if __name__=='__main__':main()
