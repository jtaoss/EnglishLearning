"""P4.1 read-only checks and evidence sidecars; never modifies vocabulary or DBs."""
import collections
import csv
import hashlib
import json
import pathlib
import re
import sqlite3
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/p41'
PRIVATE = ROOT / 'private/p41'
OUT.mkdir(parents=True, exist_ok=True)


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def read_csv(path):
    with open(path, encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))


def save(name, data):
    (OUT / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def write_csv(name, rows):
    with open(OUT / name, 'w', encoding='utf-8-sig', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


vocab_path = ROOT / 'assets/vocabulary/reviewed500.csv'
flags_path = ROOT / 'docs/p4/quality-flags.csv'
vocab = read_csv(vocab_path)
by_id = {r['entry_id']: r for r in vocab}
by_word = {r['word']: r for r in vocab}
flags = read_csv(flags_path)
assert len(vocab) == len(by_id) == len(by_word) == 500
assert digest(vocab_path) == '09cd736d61c40f9614239e451f5894ad464f2ff69a863d50bde95b03b87f651d'
required = ['meaning_zh', 'part_of_speech', 'phonics_note', 'syllables', 'stress',
            'book_category', 'source_id', 'source_pdf_pages', 'pets2015_status', 'pets2025_status']
missing = [{'id': r['entry_id'], 'field': k} for r in vocab for k in required if not r[k].strip()]
assert not missing

# All source records remain intact. Texture was the second item of one mixed row.
exclusions_path = ROOT / 'private/p3/source/清洗及排除记录.csv'
raw = next(r for r in read_csv(exclusions_path) if r['源记录ID'] == 'R4983')
assert raw['原始索引'] == 'n t/599 texture/631'
texture = by_word['texture']
assert texture['entry_id'] == '28171f83-01fb-5cf2-943d-ee61b96942c5'
assert texture['source_pdf_pages'] == '642'
book = pathlib.Path('E:/desktop/2025考研英语词汇闪过.pdf')
book_sha = digest(book)
assert book_sha == '5e4501eb7237e59ddbc6a2ba0d83bfc3874c963ded439e6394b711afd2ba192a'
save('texture-mapping.json', {
    'entry_id': texture['entry_id'], 'word': 'texture', 'source_record': 'R4983',
    'original_exclusion_record': raw,
    'before': '原5552台账无当前词头/ID直接行；恢复词映射待补证',
    'after': '补充映射已核验；原5552条台账与排除行保持原样',
    'mapping': {
        'raw_second_item': 'texture/631', 'index_pdf_page': 766,
        'body_pdf_page': 642, 'printed_page': 631, 'book_category': '偶考词',
        'contents_pdf_page': 10, 'category_start_printed': 589,
        'next_category_start_printed': 640,
    },
    'evidence': [
        '原书索引PDF766图像：texture/631；文本层独立命中texture/631',
        '原书正文PDF642图像：词头texture、名词标注，页脚631',
        '目录PDF10图像：偶考词589，基础词640；631处于偶考分区',
        'P3导入前快照已保存相同稳定ID与R4983恢复说明，未新造ID',
    ],
    'do_not_reuse_fragment_pages': 'R4983中的599/610属于排除的n t碎片，不是texture页码',
    'pdf_sha256': book_sha, 'original_exclusions_sha256': digest(exclusions_path),
    'p3_restoration_snapshot': 'private/p3/notion-authorized-before.json',
    'p3_restoration_snapshot_sha256': digest(ROOT / 'private/p3/notion-authorized-before.json'),
    'private_evidence_files': [
        'private/p41/texture-642-0.png', 'private/p41/texture-footer.png',
        'private/p41/texture-766-0.png', 'private/p41/book-contents.png',
        'private/p41/book-page-642.txt', 'private/p41/book-page-766.txt',
    ],
    'review_method': 'agent逐页图像及已有文本层核对；无OCR；不冒充用户或教师终审',
    'content_or_cloud_write': False,
})

# Reuse the recorded primary-source reviews; no changed definition is inferred.
previous = read_csv(ROOT / 'docs/p4/review-before-after.csv')
reviews = {r['word']: (r['decision'], r['evidence'], 'P4逐项词典核验记录，本轮对照当前值') for r in previous}
fresh = {
    'object': ('本卡名词物体/物品，首音节重读；动词反对后重读，不合并词性读法。', 'object'),
    'increase': ('本卡动词增加，后音节重读与所列词典读法一致；名词首重读，孤立TTS须听辨。', 'increase'),
    'address': ('本卡名词地址；美式首重读有依据，英式后重读不能据此判卡片错误。', 'address'),
    'use': ('本卡动词使用，词尾浊辅音；名词词尾不同。现有提示正确，TTS结合例句。', 'use'),
    'separate': ('本卡形容词分开的/各自的，结尾轻读；动词结尾不同，现有提示与词典一致。', 'separate'),
    'beloved': ('形容词有两/三音节变体，名词三音节；本卡明确所列为三音节，不判另一合法变体为错。', 'beloved'),
    'elementary': ('主重音在men；英美音节压缩有差异。现卡已说明所列五音节及压缩变体，保留。', 'elementary'),
    'fifteen': ('单独报数后音节主重读与词典一致；连读节奏仍需个人听辨，不将次重音当错误。', 'fifteen'),
    'interesting': ('首音节主重读；词典词条列三/四音节变体，现卡四音节说明可保留。', 'interesting'),
}
for word, (decision, suffix) in fresh.items():
    section = 'dictionary/english' if word == 'interesting' else 'pronunciation/english'
    reviews[word] = (decision, f'https://dictionary.cambridge.org/{section}/{suffix}', '2026-11-09重新查询出版社词典，并与当前卡逐字段核对')
reviews['texture'] = ('词义质地/纹理及名词保留；R4983→索引766/631→正文642页脚631→偶考分区的补充映射已证实。',
                      'texture-mapping.json; https://dictionary.cambridge.org/dictionary/english/texture',
                      '本轮原书页面图像/文本层及旧快照交叉核验')
comparison = []
for word, (decision, evidence, method) in reviews.items():
    r = by_word[word]
    item = {'entry_id': r['entry_id'], 'word': word}
    for k in ['meaning_zh', 'part_of_speech', 'phonics_note', 'syllables', 'stress']:
        item[f'before_{k}'] = r[k]
        item[f'after_{k}'] = r[k]
    item.update(decision=decision, evidence=evidence, review_method=method,
                content_changed='否', user_teacher_confirmation='未取得，不代签')
    comparison.append(item)
write_csv('review-before-after.csv', comparison)

high = {'object', 'increase', 'address', 'use', 'separate', 'beloved', 'resume', 'résumé',
        'read', 'lead', 'overhaul', 'combat', 'oriental', 'texture'}
classified = []
for i, f in enumerate(flags, 1):
    r = by_id[f['entry_id']]
    assert f['word'] == r['word']
    issue, word = f['issue'], f['word']
    if '台账' in issue:
        kind, priority, state = '数据来源问题', 'P1', '已补证关闭；原台账不改写'
        action, evidence = reviews[word][0], 'texture-mapping.json'
    elif 'WordNet' in issue:
        kind, priority = '词性歧义', 'P2'
        state = '词典覆盖/语法标签差异；未证实错误'
        action = '有词典对照者保留原标注；yes语法标签统一仍待人工决定'
        evidence = reviews.get(word, ('', 'docs/p4/quality-flags.csv', ''))[1]
    elif '当前词性' in issue:
        kind, priority = '词性歧义', 'P1' if word in high else 'P2'
        state = '保留当前语境；TTS读法待个人听辨'
        action = '先按当前词性自主认读；可播放例句，不能由自动播放完成推断读音正确'
        evidence = reviews.get(word, ('', '原卡phonics_note及example_en；P4 CMUdict对照', ''))[1]
    elif '音节' in issue or '重读' in issue:
        kind, priority = '自然拼读提示错误候选', 'P1' if word in high else 'P2'
        state = '未证实错误；读法变体待听辨'
        action = '保留现有变体说明；不以另一合法音节数或主次重音直接覆盖提示'
        evidence = reviews.get(word, ('', '原卡提示；P4 CMUdict多读法记录', ''))[1]
    else:
        kind, priority = '普通警告', 'P1' if word == 'oriental' else 'P3'
        state = '语域提示保留' if word == 'oriental' else '独立词形/ID保留'
        action = '不推荐用此词称人，保留地毯例句及用法警示' if word == 'oriental' else '不得大小写折叠或去重音符号合并ID'
        evidence = reviews.get(word, ('', '原卡词形和独立ID', ''))[1]
    classified.append({
        'flag_id': f'P41-{i:03}', **f, 'p41_category': kind, 'priority': priority,
        'confirmed_content_error': '否；本轮未证实', 'resolution': state,
        'decision': action, 'evidence': evidence, 'content_changed': '否',
    })
write_csv('quality-triage.csv', classified)

# Identity, hash, PCM format and recording attribution. No downloads or re-encoding.
manifest = json.loads((ROOT / 'assets/pronunciation/manifest.json').read_text(encoding='utf-8'))
audio = []
for r in manifest['items']:
    assert by_id[r['entry_id']]['word'] == r['word']
    path = ROOT / r['asset_path']
    assert digest(path) == r['sha256']
    with wave.open(str(path), 'rb') as w:
        duration = round(w.getnframes() * 1000 / w.getframerate())
        assert w.getnchannels() == r['channels'] and w.getframerate() == r['sample_rate']
        assert abs(duration - r['duration_ms']) <= 2
        assert w.getsampwidth() == 2
    audio.append({k: r[k] for k in ['entry_id', 'word', 'asset_path', 'sha256', 'source_url',
                                   'author', 'license', 'license_url', 'changes']})
    audio[-1].update(hash_and_word_match=True, pcm_duration_ms=duration,
                     source_page_rechecked='2026-11-09：Wikimedia词头/作者/许可证一致',
                     subjective_hearing='待用户亲自听辨；原生完整播放不能代替声学/口音终审')
save('audio-audit.json', audio)

# Read back a restore rehearsal into a new private file, never replace formal data.
meta = json.loads((PRIVATE / 'personal-backup.json').read_text(encoding='utf-8'))
backup = pathlib.Path(meta['backup_path'])
assert digest(backup) == meta['backup_sha256']
restore = PRIVATE / 'restore-rehearsal.sqlite3'
with sqlite3.connect(backup.as_uri() + '?mode=ro', uri=True) as src:
    with sqlite3.connect(restore) as dst:
        src.backup(dst)


def tables(path):
    with sqlite3.connect(path.as_uri() + '?mode=ro', uri=True) as c:
        c.row_factory = sqlite3.Row
        assert c.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert not c.execute('PRAGMA foreign_key_check').fetchall()
        assert c.execute('PRAGMA user_version').fetchone()[0] == 3
        names = [r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
        return {t: [dict(r) for r in c.execute(f'SELECT * FROM "{t}" ORDER BY 1')] for t in names}


backup_tables, restored = tables(backup), tables(restore)
assert backup_tables == restored
# Separate reopened connection models reading the restored file after closing it.
assert tables(restore) == restored
before = json.loads((PRIVATE / 'personal-before-tables.json').read_text(encoding='utf-8'))
formal = tables(pathlib.Path(meta['source_path']))
equal = {t: before[t] == formal[t] for t in before}
assert all(equal.values()), 'Concurrent personal changes detected; inspect privately rather than overwrite.'
save('personal-preservation.json', {
    'backup_integrity': 'ok', 'backup_sha256': meta['backup_sha256'],
    'foreign_key_check': 'no violations', 'schema_version': 3,
    'restore_rehearsal': 'private new SQLite file; all tables equal on copy and reopened connection',
    'formal_table_row_counts': {t: len(rows) for t, rows in formal.items()},
    'formal_tables_equal_before_after': equal,
    'formal_database_replaced': False, 'credentials_copied': False,
})

starter = json.loads((ROOT / 'private/p3/starter-hashes-before.json').read_text(encoding='utf-8'))
starter_checked = 0
for base, files in starter.items():
    for rel, sha in files.items():
        assert digest(pathlib.Path(base) / rel) == sha
        starter_checked += 1

# Chinese semantic substring check complements the native hidden-answer assertions.
hint_leaks = []
for r in vocab:
    for token in re.split('[；，：、（）]', r['meaning_zh']):
        if len(token) > 1 and token not in {'名词', '动词', '形容词', '副词'} and token in r['phonics_note']:
            hint_leaks.append({'word': r['word'], 'token': token})
save('quality-summary.json', {
    'date': '2026-11-09', 'version': '0.7.0+10', 'words': 500,
    'input_flags': len(flags), 'flagged_words': len({r['entry_id'] for r in flags}),
    'input_flags_sha256': digest(flags_path),
    'categories': dict(collections.Counter(r['p41_category'] for r in classified)),
    'priorities': dict(collections.Counter(r['priority'] for r in classified)),
    'confirmed_incorrect_definitions': 0, 'confirmed_phonics_errors': 0,
    'definition_coverage_limit': '500词结构检查；26词依据对照，不等于500词全部经教师终审',
    'evidence_reviewed_words': len(comparison), 'texture_mapping': 'resolved in supplementary ledger',
    'vocabulary_content_changes': 0, 'vocabulary_sha256': digest(vocab_path),
    'all_required_fields_present': not missing, 'duplicate_ids': 0,
    'human_audio': len(audio), 'local_tts_fallback_candidates': 500 - len(audio),
    'pets2025_states': dict(collections.Counter(r['pets2025_status'] for r in vocab)),
    'hint_definition_substring_flags': hint_leaks,
    'hint_check_limit': '自动子串检查只作补充；原生界面另查答案/双语例句隐藏',
    'starter_files_unchanged': starter_checked,
    'notion_content_writes': 0, 'real_events_uploaded': 0,
})
print(json.dumps({'flags': len(flags), 'words': len(vocab), 'reviews': len(comparison),
                  'audio': len(audio), 'formal_preserved': all(equal.values()),
                  'starter_unchanged': starter_checked}, ensure_ascii=False))
