"""Predeclared targeted independent verification, all within existing700."""
import argparse
from common import *
from run import stage
from reconcile_inputs import supplement,adapted_packets

POLICY={'known_before4_and_after4_plus_pursue':True,
        'all_primary_Major_or_Critical_proposals':True,
        'all_primary_narrowing_broadening_or_mismatch_relations':True,
        'all24_preselected_holdouts_comparison':True,
        'unknown_only_words': 'remain explicitly pending; not all automatically re-reviewed just to erase uncertainty',
        'no_new_IDs_or_human_approval':True}

def main():
    p=argparse.ArgumentParser();p.add_argument('part',choices=['known','targeted']);args=p.parse_args()
    m=verify_frozen();verify_protection()
    once(OUT/'SECONDARY_MANIFEST.json',{'policy':POLICY,'script_sha256':sha(Path(__file__)),
         'original_manifest_sha256':sha(OUT/'RUN_MANIFEST.json'),'secondary_model':m['secondary_model'],
         'rules_hash':sha(RULES),'candidate_changes_allowed':False})
    updates=supplement()
    if args.part=='known':
        before=read(OUT/'inputs/calibration_before.json')['records']
        stage('verify_known_before','verify',before,m['secondary_model'],2)
        after=adapted_packets(read(OUT/'inputs/calibration_after.json')['records'],updates)
        r=next(r for r in working() if r['headword']=='pursue')
        after.append(packet(r,evidence()[r['headword']]))
        once(OUT/'inputs/verify_known_after_and_pursue.json',{'records':after,'pursue_prior_failure_not_deleted':True})
        stage('verify_known_after_and_pursue','verify',after,m['secondary_model'],2)
    else:
        hold=set(read(OUT/'INPUT_SETS.json')['holdout24']);chosen=set(hold);hypotheses={}
        for b in range(1,8):
            d=read(OUT/f'reviews/audit_v5e_{b:02d}.json')
            for r in d['records']:
                risk=any(i['severity'] in ('Major','Critical') for i in r['issues']) or any(m['relation'] in ('范围收窄','范围扩大','语义不匹配') for m in r['mappings'])
                if risk:chosen.add(r['id']);hypotheses[r['id']]=r
        ps=[]
        es=evidence()
        for r in working():
            if r['stable_id'] not in chosen:continue
            item=adapted_packets([packet(r,es[r['headword']])],updates)[0]
            # Holdout proposal was sealed with no answer. This later candidate
            # comparison is a separate context, not a rewrite of the blind one.
            if r['stable_id'] not in hold:item['primary_audit_hypothesis_only']=hypotheses.get(r['stable_id'])
            ps.append(item)
        once(OUT/'inputs/secondary_targeted.json',{'records':ps,'selection_policy':POLICY,
             'selected_count':len(ps),'holdout24_are_candidate_comparison_now':True})
        stage('verify_targeted_and_holdout','verify',ps,m['secondary_model'],2)

if __name__=='__main__':main()
