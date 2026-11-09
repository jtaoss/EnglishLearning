import 'dart:convert';
import 'dart:isolate';

import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';

import 'copy_learning_journal.dart';

/// Each serialized operation owns its connection inside a background isolate.
/// No SQLite handle crosses isolates; close/reopen tests use actual disk files.
final class SqliteLearningRepository
    implements LearningRepository, PronunciationStore, NotionSyncStore {
  SqliteLearningRepository._(this.path, {this.isIsolatedCopy = false});
  final bool isIsolatedCopy;
  final String path;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;

  static Future<SqliteLearningRepository> open(String path) async {
    final repository = SqliteLearningRepository._(path);
    await repository._run<void>('initialize');
    return repository;
  }

  static Future<SqliteLearningRepository> openIsolatedCopy(
    String path, {
    bool failMigrationAfterSchema = false,
  }) async {
    verifyCopyPermit(path);
    final repo = SqliteLearningRepository._(path, isIsolatedCopy: true);
    await repo._run<void>('initialize', [failMigrationAfterSchema]);
    return repo;
  }

  Future<List<Map<String, Object?>>> readJournal() =>
      _run<List<Map<String, Object?>>>('journal-read');
  Future<void> setJournalState(
    String id,
    String state, {
    String? remoteId,
    DateTime? next,
    String? error,
  }) => _run<void>('journal-state', [
    id,
    state,
    remoteId,
    next?.toUtc().millisecondsSinceEpoch,
    error,
  ]);
  Future<void> receiveJournalEvents(List<Map<String, Object?>> events) =>
      _run<void>('journal-receive', [events]);
  Future<int?> journalDeferredUntil() => _run<int?>('journal-gate');
  Future<void> deferJournalUntil(DateTime at) =>
      _run<void>('journal-defer', [at.toUtc().millisecondsSinceEpoch]);

  Future<T> _run<T>(String operation, [List<Object?> args = const []]) {
    if (_closed) return Future<T>.error(StateError('本地词库已关闭。'));
    final databasePath = path;
    final copyMode = isIsolatedCopy;
    final result = _tail.then(
      (_) => Isolate.run<T>(
        () => _execute(databasePath, operation, args, copyMode) as T,
      ),
    );
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<ImportResult> importCsv(String csv) async {
    final entries = VocabularyCsv.parse(csv);
    return _run<ImportResult>('import', [
      entries.map((e) => e.fields).toList(),
    ]);
  }

  @override
  Future<List<StudyWord>> readWords() => _run<List<StudyWord>>('read');

  @override
  Future<void> recordReview(
    String entryId,
    ReviewGrade grade,
    DateTime at, {
    String? operationId,
  }) => _run<void>('review', [
    entryId,
    grade.name,
    at.toUtc().millisecondsSinceEpoch,
    ReviewSchedule.nextDue(grade, at).millisecondsSinceEpoch,
    isIsolatedCopy ? (operationId ?? journalUuid()) : null,
  ]);

  @override
  Future<int> reviewEventCount() => _run<int>('events');

  @override
  Future<NotionSyncState> readNotionState(String sourceId) =>
      _run<NotionSyncState>('notion-state', [sourceId]);

  @override
  Future<ImportResult> applyNotionBatch({
    required String sourceId,
    required List<NotionWord> words,
    required DateTime? expectedWatermark,
    required DateTime? watermark,
    required DateTime syncedAt,
  }) => _run<ImportResult>('notion-apply', [
    sourceId,
    words
        .map(
          (w) => <String, Object?>{
            'fields': w.entry.fields,
            'page_id': w.pageId,
            'edited': w.editedAt.millisecondsSinceEpoch,
            'hash': w.contentHash,
          },
        )
        .toList(),
    expectedWatermark?.millisecondsSinceEpoch,
    watermark?.millisecondsSinceEpoch,
    syncedAt.toUtc().millisecondsSinceEpoch,
  ]);

  @override
  Future<PronunciationProgress> readPronunciation(String entryId) =>
      _run<PronunciationProgress>('pronunciation-read', [entryId]);

  @override
  Future<void> recordPronunciation({
    required String entryId,
    required PronunciationGrade grade,
    required String audioAssetId,
    required String attemptId,
    required DateTime at,
  }) => _run<void>('pronunciation-assess', [
    entryId,
    grade.name,
    audioAssetId,
    attemptId,
    at.toUtc().millisecondsSinceEpoch,
  ]);

  @override
  Future<void> close() async {
    _closed = true;
    await _tail;
  }
}

Object? _execute(
  String path,
  String operation,
  List<Object?> args,
  bool copyMode,
) {
  if (copyMode) verifyCopyPermit(path);
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA foreign_keys = ON');
    db.execute('PRAGMA busy_timeout = 5000');
    if (!copyMode &&
        (db.select('PRAGMA user_version').single.values.single as int) > 3) {
      throw StateError('隔离副本不能作为正式个人库打开。');
    }
    if (operation.startsWith('journal-') && !copyMode) {
      throw StateError('个人事件同步尚未启用。');
    }
    switch (operation) {
      case 'initialize':
        if (copyMode) db.execute('BEGIN IMMEDIATE');
        try {
          final version =
              db.select('PRAGMA user_version').single.values.single as int;
          if (version > (copyMode ? 4 : 3)) {
            throw StateError('数据库版本较新，请更新应用；原数据未修改。');
          }
          if (copyMode && version == 0) throw StateError('隔离副本必须来自已有学习数据库。');
          if (version == 0) {
            if (db
                .select(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
                )
                .isNotEmpty) {
              throw StateError('发现无法识别的数据库，原数据未修改。');
            }
            _transaction(db, () {
              db.execute('''CREATE TABLE vocabulary (
              entry_id TEXT PRIMARY KEY NOT NULL,
              word_key TEXT UNIQUE NOT NULL,
              word TEXT NOT NULL, library_class TEXT NOT NULL,
              content_json TEXT NOT NULL)''');
              db.execute('''CREATE TABLE learning_progress (
              entry_id TEXT PRIMARY KEY REFERENCES vocabulary(entry_id),
              status TEXT NOT NULL DEFAULT 'untested'
                CHECK(status IN ('untested','mastered','familiar','forgotten')),
              pronunciation_status TEXT NOT NULL DEFAULT '未测试',
              review_count INTEGER NOT NULL DEFAULT 0 CHECK(review_count >= 0),
              last_reviewed_utc INTEGER, due_utc INTEGER)''');
              db.execute('''CREATE TABLE review_events (
              event_id INTEGER PRIMARY KEY AUTOINCREMENT,
              entry_id TEXT NOT NULL REFERENCES vocabulary(entry_id),
              grade TEXT NOT NULL, reviewed_utc INTEGER NOT NULL,
              due_utc INTEGER NOT NULL)''');
              db.execute(
                'CREATE INDEX progress_due ON learning_progress(due_utc)',
              );
              db.execute('PRAGMA user_version = 1');
            });
          }
          if (version < 2) {
            _transaction(db, () {
              db.execute('''CREATE TABLE pronunciation_progress (
              entry_id TEXT PRIMARY KEY REFERENCES vocabulary(entry_id),
              status TEXT NOT NULL CHECK(status IN ('needsPractice','familiar','confident')),
              assessed_utc INTEGER NOT NULL, audio_asset_id TEXT NOT NULL)''');
              db.execute('''CREATE TABLE pronunciation_events (
              attempt_id TEXT PRIMARY KEY NOT NULL,
              entry_id TEXT NOT NULL REFERENCES vocabulary(entry_id),
              status TEXT NOT NULL CHECK(status IN ('needsPractice','familiar','confident')),
              audio_asset_id TEXT NOT NULL, assessed_utc INTEGER NOT NULL)''');
              db.execute('PRAGMA user_version = 2');
            });
          }
          if (version < 3) {
            _transaction(db, () {
              db.execute('''CREATE TABLE notion_sync_state (
              source_id TEXT PRIMARY KEY NOT NULL,
              watermark_utc INTEGER, synced_utc INTEGER NOT NULL)''');
              db.execute('''CREATE TABLE notion_word_links (
              source_id TEXT NOT NULL REFERENCES notion_sync_state(source_id),
              entry_id TEXT NOT NULL REFERENCES vocabulary(entry_id),
              page_id TEXT NOT NULL, content_hash TEXT NOT NULL,
              remote_edited_utc INTEGER NOT NULL,
              PRIMARY KEY(source_id,entry_id), UNIQUE(source_id,page_id))''');
              db.execute('PRAGMA user_version = 3');
            });
          }
          if (copyMode && version < 4) {
            migrateCopyJournal(
              db,
              failAfterSchema: args.isNotEmpty && args.single == true,
            );
          }
          if (copyMode &&
              db
                      .select(
                        'SELECT simulation_only FROM copy_journal_meta WHERE singleton=1',
                      )
                      .single['simulation_only'] !=
                  1) {
            throw StateError('副本模式无效。');
          }
          if (copyMode) db.execute('COMMIT');
        } catch (_) {
          if (copyMode && !db.autocommit) db.execute('ROLLBACK');
          rethrow;
        }
        return null;
      case 'journal-read':
        return db
            .select(
              'SELECT e.payload_json,e.payload_hash,o.state,o.remote_id,o.next_attempt_utc FROM learning_journal e JOIN journal_outbox o USING(event_id) ORDER BY e.device_sequence',
            )
            .map(
              (r) => <String, Object?>{
                'payload': jsonDecode(r['payload_json'] as String),
                'hash': r['payload_hash'],
                'state': r['state'],
                'remote_id': r['remote_id'],
                'next_attempt_utc': r['next_attempt_utc'],
              },
            )
            .toList();
      case 'journal-state':
        db.execute(
          'UPDATE journal_outbox SET state=?,remote_id=COALESCE(?,remote_id),next_attempt_utc=?,last_error_code=? WHERE event_id=?',
          [args[1], args[2], args[3], args[4], args[0]],
        );
        if (db.updatedRows != 1) throw StateError('Event missing');
        return null;
      case 'journal-receive':
        _transaction<void>(db, () {
          for (final p in (args.single as List).cast<Map<String, Object?>>()) {
            receiveCopyEvent(db, p);
          }
        });
        return null;
      case 'journal-gate':
        return db
            .select(
              'SELECT deferred_until_utc FROM copy_journal_meta WHERE singleton=1',
            )
            .single['deferred_until_utc'];
      case 'journal-defer':
        db.execute(
          'UPDATE copy_journal_meta SET deferred_until_utc=MAX(COALESCE(deferred_until_utc,0),?) WHERE singleton=1',
          args,
        );
        return null;
      case 'notion-state':
        final state = db.select(
          'SELECT * FROM notion_sync_state WHERE source_id=?',
          args,
        );
        if (state.isEmpty) return const NotionSyncState();
        return NotionSyncState(
          watermark: _date(state.single['watermark_utc']),
          syncedAt: _date(state.single['synced_utc']),
          linkedWords:
              db
                      .select(
                        'SELECT COUNT(*) AS n FROM notion_word_links WHERE source_id=?',
                        args,
                      )
                      .single['n']
                  as int,
        );
      case 'notion-apply':
        return _transaction(db, () {
          final sourceId = args[0] as String;
          if (!notionIdPattern.hasMatch(sourceId)) {
            throw const NotionFailure('数据源 ID 无效。');
          }
          final rows = (args[1] as List).cast<Map<String, Object?>>();
          if (rows.length > VocabularyCsv.maxEntries) {
            throw const NotionFailure('同步超出本阶段 500 词范围。');
          }
          final previous = db.select(
            'SELECT watermark_utc FROM notion_sync_state WHERE source_id=?',
            [sourceId],
          );
          if ((previous.isEmpty ? null : previous.single['watermark_utc']) !=
              args[2]) {
            throw const NotionFailure('本地同步位置已更新，请重新同步。');
          }
          if (args[2] != null &&
              (args[3] == null || (args[3] as int) < (args[2] as int))) {
            throw const NotionFailure('同步时间不能后退，整批未同步。');
          }
          final ids = <String>{}, pages = <String>{};
          for (final row in rows) {
            final fields = row['fields'] as Map<String, String>;
            final id = fields['entry_id']!;
            final page = row['page_id'] as String;
            if (!ids.add(id) ||
                !pages.add(page) ||
                !notionIdPattern.hasMatch(page)) {
              throw const NotionFailure('同步批次有重复 ID 或无效页面。');
            }
            final links = db.select(
              'SELECT source_id,page_id FROM notion_word_links WHERE entry_id=?',
              [id],
            );
            if (links.any(
              (l) => l['source_id'] != sourceId || l['page_id'] != page,
            )) {
              throw const NotionFailure('稳定 ID 已关联其他 Notion 来源或页面，整批未同步。');
            }
            final collision = db.select(
              'SELECT entry_id FROM notion_word_links WHERE source_id=? AND page_id=? AND entry_id<>?',
              [sourceId, page, id],
            );
            if (collision.isNotEmpty) {
              throw const NotionFailure('Notion 页面已关联其他稳定 ID，整批未同步。');
            }
          }
          final result = _importFields(
            db,
            rows.map((row) => row['fields'] as Map<String, String>).toList(),
          );
          db.execute(
            '''INSERT INTO notion_sync_state VALUES(?,?,?)
            ON CONFLICT(source_id) DO UPDATE SET watermark_utc=excluded.watermark_utc,synced_utc=excluded.synced_utc''',
            [sourceId, args[3], args[4]],
          );
          for (final row in rows) {
            db.execute(
              '''INSERT INTO notion_word_links VALUES(?,?,?,?,?)
              ON CONFLICT(source_id,entry_id) DO UPDATE SET content_hash=excluded.content_hash,remote_edited_utc=excluded.remote_edited_utc''',
              [
                sourceId,
                (row['fields'] as Map)['entry_id'],
                row['page_id'],
                row['hash'],
                row['edited'],
              ],
            );
          }
          return result;
        });
      case 'pronunciation-read':
        final rows = db.select(
          'SELECT * FROM pronunciation_progress WHERE entry_id=?',
          args,
        );
        if (rows.isEmpty) {
          final legacy = db.select(
            'SELECT pronunciation_status FROM learning_progress WHERE entry_id=?',
            args,
          );
          return PronunciationProgress(
            legacyLabel: legacy.isEmpty
                ? null
                : legacy.single['pronunciation_status'] as String,
          );
        }
        return PronunciationProgress(
          grade: PronunciationGrade.values.byName(
            rows.single['status'] as String,
          ),
          assessedAt: _date(rows.single['assessed_utc']),
          sourceId: rows.single['audio_asset_id'] as String,
        );
      case 'pronunciation-assess':
        _transaction<void>(db, () {
          if (copyMode &&
              copyActionExists(
                db,
                'pronunciation:${args[3]}',
                args[0] as String,
                'pronunciation',
                args[1] as String,
                args[4] as int,
              )) {
            return;
          }
          if ((args[2] as String).isEmpty || (args[3] as String).isEmpty) {
            throw ArgumentError('发音资源或尝试标识为空。');
          }
          // Enum validation precedes any write; foreign keys require an existing word.
          PronunciationGrade.values.byName(args[1] as String);
          final prior = db.select(
            'SELECT * FROM pronunciation_events WHERE attempt_id=?',
            [args[3]],
          );
          if (prior.isNotEmpty) {
            if (prior.single['entry_id'] != args[0] ||
                prior.single['status'] != args[1] ||
                prior.single['audio_asset_id'] != args[2]) {
              throw StateError('同一次发音尝试不能覆盖其他记录。');
            }
            return;
          }
          db.execute('INSERT INTO pronunciation_events VALUES(?,?,?,?,?)', [
            args[3],
            args[0],
            args[1],
            args[2],
            args[4],
          ]);
          db.execute(
            '''INSERT INTO pronunciation_progress VALUES(?,?,?,?)
            ON CONFLICT(entry_id) DO UPDATE SET status=excluded.status,
              assessed_utc=excluded.assessed_utc,audio_asset_id=excluded.audio_asset_id''',
            [args[0], args[1], args[4], args[2]],
          );
          // No writes to learning_progress, review_events, or legacy pronunciation_status.
          if (copyMode) {
            appendCopyEvent(
              db,
              actionKey: 'pronunciation:${args[3]}',
              word: args[0] as String,
              type: 'pronunciation',
              grade: args[1] as String,
              at: args[4] as int,
            );
          }
        });
        return null;
      case 'import':
        final fields = (args.single as List).cast<Map<String, String>>();
        return _transaction(db, () => _importFields(db, fields));
      case 'read':
        return db
            .select('''SELECT v.content_json, p.*, a.status AS reading_grade,
              a.assessed_utc AS reading_assessed_utc FROM vocabulary v
          JOIN learning_progress p USING(entry_id)
          LEFT JOIN pronunciation_progress a USING(entry_id)
          ORDER BY v.word_key COLLATE NOCASE, v.word_key''')
            .map(
              (row) => StudyWord(
                entry: VocabularyEntry(
                  (jsonDecode(
                    row['content_json'] as String,
                  ) as Map<String, dynamic>).cast<String, String>(),
                ),
                status: row['status'] as String,
                pronunciationStatus: row['pronunciation_status'] as String,
                reviewCount: row['review_count'] as int,
                lastReviewedAt: _date(row['last_reviewed_utc']),
                dueAt: _date(row['due_utc']),
                pronunciationProgress: row['reading_grade'] == null
                    ? null
                    : PronunciationProgress(
                        grade: PronunciationGrade.values.byName(
                          row['reading_grade'] as String,
                        ),
                        assessedAt: _date(row['reading_assessed_utc']),
                      ),
              ),
            )
            .toList();
      case 'review':
        _transaction<void>(db, () {
          final id = args[0] as String;
          if (copyMode &&
              copyActionExists(
                db,
                'meaning:${args[4]}',
                id,
                'meaning',
                args[1] as String,
                args[2] as int,
              )) {
            return;
          }
          final word = db.select(
            'SELECT library_class FROM vocabulary WHERE entry_id=?',
            [id],
          );
          if (word.isEmpty) throw StateError('未找到该词条，未保存评分。');
          if (word.single['library_class'] == '暂缓') {
            throw StateError('暂缓词不安排复习。');
          }
          db.execute(
            'UPDATE learning_progress SET status=?,review_count=review_count+1,last_reviewed_utc=?,due_utc=? WHERE entry_id=?',
            [args[1], args[2], args[3], id],
          );
          db.execute(
            'INSERT INTO review_events(entry_id,grade,reviewed_utc,due_utc) VALUES(?,?,?,?)',
            [id, args[1], args[2], args[3]],
          );
          if (copyMode) {
            appendCopyEvent(
              db,
              actionKey: 'meaning:${args[4]}',
              word: id,
              type: 'meaning',
              grade: args[1] as String,
              at: args[2] as int,
            );
          }
        });
        return null;
      case 'events':
        return db.select('SELECT COUNT(*) AS n FROM review_events').single['n']
            as int;
      default:
        throw StateError('Unknown repository operation.');
    }
  } finally {
    db.close();
  }
}

