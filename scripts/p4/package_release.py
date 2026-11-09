"""Package the accepted Windows application; never include personal state or keys."""
import hashlib
import json
import pathlib
import re
import zipfile

root=pathlib.Path(__file__).resolve().parents[2]
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
qa=read(root/'docs/p4/acceptance.json'); ui=read(root/'docs/p4/release-ui.json')
integrity=read(root/'docs/p4/source-integrity.json')
assert qa['version']=='0.7.0+10' and ui['status']=='PASS'
assert qa['notion_actual_500_full_repeat_incremental']=='PASS'
assert integrity['starter_files_unchanged']==417 and integrity['plaintext_notion_token_matches']==0
release=root/'build/windows/x64/runner/Release'
files=[p for p in release.rglob('*') if p.is_file()]
assert (release/'english_learning.exe').is_file()
assert not [p for p in files if p.suffix.lower() in {'.sqlite','.sqlite3','.db','.enc','.keystore','.jks','.key','.pem'}]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
csv=root/'assets/vocabulary/reviewed500.csv'
assert sha(csv)==qa['vocabulary_sha256']
assert sha(release/'data/flutter_assets/assets/vocabulary/reviewed500.csv')==qa['vocabulary_sha256']
out=root/'output/windows';out.mkdir(parents=True,exist_ok=True)
target=out/'EnglishLearning-0.7.0+10-Windows.zip'
manifest={**qa,'normal_release_ui':'PASS','release_exe_sha256':sha(release/'english_learning.exe'),
    'personal_database_included':False,'credentials_included':False,'system_tts_voice_files_included':False}
with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
    for p in files:z.write(p,p.relative_to(release))
    z.write(csv,'vocabulary/reviewed500.csv')
    for p in (root/'docs/p4').iterdir():
        if p.is_file() and p.suffix in {'.md','.json','.csv'}:z.write(p,'reports/'+p.name)
    z.writestr('BUILD_INFO.json',json.dumps(manifest,ensure_ascii=False,indent=2))
    z.writestr('README.txt','EnglishLearning 0.7.0+10 — Windows x64\n\n'
        '解压整个目录，运行 english_learning.exe，保留相邻 DLL 和 data 目录。\n'
        '保持500词；本机现有学习记录位于应用数据目录，不随程序包分发。新设备可连接Notion或导入vocabulary/reviewed500.csv。\n'
        'Notion配置保存在各机器Windows凭据管理器，密钥仅在软件隐藏输入框安全保存。不会上传真实学习事件。\n'
        '6词优先合法真人录音；其余可用本机已安装的Microsoft美式英语Desktop TTS。声库不随包分发。\n'
        '完整听音后才可保存对应发音自评；也可跳过听音仅学词义。TTS不是人工标准或自动发音评分。\n'
        '完整验收、质量提示及剩余问题见reports/REPORT.md。\n')
with zipfile.ZipFile(target) as z:
    assert z.testzip() is None
    assert hashlib.sha256(z.read('vocabulary/reviewed500.csv')).hexdigest()==qa['vocabulary_sha256']
    hits=[name for name in z.namelist() if re.search(rb'(?:ntn_|secret_)[A-Za-z0-9]{30,}',z.read(name))]
    assert not hits, 'Potential credential material in package; review without printing values'
manifest.update(zip_file=target.name,zip_bytes=target.stat().st_size,zip_sha256=sha(target))
(out/'manifest-0.7.0+10.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'zip_file':str(target),'zip_bytes':manifest['zip_bytes'],'zip_sha256':manifest['zip_sha256'],
    'package_crc':'PASS','credential_pattern_matches':0},ensure_ascii=False,indent=2))
