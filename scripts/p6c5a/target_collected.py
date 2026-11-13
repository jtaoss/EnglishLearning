"""Select all risky real per-word audits plus fixed holdout; no new IDs."""
from common import *
from run import stage
from reconcile_inputs import supplement,adapted_packets

def main():
    m=verify_frozen();verify_protection()
    primary=read(OUT/'COLLECTED_PRIMARY_AUDITS.json')
    require(primary['completed_outer_stages']==7 and primary['record_count']==700,'700 actual audits not available')
    hold=set(read(OUT/'INPUT_SETS.json')['holdout24']);chosen=set(hold);hyp={}
    for entry in primary['records']:
        r=entry['review']
        if any(i['severity'] in ('Major','Critical') for i in r['issues']) or any(x['relation'] in ('范围收窄','范围扩大','语义不匹配') for x in r['mappings']):
            chosen.add(r['id']);hyp[r['id']]=r
    es=evidence();updates=supplement();ps=[]
    for r in working():
        if r['stable_id'] not in chosen:continue
        p=adapted_packets([packet(r,es[r['headword']])],updates)[0]
        if r['stable_id'] not in hold:p['primary_audit_hypothesis_only']=hyp.get(r['stable_id'])
        ps.append(p)
    once(OUT/'inputs/secondary_collected_targeted.json',{'records':ps,'selected_count':len(ps),
         'selection':'all primary scope relation risks or Major/Critical proposals, plus every fixed24 holdout',
         'source_first_holdout_already_sealed':True,'candidate_changes_allowed':False,
         'canonical_primary_sha256':sha(OUT/'COLLECTED_PRIMARY_AUDITS.json')})
    once(OUT/'TARGETED_CANONICAL_MANIFEST.json',{'script_sha256':sha(Path(__file__)),
         'primary_sha256':sha(OUT/'COLLECTED_PRIMARY_AUDITS.json'),
         'scope_rules_and_gate_unchanged':True,'selection_policy_not_weakened':True,
         'includes5_actual_reviews_recovered_from_first_batch_structural_rejection':True})
    print('Selected',len(ps),'for independent candidate verification',flush=True)
    stage('verify_collected_targeted','verify',ps,m['secondary_model'],2)

if __name__=='__main__':main()