ImportResult _importFields(Database db, List<Map<String, String>> fields) {
  var inserted = 0, updated = 0, unchanged = 0;
  for (final row in fields) {
    final entry = VocabularyEntry(row);
    final old = db.select(
      'SELECT word_key, content_json FROM vocabulary WHERE entry_id=?',
      [entry.id],
    );
    if (old.isNotEmpty && old.single['word_key'] != entry.wordKey) {
      throw FormatException('稳定 ID ${entry.id} 已对应另一个词头，整批未导入。');
    }
    final collision = db.select(
      'SELECT entry_id FROM vocabulary WHERE word_key=? AND entry_id<>?',
      [entry.wordKey, entry.id],
    );
    if (collision.isNotEmpty) {
      throw FormatException('词头 ${entry.word} 已有不同稳定 ID，整批未导入。');
    }
    final content = jsonEncode(row);
    if (old.isEmpty) {
      db.execute('INSERT INTO vocabulary VALUES(?,?,?,?,?)', [
        entry.id,
        entry.wordKey,
        entry.word,
        entry.libraryClass,
        content,
      ]);
      db.execute('INSERT INTO learning_progress(entry_id) VALUES(?)', [
        entry.id,
      ]);
      inserted++;
    } else if (old.single['content_json'] != content) {
      db.execute(
        'UPDATE vocabulary SET word=?,library_class=?,content_json=? WHERE entry_id=?',
        [entry.word, entry.libraryClass, content, entry.id],
      );
      updated++;
    } else {
      unchanged++;
    }
  }
  return ImportResult(inserted, updated, unchanged);
}

DateTime? _date(Object? value) => value == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);

T _transaction<T>(Database db, T Function() action) {
  final nested = !db.autocommit;
  db.execute(nested ? 'SAVEPOINT learning_unit' : 'BEGIN IMMEDIATE');
  try {
    final result = action();
    db.execute(nested ? 'RELEASE learning_unit' : 'COMMIT');
    return result;
  } catch (_) {
    if (nested) {
      db.execute('ROLLBACK TO learning_unit');
      db.execute('RELEASE learning_unit');
    } else {
      db.execute('ROLLBACK');
    }
    rethrow;
  }
}
