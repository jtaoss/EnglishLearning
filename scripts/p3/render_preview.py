"""Render local approval previews, without contacting or writing Notion."""
import csv
import html
import json
import pathlib

root=pathlib.Path(__file__).resolve().parents[2]
private=root/'private/p3'
for size in [200,500]:
    preview=json.loads((private/f'notion-preview-{size}.json').read_text(encoding='utf-8'))
    with (private/f'preview-{size}.csv').open(encoding='utf-8-sig',newline='') as stream:
        rows=list(csv.DictReader(stream))
    def esc(value): return html.escape(str(value))
    body=[]
    for index,row in enumerate(rows):
        action='既有词条：内容更新' if index<100 and size==200 else '第一批验收后保留' if index<200 and size==500 else '新增'
        body.append('<tr>'+''.join(f'<td>{esc(v)}</td>' for v in [index+1,action,row['entry_id'],row['word'],row['part_of_speech'],row['meaning_zh'],row['example_en'],row['example_zh'],row['book_category'],row['library_class'],row['learning_priority'],row['pets2015_status'],row['pets2025_status'],row['syllables'],row['stress'],row['phonics_note'],row['audio_status'],row['selection_reason']])+'</tr>')
    changes=[]
    for update in preview['updates']:
        content=''.join(f'<li><b>{esc(key)}</b>：{esc(update["before"].get(key) or "（空）")} → {esc(value)}</li>' for key,value in update['after'].items())
        changes.append(f'<details><summary>{esc(update["entry_id"])} · {len(update["after"])} 项内容变更</summary><ul>{content}</ul></details>')
    text=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>{size} 词导入预览</title>
<style>body{{font:15px/1.65 system-ui,sans-serif;color:#18202b;margin:28px}}h1{{font-size:25px}}.status{{padding:18px;background:#fff4da;border-left:5px solid #d69a25}}table{{border-collapse:collapse;min-width:2600px}}th,td{{border:1px solid #d8dfe7;padding:9px;vertical-align:top}}th{{position:sticky;top:0;background:#edf3fa}}td:nth-child(4){{font-weight:bold}}.scroll{{overflow:auto;max-height:70vh}}code{{overflow-wrap:anywhere}}details{{padding:6px;border-bottom:1px solid #ddd}}</style>
<h1>EnglishLearning · {size} 词导入预览</h1><div class="status"><b>仅预览，尚未执行 Notion 写入。</b><br>
预期已有 {preview['expected_before']} 词；新增 {len(preview['creates'])} 词；更新 {len(preview['updates'])} 个既有词的内容字段；删除 0 词。<br>
不写入个人词义/发音/自然拼读/听音状态。500 词批次须先完成 200 词验收。<br>
审批清单 SHA-256：<code>{preview['sha256']}</code></div>
<p>来源：既有 5,552 词候选台账。中文常用义与新增例句独立编写并经 AI 复核，待个人确认；2015 仅作官方附录明确词形参考，2025 全部待核实。音节数与主重音已对照 CMUdict；拼写分块不是国际音标。6 词有既有合法音频，其余待补充。</p>
<h2>词条清单（横向滚动查看全部字段）</h2><div class="scroll"><table><thead><tr>'''+''.join(f'<th>{h}</th>' for h in ['序号','操作','稳定 ID','单词','词性','中文常用义','英文例句','译文','原书分类','学习分类','优先级','2015 参考','2025 归属','音节','重音','拼读提示','音频状态','筛选理由'])+f'''</tr></thead><tbody>{''.join(body)}</tbody></table></div>
<h2>既有词条的逐项变更</h2>{''.join(changes) or '<p>本批不再修改第一批已验收词条。</p>'}
<h2>拟新增字段</h2><p>{esc(', '.join(x['name'] for x in preview['schema_additions'])) or '无'}</p>
<p>重复提交保护：先按稳定 ID 查重并比对内容；创建结果不明时先查询对账，不盲目重建。个人学习事件上传仍未授权。</p></html>'''
    (private/f'notion-preview-{size}.html').write_text(text,encoding='utf-8')
    print(f'{size}: create={len(preview["creates"])} update={len(preview["updates"])} sha256={preview["sha256"]}')
