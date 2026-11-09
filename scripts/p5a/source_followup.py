"""Target unresolved head/title references using the PDF's existing text only.

No OCR and no repeated image checks on already evidenced records.
"""
import collections
import json
import pathlib
import re
import pymupdf

ROOT=pathlib.Path(__file__).resolve().parents[2]
rows=json.loads((ROOT/'private/p5a/workbench.json').read_text(encoding='utf-8'))
path=ROOT/'private/p5a/source-head-followup.json'
if path.exists():
    result=json.loads(path.read_text(encoding='utf-8'))
else:
    pdf=pymupdf.open('E:/desktop/2025考研英语词汇闪过.pdf')
    cache={}
    result=[]
    for r in rows:
        if r['existing'] or r['词头质量']!='待核对正文标题':continue
        word=r['单词']
        hits=[]
        for number in map(int,re.findall(r'\d+',r['PDF页码'])):
            if number not in cache:
                cache[number]=pdf[number-1].get_text()
            for line in cache[number].splitlines():
                # Exact spelling, allowing title initial capitalization only.
                if re.match(r'^\s*'+re.escape(word)+r'(?=$|\s|\[|\()',line):
                    hits.append({'pdf_page':number,'exact_head_at_line_start':True})
                    break
        result.append({'entry_id':r['词条ID'],'word':word,
                       'before':r['词头质量'],'hits':hits,
                       'after':'已有文本层行首词头支持；非图像终审' if hits else '仍待正文词头人工核实',
                       'ocr_performed':False})
    path.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'checked_only_unresolved_new':len(result),
                  'text_support':sum(bool(r['hits']) for r in result),
                  'still_pending':sum(not r['hits'] for r in result)},ensure_ascii=False))
