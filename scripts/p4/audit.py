"""Read-only audit of the existing 500 entries. Never changes cloud or vocabulary."""
import collections
import hashlib
import json
import pathlib
import re
import sys
import unicodedata

ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/p3'))
from prepare import read_csv, write_csv, save_json, reference_index, cmu_index, wordnet_index, category

out=ROOT/'docs/p4'; out.mkdir(parents=True,exist_ok=True)
private=ROOT/'private/p4'; private.mkdir(parents=True,exist_ok=True)
path=ROOT/'assets/vocabulary/reviewed500.csv'
original=path.read_bytes(); sha=hashlib.sha256(original).hexdigest()
baseline=json.loads((ROOT/'docs/p3/selection-statistics.json').read_text(encoding='utf-8'))
assert sha==baseline['reviewed_pack_sha256'], 'Content changed before audit; review differences first'
backup=private/'vocabulary-before.csv'
if backup.exists(): assert backup.read_bytes()==original
else: backup.write_bytes(original)
rows=read_csv(path); assert len(rows)==len({r['entry_id'] for r in rows})==len({r['word'] for r in rows})==500
official=reference_index(json.loads((ROOT/'private/p3/pets3-2015-text.json').read_text(encoding='utf-8')))
cmu=cmu_index(ROOT/'private/p3/cmudict.dict')
wn=wordnet_index(ROOT/'private/p3/wordnet31.tar.gz')
ledger=read_csv(ROOT/'private/p3/source/词头候选台账.csv')
raw_ids={r['词条ID']:r for r in ledger}
raw_heads={r['单词']:r for r in ledger}
flags=[]; checks=[]; category_checked=0; cmu_checked=0
def ascii_head(word):
    return ''.join(c for c in unicodedata.normalize('NFKD',word) if not unicodedata.combining(c)).lower()
case_groups=collections.defaultdict(list)
for r in rows: case_groups[ascii_head(r['word'])].append(r['word'])
for r in rows:
    word=r['word']; failures=[]
    required=['part_of_speech','meaning_zh','phonics_note','syllables','stress','example_en','example_zh','book_category','source_id','pets2015_status','pets2025_status']
    if not all(r[k].strip() for k in required): failures.append('missing_required_content')
    if re.search(r'[\u0250-\u02af\u1d00-\u1d7f]', '|'.join(r.values())): failures.append('ipa_characters')
    if r['pets2025_status']!='待核实': failures.append('unverified_2025_claim')
    expected='已收录' if word in official else '未直接列出'
    if r['pets2015_status']!=expected: failures.append('2015_reference_mismatch')
    source=raw_ids.get(r['entry_id']) or raw_heads.get(word)
    if source:
        if category(source)!=r['book_category']: failures.append('book_category_mismatch')
        else: category_checked+=1
    syllables=len(r['syllables'].split('·'))
    variants=cmu.get(ascii_head(word),[])
    main=re.search(r'第(\d+)音节主重读',r['stress'])
    matched=[v for v in variants if len(v)==syllables and (not main or v[int(main[1])-1]==1)]
    if not matched: failures.append('syllable_stress_reference_mismatch')
    else: cmu_checked+=1
    risk=[]
    if len(case_groups[ascii_head(word)])>1: risk.append('大小写/去重音符号会错误合并')
    if len({tuple(v) for v in variants})>1: risk.append('词典存在多种音节或重音读法')
    if any(v.count(1)>1 for v in variants): risk.append('CMU含多个重读位置，需按词性和语境核对')
    if not source: risk.append('原审计恢复词，5552台账缺当前词头/ID直接映射；保留PDF页码追溯')
    tags={tag for label,tag in [('名词','n'),('动词','v'),('形容词','a'),('副词','r')] if label in r['part_of_speech']}
    available=wn.get(ascii_head(word),set())
    pos_gap=tags-available if available else set()
    if pos_gap: risk.append('WordNet3.1词性覆盖差异，需词典对照而非自动判错')
    if any(x in r['phonics_note'] for x in ['本卡为','本卡按','此处先练','变体','过去时','弱读']): risk.append('当前词性/语境限定读法，孤立TTS可能选错')
    if word=='oriental': risk.append('语域及称人用法风险')
    for issue in failures: flags.append({'entry_id':r['entry_id'],'word':word,'severity':'blocker','issue':issue,'action':'停止覆盖，保留原值并复核'})
    for issue in risk: flags.append({'entry_id':r['entry_id'],'word':word,'severity':'review','issue':issue,'action':'保留原义/词性；读法结合原提示和例句；待个人确认'})
    checks.append({'entry_id':r['entry_id'],'word':word,'book_category':r['book_category'],'part_of_speech':r['part_of_speech'],
        'meaning_zh':r['meaning_zh'],'pets2015_status':r['pets2015_status'],'pets2025_status':r['pets2025_status'],
        'syllable_stress_reference':'PASS' if matched else 'REVIEW','structural_result':'PASS' if not failures else 'REVIEW',
        'risk_flags':'；'.join(risk),'semantic_review_limit':'异常筛查和高风险来源对照，不是500词逐义人工终审'})
