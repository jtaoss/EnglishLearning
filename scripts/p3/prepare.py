"""Build reviewed vocabulary and read-only Notion change previews.

Uses the existing extracted ledger, never OCR. Raw sources and live Notion
snapshots remain under ignored private/. No network or Notion writes occur.
"""
from __future__ import annotations

import argparse
import collections
import csv
import hashlib
import json
import pathlib
import re
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
HERE = pathlib.Path(__file__).resolve().parent
WORD_HINTS = dict(line.split('|',1) for line in (HERE/'phonics.txt').read_text(encoding='utf-8').splitlines() if line and not line.startswith('#'))
OFFICIAL = 'https://pets.neea.edu.cn/res/Home/2507/7186495d90963d37a36afccbfb505cc9.pdf'
CMU = 'https://github.com/cmusphinx/cmudict'
CORE = ['entry_id','word','meaning_zh','book_category','source_file','source_id',
        'source_pdf_pages','source_index_pages','book_verification',
        'meaning_review_status','pets2015_status','pets2025_status','library_class',
        'part_of_speech','usage_note','lexical_sources']
EXTRA = ['example_en','example_zh','learning_priority','selection_reason','phonics_note',
         'syllables','stress','reading_review_status','audio_status','audio_source',
         'audio_license','pets2015_evidence','pets2015_match_method']
MAPPING = dict(zip(CORE, ['词条ID','单词','中文词义','原书分类','来源文件','来源ID',
    '原书PDF页码','索引PDF页码','原书核验状态','释义复核说明','PETS3 2015收录状态',
    'PETS3 2025收录状态','学习词库分类','词性','用法说明','释义来源']))
MAPPING.update(dict(zip(EXTRA,['原创例句','例句译文','学习优先级','筛选理由','拼读提示',
    '音节说明','重音说明','拼读复核说明','音频许可状态','标准音频来源','标准音频许可',
    'PETS3 2015证据','PETS3 2015匹配方法'])))
PERSONAL = {'学习状态','发音状态','自然拼读状态','自然拼读笔记','听音学习状态','听音学习笔记'}
RANGES = [(1,284,'高频词'),(285,440,'中频词'),(441,588,'低频词'),
          (589,639,'偶考词'),(640,700,'基础词'),(701,715,'补充词')]
AI_REASONS = {
    'oriental':'传统艺术和地毯等阅读语境可见，作为扩展识别词保留；描述人时需注意现代用法。',
    'amplify':'音量、信号与表达效果的工作语境常见，保留为通用技术扩展词。',
    'beloved':'人物、地方与文化叙述中的常见修饰词，保留用于阅读。',
    'autonomy':'工作自主权、学校组织与公共事务阅读可用，作为扩展保留。',
    'texture':'衣物、食物与材料的质感描述实用，作为生活扩展词保留。',
    'allege':'新闻和正式报道用于区分指称与已证实事实，保留阅读识别价值。',
    'overhaul':'设备检修和系统改进的工作语境实用，作为扩展保留。',
    'vegetarian':'餐饮点餐与饮食习惯交流实用，保留日常词义。',
    'bin':'垃圾分类与收纳的日常生活用词，保留常见义。',
    'groan':'身体不适、抱怨和叙事中的声音动作词，保留阅读识别价值。',
    'compile':'软件开发、资料汇集与清单编纂实用，作为工作扩展词保留。',
    'imaginary':'故事、假设情境与想象活动常见，作为阅读扩展词保留。',
    'menace':'新闻、危险提示和叙事中的威胁概念，作为阅读识别扩展词保留。',
    'shove':'拥挤场景和动作叙述中可用，作为阅读扩展词保留。',
    'pottery':'旅行、博物馆和手工兴趣交流可用，作为文化扩展词保留。',
    'résumé':'求职与工作沟通直接实用，保持与动词 resume 独立的既有身份。',
    'anecdote':'口头分享与阅读中的短小趣闻概念实用，作为扩展保留。',
    'splash':'水花、泼溅等日常动作叙述实用，作为阅读扩展词保留。',
}

def read_csv(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream))

def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def write_csv(path, rows, columns):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='utf-8-sig', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=columns, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(rows)

def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()

def category(row):
    pages = [int(x) for x in re.findall(r'\d+', row['书内页码'])]
    categories = {label for page in pages for start,end,label in RANGES if start<=page<=end}
    if len(categories) != 1:
        raise ValueError(f"Ambiguous book category: {row['词条ID']}")
    return categories.pop()

