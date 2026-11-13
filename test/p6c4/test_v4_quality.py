import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/p6c4'))
from prepare import read,sha
spec=importlib.util.spec_from_file_location('p6c4_validation',ROOT/'scripts/p6c4/validate.py')
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)

class V4Quality(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reg=read('docs/p6/p6c4/regression_500.json');cls.blind=read('docs/p6/p6c4/blind_test_100.json')
        cls.orig={r['stable_id']:r for r in read('docs/p6/p6c2/core_meanings_500.json')['records']}
        cls.gen={r['stable_id']:r for r in read('docs/p6/p6c4/generation/generated_100.json')['records']}
        cls.wn=read('private/p6c4/wordnet_selected600.json')['headwords']

    def fresh(self,w):return copy.deepcopy(next(r['candidate'] for r in self.blind['records'] if r['headword']==w))
    def check(self,c):return v.validate_record(c,self.orig.get(c['stable_id'],self.gen.get(c['stable_id'])),self.wn[c['headword']])

    def test_all_artifacts_protocols_and600_sources(self):self.assertTrue(v.validate_all()[0]['passed'])
    def test_source_text_cannot_be_silently_fixed(self):
        c=self.fresh('clause');c['original_meaning_zh']='分句；条款'
        with self.assertRaisesRegex(ValueError,'Immutable'):self.check(c)
    def test_clause_preserves_narrow_original_without_promoting_replacement(self):
        c=self.fresh('clause');self.assertTrue(self.check(c))
        self.assertEqual([a['text'] for a in c['reserved_original_items']],['从句'])
        self.assertFalse(any('s001' in g['source_sense_ids'] for g in c['core_meanings']))
        self.assertEqual(c['dictionary_additions'][-1]['source_sense_ids'],[])
    def test_external_scope_replacement_cannot_attach_to_original(self):
        c=self.fresh('clause');c['dictionary_additions'][-1]['source_sense_ids']=['s001']
        with self.assertRaisesRegex(ValueError,'Dictionary content'):self.check(c)
    def test_dropped_source_rejected_even_if_core_still_looks_natural(self):
        c=self.fresh('cap');c['core_meanings']=c['core_meanings'][:-1]
        with self.assertRaisesRegex(ValueError,'Lost/invented'):self.check(c)
    def test_unexplained_multi_POS_mapping_rejected(self):
        c=self.fresh('fit');c['semantic_splits']=[]
        with self.assertRaisesRegex(ValueError,'one-to-many'):self.check(c)
    def test_wrong_headword_reference_rejected(self):
        c=self.fresh('toe');bad='wn31:n:02821967'
        c['core_meanings'][0]['evidence_ids']=[bad];c['supporting_sources'].append({'evidence_id':bad})
        with self.assertRaisesRegex(ValueError,'Wrong-headword'):self.check(c)
    def test_fake_human_or_adoption_rejected(self):
        c=self.fresh('clause');c['human_approved']=True
        with self.assertRaisesRegex(ValueError,'falsely approved'):self.check(c)
        c=self.fresh('clause');c['dictionary_additions'][-1]['auto_promoted_to_core']=True
        with self.assertRaisesRegex(ValueError,'Unauthorized'):self.check(c)
    def test_two48_sets_are_disjoint_and_old_risk_stays_pending(self):
        old={r['stable_id'] for r in self.reg['historical48_review']}
        c3=read('docs/p6/p6c3/independent_quality_review.json')
        extra={r['stable_id'] for r in c3['records'] if r['selection']['role']=='stratified_audit'}
        self.assertEqual(len(old),48);self.assertEqual(len(extra),48);self.assertFalse(old&extra)
        self.assertTrue(all(r['status']=='pending_not_auto_passed' for r in self.reg['historical48_review']))
    def test_existing_correct_use_survives_new_regression_additions(self):
        for w in ['escape','transfer','neglect','support']:
            r=next(r for r in self.reg['records'] if r['headword']==w);o=self.orig[r['stable_id']]
            self.assertEqual(r['candidate']['core_meanings'][:len(o['core_meanings'])],o['core_meanings'])
            self.assertEqual(r['candidate']['original_meanings'],o['original_meanings'])
    def test_sealed_generation_is_not_rewritten_to_fit_reviewer(self):
        for r in self.blind['records']:self.assertEqual(r['initial_generation'],self.gen[r['stable_id']])
        self.assertEqual([r['headword'] for r in self.blind['records'] if r['semantic_changes']],['clause'])
    def test_source_warning_is_not_automatically_current_error(self):
        for w in ['pine','coke','statute','statement','could','pronounce','intercourse']:
            r=next(r for r in self.blind['records'] if r['headword']==w)
            self.assertTrue(r['adjudication']['raw_source_findings_not_automatically_transferred'])
            self.assertFalse(r['adjudication']['confirmed_findings'])
    def test_gate_uses_prespecified_thresholds_not_confidence(self):
        self.assertEqual(v.evaluate_gate(self.reg,self.blind,True)['decision'],'A')
        x=copy.deepcopy(self.blind);x['metrics']['initial_confirmed_Major']=4
        self.assertEqual(v.evaluate_gate(self.reg,x,True)['decision'],'B')
    def test_repeated_major_cause_blocks_scale_even_if_total_under_limit(self):
        x=copy.deepcopy(self.blind);i=copy.deepcopy(x['confirmed_findings'][0]);i['stable_id']='counterexample-second-word'
        x['confirmed_findings'].append(i);x['metrics']['initial_confirmed_Major']=2
        self.assertEqual(v.evaluate_gate(self.reg,x,True)['decision'],'B')
    def test_critical_or_integrity_failure_cannot_pass(self):
        x=copy.deepcopy(self.blind);x['confirmed_findings'][0]['severity']='Critical'
        self.assertEqual(v.evaluate_gate(self.reg,x,True)['decision'],'B')
        self.assertEqual(v.evaluate_gate(self.reg,self.blind,False)['decision'],'B')
    def test_C_needs_concrete_fundamental_evidence_not_risk_labels(self):
        x=copy.deepcopy(self.blind);x['fundamental_method_evidence']={'unrepairable_by_local_rule':True,'affected_strata':['s1','s2','s3'],'concrete_evidence_ids':['unit-test-counterexample-evidence']}
        self.assertEqual(v.evaluate_gate(self.reg,x,True)['decision'],'C')
        self.assertEqual(v.evaluate_gate(self.reg,self.blind,True)['decision'],'A')
    def test_management_and_clause_adoption_not_falsely_closed(self):
        known=next(i for i in self.reg['C3_confirmed_problem_verification'] if i['headword']=='management')
        self.assertFalse(known['source_gap_closed'])
        self.assertEqual(self.blind['confirmed_findings'][0]['original_source_scope_adoption_status'],'unresolved_not_adopted')
        self.assertFalse(v.evaluate_gate(self.reg,self.blind,True)['remaining_full_run_started'])

if __name__=='__main__':unittest.main()
