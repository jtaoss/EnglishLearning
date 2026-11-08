import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/core/storage/copy_learning_journal.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';

import 'support.dart';

void main() {
  late Directory dir;
  late String original, copy;
  SqliteLearningRepository? repo;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('p2b1_migration_');
    original = '${dir.path}/original.sqlite3';
    copy = '${dir.path}/copy.sqlite3';
    final old = await SqliteLearningRepository.open(original);
    await old.importCsv(
      File('assets/vocabulary/verified100.csv').readAsStringSync(),
    );
    final id = (await old.readWords()).first.entry.id;
    await old.recordReview(id, ReviewGrade.familiar, DateTime.utc(2026, 11, 8));
    await old.recordPronunciation(
      entryId: id,
      grade: PronunciationGrade.confident,
      audioAssetId: 'fixture',
      attemptId: 'old-attempt',
      at: DateTime.utc(2026, 11, 8),
    );
    await old.close();
    File(original).copySync(copy);
    writePermit(copy, original);
  });
  tearDown(() async {
    await repo?.close();
    repo = null;
    final resolved = dir.resolveSymbolicLinksSync().toLowerCase();
    if (!resolved.startsWith(
      '${Directory.systemTemp.resolveSymbolicLinksSync().toLowerCase()}${Platform.pathSeparator}p2b1_migration_',
    )) {
      throw StateError('Unsafe test cleanup');
    }
    await dir.delete(recursive: true);
  });
  test('100 words, IDs, grades, due dates and old events survive repeat migration byte-for-byte as rows', () async {
    final before = snapshotTables(copy);
    repo = await reopenCopy(copy);
    expect(snapshotTables(copy), before);
    expect((await repo!.readWords()).length, 100);
    expect(await repo!.readJournal(), isEmpty);
    final db = sqlite3.open(copy);
    expect(
      db.select('SELECT COUNT(*) n FROM migration_state_snapshots').single['n'],
      100,
    );
    expect(db.select('SELECT COUNT(*) n FROM journal_outbox').single['n'], 0);
    db.close();
    final all = snapshotTables(copy, all: true);
    await repo!.close();
    repo = await reopenCopy(copy);
    expect(snapshotTables(copy, all: true), all);
    expect(snapshotTables(original), before);
  });
  test('missing old event timestamps/counts are state snapshots, never invented upload events', () async {
    final db = sqlite3.open(copy);
    db.execute('DELETE FROM review_events');
    db.execute(
      'UPDATE learning_progress SET review_count=8,last_reviewed_utc=NULL',
    );
    db.close();
    repo = await reopenCopy(copy);
    expect(await repo!.readJournal(), isEmpty);
    final after = sqlite3.open(copy);
    expect(after.select('SELECT COUNT(*) n FROM review_events').single['n'], 0);
    final state = jsonDecode(
      after
              .select(
                'SELECT state_json FROM migration_state_snapshots LIMIT 1',
              )
              .single['state_json']
          as String,
    ) as Map;
    expect((state['meaning_state'] as Map)['review_count'], 8);
    expect(state['inferred_event_time'], isNull);
    after.close();
  });
  for (final version in [1, 2, 3]) {
    test(
      'v$version failure rolls back schema, PRAGMA version, all rows; then retry succeeds',
      () async {
        final db = sqlite3.open(copy);
        if (version < 3) {
          db.execute('DROP TABLE notion_word_links');
          db.execute('DROP TABLE notion_sync_state');
        }
        if (version < 2) {
          db.execute('DROP TABLE pronunciation_events');
          db.execute('DROP TABLE pronunciation_progress');
        }
        db.execute('PRAGMA user_version=$version');
        db.close();
        final before = snapshotTables(copy, all: true);
        await expectLater(
          SqliteLearningRepository.openIsolatedCopy(
            copy,
            failMigrationAfterSchema: true,
          ),
          throwsStateError,
        );
        expect(snapshotTables(copy, all: true), before);
        final checked = sqlite3.open(copy);
        expect(
          checked.select('PRAGMA user_version').single.values.single,
          version,
        );
        checked.close();
        repo = await reopenCopy(copy);
        expect((await repo!.readWords()).length, 100);
        expect(await repo!.readJournal(), isEmpty);
      },
    );
  }
  test('missing marker and a forged marker pointing at the protected file are rejected', () async {
    File('$copy.copy-permit.json').deleteSync();
    final before = File(original).readAsBytesSync();
    await expectLater(reopenCopy(copy), throwsStateError);
    writePermit(original, original);
    await expectLater(reopenCopy(original), throwsStateError);
    expect(File(original).readAsBytesSync(), before);
  });
  test('normal repository cannot open migrated copy or import simulation events into personal tables', () async {
    repo = await reopenCopy(copy);
    await expectLater(SqliteLearningRepository.open(copy), throwsStateError);
    final actual = await SqliteLearningRepository.open(original);
    final before = snapshotTables(original);
    await expectLater(
      actual.receiveJournalEvents([
        {'event_id': 'sim-old', 'origin': 'simulation_test'},
      ]),
      throwsStateError,
    );
    expect(snapshotTables(original), before);
    await actual.close();
    expect(personalEventUploadEnabled, false);
  });
  test('outbox INSERT failure rolls back meaning rating, legacy event, journal and device sequence', () async {
    repo = await reopenCopy(copy);
    final before = snapshotTables(copy, all: true);
    final db = sqlite3.open(copy);
    db.execute(
      "CREATE TRIGGER reject_outbox BEFORE INSERT ON journal_outbox BEGIN SELECT RAISE(ABORT,'controlled queue failure'); END",
    );
    db.close();
    final id = (await repo!.readWords()).first.entry.id;
    await expectLater(
      repo!.recordReview(id, ReviewGrade.mastered, DateTime.utc(2026, 11, 9)),
      throwsA(isA<SqliteException>()),
    );
    expect(snapshotTables(copy, all: true), before);
  });
  test('outbox INSERT failure rolls back pronunciation only, preserving meaning state', () async {
    repo = await reopenCopy(copy);
    final before = snapshotTables(copy, all: true);
    final db = sqlite3.open(copy);
    db.execute(
      "CREATE TRIGGER reject_outbox BEFORE INSERT ON journal_outbox BEGIN SELECT RAISE(ABORT,'controlled queue failure'); END",
    );
    db.close();
    final id = (await repo!.readWords()).first.entry.id;
    await expectLater(
      repo!.recordPronunciation(
        entryId: id,
        grade: PronunciationGrade.needsPractice,
        audioAssetId: 'fixture',
        attemptId: 'new',
        at: DateTime.utc(2026, 11, 9),
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(snapshotTables(copy, all: true), before);
  });
  test('new actions commit state + event + queue together, duplicate action is idempotent and IDs persist', () async {
    repo = await reopenCopy(copy);
    final id = (await repo!.readWords()).first.entry.id;
    final at = DateTime.utc(2026, 11, 9);
    await repo!.recordReview(
      id,
      ReviewGrade.mastered,
      at,
      operationId: 'one-action',
    );
    await repo!.recordReview(
      id,
      ReviewGrade.mastered,
      at,
      operationId: 'one-action',
    );
    final meaning = (await repo!.readWords()).first;
    await repo!.recordPronunciation(
      entryId: id,
      grade: PronunciationGrade.needsPractice,
      audioAssetId: 'fixture',
      attemptId: 'new-action',
      at: at,
    );
    expect((await repo!.readWords()).first.status, meaning.status);
    expect((await repo!.readWords()).first.dueAt, meaning.dueAt);
    final events = await repo!.readJournal();
    expect(events.length, 2);
    expect(events.map((r) => eventPayload(r)['learning_type']), [
      'meaning',
      'pronunciation',
    ]);
    expect(
      events.every((r) => eventPayload(r)['origin'] == 'simulation_test'),
      true,
    );
    final all = snapshotTables(copy, all: true);
    await repo!.close();
    repo = await reopenCopy(copy);
    expect(snapshotTables(copy, all: true), all);
    await expectLater(
      repo!.recordReview(
        id,
        ReviewGrade.forgotten,
        at,
        operationId: 'one-action',
      ),
      throwsStateError,
    );
    expect(snapshotTables(copy, all: true), all);
  });
}
