"""Corruption tests and reviewer-specific policy regressions; no DB or network."""

import copy
import unittest

from validate_review import digest, inputs, validate


class ReviewTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = inputs()

    def corrupt(self, word, mutation):
        args = copy.deepcopy(self.fixture)
        record = next(r for r in args[0]["records"] if r["headword"] == word)
        mutation(record)
        record["review_hash"] = digest({k: v for k, v in record.items() if k != "review_hash"})
        with self.assertRaises(ValueError):
            validate(*args)

    def test_full_100_and_263_original_glosses(self):
        self.assertEqual(validate(*self.fixture)["preserved_original_glosses"], 263)

    def test_omitting_original_and_its_alignment_both_is_detected(self):
        def remove(r):
            r["reserved_original_items"] = []
            r["source_alignment"] = [a for a in r["source_alignment"] if a["source_sense_id"] != "s001"]
        self.corrupt("notify", remove)

    def test_added_meaning_cannot_claim_original_provenance(self):
        self.corrupt("run", lambda r: r["dictionary_addition_candidates"][0].update(source_sense_ids=["s001"]))

    def test_added_meaning_cannot_claim_formal_origin(self):
        self.corrupt("run", lambda r: r["dictionary_addition_candidates"][0].update(origin="formal_gloss"))

    def test_evidence_of_another_word_is_rejected(self):
        self.corrupt("run", lambda r: r["dictionary_addition_candidates"][0].update(evidence_ids=["wn31:n:03005231"]))

    def test_invented_reference_is_rejected(self):
        self.corrupt("run", lambda r: r["source_alignment"][0].update(evidence_ids=["wn31:v:99999999"]))

    def test_part_of_speech_merge_is_rejected(self):
        self.corrupt("major", lambda r: r["proposed_layers"]["core_meanings"][0].update(part_of_speech="动词"))

    def test_memory_cluster_cannot_erase_subsense_distinctions(self):
        self.corrupt("chop", lambda r: r["proposed_layers"]["core_meanings"][0].update(source_subsenses=[]))

    def test_duplicate_source_assignment_is_rejected(self):
        self.corrupt("chop", lambda r: r["proposed_layers"]["extended_meanings"].append(copy.deepcopy(r["proposed_layers"]["core_meanings"][0])))

    def test_fake_human_signoff_is_rejected(self):
        self.corrupt("bank", lambda r: r.update(human_confirmation="approved"))

    def test_scope_cannot_expand_to_5332(self):
        args = copy.deepcopy(self.fixture)
        args[0]["records"].append(copy.deepcopy(args[0]["records"][0]))
        with self.assertRaises(ValueError):
            validate(*args)

    def test_multisense_and_pos_recommendations_remain_distinct(self):
        records = {r["headword"]: r for r in self.fixture[0]["records"]}
        self.assertEqual(len(records["get"]["proposed_layers"]["core_meanings"]), 4)
        self.assertEqual(len(records["major"]["proposed_layers"]["core_meanings"]), 3)
        self.assertEqual(records["knock"]["source_alignment"][0]["part_of_speech"], None)
        self.assertEqual(records["knock"]["proposed_layers"]["core_meanings"][0]["part_of_speech"], "动词")

    def test_uncertain_translations_are_reserved_without_erasing_original(self):
        records = {r["headword"]: r for r in self.fixture[0]["records"]}
        self.assertEqual(records["notify"]["reserved_original_items"][0]["original_gloss"], "使注意")
        self.assertIn("使注意", records["notify"]["original_meaning_zh"])
        self.assertEqual(records["obvious"]["reserved_original_items"][0]["state"], "contextual_paraphrase_only")
        self.assertIn("n:08005299", str(records["couple"]["dictionary_addition_candidates"]))


if __name__ == "__main__":
    unittest.main()