def reference_index(pages):
    """Exact, case-sensitive explicit forms. No stemming or inferred derivatives."""
    index = {}
    for page_no in range(90,153):
        for line in pages[page_no-1].splitlines():
            line = line.strip().replace('’', "'").replace('‘', "'")
            if not line or (len(line)==1 and line.isupper() and line!='I'):
                continue
            for form in re.split(r'\s*/\s*',line):
                # Only a printed optional ending is expanded; no linguistic guess.
                match = re.fullmatch(r"([A-Za-z'-]+)\(([A-Za-z]+)\)",form)
                forms = [match[1],match[1]+match[2]] if match else [form]
                for head in forms:
                    if re.fullmatch(r"[A-Za-z][A-Za-z'-]*",head):
                        index.setdefault(head,[]).append({'pdf_page':page_no,
                            'printed_page':page_no-4,'printed_form':line,
                            'section':'main' if page_no<=147 else 'supplement'})
    return index

def cmu_index(path):
    result = collections.defaultdict(list)
    for line in path.read_text(encoding='utf-8').splitlines():
        if not line or line.startswith(';;;'): continue
        head, *phones = line.split()
        head = re.sub(r'\(\d+\)$','',head).lower()
        stresses = [int(p[-1]) for p in phones if p[-1:].isdigit()]
        result[head].append(stresses)
    return result

def wordnet_index(path):
    result = collections.defaultdict(set)
    with tarfile.open(path) as archive:
        for member in archive.getmembers():
            name = pathlib.PurePosixPath(member.name).name
            if name not in {'index.noun','index.verb','index.adj','index.adv'}: continue
            for raw in archive.extractfile(member):
                line = raw.decode('utf-8').rstrip()
                if not line or line.startswith(' '): continue
                parts = line.split()
                result[parts[0]].add(parts[1])
    return result

