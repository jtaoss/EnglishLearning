"""Meaningful negative contracts for isolated full-vocabulary processing."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/p6c5'))
from records import validate_decision
from common import OUT, canonical, formal_rows, read, sha, RULES

class TransportContracts(unittest.TestCase):
    def setUp(self):
        self.item = {'id':'SG25-test','word':'test','pos':'名词；动词',
                     'senses':[{'source_sense_id':'s001','text':'测试'}],
                     'evidence':[{'id':'wn31:n:00000001','pos':'n','definition':'a test'},
                                 {'id':'wn31:v:00000002','pos':'v','definition':'to test'}]}
        self.d = {'id':'SG25-test','core':[['测试','名词',['s001'],['wn31:n:00000001'],'测试活动']],
                  'extended':[],'other':[],'hold':[],'splits':{},'additions':[],
                  'reason':'先掌握测试活动；动词对应待核。','flags':[['Info','POS_pending','动词待核。']]}

    def test_traceable_candidate(self):
        self.assertTrue(validate_decision(self.d,self.item))

    def test_missing_original_rejected(self):
        self.d['core']=[]
        with self.assertRaisesRegex(ValueError,'incomplete'):
            validate_decision(self.d,self.item)

    def test_explicit_evidence_failure_retains_original(self):
        self.d['core']=[]
        self.d['hold']=[['s001','没有独立证据，保留原文。']]
        self.assertTrue(validate_decision(self.d,self.item))

    def test_wrong_headword_evidence_rejected(self):
        self.d['core'][0][3]=['wn31:n:99999999']
        with self.assertRaisesRegex(ValueError,'Unprovided'):
            validate_decision(self.d,self.item)

    def test_wrong_dictionary_POS_rejected(self):
        self.d['core'][0][3]=['wn31:v:00000002']
        with self.assertRaisesRegex(ValueError,'POS mismatch'):
            validate_decision(self.d,self.item)

    def test_unexplained_one_to_many_rejected(self):
        self.d['core'].append(['测试','动词',['s001'],['wn31:v:00000002'],'进行测试'])
        with self.assertRaisesRegex(ValueError,'one-to-many'):
            validate_decision(self.d,self.item)
        self.d['splits']['s001']='测试既可指测试活动，也可指进行测试，词性与英语证据独立。'
        self.assertTrue(validate_decision(self.d,self.item))

    def test_external_addition_requires_actual_lexical_evidence(self):
        self.d['additions']=[['试验','名词',['source:SG25-test:s001'],'补充候选']]
        with self.assertRaisesRegex(ValueError,'external addition'):
            validate_decision(self.d,self.item)

    def test_other_word_ID_rejected(self):
        self.d['id']='SG25-wrong'
        with self.assertRaisesRegex(ValueError,'stable ID'):
            validate_decision(self.d,self.item)

class IntegratedContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        path=OUT/'core_meanings_5332_candidates.json'
        if not path.exists():
            raise unittest.SkipTest('Final isolated merge not yet available')
        cls.data=read(path)
        cls.rs=cls.data['records']

    def test_exact_formal_set_or_honest_incomplete(self):
        formal={r['entry_id'] for r in formal_rows()}
        ids={r['stable_id'] for r in self.rs}
        self.assertEqual(len(ids),len(self.rs))
        self.assertEqual(self.data['missing_ids'],sorted(formal-ids))
        self.assertEqual(self.data['generation_complete'],ids==formal)

    def test_no_approval_or_publication(self):
        self.assertTrue(all(r['human_approved'] is False and r['publication_status']=='isolated_not_published' for r in self.rs))

    def test_all_source_snapshots_exact(self):
        formal={r['entry_id']:r for r in formal_rows()}
        for r in self.rs:
            self.assertEqual(r['source_fields'],formal[r['stable_id']])
            self.assertEqual(r['source_hash'],canonical(formal[r['stable_id']]))

    def test_historical48_not_auto_cleared(self):
        hist=set(read(OUT/'INPUT_SETS.json')['historical48'])
        self.assertEqual({r['stable_id'] for r in self.rs if r['historical_risk_retained']},hist)
        self.assertEqual(len(hist),48)
        self.assertTrue(all(r['needs_human_review'] for r in self.rs if r['stable_id'] in hist))

    def test_claus_management_not_adopted(self):
        for w in ('management','clause'):
            r=next(r for r in self.rs if r['headword']==w)
            self.assertEqual(r['review_status'],'confirmed_problem_revision_pending')
            self.assertIn('quarantine',r)
        clause=next(r for r in self.rs if r['headword']=='clause')
        self.assertTrue(any(s['text']=='从句' for s in clause['reserved_original_items']))

    def test_core_source_or_external_never_interchange(self):
        for r in self.rs:
            original={s['source_sense_id'] for s in r['original_meanings']}
            for k in ('core_meanings','extended_meanings','other_meanings'):
                for g in r[k]:
                    self.assertTrue(set(g['source_sense_ids'])<=original)
            for a in r['dictionary_additions']:
                self.assertEqual(a['source_sense_ids'],[])
                self.assertFalse(a.get('human_approved',False))
                self.assertFalse(a.get('auto_promoted_to_core',False))

    def test_frozen_rule_hash(self):
        self.assertTrue(all(r['rules_hash']==sha(RULES) for r in self.rs))

    def test_confirmed_systematic_stop_cannot_be_reported_complete(self):
        metrics=read(OUT/'QUALITY_METRICS.json')
        checkpoints=read(OUT/'BATCH_CHECKPOINTS.json')
        self.assertEqual(metrics['decision'],'C')
        self.assertFalse(self.data['generation_complete'])
        self.assertEqual(len(self.rs),700)
        self.assertEqual(len(self.data['missing_ids']),4632)
        self.assertTrue(checkpoints['systematic_stop'])
        self.assertIsNone(checkpoints['next_batch'])
        self.assertFalse((OUT/'inputs/batch_002.json').exists() and (OUT/'generation/batch_002.json').exists())

    def test_resume_stop_precedes_any_model_or_next_batch_call(self):
        import run_batches
        before={p.name:sha(p) for p in (OUT/'api').glob('*.json')}
        with mock.patch.object(sys,'argv',['run_batches.py','--through','2']), mock.patch.object(run_batches,'call',side_effect=AssertionError('API must not run after semantic stop')) as api:
            with self.assertRaisesRegex(ValueError,'Repeated Major proposals'):
                run_batches.main()
            api.assert_not_called()
        self.assertEqual(before,{p.name:sha(p) for p in (OUT/'api').glob('*.json')})

    def test_new_confirmation_and_AI_risk_counts_stay_separate(self):
        m=read(OUT/'QUALITY_METRICS.json')
        self.assertEqual(m['confirmed_new_problem_severity'],{'Major':2,'Minor':2})
        self.assertNotEqual(m['AI_risk_flags_by_severity']['Major'],2)
        self.assertEqual(m['second_review_failed_words'],1)

    def test_fake_approval_and_wrong_reference_rejected(self):
        from validate import validate_record
        r=copy.deepcopy(next(r for r in self.rs if r.get('generation_provenance')))
        row=r['source_fields']
        r['human_approved']=True
        with self.assertRaisesRegex(ValueError,'approval'):
            validate_record(r,row)
        r['human_approved']=False
        r['core_meanings'][0]['evidence_ids']=['wn31:n:99999999']
        with self.assertRaisesRegex(ValueError,'Dangling'):
            validate_record(r,row)

    def test_independent_revisions_keep_original_and_are_not_adopted(self):
        from validate import validate_record
        revisions=read(OUT/'REVISED_CANDIDATES.json')['records']
        self.assertEqual(len(revisions),4)
        byid={r['stable_id']:r for r in self.rs}
        for rev in revisions:
            a=rev['candidate_revision'];b=rev['before']
            self.assertEqual(a['source_fields'],b['source_fields'])
            self.assertEqual(a['original_meanings'],b['original_meanings'])
            self.assertEqual(a['source_hash'],b['source_hash'])
            self.assertTrue(validate_record(a,a['source_fields']))
            self.assertEqual(byid[a['stable_id']]['core_meanings'],b['core_meanings'])
            self.assertFalse(rev['active_merged_candidate_replaced'])

if __name__=='__main__':
    unittest.main()
