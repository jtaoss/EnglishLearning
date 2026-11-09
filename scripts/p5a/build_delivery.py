"""Offline, deterministic P5-A selection, read-only Notion diff and validation.

Never opens credentials or performs network calls. Never writes the personal DB.
"""
import collections
import copy
import csv
import hashlib
import json
import pathlib
import re
import shutil
import sqlite3
import sys
import unicodedata

ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/p3'))
from prepare import CORE, EXTRA, MAPPING, PERSONAL
OUT=ROOT/'docs/p5a'
PRIVATE=ROOT/'private/p5a'
OUT.mkdir(parents=True,exist_ok=True)


def load(path):return json.loads((ROOT/path).read_text(encoding='utf-8-sig'))
def digest(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
def json_text(obj):return json.dumps(obj,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def save(name,obj):(OUT/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def csv_write(name,rows,fields=None):
    fields=fields or list(rows[0])
    with open(OUT/name,'w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=fields,extrasaction='ignore');w.writeheader();w.writerows(rows)
def plain(p):
    typ=p['type']
    if typ in ['title','rich_text']:return ''.join(v.get('plain_text',v.get('text',{}).get('content','')) for v in p[typ])
    if typ=='select':return (p[typ] or {}).get('name','')
    return p.get(typ)


raw=load('private/p5a/workbench.json')
assert len(raw)==5552
assert len({r['词条ID'] for r in raw})==5552
assert len({r['单词'] for r in raw})==5552
source_follow={r['entry_id']:r for r in load('private/p5a/source-head-followup.json')}
original_csv=ROOT/'private/p3/source/词头候选台账.csv'
shutil.copyfile(original_csv,OUT/'original_candidates.csv')
old=list(csv.DictReader(open(ROOT/'assets/vocabulary/reviewed500.csv',encoding='utf-8-sig')))
assert digest('assets/vocabulary/reviewed500.csv')=='09cd736d61c40f9614239e451f5894ad464f2ff69a863d50bde95b03b87f651d'
old_ids={r['entry_id']:r for r in old}
current=load('private/p5a/notion-direct-live.json')
assert current['has_more'] is False and current['content_writes']==current['event_uploads']==0
cloud={}
for page in current['results']:
    r={k:plain(p) for k,p in page['properties'].items()}
    assert r['词条ID'] not in cloud
    cloud[r['词条ID']]={**r,'page_id':page['id'],'url':page['url']}
assert set(cloud)==set(old_ids) and len(cloud)==500
for r in old:
    assert all((cloud[r['entry_id']].get(prop) or '')==r[field] for field,prop in MAPPING.items())

# Source-controlled, explicit in-session decisions, persisted in resumable batches.
value={}
for p in sorted((OUT/'value_batches').glob('*.json')):
    for r in json.loads(p.read_text(encoding='utf-8')):
        assert r['candidate_id'] not in value;value[r['candidate_id']]=r
assert len(value)==1145
content={}
for p in sorted((OUT/'content_batches').glob('*.json')):
    for r in json.loads(p.read_text(encoding='utf-8')):
        assert r['candidate_id'] not in content;content[r['candidate_id']]=r
assert len(content)==2144
cow_review_count=len(content)
extended_count=0
for p in sorted((OUT/'extended_content_batches').glob('*.json')):
    for r in json.loads(p.read_text(encoding='utf-8')):
        assert r['candidate_id'] not in content
        r['source_synset']=';'.join(s['id'] for s in r['wordnet_senses'])
        r['english_sense']=' | '.join(s['gloss'] for s in r['wordnet_senses'])
        r['before_meaning']=''
        content[r['candidate_id']]=r;extended_count+=1
assert extended_count==2909 and len(content)==5053
resolutions={r['word']:r for r in load('docs/p5a/quality_resolutions.json') if r['status']=='approved'}
for r in content.values():
    if r['word'] in resolutions:
        fix=resolutions[r['word']]
        r.update(pos=fix['pos'],meaning_zh=fix['meaning_zh'],after_meaning=fix['meaning_zh'],
                 status='approved',review='出版社/官方来源对照后独立编写；非教师终审',
                 evidence_source=fix['evidence'],resolution=fix['decision'],
                 rejected_or_prior_synset=r['source_synset'],source_synset='',
                 english_sense='已改用所列出版社/官方来源；不将原不匹配词网概念当作新义证据')
second_pass={r['word']:r for r in load('docs/p5a/semantic_second_pass.json')}
second_pass_diffs=[]
for r in content.values():
    fix=second_pass.get(r['word'])
    if fix:
        second_pass_diffs.append({'entry_id':r['candidate_id'],'word':r['word'],
            'before':r['meaning_zh'],'after':fix['meaning_zh'],'reason':fix['reason'],'evidence':fix['evidence']})
        r.update(meaning_zh=fix['meaning_zh'],after_meaning=fix['meaning_zh'],second_pass_evidence=fix['evidence'])
csv_write('semantic_second_pass_diffs.csv',second_pass_diffs)
raw_ids={r['词条ID'] for r in raw}
assert set(value)<=raw_ids and set(content)<=raw_ids
audio={r['entry_id']:r for r in load('assets/pronunciation/manifest.json')['items']}
p41=load('docs/p41/texture-mapping.json')
assert p41['after'].startswith('补充映射已核验')
prior_flags=list(csv.DictReader(open(ROOT/'docs/p41/quality-triage.csv',encoding='utf-8-sig')))
flags_by_id=collections.defaultdict(list)
for r in prior_flags:flags_by_id[r['entry_id']].append(r)
mandatory={'高频词','中频词','基础词'}
pos_labels={'n':'名词','v':'动词','a':'形容词','r':'副词'}
special_hold={
    'despite':'词网命中少用名词，未覆盖常用介词；须独立确定词性与义项',
    'unlike':'词网只列形容词，常用介词需单独复核',
    'bible':'大小写及圣经/权威著作义需核对，不从词网大小写折叠自动定义',
    'whatsoever':'限定词/代词标签和语境需核对',
    'dumb':'称人用法和贬义风险需核对',
    'at':'词网误配元素符号At，不能替代介词义',
    'he':'词网误配元素符号He，不能替代代词义',
    'but':'常用连词/介词与词网副词义不能互相替代',
    'except':'常用介词/连词缺义，不能只采用少用动词',
    'while':'常用连词义未覆盖，不能只列名词一会儿',
    'every':'限定词标签需按统一语法规范处理',
    'another':'限定词/代词义需区分',
    'both':'限定词/代词/副词结构需区分',
    'several':'限定词/代词标签需区分',
    'someone':'应核对代词某人，词网普通名词个体义不能直接采用',
    'whatever':'限定词/代词/让步结构需按语境核对',
    'used':'用过的/二手的与be used to结构需分开，词网草稿不足',
    'queer':'现代身份用法、旧义和贬义标签需可靠词典/人工核实',
    'idiot':'侮辱性及过时标签不能作为中性称人释义',
    'renaissance':'小写复兴义与专名文艺复兴需区分，保留原词头',
    'handicap':'不利条件与残障旧称的语域需审定，不直接使用过时称人释义',
    'lame':'身体状态义与贬义修辞需标签复核',
    'dwarf':'称人名词与矮小品种/天体、动词义需用法审定',
    'rape':'暴力犯罪常用义与植物名同形义的呈现需审定',
    'gay':'身份义与旧式快乐义需语域审定，避免采用词网过时称人表述',
    'cock':'公鸡义与粗俗义需加标签并决定教材呈现范围',
    'irrespective':'常用于irrespective of；独立词头的词性标注及固定结构需统一',
}
issues=[]
audit=[]
reason_refinements=[]
for r in raw:
    uid,word=r['词条ID'],r['单词']
    existing=r['existing']
    decision=value.get(uid)
    reviewed=content.get(uid)
    force_keep=r['book_category'] in mandatory
    pets=r['pets2015_status']=='已收录'
    if existing:
        recommendation,mechanism='保留','沿用已验收500词'
        reason=existing['selection_reason']
        confidence='高（已有验收）；不是个人掌握结论'
    elif force_keep:
        recommendation,mechanism='保留','原书必留规则'
        reason='原书高频/中频/基础词必须保留；质量未就绪时进入待核实而非按AI低分暂缓。'
        confidence='高（规则）；内容质量另审'
    elif pets:
        recommendation,mechanism='保留','2015附录明确词形优先'
        reason='2015官方附录明确列出本词形，优先保留；不推断2025归属或官方词频。'
        confidence='高（明确词形参考）；内容质量另审'
    else:
        assert decision is not None,word
        recommendation={'建议保留':'保留','暂缓':'暂缓','待核实':'待核实'}[decision['model_recommendation']]
        mechanism='AI逐词用途建议'
        reason=decision['reason'];confidence=decision['confidence']
    blockers=[];warnings=[]
    if not re.fullmatch(r"[A-Za-zÀ-ÖØ-öø-ÿ]+(?:[-'][A-Za-zÀ-ÖØ-öø-ÿ]+)*",word):
        blockers.append('词头字符模式异常')
    follow=source_follow.get(uid)
    source_ready=existing or r['词头质量']!='待核对正文标题' or bool(follow and follow['hits'])
    if not source_ready:blockers.append('原书正文词头仍待核实')
    if follow:
        warnings.append('PDF已有xref警告；新匹配只作现有文本层辅助证据，未冒充图像终审')
    if not existing:
        if not reviewed:
            blockers.append('常用词性/多义项尚未完成独立中文语义复核' if r['senses'] else '许可词网无直接义项，须独立补释义和词性')
        elif reviewed['status']!='approved':blockers.append(special_hold.get(word,'词性/中文义项待人工复核'))
        if word in special_hold and word not in resolutions and special_hold[word] not in blockers:blockers.append(special_hold[word])
    if recommendation=='待核实':blockers.append(special_hold.get(word,'学习价值或语域仍待核实'))
    blockers=list(dict.fromkeys(blockers))
    if existing:
        fields={k:existing[k] for k in CORE+EXTRA}
        warnings.extend(f['issue'] for f in flags_by_id.get(uid,[]) if f['p41_category']!='数据来源问题')
        quality='沿用P3/P4/P4.1已验收内容；未将历史审计冒称本轮重复终审'
    else:
        fields={k:'' for k in CORE+EXTRA}
        fields.update(entry_id=uid,word=word,book_category=r['book_category'],
            source_file='2025考研英语词汇闪过.pdf',source_id='src_sg25_5e4501eb7237',
            source_pdf_pages=r['PDF页码'],source_index_pages=r['索引PDF页码'],
            book_verification='已核验' if source_ready else '待核验',
            pets2015_status='已收录' if pets else '未直接列出',pets2025_status='待核实',
            learning_priority='P1' if force_keep or pets else 'P2',
            library_class='主学习' if force_keep or pets else '扩展',
            selection_reason=reason,
            phonics_note='',syllables='',stress='',
            reading_review_status='逐词自然拼读教学提示未建设；不得据空白猜造规律；可用现有Windows本地TTS备用',
            audio_status='真人未配置；本机已安装Microsoft en-US Desktop语音时可用本地TTS备用',
            audio_source='真人录音未配置；备用为Windows本地SAPI系统合成语音（不是独立标准录音）',
            audio_license='真人音频授权未取得；TTS仅系统运行时使用；不分发语音引擎或合成录音',
            pets2015_evidence=json_text(r['pets2015_evidence']),
            pets2015_match_method='exact_case_sensitive_explicit_form' if pets else 'complete_explicit_form_lookup_no_hit')
        if reviewed:
            chosen_pos=reviewed['pos']
            pos_label='；'.join(pos_labels[p] for p in chosen_pos) if chosen_pos and all(p in pos_labels for p in chosen_pos) else chosen_pos
            fields.update(meaning_zh=reviewed['meaning_zh'],part_of_speech=pos_label,
                          lexical_sources=reviewed['evidence_source']+(' ; WordNet 3.0 '+reviewed['source_synset'] if reviewed['source_synset'] else ''),
                          meaning_review_status=reviewed['review']+'；同会话检查不是独立教师复核')
        quality='中文草稿经会话逐词语义检查；非教师终审' if reviewed and reviewed['status']=='approved' else '未达到正式内容门槛；保留线索待人工复核'
    current_ai_reason=''
    if decision:
        # Explanatory formatting only, not another model score or corpus-frequency test.
        common=fields['meaning_zh'] if reviewed and reviewed['status']=='approved' else '拟用义项仍待核实'
        chosen=next((s for s in r['senses'] if s['pos'] in (reviewed['pos'] if reviewed else '')),None)
        domain={4:'日常活动和工作叙述',5:'自然和动物阅读',6:'用品、设备和技术阅读',
                8:'身体与健康相关阅读',9:'知识概念和通用阅读',10:'沟通、信息与阅读',
                12:'情绪与人物描写',13:'饮食与生活交流',14:'社会组织与职场阅读',
                15:'地点与出行阅读',18:'人物和社会阅读',20:'自然和植物阅读',
                21:'商务和财务阅读',27:'材料与一般科学阅读',28:'时间表达',
                32:'沟通与信息表达',35:'日常操作和动作叙述',38:'出行与动作叙述'}.get(chosen['lex_file'] if chosen else -1,'通用描述和阅读理解')
        if recommendation=='保留':
            current_ai_reason=f'AI建议保留{word}，用于{domain}；采用的常用义为“{common}”。优先级P2；主观用途判断，无客观语料词频或官方考试频率断言。'
        elif recommendation=='暂缓':
            current_ai_reason=f'AI建议后置{word}（{common}）；本阶段先学通用基础及2015参考词，较专门、历史或低增量用途可稍后学习。仍保留原词条，不认定无价值或官方不考。'
        else:
            current_ai_reason=f'AI对{word}的语域或教材呈现仍有疑点，暂不正式纳入；保留源记录及词典线索，待人工审定。'
        reason_refinements.append({'entry_id':uid,'word':word,'before_first_pass_reason':reason,
            'after_reason':current_ai_reason,'basis':'把已经逐词复核的常用义与许可词网概念域合并为用途说明；不把词网第一义自动当教学义，不是新增模型评分'})
        reason=current_ai_reason
        fields['selection_reason']=reason
    # A selective defer is a learning-order decision, never deletes the source.
    if existing:state='正式入选'
    elif recommendation=='暂缓':state='暂缓学习'
    elif blockers:state='待人工核实'
    else:state='正式入选'
    if state=='正式入选':
        assert fields['meaning_zh'] and fields['part_of_speech'] and fields['entry_id']
        assert not blockers
    for issue in blockers:
        issues.append({'entry_id':uid,'word':word,'severity':'需处理','issue':issue,'disposition':state})
    for warning in warnings:
        issues.append({'entry_id':uid,'word':word,'severity':'警告','issue':warning,'disposition':state})
    provenance=('沿用当前500源核验' if existing else follow['after'] if follow else r['词头质量'])
    row={**fields,'processing_status':state,'recommend_keep':recommendation,
        'selection_method':mechanism,'selection_confidence':confidence,'quality_status':quality,
        'blocking_issues':'；'.join(blockers),'warnings':'；'.join(dict.fromkeys(warnings)),
        'source_verification_method':provenance,'original_printed_pages':r['书内页码'],
        'book_category_status':'沿用既有核验' if existing else ('目录分区及既有索引/正文支持（核验层级见来源状态）' if source_ready else '按既有索引页码暂定位；正文词头待确认'),
        'book_category_evidence':f"原书目录PDF10；候选台账书内页{r['书内页码']}，PDF页{r['PDF页码']}；不是PETS频率",
        'pets2015_reference_status':r['pets2015_status'],'pets2025_verification_status':'待核实',
        'phonics_resource_status':'沿用现有教学提示（原自评状态不包含在数据包）' if existing else '未编写逐词提示；TTS备用不等于自然拼读规则',
        'pronunciation_resource_status':'合法真人录音优先；本地TTS备用' if uid in audio else '无独立真人录音；现有Windows本地TTS备用，需已安装语音',
        'existing_notion':'是' if uid in cloud else '否',
        'ai_model':decision['model'] if decision else '不适用：规则或既有验收',
        'ai_reason':current_ai_reason,
        'ai_reason_first_pass':decision['reason'] if decision else '',
        'ai_confidence':decision['confidence'] if decision else '不适用',
        'historical_ai_reason':(cloud.get(uid,{}).get('AI 筛选理由') or '') if existing else '',
        'historical_ai_score':cloud.get(uid,{}).get('AI 筛选得分') if existing else '',
        'evidence_source':('2015官方附录明确词形；' if pets else '')+
            ('P3/P4/P4.1已有复核记录' if existing else ('WordNet3.0；'+reviewed['evidence_source'] if reviewed else '原始索引台账；WordNet线索，不冒充已核实义项')),
        'source_sense_id':reviewed['source_synset'] if reviewed else '',
        'content_license':'沿用既有独立编写内容及音频许可' if existing else '独立编写/许可COW参考；WordNet式许可及署名见licenses/',
        'candidate_scope':'original_5552',
        'head_change_note':('沿用既有500规范词头；原台账'+word+'→已验收'+fields['word']+'；本轮不重新改ID或全局小写化' if fields['word']!=word else ''),
        **{'original_'+k:v for k,v in r.items() if k in ['单词','词条ID','书内页码','PDF页码','索引PDF页码','词头质量','质量说明','PETS3状态','依据版本','PETS3说明','原始词头','清洗记录','源记录ID']}}
    audit.append(row)

selected=[r for r in audit if r['processing_status']=='正式入选']
deferred=[r for r in audit if r['processing_status']=='暂缓学习']
manual=[r for r in audit if r['processing_status']=='待人工核实']
assert len(selected)+len(deferred)+len(manual)==5552
assert all(r['recommend_keep']=='保留' for r in audit if r['book_category'] in mandatory)
assert not any(r['book_category'] in mandatory for r in deferred)
assert len([r for r in selected if r['existing_notion']=='是'])==499
assert len({r['entry_id'] for r in audit})==5552
assert len({r['word'] for r in audit})==5552
csv_write('all_candidates_audit.csv',audit)
csv_write('selection_reason_refinements.csv',reason_refinements)
csv_write('head_normalizations.csv',[r for r in audit if r['head_change_note']],['entry_id','word','original_单词','head_change_note'])
csv_write('selected_vocabulary.csv',selected)
csv_write('deferred_vocabulary.csv',deferred,list(audit[0]))
csv_write('manual_review.csv',manual,list(audit[0]))
csv_write('quality_anomalies.csv',issues)
csv_write('preserved_existing500.csv',old,CORE+EXTRA)
supplement=[r for r in old if r['entry_id'] not in raw_ids]
assert len(supplement)==1 and supplement[0]['word']=='texture'
csv_write('retained_supplemental.csv',supplement,CORE+EXTRA)
formal=[{k:r[k] for k in CORE+EXTRA} for r in selected]+supplement
csv_write('formal_learning_vocabulary.csv',formal,CORE+EXTRA)

# Content-only mapping; personal learning/notes/dates are deliberately absent.
extra_mapping={'ai_reason':'AI 筛选理由','ai_confidence':'筛选置信度',
    'original_源记录ID':'原记录ID','original_原始词头':'原始词头',
    'original_清洗记录':'清洗记录','original_书内页码':'原书书内页码',
    'book_category_evidence':'分类依据'}
schema=current['schema']['properties']
assert set(MAPPING.values())<=set(schema)
assert not set(MAPPING.values()) & PERSONAL
mapping=[]
for field,prop in {**MAPPING,**extra_mapping}.items():
    mapping.append({'csv_field':field,'notion_property':prop,'notion_type':schema[prop]['type'],
                    'policy':'只预览内容；已有条目无变化则不更新；禁止个人状态/日期字段'})
mapping.extend([
    {'csv_field':'candidate_scope','notion_property':'原5552台账内','notion_type':'select',
     'policy':'仅新增原5552候选写入是；texture既有恢复历史原样保留'},
    {'csv_field':'pronunciation_resource_status','notion_property':'发音资源状态','notion_type':'select',
     'policy':'新增词未配置独立真人录音：未配置；本地TTS备用另记音频许可状态/来源，不等同真人'}])
csv_write('field_mapping.csv',mapping)
preview=[]; payloads=[]; conflicts=[]
for row in audit+[{**r,'candidate_scope':'retained_recovered','processing_status':'正式入选',
                  'existing_notion':'是','ai_reason':'','ai_confidence':'不适用'} for r in supplement]:
    uid=row['entry_id'];before=cloud.get(uid)
    if before:
        payload={}
        if before['单词']!=row['word']:conflicts.append({'id':uid,'word':row['word'],'issue':'existing ID has different head'})
        for f,prop in MAPPING.items():
            if (before.get(prop) or '') != (row.get(f) or ''):payload[prop]=row.get(f) or ''
        action='更新' if payload else '保持不变'
    elif row['processing_status']!='正式入选':payload={};action='跳过-待核实' if row['processing_status']=='待人工核实' else '跳过-暂缓'
    else:
        payload={prop:row.get(f) or '' for f,prop in MAPPING.items()}
        for f,prop in extra_mapping.items():
            if f not in ['ai_reason','ai_confidence']:payload[prop]=row.get(f) or ''
        payload['原5552台账内']='是'
        payload['发音资源状态']='未配置' # No independent recording; TTS is described separately.
        if row.get('ai_reason'):
            payload['AI 筛选理由']=row['ai_reason'];payload['筛选置信度']=row['ai_confidence']
        action='新增'
    assert not set(payload)&PERSONAL
    assert not any('复习' in k or '评级' in k or '日期' in k for k in payload)
    for prop,val in payload.items():
        if schema[prop]['type']=='select':assert val in [x['name'] for x in schema[prop]['select']['options']],(prop,val)
    preview.append({'entry_id':uid,'word':row['word'],'action':action,
        'processing_status':row['processing_status'],'candidate_scope':row['candidate_scope'],
        'changed_fields':'；'.join(payload) if action=='更新' else '',
        'payload_json':json_text(payload),'personal_fields_policy':'不提供、不重置、不覆盖；日期/评级/笔记保留'})
    if action in ['新增','更新']:payloads.append({'entry_id':uid,'word':row['word'],'action':action,'properties':payload})
assert not conflicts
csv_write('notion_import_preview.csv',preview)
for action,name in [('新增','notion_new.csv'),('更新','notion_updates.csv'),('保持不变','notion_unchanged.csv')]:
    csv_write(name,[r for r in preview if r['action']==action],list(preview[0]))
csv_write('stable_id_conflicts.csv',conflicts,['id','word','issue'])
save('notion_content_payloads.json',payloads)


def apply_locally(before,plans):
    after=copy.deepcopy(before);counts=collections.Counter()
    for p in plans:
        uid=p['entry_id'];props=p['properties']
        if uid not in after:
            assert props['词条ID']==uid
            after[uid]=copy.deepcopy(props);counts['inserted']+=1
        elif any((after[uid].get(k) or '')!=(v or '') for k,v in props.items()):
            after[uid].update(copy.deepcopy(props));counts['updated']+=1
        else:counts['unchanged']+=1
    return after,dict(counts)


first,first_counts=apply_locally(cloud,payloads)
second,second_counts=apply_locally(first,payloads)
assert first==second and second_counts.get('inserted',0)==second_counts.get('updated',0)==0
assert all(first[uid]==r for uid,r in cloud.items())
# Exercise an update on a local synthetic row; never a remote/personal row.
synthetic={'dry-run-only':{'词条ID':'dry-run-only','中文词义':'旧测试值','学习状态':'本地模拟状态'}}
test_plan=[{'entry_id':'dry-run-only','properties':{'词条ID':'dry-run-only','中文词义':'新测试值'}}]
one,one_count=apply_locally(synthetic,test_plan);two,two_count=apply_locally(one,test_plan)
assert one_count=={'updated':1} and two_count=={'unchanged':1} and one==two
assert two['dry-run-only']['学习状态']=='本地模拟状态'

# Preserve and compare every personal SQLite table using read-only connections.
db=pathlib.Path('C:/Users/Administrator/AppData/Roaming/Personal/English Learning/english_learning_v1.sqlite3')
before_personal=load('private/p5a/personal-before.json')
with sqlite3.connect(db.as_uri()+'?mode=ro',uri=True) as connection:
    connection.row_factory=sqlite3.Row
    assert connection.execute('PRAGMA integrity_check').fetchone()[0]=='ok'
    after_personal={t:[dict(r) for r in connection.execute(f'SELECT * FROM "{t}" ORDER BY 1')] for t in before_personal}
assert before_personal==after_personal

# Connector projections are retained only for discrepancy diagnostics.
connector=load('private/p5a/notion-connector-rows.json')
connector_by_id={r['词条ID']:r for r in connector}
projection_diff=[]
for uid,r in cloud.items():
    for field,prop in MAPPING.items():
        if (connector_by_id[uid].get(prop) or '') != (r.get(prop) or ''):
            projection_diff.append({'entry_id':uid,'word':r['单词'],'field':prop,
                                    'connector_value':connector_by_id[uid].get(prop),
                                    'direct_value':r.get(prop)})
(PRIVATE/'connector-projection-differences.json').write_text(json.dumps(projection_diff,ensure_ascii=False,indent=2),encoding='utf-8')

changes=[]
for uid,r in content.items():
    if r['before_meaning']!=r['after_meaning']:
        changes.append({'entry_id':uid,'word':r['word'],'before_source_draft':r['before_meaning'],
            'after_proposed_meaning':r['after_meaning'],'reason':('原台账没有中文释义；独立补全后逐词自检' if not r['before_meaning'] else '会话复核：纠正错配/不自然词元，补入常用义')+'；不是修改既有500词',
            'evidence':r['source_synset']+'; '+r['evidence_source'],
            'source_english_gloss':r['english_sense'],'review_status':r['review'],
            'scope':'仅新增候选草稿；原500释义不变'})
csv_write('meaning_before_after.csv',changes)

stats={
    'version':'0.7.0+10','original_candidates':5552,'unique_case_sensitive_heads':5552,
    'original_category_counts':dict(collections.Counter(r['book_category'] for r in audit)),
    'selected_original':len(selected),'deferred_original':len(deferred),'manual_original':len(manual),
    'conservation':len(selected)+len(deferred)+len(manual)==5552,
    'category_dispositions':{cat:dict(collections.Counter(r['processing_status'] for r in audit if r['book_category']==cat))
                             for cat in ['高频词','中频词','基础词','低频词','偶考词','补充词']},
    'mandatory_recommended_keep':sum(r['book_category'] in mandatory for r in audit),
    'mandatory_deferred':0,
    'subjective_value_reviewed':len(value),
    'subjective_value_outcomes':dict(collections.Counter(r['model_recommendation'] for r in value.values())),
    'ai_selected_original':sum(r['selection_method']=='AI逐词用途建议' for r in selected),
    'semantic_new_reviewed':len(content),'cow_draft_reviewed':cow_review_count,'independently_written_remaining':extended_count,
    'semantic_new_approved':sum(r['status']=='approved' for r in content.values()),
    'semantic_new_held':sum(r['status']=='hold' for r in content.values()),
    'source_draft_rewrites':sum(bool(r['before_source_draft']) for r in changes),
    'new_meaning_fields_added':sum(not r['before_source_draft'] for r in changes),
    'semantic_second_pass':len(second_pass_diffs),
    'pets2015_exact_matches':sum(r['pets2015_reference_status']=='已收录' for r in audit),
    'pets2015_not_explicitly_listed':sum(r['pets2015_reference_status']=='未收录' for r in audit),
    'pets2025_pending':5552,'existing_notion':500,'existing_original_candidates':499,
    'retained_supplemental':1,'formal_total_with_texture':len(formal),
    'notion_expected_new':sum(r['action']=='新增' for r in preview),
    'notion_expected_updates':sum(r['action']=='更新' for r in preview),
    'notion_unchanged':sum(r['action']=='保持不变' for r in preview),
    'duplicate_ids':0,'duplicate_exact_heads':0,
    'case_accent_collision_groups':[['May','may'],['March','march'],['resume','résumé']],
    'source_new_pending_checked':len(source_follow),'source_new_pending_remaining':sum(not r['hits'] for r in source_follow.values()),
    'anomaly_entries':len({r['entry_id'] for r in issues}),
    'manual_issue_counts':dict(collections.Counter(issue for r in manual for issue in r['blocking_issues'].split('；') if issue)),
    'notion_direct_fields_equal_existing_pack':29,'connector_projection_field_differences':len(projection_diff),
    'live_snapshot_fetched_utc':current['fetched_utc'],
    'personal_sqlite_unchanged':True,'cloud_writes':0,'events_uploaded':0,'ocr_performed':False,
    'dry_run_first':first_counts,'dry_run_repeat':second_counts,'synthetic_update_idempotency':True,
    'selected_missing_required':0,'original_ledger_sha256':digest('private/p3/source/词头候选台账.csv'),
    'unchanged_pack_sha256':digest('assets/vocabulary/reviewed500.csv'),
    'dataset_sources_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (PRIVATE/'sources').glob('*') if p.is_file()},
}
save('statistics.json',stats)
licenses=OUT/'licenses';licenses.mkdir(exist_ok=True)
for name in ['COW_LICENSE','WORDNET30_LICENSE']:
    shutil.copyfile(PRIVATE/'sources'/name,licenses/(name+'.txt'))
save('validation.json',{'status':'PASS','conservation':True,'unique_ids':True,
    'existing500_unchanged':True,'notion_direct29_fields_match':True,'sqlite_all_tables_equal':True,
    'idempotent_local_upsert':True,'synthetic_update_preserves_personal_field':True,
    'remote_write_functions_implemented':False,'all_data_ready':not manual,
    'all_candidates_have_exclusive_processing_status':True})
print(json.dumps({k:stats[k] for k in ['original_candidates','selected_original','deferred_original',
     'manual_original','formal_total_with_texture','notion_expected_new','notion_expected_updates',
     'notion_unchanged','connector_projection_field_differences']},ensure_ascii=False))