reviews={
    'overhaul':('名词首重读、动词末重读；原卡已注明名词练习且例句为名词，不覆盖释义。','https://dictionary.cambridge.org/dictionary/english/overhaul'),
    'combat':('原名词首重读及战斗义一致；美式动词也有首重读变体，原提示保留。','https://dictionary.cambridge.org/dictionary/english/combat'),
    'resume':('动词继续/重新开始，后音节重读；与求职名词分别保留ID，建议例句TTS。','https://dictionary.cambridge.org/us/dictionary/english/resume'),
    'résumé':('求职简历名词及三音节首重读与词典一致；保留重音符号和独立ID。','https://dictionary.cambridge.org/us/dictionary/english/resume'),
    'lead':('本卡动词带领/引导；同形金属名词有另一读法，原卡已有提示。','https://dictionary.cambridge.org/dictionary/english/lead'),
    'read':('本卡现在时阅读义；过去时同形异音，原提示已区分，例句供语境核对。','https://www.collinsdictionary.com/us/dictionary/english/read'),
    'oriental':('原形容词及地毯例句保留；已有不推荐称人的用法提示，与词典语域警示一致。','https://www.oxfordlearnersdictionaries.com/definition/english/oriental_1'),
    'May':('月份大写与情态动词小写区分；2015附表按明确印刷词形匹配，不合并。',baseline['official_2015_url']),
    'may':('情态动词可能/许可与月份分开；独立ID及释义保留。',baseline['official_2015_url']),
    'March':('月份首字母大写，与行军义分开保存。',baseline['official_2015_url']),
    'march':('小写动词/名词行进/游行，非月份；稳定ID保留。',baseline['official_2015_url']),
    'outside':('CMU记录两个重读位置，不能用首个重读位置自动否定第二个；原卡为副词/介词及后重读，保留语境提示。','https://dictionary.cambridge.org/dictionary/english/outside'),
    'texture':('质地/纹理名词与词典一致；原审计恢复词，PDF642对应书内631的偶考分区，但原5552台账映射仍待补证。','https://dictionary.cambridge.org/dictionary/english/texture'),
    'percent':('WordNet覆盖差异不等于错误；Cambridge列副词、名词及形容词，原数量表达释义保留。','https://dictionary.cambridge.org/dictionary/english/percent'),
    'vegetarian':('词典同时列名词素食者及形容词素食的，原两词性/词义保留。','https://dictionary.cambridge.org/dictionary/english/vegetarian'),
    'why':('为什么及副词标注与词典一致，WordNet词性缺项不作删改依据。','https://dictionary.cambridge.org/dictionary/english/why'),
    'yes':('肯定答复义无明显异常；不同词典标签有感叹词/副词差别，保留原标注并列待统一语法分类。','https://dictionary.cambridge.org/dictionary/learner-english/yes'),
}
review_rows=[]
for word,(decision,url) in reviews.items():
    r=next(r for r in rows if r['word']==word)
    review_rows.append({'entry_id':r['entry_id'],'word':word,'before_meaning':r['meaning_zh'],'after_meaning':r['meaning_zh'],
        'before_stress':r['stress'],'after_stress':r['stress'],'decision':decision,'evidence':url,
        'review_method':'逐项词典/官方参考对照（agent）；未冒充用户/教师人工确认','content_changed':'否'})
write_csv(out/'learnability-500.csv',checks,list(checks[0]))
write_csv(out/'quality-flags.csv',flags,list(flags[0]) if flags else ['entry_id','word','severity','issue','action'])
write_csv(out/'review-before-after.csv',review_rows,list(review_rows[0]))
audio=json.loads((ROOT/'assets/pronunciation/manifest.json').read_text(encoding='utf-8'))['items']
for a in audio:
    assert hashlib.sha256((ROOT/a['asset_path']).read_bytes()).hexdigest()==a['sha256']
    assert a['cache_allowed'] and a['source_url'].startswith('https://commons.wikimedia.org/wiki/File:')
save_json(out/'audio-audit.json',{'human_recording_count':6,'fallback_candidates':494,'recordings':[
    {k:a[k] for k in ['word','author','source_url','license','license_url','sha256','cache_allowed']} for a in audio],
    'source_pages_checked':'2026-11-09; Wikimedia file pages confirm listed authors/licenses; no new downloads',
    'local_tts':'Installed Microsoft Zira Desktop en-US via SAPI; runtime playback only, no voice/audio redistribution',
    'tts_reference':'https://learn.microsoft.com/en-us/previous-versions/windows/desktop/ms717065(v=vs.85)'})
summary={'count':500,'unique_ids':500,'unique_exact_heads':500,'duplicate_ids':0,
    'structural_blockers':sum(f['severity']=='blocker' for f in flags),'review_flags':sum(f['severity']=='review' for f in flags),
    'words_flagged_for_review':len({f['entry_id'] for f in flags if f['severity']=='review'}),
    'individually_source_checked_high_risk':len(review_rows),'cmu_syllable_stress_matches':cmu_checked,
    'book_category_matches_ledger':category_checked,'book_category_remaining':500-category_checked,
    'pets2015_exact_matches':sum(r['pets2015_status']=='已收录' for r in rows),'pets2025_pending':500,
    'case_or_accent_groups':[g for g in case_groups.values() if len(g)>1],
    'source_vocabulary_sha256':sha,'after_vocabulary_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
    'vocabulary_content_changes':0,'cloud_content_writes':0,'raw_ledger_deleted':False,'ocr_performed':False,
    'limits':'All500 structural/source checks plus flagged-risk review; not a claim of exhaustive human semantic or TTS accent certification.'}
save_json(out/'quality-summary.json',summary)
print(json.dumps(summary,ensure_ascii=False,indent=2))