def phonics(word, chunks, audio):
    if audio:
        return audio['phonics_note']
    cautions = {
        'a':'冠词有强读与弱读，句中通常轻读，不机械套用字母名称音。',
        'an':'冠词有强读与弱读，句中通常轻读。',
        'the':'功能词有强读、弱读及后接元音时的变体，不固定强调。',
        'live':'本卡为动词，i 读短元音；同拼写的形容词读音不同。',
        'lead':'本卡为动词，ea 读长元音；同拼写的名词另有不同读音。',
        'read':'本卡示例为现在时，ea 读长元音；过去时同拼写但读音不同。',
        'object':'本卡为名词，首音节重读；同拼写的动词重音在后。',
        'progress':'本卡为名词，首音节重读；动词重音可能不同。',
        'increase':'本卡为动词，后音节重读；名词通常首音节重读。',
        'use':'本卡为动词，词尾为浊辅音；名词的词尾读音不同。',
        'address':'本卡为名词，列美式首音节重读变体；另有后音节重读读法。',
        'combat':'本卡按名词列首音节重读；动词有另一重音变体。',
        'overhaul':'此处先练名词的首音节重读；动词末音节重读，需按词性另行核对。',
        'tired':'有单音节与两音节读法；此处列两音节变体，词尾 ed 不套用规则动词过去式。',
        'outside':'后部音节可重读，句中两部分的突出程度随词性及语境变化。',
        'first':'ir 为受 r 影响的元音组合，不按一般 i-e 长元音模式读。',
        'give':'i 在本词为短元音；末尾 e 不成音节，不套用一般 i-e 长元音模式。',
        'learn':'ear 在本词受 r 影响；不与 hear 的元音机械等同。',
        'right':'igh 在本词为双元音拼写；gh 不另发音，单音节。',
        'warm':'ar 的本词读音受前面的 w 影响，不按一般 ar 机械套用。',
        'separate':'本卡为形容词，结尾轻读；动词的结尾元音不同。',
        'resume':'本卡为动词，重读末音节；区别于名词 résumé。',
        'résumé':'此带重音符号的名词按三个音节认读，首音节主重读；区别于动词 resume。',
        'autumn':'首音节重读；词尾 n 不发音。',
        'Wednesday':'常用两个音节；拼写中的第一个 d 不单独发音。',
        'answer':'w 不发音；首音节重读。',
        'know':'开头 k 不发音；ow 在本词为长元音组合。',
        'wrong':'开头 w 不发音；单音节。',
        'sign':'g 不发音；单音节。',
        'hour':'h 不发音；有单音节与轻微双音节读法。',
        'blood':'oo 在本词不按 food 或 book 读音套用，建议听音记忆。',
        'enough':'重读后音节；词尾 gh 为辅音，不按 through 的 gh 套用。',
        'through':'th 是辅音组合；ough 的本词读音需整体记忆，gh 不发音。',
        'laugh':'gh 在本词为辅音；存在英美元音差异。',
        'busy':'u 在本词不按字母名称音读；首音节重读。',
        'sugar':'s 在本词读音特殊，不按普通 s 套用。',
        'money':'o 在本词不按字母名称音读；首音节重读。',
        'lose':'末尾 e 不成音节，但 o 不能按 close 套用。',
        'put':'u 在本词不按 cut 的短元音套用。',
        'woman':'首音节重读；o 不按字母名称音读。',
        'would':'l 不发音；ou 的本词读音需要整体记忆。',
        'could':'l 不发音；ou 的本词读音需要整体记忆。',
        'have':'末尾 e 不成音节，a 不套用一般 a-e 长元音模式。',
        'clothes':'单音节；th 和词尾 s 的衔接需听音核对。',
        'breathe':'ea 在本词为长元音，th 为浊音；区别于 breath。',
        'double':'ou 不按 out 的读音套用，建议听音记忆。',
        'shove':'ove 不按 move 或 drove 套用，建议听音记忆。',
        'beloved':'本卡形容词常作三个音节，ed 单独成音节。',
        'fragile':'首音节重读；结尾元音存在英美读音差异。',
        'database':'主重音在首音节；data 的开头元音有变体，需跟随所选录音。',
        'o\'clock':'开头 o\' 弱读，clock 为重读部分。',
    }
    if word in cautions: return cautions[word]
    if word in WORD_HINTS: return WORD_HINTS[word]
    groups = [
        ('bad cash cat hat man map match back catch','a 在本词的重读音节中为短元音。'),
        ('bed desk end fresh get head help red set ten test them when yes bread death health','e 或 ea 在本词为短元音，不按 ea 一律长读。'),
        ('big bin dish fill film finish fit him hill his in it milk miss six still swim thin win wind wish','i 在本词重读音节中为短元音。'),
        ('block clock cross doctor hot job lock lot rock shop stop wrong','o 在本词不按字母名称音读；留意英美元音差异。'),
        ('bus cup cut fun lunch run shut some son summer sun under up','本词重读元音需与 put 的元音区别。'),
        ('beach clean dear deep each eat feel feeling green hear heat key lead leap meal meat meet need sea see she sheep sleep teach tea tree week','ee、ea 或单写 e 的长元音按本词认读；不推广到所有同形词。'),
        ('age cake change daily date day game late main name paint pay place rain rate safe same say shape shade stay take they trade way weight','本词重读元音为长元音或双元音；末尾不发音 e 不增加音节。'),
        ('bike bright by die dry eye fight find first ice lie life like line might my nice nine rice ride rise side sign sky smile time tired white why wife wipe','本词的 i、igh、y 等拼写按本词读音认读，不机械推广。'),
        ('boat coat cold go goal hope low no own snow soap toe total','本词重读元音为长元音或双元音；不要照搬到 cow 的 ow。'),
        ('boy enjoy joint oil toy voice','oi 或 oy 在本词作为一个双元音组合认读。'),
        ('about around brown count cow crowd down house how mountain mouth now out round sound town thousand','ou 或 ow 在本词作为双元音组合认读；不是所有 ou/ow 都同读。'),
        ('book cook foot look good','oo 在本词为较短的元音，不与 food 一律同读。'),
        ('food moon movie school soon tool too two zoo','本词重读元音较长；双写元音不增加音节。'),
    ]
    # These are deliberately finite, reviewed word sets, not a pronunciation engine.
    for words,note in groups:
        if word.lower() in words.split(): return note
    return '本词不宜机械按单个字母推断全部读音。先按已核对的音节和重音认读，标准音频补充后再听音校正。'

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--private',type=pathlib.Path,default=ROOT/'private/p3')
    args=parser.parse_args(); private=args.private.resolve()
    source=private/'source'
    ledger=read_csv(source/'词头候选台账.csv')
    assert len(ledger)==5552 and len({r['词条ID'] for r in ledger})==5552
    by_word={r['单词']:r for r in ledger}
    base=read_csv(ROOT/'assets/vocabulary/verified100.csv')
    remote=json.loads((private/'notion-baseline.json').read_text(encoding='utf-8'))
    assert remote.get('has_more') is False, 'Incomplete cloud snapshot'
    remote=remote['results']; cloud={r['词条ID']:r for r in remote}
    assert len(cloud)==len(remote)==100
    assert {(r['entry_id'],r['word']) for r in base}=={(r['词条ID'],r['单词']) for r in remote}
    reference_pages=json.loads((private/'pets3-2015-text.json').read_text(encoding='utf-8'))
    assert '2015年3月' in reference_pages[1] and '附录四' in reference_pages[89]
    ref=reference_index(reference_pages)
    cmu=cmu_index(private/'cmudict.dict'); wn=wordnet_index(private/'wordnet31.tar.gz')
    editorial={}; chunks={}
    for line in (HERE/'editorial.txt').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'): continue
        word,pos,meaning,syllables,example,translation=line.split('|')
        assert word not in editorial, f'Duplicate editorial: {word}'
        editorial[word]=dict(part_of_speech=pos,meaning_zh=meaning,
            example_en=example,example_zh=translation)
        chunks[word]=syllables
    assert len(editorial)==400
    for line in (HERE/'reading.txt').read_text(encoding='utf-8').splitlines():
        if not line or line.startswith('#'): continue
        word,syllables=line.split('|'); assert word not in chunks
        chunks[word]=syllables
    assert len(chunks)==500
    audio={r['word']:r for r in json.loads((ROOT/'assets/pronunciation/manifest.json').read_text(encoding='utf-8'))['items']}
    output=[]
    for row in base:
        row=dict(row); actual=cloud[row['entry_id']]
        row['example_en']=actual['原创例句'] or ''
        row['example_zh']=actual['例句译文'] or ''
        if row['word']=='combat':
            row['example_en']='The soldiers returned from combat.'
            row['example_zh']='士兵们从战斗中归来。'
        if row['word']=='overhaul':
            row['example_en']='The engine needs a complete overhaul.'
            row['example_zh']='这台发动机需要彻底检修。'
        if row['word']=='limitation':
            row['example_en']='The main limitation is the small screen.'
            row['example_zh']='主要局限是屏幕小。'
        row['learning_priority']=actual['学习优先级'] if actual['学习优先级'] in ['P1','P2'] else 'P2'
        row['selection_reason']='保留既有稳定 ID；'+('原书高频/中频/基础词全部保留。' if row['book_category'] in ['高频词','中频词','基础词'] else 'AI 主观保留：已有独立常用释义及自然语境，可作为阅读/工作扩展词；不据此宣称 PETS 官方收录。')
        if row['word'] in AI_REASONS:
            row['selection_reason']='AI 主观筛选：'+AI_REASONS[row['word']]+' 不代表PETS官方收录或词频。'
        if row['library_class']=='暂缓': row['library_class']='扩展'
        output.append(row)
    for word,content in editorial.items():
        source_row=by_word[word]
        assert source_row['词头质量'] in ['同页正文标题自动同形支持','索引及正文原图已核对'], f'Unverified head: {word}'
        cat=category(source_row)
        assert cat not in ['偶考词','补充词']
        row=dict(entry_id=source_row['词条ID'],word=word,book_category=cat,
            source_file='2025考研英语词汇闪过.pdf',source_id='src_sg25_5e4501eb7237',
            source_pdf_pages=source_row['PDF页码'],source_index_pages=source_row['索引PDF页码'],
            book_verification='已核验',meaning_review_status='独立编写；词性/常用义/例句复核（AI）；待个人确认',
            pets2025_status='待核实',library_class='主学习',
            usage_note='仅列常用义；原台账索引及正文同页文本支持，不冒充逐页人工图像终审。',
            lexical_sources='中文释义及例句独立编写、AI语义复核；WordNet 3.1 词性对照（可查项）：https://wordnetcode.princeton.edu/wn3.1.dict.tar.gz；音节/重音对照：'+CMU,
            learning_priority='P1' if cat in ['高频词','基础词'] else 'P2',
            selection_reason='原书高频/中频/基础词全部保留；本批优先日常通用词。' if cat in ['高频词','中频词','基础词'] else 'AI 实用性筛选：日常学习/工作常用词，结合2015附录匹配；原书低频不是PETS低频。')
        row.update(content); output.append(row)
    mismatches=[]
    for row in output:
        word=row['word']; parts=chunks[word].split('-')
        assert ''.join(parts).lower()==word.lower(), f'Bad chunks: {word}'
        stressed=[i for i,p in enumerate(parts) if p.isupper()]
        assert len(stressed)==1, f'Bad stress annotation: {word}'
        cmu_key={'résumé':'resume',"o'clock":"o'clock"}.get(word,word).lower()
        variants=cmu.get(cmu_key,[])
        matches=[v for v in variants if len(v)==len(parts) and v[stressed[0]]==1]
        if not matches: mismatches.append({'word':word,'chunks':chunks[word],'cmu_stresses':variants})
        evidence=ref.get(word,[])
        row['pets2015_status']='已收录' if evidence else '未直接列出'
        row['pets2015_evidence']='；'.join(f"PDF{x['pdf_page']}/书内{x['printed_page']}：{x['printed_form']}" for x in evidence)
        row['pets2015_match_method']='explicit_form_case_sensitive_no_stemming'
        row['syllables']=' · '.join(p.lower() for p in parts)
        row['stress']='单音节；句中强弱随语境变化' if len(parts)==1 else f"第{stressed[0]+1}音节主重读：{' · '.join(parts)}"
        row['phonics_note']=phonics(word,parts,audio.get(word))
        row['reading_review_status']='逐词分块与CMUdict美式音节数/主重音对照（AI）；非个人确认或自动发音评分'
        row['audio_status']='已授权；随包可离线播放' if word in audio else '待补充；缺音频不阻塞学习'
        row['audio_source']=audio[word]['source_url'] if word in audio else ''
        row['audio_license']=audio[word]['license'] if word in audio else '无已核验可分发音频'
        assert row['example_en'] and row['example_zh'] and row['part_of_speech']
        assert not re.search(r'[\u0250-\u02af\u1d00-\u1d7f]',row['phonics_note']+row['syllables'])
    save_json(private/'reading-check.json',mismatches)
    if mismatches:
        print(json.dumps(mismatches,ensure_ascii=False,indent=2))
        raise SystemExit('Resolve reading checks before generating a reviewed pack.')
    assert len(output)==500 and len({r['entry_id'] for r in output})==500
    assert len({r['word'] for r in output})==500
    write_csv(ROOT/'assets/vocabulary/reviewed500.csv',output,CORE+EXTRA)
    reviewed_ids={r['entry_id'] for r in output}
    screened=[]
    for original in ledger:
        row=dict(original); cat=category(row); word=row['单词']; evidence=ref.get(word,[])
        mandatory=cat in ['高频词','中频词','基础词']
        selected=mandatory or bool(evidence) or word in editorial
        row.update(原书分类=cat,PETS2015参考状态='已收录' if evidence else '未直接列出',
            PETS2025官方归属='待核实',筛选结论='保留候选' if selected else '暂不入本批；保留原始记录',
            筛选理由='原书高频/中频/基础词全部保留；内容仍需分批核验' if mandatory else
                '2015附录明确词形匹配；保留候选，不等于2025归属' if evidence else
                'AI日常实用性选择；本批独立编写释义/例句' if word in editorial else
                'AI保守暂缓：尚无本轮逐词实用性充分理由，未作低价值或官方未收录判定',
            本批500内='是' if row['词条ID'] in reviewed_ids else '否',
            分类核验='目录页范围及正文同页支持' if row['词头质量'] in ['同页正文标题自动同形支持','索引及正文原图已核对'] else '按既有页码暂归类；正文词头待复核',
            正式内容核验='已完成本批复核' if row['词条ID'] in reviewed_ids else '待后续逐词核验')
        screened.append(row)
    write_csv(private/'screening5552.csv',screened,list(screened[0]))
    schema_additions=[{'name':name,'type':'rich_text'} for key,name in MAPPING.items()
        if key in EXTRA and key not in {'example_en','example_zh','learning_priority','selection_reason','pets2015_evidence','pets2015_match_method'}]
    for size,start in [(200,100),(500,200)]:
        creates=[]
        for row in output[start:size]:
            properties={MAPPING[k]:row[k] for k in CORE+EXTRA}
            properties.update({'数据版本':'p3-20261109-v1','数据哈希':digest({k:row[k] for k in CORE+EXTRA}),
                '导入批次':f'p3-{size}-20261109-v1'})
            assert not PERSONAL.intersection(properties)
            creates.append({'entry_id':row['entry_id'],'properties':properties})
        updates=[]
        if size==200:
            for row in output[:100]:
                old=cloud[row['entry_id']]
                changes={MAPPING[k]:row[k] for k in CORE+EXTRA if (old.get(MAPPING[k]) or '')!=row[k]}
                changes.update({'数据版本':'p3-20261109-v1','数据哈希':digest({k:row[k] for k in CORE+EXTRA})})
                assert not PERSONAL.intersection(changes)
                if changes: updates.append({'entry_id':row['entry_id'],'page_url':old['url'],
                    'before':{name:old.get(name) for name in changes},'after':changes,
                    'precondition_hash':digest({name:old.get(name) for name in [*MAPPING.values(),'数据版本','数据哈希']})})
        preview={'mode':'PREVIEW_ONLY_NOT_EXECUTED','target_size':size,'expected_before':start,
            'source_id':'157d89e5-71fb-4e68-9640-1b04dbb1e627',
            'schema_additions':schema_additions if size==200 else [],'creates':creates,'updates':updates,
            'personal_properties_excluded':sorted(PERSONAL),
            'gate':'Requires explicit user approval of this exact preview hash. 500 batch also requires 200 acceptance.',
            'recovery':'After ambiguous create, query stable ID and compare content before retry; never blind-create or delete history.'}
        preview['sha256']=digest(preview)
        save_json(private/f'notion-preview-{size}.json',preview)
        write_csv(private/f'preview-{size}.csv',output[:size],CORE+EXTRA)
    stats={'date':'2026-11-09','raw_candidates':len(ledger),
        'raw_category_counts':dict(collections.Counter(category(r) for r in ledger)),
        'mandatory_retained':sum(category(r) in ['高频词','中频词','基础词'] for r in ledger),
        'screened_candidate_retained':sum(r['筛选结论']=='保留候选' for r in screened),
        'raw_rows_deleted':0,'notion_actual_count':len(remote),'notion_writes_performed':0,
        'reviewed_pack_count':len(output),'selected_category_counts':dict(collections.Counter(r['book_category'] for r in output)),
        'all_selected_learnable':all(r['library_class']!='暂缓' for r in output),
        'existing_class_changes':[{'id':r['entry_id'],'word':r['word'],'from':cloud[r['entry_id']]['学习词库分类'],'to':r['library_class']} for r in output[:100] if r['library_class']!=cloud[r['entry_id']]['学习词库分类']],
        'audio_ready':sum(r['word'] in audio for r in output),
        'audio_pending':sum(r['word'] not in audio for r in output),
        'reading_verified':len(output)-len(mismatches),
        'new_words_with_body_title_support':len(editorial),
        'word_specific_phonics_hints':sum(not r['phonics_note'].startswith('本词不宜机械') for r in output),
        'pets2015_matches':sum(r['pets2015_status']=='已收录' for r in output),
        'pets2025_pending':len(output),
        'official_2015_url':OFFICIAL,
        'official_pdf_sha256':hashlib.sha256((private/'pets3-2015-official.pdf').read_bytes()).hexdigest(),
        'ledger_sha256':hashlib.sha256((source/'词头候选台账.csv').read_bytes()).hexdigest(),
        'cmudict_sha256':hashlib.sha256((private/'cmudict.dict').read_bytes()).hexdigest(),
        'wordnet_sha256':hashlib.sha256((private/'wordnet31.tar.gz').read_bytes()).hexdigest(),
        'editorial_sha256':hashlib.sha256((HERE/'editorial.txt').read_bytes()).hexdigest(),
        'phonics_hints_sha256':hashlib.sha256((HERE/'phonics.txt').read_bytes()).hexdigest(),
        'reviewed_pack_sha256':hashlib.sha256((ROOT/'assets/vocabulary/reviewed500.csv').read_bytes()).hexdigest(),
        'reference_limits':'Exact printed forms only; no stemming, no inference of official exclusion, no PETS frequency claim.',
        'content_review_limits':'AI editorial/semantic review and lexical cross-check, not personal confirmation or official definitions.'}
    save_json(ROOT/'docs/p3/selection-statistics.json',stats)
    print(json.dumps(stats,ensure_ascii=False,indent=2))
    print('WordNet lexical matches:',sum(r['word'].lower() in wn for r in output))

if __name__=='__main__': main()
