"""Meaningful corruption and policy regression tests; no SQL/network/UI writes."""
import copy
import unittest

from prepare import load
from validate import inputs,validate


class ContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.payload=load('docs/p6/p6c2/core_meanings_500.json')
        cls.context=inputs()

    def rejected(self,mutation):
        payload=copy.deepcopy(self.payload)
        mutation(payload)
        with self.assertRaises(ValueError):validate(payload,*self.context)

    def test_complete_500_and_1216_original_fragments(self):
        self.assertEqual(validate(self.payload,*self.context)['original_fragments'],1216)

    def test_duplicate_id_rejected(self):
        self.rejected(lambda p:p['records'].__setitem__(101,copy.deepcopy(p['records'][100])))

    def test_missing_old_word_rejected(self):
        self.rejected(lambda p:p['records'].__setitem__(0,copy.deepcopy(p['records'][100])))

    def test_headword_case_change_rejected(self):
        self.rejected(lambda p:p['records'][100].update(headword='Advanced'))

    def test_deleted_original_rejected(self):
        self.rejected(lambda p:p['records'][100]['original_meanings'].pop())

    def test_disappeared_mapping_rejected(self):
        self.rejected(lambda p:p['records'][100]['extended_meanings'].clear())

    def test_fake_human_approval_rejected(self):
        self.rejected(lambda p:p['records'][100].update(human_approved=True))

    def test_new_addition_cannot_claim_original(self):
        def change(p):next(r for r in p['records'][100:] if r['dictionary_additions'])['dictionary_additions'][0]['source_sense_ids']=['s001']
        self.rejected(change)

    def test_addition_cannot_auto_promote(self):
        def change(p):next(r for r in p['records'][100:] if r['dictionary_additions'])['dictionary_additions'][0]['auto_promoted_to_core']=True
        self.rejected(change)

    def test_wrong_evidence_rejected(self):
        self.rejected(lambda p:p['records'][100]['core_meanings'][0].update(evidence_ids=['wn31:v:99999999']))

    def test_prior_review_mutation_rejected(self):
        self.rejected(lambda p:p['records'][0]['prior_independent_review'].update(human_confirmation='approved'))

    def test_cross_pos_merge_rejected(self):
        self.rejected(lambda p:p['records'][100]['core_meanings'][0].update(part_of_speech='名词'))

    def test_distinct_direction_and_stewardess_range(self):
        by={r['headword']:r for r in self.payload['records']}
        benefit=by['benefit']
        self.assertTrue(all(not {'s003','s004'}<=set(g['source_sense_ids']) for k in ['core_meanings','extended_meanings'] for g in benefit[k]))
        self.assertEqual(by['stewardess']['core_meanings'][0]['source_sense_ids'],['s001'])
        self.assertEqual(by['stewardess']['extended_meanings'][0]['source_sense_ids'],['s002'])
        self.assertEqual(len(by['get']['core_meanings']),4)


if __name__=='__main__':unittest.main()
