"""Adversarial provenance tests plus explicit semantic regression examples."""

import copy
import unittest

from validate_pilot import canonical_hash, inputs, validate


class PilotTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = inputs()

    def altered(self, action, resign=False):
        args = copy.deepcopy(self.fixture)
        record = args[0]["records"][0]
        action(args, record)
        if resign:
            record["decision_hash"] = canonical_hash({k: v for k, v in record.items() if k != "decision_hash"})
            args[4]["records"][0]["decision_hash"] = record["decision_hash"]
        with self.assertRaises(ValueError):
            validate(*args)

    def test_complete_selected_inventory(self):
        summary = validate(*self.fixture)
        self.assertEqual(summary["source_atoms"], 263)
        self.assertEqual(summary["human_status_counts"], {"pending": 100})

    def test_duplicate_ids_rejected(self):
        self.altered(lambda a, r: a[0]["records"].__setitem__(1, copy.deepcopy(r)))

    def test_foreign_word_rejected(self):
        self.altered(lambda a, r: r.update(stable_id="SG25-not-selected"))

    def test_formal_source_drift_rejected(self):
        self.altered(lambda a, r: r["source_fields"].update(meaning_zh="被篡改的中文"), resign=True)

    def test_changed_explanation_rejects_stale_human_review(self):
        args = copy.deepcopy(self.fixture)
        record = args[0]["records"][0]
        record["core_explanation"] = "修订后的说明"
        record["decision_hash"] = canonical_hash({k: v for k, v in record.items() if k != "decision_hash"})
        with self.assertRaisesRegex(ValueError, "Stale human"):
            validate(*args)

    def test_removed_gloss_and_trace_both_detected(self):
        def remove(args, record):
            record["other_meanings"] = []
            record["source_senses"] = [a for a in record["source_senses"] if a["text"] != "替身"]
        self.altered(remove, resign=True)

    def test_duplicated_sense_detected(self):
        self.altered(lambda a, r: r["extended_meanings"].append(copy.deepcopy(r["core_meanings"][0])), resign=True)

    def test_cross_pos_merge_detected(self):
        self.altered(lambda a, r: r["core_meanings"][0].update(part_of_speech="名词"), resign=True)

    def test_invented_gloss_detected(self):
        self.altered(lambda a, r: r["core_meanings"][0]["glosses"].__setitem__(0, "官方必考释义"), resign=True)

    def test_source_offsets_detected(self):
        self.altered(lambda a, r: r["source_senses"][0].update(start=0), resign=True)

    def test_unsigned_approval_rejected(self):
        self.altered(lambda a, r: a[4]["records"][0].update(status="approved"))

    def test_semantic_boundaries_and_multiple_important_senses(self):
        records = {r["headword"]: r for r in self.fixture[0]["records"]}
        for word, distinct in {"light": {"光", "灯", "轻的"}, "bank": {"银行", "河岸"},
                               "miss": {"错过", "想念"}, "get": {"得到", "变得", "到达"}}.items():
            with self.subTest(word=word):
                groups = records[word]["core_meanings"]
                self.assertTrue(distinct <= {g["glosses"][0] for g in groups})
        self.assertTrue(all(g["part_of_speech"] == "待核实" for key in ("core_meanings", "extended_meanings") for g in records["knock"][key]))
        self.assertEqual(records["aisle"]["other_meanings"][0]["glosses"], ["林中小径"])


if __name__ == "__main__":
    unittest.main()
