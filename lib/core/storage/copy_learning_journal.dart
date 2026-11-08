import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

/// P2-B1 has no production activation switch or real Notion write target.
const personalEventUploadEnabled = false;
String journalPayloadHash(Map<String, Object?> payload) {
  final keys = payload.keys.toList()..sort();
  return sha256
      .convert(utf8.encode(jsonEncode({for (final k in keys) k: payload[k]})))
      .toString();
}

String journalUuid() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

void verifyCopyPermit(String path) {
  try {
    final p =
        jsonDecode(File('$path.copy-permit.json').readAsStringSync()) as Map;
    final target = File(path).resolveSymbolicLinksSync();
    final declared = File(p['copy_path'] as String).resolveSymbolicLinksSync();
    final original = File(p['protected_path'] as String)
        .resolveSymbolicLinksSync();
    String key(String p) => Platform.isWindows ? p.toLowerCase() : p;
    if (p['role'] != 'isolated_learning_copy' ||
        p['simulation_only'] != true ||
        key(target) != key(declared) ||
        key(target) == key(original) ||
        FileSystemEntity.identicalSync(target, original)) {
      throw const FormatException();
    }
  } catch (_) {
    throw StateError('必须使用已标记的隔离副本；未操作个人学习库。');
  }
}

/// Caller owns one transaction spanning legacy migrations and these additions.
void migrateCopyJournal(Database db, {bool failAfterSchema = false}) {
  db.execute(
    'CREATE TABLE copy_journal_meta(singleton INTEGER PRIMARY KEY CHECK(singleton=1), device_id TEXT UNIQUE NOT NULL, next_sequence INTEGER NOT NULL, simulation_only INTEGER NOT NULL CHECK(simulation_only=1), deferred_until_utc INTEGER)',
  );
  db.execute('INSERT INTO copy_journal_meta VALUES(1,?,1,1,NULL)', [
    'device-${journalUuid()}',
  ]);
  db.execute(
    '''CREATE TABLE learning_journal(
    event_id TEXT PRIMARY KEY NOT NULL, action_key TEXT UNIQUE NOT NULL,
    word_id TEXT NOT NULL REFERENCES vocabulary(entry_id), learning_type TEXT NOT NULL CHECK(learning_type IN ('meaning','pronunciation')),
    grade TEXT NOT NULL, occurred_utc INTEGER NOT NULL, device_id TEXT NOT NULL,
    device_sequence INTEGER NOT NULL, schema_version INTEGER NOT NULL,
    algorithm_version TEXT NOT NULL, origin TEXT NOT NULL CHECK(origin='simulation_test'),
    payload_json TEXT NOT NULL, payload_hash TEXT NOT NULL, UNIQUE(device_id,device_sequence))''',
  );
  db.execute('''CREATE TABLE journal_outbox(event_id TEXT PRIMARY KEY REFERENCES learning_journal(event_id),
    state TEXT NOT NULL CHECK(state IN ('pending','sending','uncertain','synced','conflict')),
    remote_id TEXT, next_attempt_utc INTEGER, last_error_code TEXT)''');
  db.execute('''CREATE TABLE migration_state_snapshots(word_id TEXT PRIMARY KEY REFERENCES vocabulary(entry_id),
    origin TEXT NOT NULL CHECK(origin='history_state_snapshot'), captured_utc INTEGER NOT NULL,
    state_json TEXT NOT NULL)''');
  db.execute('''CREATE TABLE journal_inbox(remote_event_id TEXT NOT NULL, payload_hash TEXT NOT NULL,
    origin TEXT NOT NULL, state TEXT NOT NULL CHECK(state IN ('matched','requires_review','quarantined')),
    payload_json TEXT NOT NULL, PRIMARY KEY(remote_event_id,payload_hash))''');
  if (failAfterSchema) throw StateError('Controlled copy migration rollback');
  final captured = DateTime.now().toUtc().millisecondsSinceEpoch;
  for (final row in db.select(
    'SELECT * FROM learning_progress ORDER BY entry_id',
  )) {
    final pron = db.select(
      'SELECT * FROM pronunciation_progress WHERE entry_id=?',
      [row['entry_id']],
    );
    db.execute('INSERT INTO migration_state_snapshots VALUES(?,?,?,?)', [
      row['entry_id'],
      'history_state_snapshot',
      captured,
      jsonEncode({
        'meaning_state': Map<String, Object?>.from(row),
        'pronunciation_state': pron.isEmpty
            ? null
            : Map<String, Object?>.from(pron.single),
        'provenance': 'original persisted state; no inferred events',
        'inferred_event_time': null,
      }),
    ]);
  }
  // Actual old events remain in their original tables, without queue backfill.
  db.execute('PRAGMA user_version=4');
}

