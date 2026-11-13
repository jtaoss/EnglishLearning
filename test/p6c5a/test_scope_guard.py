"""Scope-guard contracts: preserve sources, evidence, uncertainty and old state."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/p6c5a'))
from common import OUT,read,sha,RULES,RELATIONS
from scope_guard import decision,validate_result,make_mappings
from extra_checks import packet_integrity,advisory_text_risks

class ScopeGuardContracts(unittest.TestCase):
    def setUp(self):
        self.p={'id':'unit:scope','word':'unit-scope','source_pos':'名词','raw':'资料；文件',
                'senses':[{'source_sense_id':'s001','text':'资料','part_of_speech':'名词','pos_evidence':'single_pos_field','start':0,'end':2},
                          {'source_sense_id':'s002','text':'文件','part_of_speech':'名词','pos_evidence':'single_pos_field','start':3,'end':5}],
                'evidence':[{'id':'lex:unit','definition':'information or documents','pos':'n'}],
                'groups':[{'id':'g1','source_ids':['s001'],'evidence_ids':['lex:unit'],'pos':'名词','text':'资料','note':'一般资料','layer':'core_meanings'},
                          {'id':'g2','source_ids':['s002'],'evidence_ids':['lex:unit'],'pos':'名词','text':'文件','note':'保留在扩展','layer':'extended_meanings'}],
                'held':[],'reason':'教学建议，不主张义项频率。'}
        self.m={'sid':'s001','source_scope':'一般资料','relation':'语义等价','reason':'来源和保留目标对象一致。',
                'evidence_ids':['lex:unit'],'context':'none','residual_scope':'','counterexample':'',
                'counterexample_evidence_ids':[],'risk':'none'}
        self.row={'id':'unit:scope','mappings':[self.m,{**self.m,'sid':'s002','source_scope':'文件'}],
                  'word_status':'complete','core_status':'justified_deferred','issues':[],'note':'文件在扩展保留，不是全词丢义。'}

    def result(self):return {'requested_model':'model','response_model':'model','finish_reason':'stop','content':json.dumps({'records':[self.row]},ensure_ascii=False)}
    def test_union_preserves_extension_not_all_source_required_in_core(self):
        self.assertTrue(packet_integrity(self.p))
        self.assertEqual(len(validate_result(self.result(),[self.p],'audit')),1)
    def test_Chinese_substring_does_not_clear_known_narrowing(self):
        self.p['groups'][0]['text']='资料（仅医学资料）'
        self.m.update(relation='范围收窄',context='unlicensed_limit',residual_scope='非医学资料',counterexample='法律资料',counterexample_evidence_ids=['lex:unit'],risk='suspected_Major')
        self.assertIn('资料',self.p['groups'][0]['text'])
        self.assertEqual(decision(self.m),'scope_risk_requires_evidence_adjudication')
    def test_licensed_context_or_example_is_not_automatic_defect(self):
        self.m['context']='example_not_exclusive'
        self.assertEqual(decision(self.m),'AI_no_obvious_scope_defect_not_human_approved')
        self.m['context']='required_from_source'
        self.assertEqual(decision(self.m),'AI_no_obvious_scope_defect_not_human_approved')
    def test_unknown_is_pending_not_semantically_passed(self):
        self.m.update(relation='无法确定',risk='pending',context='uncertain')
        self.assertEqual(decision(self.m),'evidence_pending_not_passed')
    def test_narrowing_cannot_be_marked_no_risk_without_remainder(self):
        self.m.update(relation='范围收窄',risk='none')
        with self.assertRaisesRegex(ValueError,'silently passed'):validate_result(self.result(),[self.p],'audit')
    def test_source_id_loss_rejected(self):
        self.row['mappings']=self.row['mappings'][:1]
        with self.assertRaisesRegex(ValueError,'fragment audit'):validate_result(self.result(),[self.p],'audit')
    def test_wrong_model_ID_or_word_ID_not_silently_reconciled(self):
        self.row['id']='unit:truncated'
        with self.assertRaisesRegex(ValueError,'review IDs'):validate_result(self.result(),[self.p],'audit')
    def test_missing_publisher_reference_fails_graph_preflight(self):
        self.p['groups'][0]['evidence_ids']=['publisher:omitted']
        with self.assertRaisesRegex(ValueError,'omitted from packet'):packet_integrity(self.p)
        self.p['evidence'].append({'id':'publisher:omitted','definition':'actual supplied original observation'})
        self.assertTrue(packet_integrity(self.p))
    def test_cited_but_not_supplied_counterexample_rejected(self):
        self.m['counterexample_evidence_ids']=['invented:source']
        with self.assertRaisesRegex(ValueError,'Unprovided evidence'):validate_result(self.result(),[self.p],'audit')
    def test_held_fragment_cannot_be_called_complete(self):
        self.p['held']=[{'source_id':'s002','reason':'evidence pending'}]
        with self.assertRaisesRegex(ValueError,'falsely complete'):validate_result(self.result(),[self.p],'audit')
    def test_frequency_scan_is_only_an_advisory_alarm(self):
        self.p['reason']='最常用的解释；没有义项统计。'
        flags=advisory_text_risks(self.p)
        self.assertEqual(len(flags),1)
        self.assertFalse(flags[0]['confirmed_error'])
        self.p['reason']='不宣称最常用。'
        self.assertFalse(advisory_text_risks(self.p)[0]['confirmed_error'])
    def test_relation_schema_includes_all_six_without_word_hardcodes(self):
        self.assertEqual(set(RELATIONS),{'语义等价','合理概括','范围收窄','范围扩大','语义不匹配','无法确定'})

class RealRegressionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not (OUT/'regression_700.json').exists():raise unittest.SkipTest('Final regression not yet assembled')
        cls.data=read(OUT/'regression_700.json');cls.rs=cls.data['records']
    def test_exact_existing700_no_701st(self):
        self.assertEqual(len(self.rs),700)
        self.assertEqual({r['stable_id'] for r in self.rs},set(read(OUT/'INPUT_SETS.json')['all700']))
    def test_all_1702_source_fragments_retained(self):
        self.assertEqual(sum(len(r['candidate']['original_meanings']) for r in self.rs),1702)
        self.assertTrue(all(r['human_approved'] is False for r in self.rs))
    def test_historical48_and_pursue_failure_kept(self):
        hist=set(read(OUT/'INPUT_SETS.json')['historical48'])
        self.assertTrue(all(r['candidate']['historical_risk_retained'] for r in self.rs if r['stable_id'] in hist))
        p=next(r for r in self.rs if r['headword']=='pursue')
        self.assertEqual(p['prior_review_status'],'review_incomplete_after_bounded_attempts')
        self.assertTrue(p['prior_failure_reconciliation_pending'])
    def test_24_holdout_selection_frozen_and_excludes_repairs(self):
        h=read(OUT/'HOLDOUT_SELECTION.json');s=read(OUT/'INPUT_SETS.json')
        self.assertEqual(h['count'],24)
        self.assertFalse(set(s['holdout24'])&set(s['repair4']))
        self.assertFalse(read(OUT/'HOLDOUT_PROPOSAL_SEAL.json')['no_wrong_ID_remapping'] is False)
    def test_reused600_semantic_content_not_rewritten(self):
        old={r['stable_id']:r for r in read(ROOT/'docs/p6/p6c5/core_meanings_5332_candidates.json')['records']}
        reused=set(read(OUT/'INPUT_SETS.json')['reused600'])
        for r in self.rs:
            if r['stable_id'] in reused:
                for k in ['core_meanings','extended_meanings','other_meanings','original_meanings','reserved_original_items','dictionary_additions']:
                    self.assertEqual(r['candidate'][k],old[r['stable_id']][k])

    def test_known_narrowing_detected_before_and_not_silently_removed_after(self):
        before=read(OUT/'reviews/calibration_before.json')['records']
        after=read(OUT/'reviews/calibration_after_evidence_reconciled.json')['records']
        by={r['stable_id']:r for r in self.rs}
        for word in ('ritual','extend'):
            sid=next(r['stable_id'] for r in self.rs if r['headword']==word)
            a=next(r for r in before if r['id']==sid)['mappings'][0]
            b=next(r for r in after if r['id']==sid)['mappings'][0]
            self.assertEqual(a['relation'],'范围收窄')
            self.assertIn(b['relation'],('语义等价','合理概括'))
            self.assertFalse(by[sid]['human_approved'])
        e=next(r for r in self.rs if r['headword']=='extend')
        self.assertTrue(e['candidate']['reserved_original_items'])

    def test_no_categorical_contact_causative_false_gold(self):
        obs=read(OUT/'SUPPLEMENTAL_PUBLISHER_OBSERVATIONS.json')['records']
        c=next(r for r in obs if r['headword']=='contact')
        self.assertIn('使之接触',c['observation_zh'])
        self.assertTrue(c['not_in_frozen_model_packets'])
        a=read(OUT/'PARENT_EVIDENCE_ADJUDICATION.json')['known_four_status']['contact']
        self.assertIn('不能作为整词无使动义',a['evidence_adjudication'])

    def test_second_review_risk_does_not_become_human_signoff(self):
        for word in ('determine','sensitive'):
            r=next(r for r in self.rs if r['headword']==word)
            self.assertEqual(r['parent_evidence_adjudication']['confirmed_severity_for_stated_issue'],'Major')
            self.assertTrue(r['requires_human_review'])
            self.assertFalse(r['human_approved'])

    def test_old_sources_checkpoints_and_database_hashes_preserved(self):
        from common import verify_frozen,verify_protection
        verify_frozen()
        self.assertTrue(verify_protection()['unchanged'])

if __name__=='__main__':unittest.main()
