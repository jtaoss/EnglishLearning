"""Validate source-only independent proposals and freeze hashes before comparison."""
import collections
import hashlib
import json
import pathlib
from prepare_review import ROOT,OUT,PRIVATE,load,write_once,state,preservation_check


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    preservation_check()
    manifest={'protocol':'source_only_fresh_context_then_sealed_proposal_then_comparison',
        'configured_review_model':'gpt-6-astra','original_generator_backend':None,
        'proven_different_model_identity':False,
        'identity_limit':'Original backend was not exposed; separate contexts and configured reviewer model are recorded, not proof of a different original backend.',
        'reviewer_jobs':2,'actual_tokens':None,'actual_cost':None,'reviewers':{}}
    all_ids=[]
    for name in ['A','B']:
        packet_path=PRIVATE/f'blind_packet_{name}.json'
        review_path=OUT/'blind_reviews'/f'reviewer_{name}.json'
        packet=json.loads(packet_path.read_text(encoding='utf-8'))
        reviewed=json.loads(review_path.read_text(encoding='utf-8'))
        assert reviewed['context']=='fresh_fork_none_source_only'
        assert reviewed['reviewer_config_model']=='gpt-6-astra'
        assert reviewed['input_sha256']==digest(packet_path)
        assert len(reviewed['records'])==reviewed['record_count']==45
        raw={r['stable_id']:r for r in packet['records']}
        assert len(raw)==45 and {r['stable_id'] for r in reviewed['records']}==set(raw)
        parts=[json.loads((OUT/'blind_reviews'/f'reviewer_{name}_part_{i}.json').read_text(encoding='utf-8')) for i in range(1,4)]
        combined=[]
        for part in parts:
            items=part['records'] if isinstance(part,dict) else part
            assert len(items)==15
            combined+=items
        assert combined==reviewed['records']
        for r in reviewed['records']:
            original=raw[r['stable_id']]
            assert r['headword']==original['headword'] and r['source_hash']==original['source_hash']
            assert r['original_meaning_zh']==original['original_meaning_zh']
            assert r['original_meanings']==original['original_meanings']
            assert r['human_approved'] is False and r['is_AI_candidate'] is True
            ids={a['source_sense_id'] for a in original['original_meanings']}
            mapped=[]
            evidence={e['evidence_id']:e for e in r['evidence_sources']}
            wn={e['evidence_id']:e for e in original['unfiltered_wordnet_senses']}
            for eid,e in evidence.items():
                if eid.startswith('wn31:'):
                    assert eid in wn,'Wrong-headword WordNet evidence'
                    assert e['definition_en']==wn[eid]['definition_en'],'Changed WordNet definition'
            for layer in ['core_meanings','extended_meanings','other_meanings']:
                for g in r[layer]:
                    assert g['display_zh'] and g['part_of_speech'] and g['source_sense_ids'] and g['evidence_ids']
                    mapped+=g['source_sense_ids']
                    for e in g['evidence_ids']:
                        assert e in evidence
                        if e.startswith('wn31:'):assert e in wn,'Wrong-headword WordNet evidence'
            mapped += [x['source_sense_id'] for x in r['reserved_original_items']]
            assert set(mapped)==ids,'Blind proposal lost/invented source'
            if len(mapped)!=len(set(mapped)):
                splits=r.get('semantic_splits') or r.get('semantic_split_notes') or r.get('ai_semantic_splits')
                assert splits,'Unexplained repeated source reference'
                repeated={s for s,n in collections.Counter(mapped).items() if n>1}
                assert repeated <= {s['source_sense_id'] for s in splits},'Repeated reference missing explicit split annotation'
            for added in r['dictionary_additions']:
                assert added['source_sense_ids']==[] and added['evidence_ids']
                assert all(e in evidence for e in added['evidence_ids'])
            # Previous-model groups/labels are absent from the source packet.
            forbidden={'core_meanings','extended_meanings','other_meanings','risk_level','prior_severity','old_candidate','ai_semantic_review'}
            assert not forbidden.intersection(original)
        all_ids+=list(raw)
        manifest['reviewers'][name]={'input_sha256':digest(packet_path),'proposal_sha256':digest(review_path),
            'records':45,'source_fragments':sum(len(r['original_meanings']) for r in packet['records']),
            'backend_snapshot':reviewed.get('backend_snapshot'),'cost':reviewed.get('cost'),
            'path':review_path.relative_to(ROOT).as_posix()}
    assert len(all_ids)==len(set(all_ids))==90
    write_once(OUT/'BLIND_REVIEW_MANIFEST.json',manifest)
    print(json.dumps({'sealed_reviewers':2,'records':90,'fresh_source_only_context':True,'different_original_backend_proven':False}))


if __name__=='__main__':main()
