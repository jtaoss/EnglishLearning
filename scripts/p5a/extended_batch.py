"""Checkpoint independently written common senses for the remaining candidates.

--approve records a completed in-session semantic pass. It does not call an LLM.
"""
import argparse,json,pathlib
ROOT=pathlib.Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--start',type=int,required=True);p.add_argument('--end',type=int,required=True)
p.add_argument('--approve',action='store_true');p.add_argument('--hold',default='')
a=p.parse_args()
rows=json.loads((ROOT/'private/p5a/workbench.json').read_text(encoding='utf-8'))
known=set()
for path in (ROOT/'docs/p5a/content_batches').glob('*.json'):
    known.update(r['candidate_id'] for r in json.loads(path.read_text(encoding='utf-8')))
remaining=[r for r in rows if not r['existing'] and r['词条ID'] not in known]
batch=remaining[a.start:a.end]
if not a.approve:
    print('TOTAL_REMAINING',len(remaining))
    for i in range(0,len(batch),20):
        print(' | '.join(f"{a.start+i+j}:{r['单词']}[{''.join(dict.fromkeys(s['pos'] for s in r['senses']))}]" for j,r in enumerate(batch[i:i+20])))
else:
    editorial={}
    path=ROOT/'scripts/p5a/extended_editorial.txt'
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        if not line or line.startswith('#'):continue
        word,pos,meaning=line.split('|',2);assert word not in editorial;editorial[word]=(pos,meaning)
    holds=set(a.hold.split('|'))-{''};assert holds<={r['单词'] for r in batch}
    decisions=[]
    for r in batch:
        word=r['单词'];assert word in editorial or word in holds,word
        pos,meaning=editorial.get(word,('',''))
        assert word in holds or (meaning and pos)
        decisions.append({'candidate_id':r['词条ID'],'word':word,'pos':pos,'meaning_zh':meaning,
            'before_meaning':'原候选台账无中文释义；不覆盖任何既有词义',
            'after_meaning':meaning,'status':'hold' if word in holds else 'approved',
            'review':'独立编写并逐词常用义/词性自检；非教师终审',
            'method':'会话内逐词核对词头、常用词性和义项；WordNet提供概念线索，功能词/新增常用义为独立语言判断，不冒充词网逐义支持',
            'model':'Codex当前会话模型；精确运行型号未公开',
            'evidence_source':'原书既有词头/页码；https://wordnetcode.princeton.edu/3.0/WordNet-3.0.tar.gz',
            'wordnet_senses':[{'id':s['id'],'pos':s['pos'],'gloss':s['gloss']} for s in r['senses']],
            'origin':'独立编写常用释义；没有复制商业词典释义或例句',
            'confidence':'中；非独立教师校审'})
    out=ROOT/'docs/p5a/extended_content_batches';out.mkdir(parents=True,exist_ok=True)
    dest=out/f'{a.start:04}-{a.end:04}.json';data=json.dumps(decisions,ensure_ascii=False,indent=2)+'\n'
    if dest.exists():assert dest.read_text(encoding='utf-8')==data
    else:dest.write_text(data,encoding='utf-8')
    print(json.dumps({'batch':dest.name,'reviewed':len(decisions),'held':len(holds)}))