bool copyActionExists(
  Database db,
  String actionKey,
  String word,
  String type,
  String grade,
  int at,
) {
  final rows = db.select(
    'SELECT word_id,learning_type,grade,occurred_utc FROM learning_journal WHERE action_key=?',
    [actionKey],
  );
  if (rows.isEmpty) return false;
  final p = rows.single;
  if (p['word_id'] != word ||
      p['learning_type'] != type ||
      p['grade'] != grade ||
      p['occurred_utc'] != at) {
    throw StateError('同一学习操作标识的内容不一致，未覆盖原记录。');
  }
  return true;
}

void appendCopyEvent(
  Database db, {
  required String actionKey,
  required String word,
  required String type,
  required String grade,
  required int at,
}) {
  final meta = db
      .select('SELECT * FROM copy_journal_meta WHERE singleton=1')
      .single;
  final id = journalUuid();
  final algorithm = type == 'meaning'
      ? 'basic-intervals-v1'
      : 'pronunciation-self-assessment-v1';
  final payload = <String, Object?>{
    'event_id': id,
    'word_id': word,
    'learning_type': type,
    'grade': grade,
    'occurred_at_utc': DateTime.fromMillisecondsSinceEpoch(
      at,
      isUtc: true,
    ).toIso8601String(),
    'device_id': meta['device_id'],
    'device_sequence': meta['next_sequence'],
    'schema_version': 1,
    'algorithm_version': algorithm,
    'origin': 'simulation_test',
  };
  final encoded = jsonEncode(payload);
  final hash = journalPayloadHash(payload);
  db.execute('INSERT INTO learning_journal VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)', [
    id,
    actionKey,
    word,
    type,
    grade,
    at,
    meta['device_id'],
    meta['next_sequence'],
    1,
    algorithm,
    'simulation_test',
    encoded,
    hash,
  ]);
  db.execute("INSERT INTO journal_outbox(event_id,state) VALUES(?,'pending')", [
    id,
  ]);
  db.execute(
    'UPDATE copy_journal_meta SET next_sequence=next_sequence+1 WHERE singleton=1',
  );
}

/// Imported event differences are evidence, never automatic grade projections.
void receiveCopyEvent(Database db, Map<String, Object?> payload) {
  final id = payload['event_id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Invalid event identity');
  }
  final encoded = jsonEncode(payload);
  final hash = journalPayloadHash(payload);
  final local = db.select(
    'SELECT payload_hash FROM learning_journal WHERE event_id=?',
    [id],
  );
  final origin = payload['origin'] as String? ?? 'unknown';
  final state = origin != 'simulation_test'
      ? 'quarantined'
      : local.isNotEmpty && local.single['payload_hash'] == hash
      ? 'matched'
      : 'requires_review';
  db.execute('INSERT OR IGNORE INTO journal_inbox VALUES(?,?,?,?,?)', [
    id,
    hash,
    origin,
    state,
    encoded,
  ]);
  if (state == 'requires_review' && local.isNotEmpty) {
    db.execute(
      "UPDATE journal_outbox SET state='conflict',last_error_code='remote_payload_difference' WHERE event_id=?",
      [id],
    );
  }
}
