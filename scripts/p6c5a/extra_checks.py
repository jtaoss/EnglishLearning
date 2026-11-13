"""General evidence-graph preflight and advisory metadata checks; no word cases."""
import re
from common import *

def packet_integrity(p):
    require(bool(p['id']) and bool(p['word']),'No identity')
    source={s['source_sense_id'] for s in p['senses']}
    require(len(source)==len(p['senses']),'Duplicate source IDs')
    for s in p['senses']:
        require(p['raw'][s['start']:s['end']]==s['text'],'Source Unicode span changed')
    es={e['id'] for e in p['evidence']}
    require(len(es)==len(p['evidence']),'Duplicate evidence IDs')
    if 'groups' in p:
        mapped=[]
        for g in p['groups']:
            require(g['source_ids'] and set(g['source_ids'])<=source,'Group source ID missing/invented')
            for eid in g['evidence_ids']:
                trace=eid.startswith('source:'+p['id']+':') and eid.rsplit(':',1)[1] in g['source_ids']
                require(eid in es or trace,'Referenced lexical evidence omitted from packet: '+eid)
            mapped+=g['source_ids']
        mapped += [h['source_id'] for h in p['held']]
        require(set(mapped)==source,'Original source mapping lost')
    return True

FREQUENCY=re.compile(r'最常用|出现频率最高|官方高频义|官方重点释义|PETS[-－ ]?3.{0,8}官方.{0,5}释义',re.I)

def advisory_text_risks(p):
    """A string scan is only an alarm for evidence review, never semantic proof."""
    results=[]
    for field,text in [('selection_reason',p.get('reason',''))]+[(g['id']+':note',g['note']) for g in p.get('groups',[])]:
        for m in FREQUENCY.finditer(text):
            snippet=text[max(0,m.start()-20):min(len(text),m.end()+25)]
            results.append({'kind':'frequency_wording_requires_evidence_review','field':field,
                'snippet':snippet,'confirmed_error':False,
                'possible_false_positive':'negation, quoted warning or explicitly hypothetical wording must be read in context',
                'not_a_semantic_coverage_test':True})
    return results

def main():
    verify_frozen()
    results=[]
    for path in sorted((OUT/'reconciled_inputs').glob('audit_*.json')):
        for p in read(path)['records']:
            packet_integrity(p)
            results.append({'id':p['id'],'headword':p['word'],'packet_integrity':True,
                            'advisory_flags':advisory_text_risks(p)})
    save(OUT/'ADDITIONAL_GUARD_CHECKS.json',{'records':results,'record_count':len(results),
       'script_sha256':sha(Path(__file__)),'rules_hash':sha(RULES),
       'semantic_engine_changed':False,'note':'Complements frozen semantic audit with evidence-graph assertions and a non-authoritative metadata alarm.'})
    print('General packet checks',len(results),'advisory alarms',sum(bool(r['advisory_flags']) for r in results))

if __name__=='__main__':main()
