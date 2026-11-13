"""Cross-artifact safety contracts and regression counterexamples; stdlib only."""
import copy
import importlib.util
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'scripts/p6c3'))
from prepare_review import load, PRIVATE
spec = importlib.util.spec_from_file_location('p6c3_validate', ROOT/'scripts/p6c3/validate.py')
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)
run_validation = validation.run_validation
validate_candidate = validation.validate_candidate


class QualityContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.review = load('docs/p6/p6c3/independent_quality_review.json')
        cls.original = {r['stable_id']: r for r in load('docs/p6/p6c2/core_meanings_500.json')['records']}
        cls.candidates = {r['headword']: r['candidate'] for r in load('docs/p6/p6c3/REVISED_CANDIDATES.json')['records']}
        cls.raw = {r['stable_id']: r for n in 'AB' for r in json.loads((PRIVATE/f'blind_packet_{n}.json').read_text(encoding='utf-8'))['records']}

    def candidate_valid(self, candidate):
        return validate_candidate(candidate, self.original[candidate['stable_id']], self.raw[candidate['stable_id']])

    def test_full_provenance_and_scope_contract(self):
        self.assertTrue(run_validation()['passed'])

    def test_raw_source_warnings_are_not_current_candidate_errors(self):
        rows = {r['headword']: r for r in self.review['records']}
        # These blind source findings were real, but C2 already qualified them.
        for w in ('carve', 'nuclear', 'bias', 'transaction'):
            self.assertTrue(rows[w]['adjudication']['source_findings_not_auto_transferred'])
            self.assertFalse(rows[w]['adjudication']['confirmed_evidence_supported_findings'])

    def test_omission_is_not_a_wrong_pos_claim(self):
        issues = {i['headword']: i for i in self.review['confirmed_findings']}
        self.assertTrue(issues['import']['important_omission'])
        self.assertFalse(issues['import']['pos_confusion'])
        self.assertEqual(issues['management']['domain'], 'original_source_important_use_coverage_gap')
        self.assertFalse(issues['management']['translation_falsehood'])

    def test_new_major_findings_came_from_nonmajor_sample(self):
        rows = {r['headword']: r for r in self.review['records']}
        for w in ('import', 'management'):
            self.assertEqual(rows[w]['selection']['role'], 'stratified_audit')
            self.assertEqual(rows[w]['selection']['prior_severity'], 'Minor')
        self.assertEqual(self.review['summary']['strict_standard_risk_sample_confirmed_findings']['Major'], 0)

    def test_semantic_split_keeps_unique_original_and_multiple_uses(self):
        c = self.candidates['import']
        self.assertTrue(self.candidate_valid(c))
        self.assertEqual(len(c['original_meanings']), 2)
        self.assertEqual([g['part_of_speech'] for g in c['core_meanings']], ['动词', '名词'])
        self.assertEqual(c['core_meanings'][0]['source_sense_ids'], c['core_meanings'][1]['source_sense_ids'])

    def test_missing_split_explanation_is_rejected(self):
        c = copy.deepcopy(self.candidates['import']); del c['semantic_splits']
        with self.assertRaisesRegex(ValueError, 'one-to-many'):
            self.candidate_valid(c)

    def test_wrong_headword_evidence_is_rejected(self):
        c = copy.deepcopy(self.candidates['import'])
        c['core_meanings'][0]['evidence_ids'] = ['wn31:v:00925764']
        c['supporting_sources'].append({'evidence_id': 'wn31:v:00925764'})
        with self.assertRaisesRegex(ValueError, 'another headword'):
            self.candidate_valid(c)

    def test_raw_original_edit_is_rejected(self):
        c = copy.deepcopy(self.candidates['indicate']); c['original_meanings'][0]['text'] = '伪造'
        with self.assertRaisesRegex(ValueError, 'Immutable'):
            self.candidate_valid(c)

    def test_external_addition_cannot_claim_original_id(self):
        c = copy.deepcopy(self.candidates['management']); c['dictionary_additions'][-1]['source_sense_ids'] = ['s003']
        with self.assertRaisesRegex(ValueError, 'External content'):
            self.candidate_valid(c)

    def test_human_approval_cannot_be_inferred(self):
        c = copy.deepcopy(self.candidates['management']); c['human_approved'] = True
        with self.assertRaisesRegex(ValueError, 'human approved'):
            self.candidate_valid(c)

    def test_same_backend_identity_and_same_word_double_review_not_fabricated(self):
        self.assertFalse(self.review['independence']['proven_different_model_identity'])
        self.assertIsNone(self.review['summary']['proven_different_backend_model_disagreement_words'])
        self.assertEqual({r['reviewer'] for r in self.review['records']}, {'A', 'B'})
        self.assertEqual(len({r['stable_id'] for r in self.review['records']}), 90)

    def test_old_high_risk_not_cleared_and_gate_not_open(self):
        self.assertEqual(len(self.review['inherited100_pending_queue']), 48)
        self.assertTrue(all(r['status'] == 'pending_not_auto_passed' for r in self.review['inherited100_pending_queue']))
        self.assertEqual(self.review['quality_gate']['decision'], 'B')
        self.assertFalse(self.review['quality_gate']['expand_remaining_4832_now'])

    def test_pending_risk_union_is_distinct_from_confirmed_error_count(self):
        queue = self.review['focused_pending_priority_queue']
        self.assertEqual(len(queue), len({r['stable_id'] for r in queue}))
        self.assertEqual(len(queue), 85)
        self.assertEqual(len(self.review['confirmed_findings']), 3)
        self.assertTrue(all('not_an_error_count' in r['status'] for r in queue))


if __name__ == '__main__':
    unittest.main()
