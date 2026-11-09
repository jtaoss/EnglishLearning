"""Display/persist separate, explicit semantic review of licensed COW drafts.

Printing is not approval. A batch is saved only with --approve after the agent
has read it; exceptions can be held or independently rewritten with --edits.
"""
import argparse
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('--start',type=int,required=True)
p.add_argument('--end',type=int,required=True)
p.add_argument('--approve',action='store_true')
p.add_argument('--hold',default='')
p.add_argument('--edits',default='')
args=p.parse_args()
rows=json.loads((ROOT/'private/p5a/workbench.json').read_text(encoding='utf-8'))
choices=[]
for r in rows:
    if r['existing'] or len({s['pos'] for s in r['senses']}) != 1: continue
    usable=next((s for s in r['senses'] if s['chinese_lemmas']),None)
    if not usable: continue
    draft='；'.join(list(dict.fromkeys(w.replace('+','') for w in usable['chinese_lemmas']))[:3])
    choices.append({'candidate_id':r['词条ID'],'word':r['单词'],
                    'pos':usable['pos'],'meaning_zh':draft,
                    'source_synset':usable['id'],'source_rank':usable['rank_within_pos'],
                    'english_sense':usable['gloss'],'original_cow':usable['chinese_lemmas'],
                    'other_senses':[{'id':s['id'],'gloss':s['gloss']} for s in r['senses'] if s['id'] != usable['id']]})
batch=choices[args.start:args.end]
if not args.approve:
    print('TOTAL_DRAFT_CHOICES',len(choices))
    for i,r in enumerate(batch,args.start):
        print(f"{i}|{r['word']} [{r['pos']}] {r['meaning_zh']}")
else:
    holds=set(args.hold.split('|'))-{''}
    assert holds <= {r['word'] for r in batch}
    edits={}
    if args.edits:
        for line in (ROOT/args.edits).read_text(encoding='utf-8-sig').splitlines():
            if not line or line.startswith('#'):continue
            word,meaning=line.split('|',1);edits[word]=meaning
    for r in batch:
        before=r['meaning_zh']
        if r['word'] in edits:r['meaning_zh']=edits[r['word']]
        r.update(before_meaning=before,after_meaning=r['meaning_zh'],
                 review='待人工核实' if r['word'] in holds else '会话内语义对照通过；非教师终审',
                 status='hold' if r['word'] in holds else 'approved',
                 method='逐词阅读词头/中文义项；疑点参照WordNet英文概念；不按机器对齐直接批准',
                 model='Codex当前会话模型；不虚构精确型号',
                 origin='独立编写（参照许可词网）' if r['word'] in edits else '许可COW概念词元，经会话检查后采用',
                 license='Chinese Open WordNet permissive WordNet-style license; attribution retained',
                 evidence_source='https://github.com/omwn/omw-data/tree/main/wns/cow')
    out=ROOT/'docs/p5a/content_batches';out.mkdir(parents=True,exist_ok=True)
    path=out/f'{args.start:04}-{args.end:04}.json'
    text=json.dumps(batch,ensure_ascii=False,indent=2)+'\n'
    if path.exists():assert path.read_text(encoding='utf-8')==text
    else:path.write_text(text,encoding='utf-8')
    print(json.dumps({'batch':path.name,'count':len(batch),'approved':len(batch)-len(holds),'held':len(holds)}))
