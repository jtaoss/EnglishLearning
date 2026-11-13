"""Read-only final consistency and deterministic replay. No API requests."""
from common import *
import sys

def main():
    verify_frozen();protection=verify_protection()
    r=read(OUT/'regression_700.json');rows=r['records'];b={x['stable_id']:x for x in baseline()}
    require({x['stable_id'] for x in rows}==set(b) and len(rows)==700,'ID drift')
    formal={x['entry_id']:x for x in csv.DictReader(FORMAL.open(encoding='utf-8-sig',newline=''))}
    require(len(formal)==5332,'Formal baseline changed')
    allowed=set(RELATIONS);count=0
    for x in rows:
        c=x['candidate'];old=b[x['stable_id']]
        require(c['source_fields']==formal[x['stable_id']]==old['source_fields'],'Formal 29-field snapshot drift')
        require(c['original_meanings']==old['original_meanings'],'Original fragments changed')
        maps=x['source_scope_mappings'];originals={z['source_sense_id']:z for z in c['original_meanings']}
        require(len(maps)==len(originals) and {m['source_sense_id'] for m in maps}==set(originals),'Mappings lost')
        for m in maps:
            count+=1;o=originals[m['source_sense_id']]
            require(m['original_text']==o['text'] and m['source_pos']==o['part_of_speech'],'Source mapping drift')
            require(c['original_meaning_zh'][o['start']:o['end']]==o['text'],'Unicode span changed')
            require(m['mapping_relation'] in allowed and m['mapping_reason'],'Invalid mapping judgment')
            require(m['target_links'] or m['held_original'],'No retained target or explicit pending source')
            require(m['human_approved'] is False,'Fake mapping approval')
        require(x['human_approved'] is False and c['human_approved'] is False,'Fake word approval')
        require(not old['needs_human_review'] or x['requires_human_review'],'Old pending flag cleared')
        require(c['review_status']==old['review_status'],'Historical review status cleared')
    require(count==1702,'Count drift')
    for q in [*list((ROOT/'scripts/p6c5a').glob('*.py')),*list((ROOT/'test/p6c5a').glob('*.py'))]:
        compile(q.read_text(encoding='utf-8'),str(q),'exec')
    # Search exact environment secret values without printing values or paths of
    # a match. Include serialized data, prompts, response cache and source code.
    secrets=[os.environ.get(n) for n in ('DEEPSEEK_API_KEY','ANTHROPIC_AUTH_TOKEN','NOTION_TOKEN','NOTION_API_KEY')]
    secrets=[v.encode() for v in secrets if v and len(v)>=12]
    scan=[q for folder in (OUT,ROOT/'scripts/p6c5a',ROOT/'test/p6c5a') for q in folder.rglob('*')
          if q.is_file() and '__pycache__' not in q.parts]
    require(not any(key in q.read_bytes() for q in scan for key in secrets),'Exact credential material present in outputs')
    targets=[OUT/'regression_700.json',OUT/'revised_candidates.json']
    before={q.name:sha(q) for q in targets}
    result=subprocess.run([sys.executable,'-X','utf8',str(ROOT/'scripts/p6c5a/build_regression.py')],cwd=ROOT,capture_output=True,text=True,encoding='utf-8')
    require(result.returncode==0,'Replay failed: '+result.stderr[-300:])
    after={q.name:sha(q) for q in targets}
    require(before==after,'Replay is not byte-identical')
    save(OUT/'REPRODUCIBILITY.json',{'byte_identical':True,'files':after,'no_model_calls':True,
      'no_new_candidate_IDs':True,'protected_files_unchanged':protection['unchanged']})
    save(OUT/'VALIDATION_RESULTS.json',{'passed':True,'existing700_unique':True,'formal5332_readonly':True,
      'original_fragments':count,'mapped_fragments':count,'source_POS_and_unicode_preserved':True,
      'old_pending_flags_and_review_statuses_preserved':True,'human_approvals':0,
      'exact_environment_secret_values_found':False,'secret_values_ever_printed':False,
      'files_scanned':len(scan),'protected_file_count':protection['checked_files'],
      'replay_byte_identical':True,'semantic_gate_is_separate_and_not_passed':True})
    print('All export contracts passed; 700 / 1702, byte-identical replay, protected baseline unchanged.')

if __name__=='__main__':main()
