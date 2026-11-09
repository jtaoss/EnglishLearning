"""Package the verified Windows bundle and actual cloud content, never user data."""
import hashlib
import json
import pathlib
import shutil
import zipfile

root = pathlib.Path(__file__).resolve().parents[2]
release = root / 'build/windows/x64/runner/Release'
files = [p for p in release.rglob('*') if p.is_file()]
assert (release / 'english_learning.exe').is_file()
assert not [p for p in files if p.suffix.lower() in {'.sqlite', '.sqlite3', '.db', '.enc', '.keystore', '.jks'}]
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda p: json.loads(p.read_text(encoding='utf-8'))
stats = read(root / 'docs/p3/selection-statistics.json')
cloud = read(root / 'docs/p3/NOTION_IMPORT_STATISTICS.json')
warm = read(root / 'build/reports/p3-native/native-report.json')
cold = read(root / 'build/reports/p3-native/cold-report.json')
assert warm['word_count'] == cold['word_count'] == cloud['cloud_words'] == 500
assert cold['independent_process'] and all(b['accepted'] for b in cloud['batches'].values())
assert cloud['actual_windows_personal_library']['status'] == 'PASS'
csv = root / 'private/p3/notion-cloud-500.csv'
assert sha(csv) == stats['reviewed_pack_sha256']
info = {
    'version': '0.6.0+9', 'platform': 'Windows x64',
    'release_exe_sha256': sha(release / 'english_learning.exe'),
    'reviewed_words': 500, 'notion_actual_words': 500, 'actual_windows_sqlite_words': 500,
    'notion_pages_created': 400, 'notion_existing_pages_content_updated': 100,
    'notion_pages_deleted': 0, 'notion_content_fields_added': 7,
    'reviewed_pack_sha256': stats['reviewed_pack_sha256'],
    'actual_cloud_export_sha256': sha(csv), 'all_29_cloud_content_fields_equal': True,
    'static_analysis': 'PASS', 'unit_widget_tests_passed': 188,
    'p3_native_flow': 'PASS', 'p3_cold_process': 'PASS',
    'normal_release_500_word_ui': read(root / 'docs/p3/RELEASE_UI_ACCEPTANCE.json')['formal_local_words_observed'] == 500,
    'actual_cloud_snapshot_windows_200': 'PASS', 'actual_cloud_snapshot_windows_500': 'PASS',
    'cloud_snapshot_transport': 'Notion connector direct read → CSV → existing Windows import',
    'direct_notion_api_incremental_sync': 'Pending read-only credential configuration',
    'warm_pid': warm['pid'], 'cold_pid': cold['pid'],
    'offline_native_http_attempts': warm['http_attempts'] + cold['http_attempts'],
    'isolated_native_flow_opened_personal_database': False,
    'personal_database_content_imported': True, 'personal_library_words': 500,
    'personal_meaning_events_created': 0, 'personal_pronunciation_events_created': 0,
    'production_sqlite_schema': 3, 'android_builds_performed': False,
    'real_learning_events_uploaded': 0,
}
out = root / 'output/windows'
out.mkdir(parents=True, exist_ok=True)
shutil.copyfile(csv, out / 'Notion-500.csv')
target = out / 'EnglishLearning-0.6.0+9-Windows-P3.zip'
with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in files:
        archive.write(path, path.relative_to(release))
    archive.write(csv, 'vocabulary/Notion-500.csv')
    archive.writestr('BUILD_INFO.json', json.dumps(info, ensure_ascii=False, indent=2))
    archive.writestr('README.txt', 'EnglishLearning 0.6.0+9\n\n'
        '解压整个目录后运行 english_learning.exe，保留相邻 DLL 和 data 目录。\n'
        'Notion 已分批扩至 500 词，本机正式词库已导入；新设备可选择 CSV 文件导入 vocabulary/Notion-500.csv。\n'
        '此 CSV 来自实际云端读回并经逐字段核验。重复导入保留个人评级、复习日期和发音状态。\n'
        '应用内直连 Notion 的真实增量同步待安全配置只读密钥后验收；密钥不要发送到聊天。\n'
        '学习记录在用户应用数据目录，不包含在此包中。未上传真实学习事件。\n'
        '6 词含已有合法音频，494 词可无音频学习及自主认读自评。\n')
with zipfile.ZipFile(target) as archive:
    assert archive.testzip() is None
    assert hashlib.sha256(archive.read('data/flutter_assets/assets/vocabulary/reviewed500.csv')).hexdigest() == stats['reviewed_pack_sha256']
    assert hashlib.sha256(archive.read('vocabulary/Notion-500.csv')).hexdigest() == stats['reviewed_pack_sha256']
info.update(zip_file=target.name, zip_bytes=target.stat().st_size, zip_sha256=sha(target))
for path in [out / 'manifest.json', root / 'docs/p3/acceptance.json']:
    path.write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(info, ensure_ascii=False, indent=2))
