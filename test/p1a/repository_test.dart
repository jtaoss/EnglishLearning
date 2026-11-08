import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/review/review_schedule.dart';

import 'fixtures.dart';

void main() {
  late Directory directory;
  late String path;
  late SqliteLearningRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('english_learning_p1a_');
    path = '${directory.path}${Platform.pathSeparator}learning.sqlite3';
    repository = await SqliteLearningRepository.open(path);
  });
  tearDown(() async {
    await repository.close();
    final root = Directory.systemTemp.resolveSymbolicLinksSync().toLowerCase();
    final resolved = directory.resolveSymbolicLinksSync().toLowerCase();
    if (!resolved.startsWith(
      '$root${Platform.pathSeparator}english_learning_p1a_',
    )) {
      throw StateError(
        'Refusing cleanup outside this test temporary directory.',
      );
    }
    await directory.delete(recursive: true);
  });

  test('100 word import is idempotent and initializes all personal states as untested', () async {
    final csv = File('assets/vocabulary/verified100.csv').readAsStringSync();
    expect((await repository.importCsv(csv)).inserted, 100);
    expect((await repository.importCsv(csv)).unchanged, 100);
    final words = await repository.readWords();
    expect(words.length, 100);
    expect(
      words.every(
        (w) =>
            w.status == 'untested' &&
            w.pronunciationStatus == '未测试' &&
            w.reviewCount == 0 &&
            w.dueAt == null,
      ),
      isTrue,
    );
    expect(await repository.reviewEventCount(), 0);
  });
  test('content updates preserve progress, pronunciation, due time and events on disk reopen', () async {
    await repository.importCsv(encodeEntries([entryFields()]));
    final at = DateTime.utc(2026, 11, 7, 10);
    await repository.recordReview('test-alpha', ReviewGrade.familiar, at);
    final result = await repository.importCsv(
      encodeEntries([entryFields(meaning: '更新后的独立释义')]),
    );
    expect(result.updated, 1);
    await repository.close();
    repository = await SqliteLearningRepository.open(path);
    final word = (await repository.readWords()).single;
    expect(word.entry.meaning, '更新后的独立释义');
    expect(word.status, 'familiar');
    expect(word.reviewCount, 1);
    expect(word.pronunciationStatus, '未测试');
    expect(word.lastReviewedAt, at);
    expect(word.dueAt, at.add(const Duration(days: 1)));
    expect(await repository.reviewEventCount(), 1);
  });
  test(
    'a collision after an earlier insert rolls back the whole batch',
    () async {
      await repository.importCsv(encodeEntries([entryFields()]));
      await expectLater(
        repository.importCsv(
          encodeEntries([
            entryFields(id: 'test-beta', word: 'beta'),
            entryFields(word: 'wrong-word'),
          ]),
        ),
        throwsFormatException,
      );
      expect((await repository.readWords()).map((w) => w.entry.id), [
        'test-alpha',
      ]);
    },
  );
  test('same exact word with a different stable ID is rejected', () async {
    await repository.importCsv(encodeEntries([entryFields()]));
    await expectLater(
      repository.importCsv(
        encodeEntries([entryFields(id: 'wrong-id', word: 'alpha')]),
      ),
      throwsFormatException,
    );
    expect((await repository.readWords()).length, 1);
  });
  test('damaged input cannot alter saved learning records', () async {
    await repository.importCsv(encodeEntries([entryFields()]));
    await repository.recordReview(
      'test-alpha',
      ReviewGrade.mastered,
      DateTime.utc(2026),
    );
    await expectLater(
      repository.importCsv('entry_id,word\n"broken'),
      throwsFormatException,
    );
    expect((await repository.readWords()).single.status, 'mastered');
    expect(await repository.reviewEventCount(), 1);
  });
  test(
    'all grades append events atomically and last review determines due time',
    () async {
      await repository.importCsv(encodeEntries([entryFields()]));
      final at = DateTime.utc(2026, 11, 7, 12);
      for (final grade in ReviewGrade.values) {
        await repository.recordReview('test-alpha', grade, at);
        final word = (await repository.readWords()).single;
        expect(word.status, grade.name);
        expect(word.dueAt, ReviewSchedule.nextDue(grade, at));
      }
      expect(await repository.reviewEventCount(), 3);
      expect((await repository.readWords()).single.reviewCount, 3);
    },
  );
  test('unknown and paused entries do not create learning events', () async {
    await repository.importCsv(encodeEntries([entryFields(library: '暂缓')]));
    for (final id in ['missing', 'test-alpha']) {
      await expectLater(
        repository.recordReview(id, ReviewGrade.mastered, DateTime.now()),
        throwsStateError,
      );
    }
    expect(await repository.reviewEventCount(), 0);
    expect((await repository.readWords()).single.status, 'untested');
  });
  test('newer schema is refused without rebuilding or deleting data', () async {
    await repository.importCsv(encodeEntries([entryFields()]));
    await repository.close();
    final raw = sqlite3.open(path);
    raw.execute('PRAGMA user_version=99');
    raw.close();
    await expectLater(SqliteLearningRepository.open(path), throwsStateError);
    final preserved = sqlite3.open(path);
    expect(
      preserved.select('SELECT COUNT(*) AS n FROM vocabulary').single['n'],
      1,
    );
    expect(preserved.select('PRAGMA user_version').single.values.single, 99);
    preserved.close();
  });
}
