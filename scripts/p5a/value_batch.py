"""Persist explicit in-session lexical-value decisions after reviewing a batch.

This is a record-writing helper, not an LLM and not a frequency estimator.
"""
import argparse
import hashlib
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--start', type=int, required=True)
p.add_argument('--end', type=int, required=True)
p.add_argument('--defer', default='')
p.add_argument('--manual', default='')
args = p.parse_args()
rows = json.loads((ROOT/'private/p5a/workbench.json').read_text(encoding='utf-8'))
selective = [r for r in rows if r['book_category'] in ['低频词','偶考词','补充词']
             and r['pets2015_status'] != '已收录' and not r['existing']]
batch = selective[args.start:args.end]
defer, manual = set(args.defer.split('|'))-{''}, set(args.manual.split('|'))-{''}
assert not defer & manual
assert defer | manual <= {r['单词'] for r in batch}
decisions = []
for r in batch:
    word = r['单词']
    decision = '暂缓' if word in defer else '待核实' if word in manual else '建议保留'
    evidence = [{'synset': s['id'], 'gloss':s['gloss'], 'pos':s['pos']}
                for s in r['senses'][:3]]
    reason = ('相对偏专门学科、历史/文学或少见物品，当前PETS-3通用学习可后置；保留原始词条。'
              if decision == '暂缓' else
              '词头/语义或应用范围仍有疑点，不能仅凭词形推荐正式学习。' if decision == '待核实' else
              '用于生活、通用阅读或职场/技术文本的识别有实际价值，建议作为扩展词保留；不是官方词频结论。')
    if evidence:
        reason += ' 本轮参照的具体义项：' + evidence[0]['gloss'].split(';')[0] + '。'
    decisions.append({'candidate_id':r['词条ID'],'word':word,'model_recommendation':decision,
        'priority':'P2','reason':reason,'confidence':'中' if evidence else '低',
        'model':'Codex当前会话模型；精确运行型号未公开，不虚构型号',
        'method':'会话内逐词阅读词头及WordNet义项，主观学习价值判断；不是脚本评分或客观频率',
        'evidence_kind':'WordNet词义支持+AI用途判断；无外部客观词频',
        'evidence':evidence,'evidence_source':'https://wordnetcode.princeton.edu/3.0/WordNet-3.0.tar.gz',
        'status':'学习价值已评估；内容能否正式入选由独立质量门槛决定'})
out=ROOT/'docs/p5a/value_batches'
out.mkdir(parents=True,exist_ok=True)
path=out/f'{args.start:04}-{args.end:04}.json'
content=json.dumps(decisions,ensure_ascii=False,indent=2)+'\n'
if path.exists(): assert path.read_text(encoding='utf-8') == content
else: path.write_text(content,encoding='utf-8')
print(json.dumps({'batch':path.name,'count':len(decisions),'deferred':len(defer),'manual':len(manual)}))
