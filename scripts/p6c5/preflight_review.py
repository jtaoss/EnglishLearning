"""Pre-freeze detector test on the actual six-word generation, not invented QA."""
from common import *
from api_client import call, system_prompt

def main():
    tag='preflight_generation_v3_low_publisher_flash'
    raw=read(OUT/'api'/f'{tag}.json')
    ds=json.loads(raw['content'])['records']
    refs=read(ROOT/'private/p6c4/wordnet_selected600.json')['headwords']
    byid={r['entry_id']:r for r in formal_rows()}
    obs=read(OUT/'PREFLIGHT_PUBLISHER_EVIDENCE.json')['records']
    byword={r['word']:r for r in obs}
    items=[]
    for d in ds:
        r=byid[d['id']]
        p=packet(r,refs[r['word']])
        for pos,text in byword.get(r['word'],{}).get('observations',[]):
            p['evidence'].append({'id':f"pub:p6c5:collins:{r['word']}:{pos}",'pos':pos,'definition':text})
        p['review_role']='targeted_risk'
        p['candidate']=d
        items.append(p)
    api=call('preflight_review_pro_v1',system_prompt('review'),{'records':items},max_tokens=24000,effort='low',model='deepseek-v4-pro')
    print(api['content'])

if __name__=='__main__':main()
