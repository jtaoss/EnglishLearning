"""Audits existing700 only, with immutable real-model checkpoints."""
import argparse
import concurrent.futures
from common import *
from client import call
from scope_guard import validate_result

def request(tag,kind,packets,model):
    first=call(tag,kind,packets,model)
    try:return validate_result(first,packets,kind),first
    except (ValueError,KeyError,TypeError) as e:
        once(OUT/'failures'/(tag+'_schema.json'),{'tag':tag,'validator_error':str(e)[:600],
            'first_response_hash':sha(OUT/'api'/(tag+'.json')),'same_frozen_rules_model':True,'max_one_schema_repair':True})
        repair=call(tag+'_repair1',kind,packets,model,{'invalid_output':first['content'],
            'validator_error':str(e)[:600],'instruction':'Perform the actual requested semantic audit and return its small schema. Do not echo input or invent default reviews. Keep the same frozen V5 rules.'})
        return validate_result(repair,packets,kind),repair

def stage(name,kind,packets,model,size):
    m=verify_frozen();checkpoint=OUT/'reviews'/(name+'.json')
    if checkpoint.exists():
        d=read(checkpoint);require(d['input_hash']==canonical(packets),'Stage input changed');print('CACHED',name,len(d['records']),flush=True);return d
    chunks=[packets[i:i+size] for i in range(0,len(packets),size)]
    output={};failures=[];api_refs=[]
    print('BEGIN',name,'words',len(packets),'requests',len(chunks),flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=m['max_concurrency']) as pool:
        jobs={pool.submit(request,f'{name}_{i+1:03d}',kind,chunk,model):i for i,chunk in enumerate(chunks)}
        for job in concurrent.futures.as_completed(jobs):
            i=jobs[job]
            try:
                rs,api=job.result();output[i]=rs;api_refs.append({'tag':api['tag'],'response_sha256':sha(OUT/'api'/(api['tag']+'.json'))})
            except Exception as e:
                failures.append({'chunk':i+1,'ids':[p['id'] for p in chunks[i]],'error_type':type(e).__name__,
                    'error':str(e)[:500],'status':'incomplete_not_fabricated'})
            if (len(output)+len(failures))%5==0:print('PROGRESS',name,'transport_complete',len(output)+len(failures),'of',len(chunks),flush=True)
    rows=[r for i in sorted(output) for r in output[i]]
    d={'stage':name,'kind':kind,'model_requested':model,'record_count':len(rows),'expected_count':len(packets),
       'records':rows,'failures':failures,'input_hash':canonical(packets),'response_files':sorted(api_refs,key=lambda a:a['tag']),
       'all_output_AI_candidate':True,'human_approved':False,'rules_hash':sha(RULES)}
    once(checkpoint,d)
    print('SAVED',name,len(rows),'incomplete',sum(len(f['ids']) for f in failures),flush=True)
    return d

def main():
    parser=argparse.ArgumentParser();parser.add_argument('part',choices=['calibration','holdout','audit','secondary']);args=parser.parse_args()
    m=verify_frozen();verify_protection()
    if args.part=='calibration':
        for variant in ('before','after'):
            stage('calibration_'+variant,'audit',read(OUT/f'inputs/calibration_{variant}.json')['records'],m['primary_model'],2)
    elif args.part=='holdout':
        stage('holdout_source_first','holdout',read(OUT/'inputs/holdout_source_only.json')['records'],m['secondary_model'],2)
    elif args.part=='audit':
        # Existing holdout source-first proposals must already be sealed before
        # candidate comparison; failures remain explicit and block gate A.
        require((OUT/'reviews/holdout_source_first.json').exists(),'Source-first holdout not completed/checkpointed')
        for b in range(1,8):
            stage(f'audit_{b:02d}','audit',read(OUT/f'inputs/audit_{b:02d}.json')['records'],m['primary_model'],m['primary_batch_words'])
    else:
        stage('secondary_targeted','verify',read(OUT/'inputs/secondary_targeted.json')['records'],m['secondary_model'],m['secondary_batch_words'])

if __name__=='__main__':main()
