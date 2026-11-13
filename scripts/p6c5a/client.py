"""Environment-only credentials, isolated response cache, bounded requests."""
import time
import urllib.request
import urllib.error
from common import *

def system(kind):
    name={'audit':'AUDIT_PROMPT.md','holdout':'HOLDOUT_PROMPT.md','verify':'VERIFY_PROMPT.md'}[kind]
    # V5 contains current semantic rules, not obsolete C4 execution commands.
    return (ROOT/'scripts/p6c5a'/name).read_text(encoding='utf-8')+'\n\n'+RULES.read_text(encoding='utf-8')+'\n\nReturn the requested review JSON schema only; never echo inputs.'

def call(tag,kind,packets,model,extra=None):
    manifest=verify_frozen()
    require(model in (manifest['primary_model'],manifest['secondary_model']),'Unfrozen model')
    allowed=set(read(OUT/'INPUT_SETS.json')['all700'])
    require(all(p['id'] in allowed for p in packets),'ID outside existing700; no request allowed')
    payload={'records':packets}
    if extra:payload['repair_context']=extra
    spec={'model':model,'system':system(kind),'payload':payload,'thinking':'enabled','effort':'low','max_tokens':40000}
    request_hash=canonical(spec);path=OUT/'api'/(tag+'.json')
    if path.exists():
        result=read(path);require(result['request_hash']==request_hash,'Cache request changed: '+tag)
        return result
    key=os.environ.get('DEEPSEEK_API_KEY')
    require(bool(key),'No configured model credential; no fallback')
    body={'model':model,'messages':[{'role':'system','content':spec['system']},
        {'role':'user','content':json.dumps(payload,ensure_ascii=False,separators=(',',':'))}],
        'thinking':{'type':'enabled'},'reasoning_effort':'low','response_format':{'type':'json_object'},
        'max_tokens':40000,'stream':False}
    req=urllib.request.Request('https://api.deepseek.com/chat/completions',data=json.dumps(body,ensure_ascii=False).encode(),
        headers={'Authorization':'Bearer '+key,'Content-Type':'application/json'})
    started=now();clock=__import__('time').monotonic()
    try:
        with urllib.request.urlopen(req,timeout=900) as response:raw=json.load(response)
        c=raw['choices'][0]
        result={'tag':tag,'kind':kind,'request_hash':request_hash,'input_ids':[p['id'] for p in packets],
            'requested_model':model,'response_model':raw.get('model'),'response_id':raw.get('id'),
            'system_fingerprint':raw.get('system_fingerprint'),'finish_reason':c['finish_reason'],
            'content':c['message'].get('content'),'usage':raw.get('usage'),'started_utc':started,
            'completed_utc':now(),'elapsed_seconds':round(__import__('time').monotonic()-clock,3),
            'reasoning_content_saved':False,'credentials_saved':False}
        once(path,result)
        require(result['response_model']==model,'Model identifier changed; no fallback')
        require(result['finish_reason']=='stop','Incomplete API output saved')
        return result
    except Exception as e:
        save(OUT/'failures'/(tag+'_request.json'),{'tag':tag,'started_utc':started,'error_type':type(e).__name__,
            'http_status':e.code if isinstance(e,urllib.error.HTTPError) else None,'no_fallback':True,
            'usage_unknown_for_request_without_response':not path.exists()})
        raise RuntimeError('Model request failed; isolated checkpoint: '+tag) from None
