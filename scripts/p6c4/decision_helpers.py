"""Declarative helpers, no automatic semantic selection or model calls."""
def g(pos,text,ids,refs,note=''):
    return {'part_of_speech':pos,'display_zh':text,'source_sense_ids':[f's{i:03d}' for i in ids],
            'evidence_ids':[x if x.startswith('pub:') else 'wn31:'+x for x in refs.split(',')],
            'usage_note':note}

def a(pos,text,refs,reason):
    return {'part_of_speech':pos,'meaning_zh':text,'source_sense_ids':[],
            'evidence_ids':[x if x.startswith('pub:') else 'wn31:'+x for x in refs.split(',')],
            'reason':reason,'status':'AI_candidate_not_adopted','human_approved':False,'auto_promoted_to_core':False}

def d(core,explanation,extended=(),other=(),reserved=(),additions=(),splits=None,flags=()):
    return {'core_meanings':list(core),'extended_meanings':list(extended),'other_meanings':list(other),
            'reserved_original_items':list(reserved),'dictionary_additions':list(additions),
            'core_explanation':explanation,'semantic_split_reasons':splits or {},'risk_flags':list(flags)}
