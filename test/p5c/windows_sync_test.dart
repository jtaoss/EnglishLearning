import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_controller.dart';
import 'package:english_learning/integrations/notion/notion_sync_page.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import '../p1c/support.dart';

const blankPage = '414cd5b5-d6b9-80db-ac03-d94e99d65e61';

void main() {
  test('older 100, 200, and 500 sample sizes still sync', () {
    final reviewed = NotionScope(
      File('assets/vocabulary/reviewed500.csv').readAsStringSync(),
    );
    expect(reviewed.take(100).entries, hasLength(100));
    expect(reviewed.take(200).entries, hasLength(200));
    expect(reviewed.take(500).entries, hasLength(500));
    expect(
      () => reviewed.take(VocabularyCsv.maxEntries),
      throwsA(isA<NotionFailure>()),
    );
    final verified = NotionScope(
      File('assets/vocabulary/verified100.csv').readAsStringSync(),
    );
    expect(verified.take(100).entries, hasLength(100));
    expect(() => verified.take(500), throwsA(isA<NotionFailure>()));
  });

  testWidgets('Windows sync scope offers the formal 5332 library', (
    tester,
  ) async {
    final controller = NotionSyncController(
      NotionSyncService(
        store: _IdleStore(),
        credentials: MemoryCredentials(),
        api: NotionReadApi(
          MockClient((_) async => throw StateError('No HTTP expected')),
          delay: noDelay,
        ),
        loadScope: () async {
          final formal = File('docs/p5a/public/formal_learning_vocabulary.csv')
              .readAsStringSync();
          final reviewed = File('assets/vocabulary/reviewed500.csv')
              .readAsStringSync();
          final verified = File('assets/vocabulary/verified100.csv')
              .readAsStringSync();
          final scope = NotionScope.withHistoricalPrefix(formal, reviewed);
          expect(
            scope.take(100).entries.map((entry) => entry.id),
            VocabularyCsv.parse(verified).map((entry) => entry.id),
          );
          expect(
            scope.take(500).entries.map((entry) => entry.id),
            VocabularyCsv.parse(reviewed).map((entry) => entry.id),
          );
          expect(scope.take(5332).entries, hasLength(5332));
          return scope;
        },
      ),
      refreshVocabulary: () async => true,
    );
    addTearDown(controller.dispose);
    await controller.restore();
    expect(controller.scopeLength, VocabularyCsv.maxEntries);
    expect(controller.targetSize, VocabularyCsv.maxEntries);
    expect(controller.selectableSizes, [100, 200, 500, 5332]);
    controller.selectSize(500);
    expect(controller.targetSize, 500);
    controller.selectSize(5332);
    expect(controller.targetSize, 5332);
    await tester.pumpWidget(
      MaterialApp(home: NotionSyncPage(controller: controller)),
    );
    expect(find.text('5332 词'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notion-target-size')));
    await tester.pumpAndSettle();
    expect(find.text('100 词'), findsWidgets);
    expect(find.text('200 词'), findsWidgets);
    expect(find.text('500 词'), findsWidgets);
  });

  final payloadPath = Platform.environment['P5C5_PAYLOAD'];
  final isolatedPath = Platform.environment['P5C5_ISOLATED'];
  final personalPath = Platform.environment['P5C5_PERSONAL_PATH'];
  if (payloadPath == null || isolatedPath == null || personalPath == null) {
    return;
  }

  test(
    'verified Notion payload syncs without inventing or erasing learning state',
    () async {
      final payload = jsonDecode(
        File(payloadPath).readAsStringSync(),
      ) as Map<String, dynamic>;
      final formal = VocabularyCsv.parse(
        File('docs/p5a/public/formal_learning_vocabulary.csv')
            .readAsStringSync(),
      );
      final reviewed = VocabularyCsv.parse(
        File('assets/vocabulary/reviewed500.csv').readAsStringSync(),
      );
      final byId = {for (final entry in formal) entry.id: entry};
      final reviewedIds = reviewed.map((entry) => entry.id).toSet();
      final rawWords = (payload['words'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(rawWords, hasLength(formal.length));
      expect(payload['source_id'], notionPilotSource);
      final pageIds = <String>{};
      for (final item in rawWords) {
        final fields = Map<String, String>.from(
          item['fields'] as Map<String, dynamic>,
        );
        final entry = byId[fields['entry_id']];
        expect(entry, isNotNull, reason: fields['entry_id']);
        expect(entry!.fields, fields);
        final pageId = item['page_id'] as String;
        expect(pageId, isNot(blankPage));
        expect(pageIds.add(pageId), isTrue);
      }
      final words = [
        for (final item in rawWords)
          NotionWord(
            entry: byId[(item['fields'] as Map<String, dynamic>)['entry_id']]!,
            pageId: item['page_id'] as String,
            editedAt: DateTime.parse(item['edited'] as String).toUtc(),
          ),
      ];
      final watermark = words
          .map((word) => word.editedAt)
          .reduce((left, right) => left.isAfter(right) ? left : right);

      final isolatedFile = File(isolatedPath);
      if (isolatedFile.existsSync()) await isolatedFile.delete();
      for (final suffix in ['-wal', '-shm']) {
        final sidecar = File('$isolatedPath$suffix');
        if (sidecar.existsSync()) await sidecar.delete();
      }
      final at = DateTime.utc(2026, 11, 11, 12);
      var isolated = await SqliteLearningRepository.open(isolatedPath);
      final first = await _apply(isolated, words, null, watermark);
      expect(first.inserted, 5332);
      expect(first.updated, 0);
      expect(first.unchanged, 0);
      final original = reviewed.take(3).toList();
      await isolated.recordReview(original[0].id, ReviewGrade.mastered, at);
      await isolated.recordReview(original[1].id, ReviewGrade.familiar, at);
      await isolated.recordReview(original[2].id, ReviewGrade.forgotten, at);
      await isolated.recordPronunciation(
        entryId: original[0].id,
        grade: PronunciationGrade.confident,
        audioAssetId: 'p5c5-isolated-check',
        attemptId: 'p5c5-isolated-attempt',
        at: at,
      );
      final extra = formal.firstWhere(
        (entry) => !reviewedIds.contains(entry.id),
      );
      await isolated.recordReview(extra.id, ReviewGrade.familiar, at);
      final repeated = await _apply(
        isolated,
        words,
        (await isolated.readNotionState(notionPilotSource)).watermark,
        watermark,
      );
      expect(repeated.inserted, 0);
      expect(repeated.updated, 0);
      expect(repeated.unchanged, 5332);
      await isolated.close();
      isolated = await SqliteLearningRepository.open(isolatedPath);
      final restored = await _snapshot(isolated);
      await isolated.close();
      final restoredStatus = Map<String, String>.from(
        restored['statuses'] as Map<Object?, Object?>,
      );
      final restoredReading = Map<String, String?>.from(
        restored['pronunciation'] as Map<Object?, Object?>,
      );
      expect(restored['rows'], 5332);
      expect(restored['main'], 4259);
      expect(restored['extended'], 1073);
      expect(restored['deferred'], 0);
      expect(restored['events'], 4);
      expect(restoredStatus[original[0].id], 'mastered');
      expect(restoredStatus[original[1].id], 'familiar');
      expect(restoredStatus[original[2].id], 'forgotten');
      expect(restoredStatus[extra.id], 'familiar');
      expect(restoredReading[original[0].id], 'confident');
      expect(
        restored['untested'],
        5332 - 4,
        reason: 'new words stay untested and unrated words stay unrated',
      );
      final found = Map<String, String>.from(
        (restored['words'] as Map<Object?, Object?>)[extra.id]
            as Map<Object?, Object?>,
      );
      expect(found['word'], extra.word);
      expect(found['meaning'], extra.meaning);
      _expectHealthy(isolatedPath, linked: 5332);

      final personalFile = File(personalPath);
      expect(
        personalFile.existsSync(),
        isFalse,
        reason: '正式个人库在同步前不存在，拒绝覆盖未知文件',
      );
      await personalFile.parent.create(recursive: true);
      var personal = await SqliteLearningRepository.open(personalPath);
      final created = await _apply(personal, words, null, watermark);
      expect(created.inserted, 5332);
      expect(created.updated, 0);
      final again = await _apply(
        personal,
        words,
        (await personal.readNotionState(notionPilotSource)).watermark,
        watermark,
      );
      expect(again.inserted, 0);
      expect(again.updated, 0);
      expect(again.unchanged, 5332);
      await personal.close();
      personal = await SqliteLearningRepository.open(personalPath);
      final cold = await _snapshot(personal);
      await personal.close();
      final coldStatus = Map<String, String>.from(
        cold['statuses'] as Map<Object?, Object?>,
      );
      final coldDue = Map<String, DateTime?>.from(
        cold['due'] as Map<Object?, Object?>,
      );
      expect(cold['rows'], 5332);
      expect(cold['main'], 4259);
      expect(cold['extended'], 1073);
      expect(cold['events'], 0);
      expect(cold['untested'], 5332);
      expect(cold['pronunciation_rows'], 0);
      for (final id in reviewedIds) {
        expect(coldStatus[id], 'untested');
        expect(coldDue[id], isNull);
      }
      _expectHealthy(personalPath, linked: 5332);
      File('private/p5c/p5c5-apply-result.json').writeAsStringSync(
        jsonEncode({
          'isolated_first': {
            'inserted': first.inserted,
            'updated': first.updated,
            'unchanged': first.unchanged,
          },
          'isolated_repeat': {
            'inserted': repeated.inserted,
            'updated': repeated.updated,
            'unchanged': repeated.unchanged,
          },
          'isolated_events_after_restart': restored['events'],
          'personal_first': {
            'inserted': created.inserted,
            'updated': created.updated,
            'unchanged': created.unchanged,
          },
          'personal_repeat': {
            'inserted': again.inserted,
            'updated': again.updated,
            'unchanged': again.unchanged,
          },
          'personal_rows_after_restart': cold['rows'],
          'personal_untested_after_restart': cold['untested'],
          'personal_events_after_restart': cold['events'],
          'learned_extra_word': extra.word,
          'formal_prefix_500_is_reviewed500':
              formal
                  .take(500)
                  .map((entry) => entry.id)
                  .toSet()
                  .containsAll(reviewedIds) &&
              formal.take(500).length == reviewedIds.length,
          'protected_original_ids': original.map((entry) => entry.id).toList(),
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<ImportResult> _apply(
  SqliteLearningRepository repository,
  List<NotionWord> words,
  DateTime? expected,
  DateTime watermark,
) => repository.applyNotionBatch(
  sourceId: notionPilotSource,
  words: words,
  expectedWatermark: expected,
  watermark: watermark,
  syncedAt: DateTime.utc(2026, 11, 11, 14, 55),
);

Future<Map<String, Object?>> _snapshot(
  SqliteLearningRepository repository,
) async {
  final words = await repository.readWords();
  return {
    'rows': words.length,
    'main': words.where((word) => word.entry.libraryClass == '主学习').length,
    'extended': words.where((word) => word.entry.libraryClass == '扩展').length,
    'deferred': words.where((word) => word.entry.libraryClass == '暂缓').length,
    'events': await repository.reviewEventCount(),
    'untested': words.where((word) => word.status == 'untested').length,
    'pronunciation_rows': words
        .where((word) => word.pronunciationProgress != null)
        .length,
    'statuses': {for (final word in words) word.entry.id: word.status},
    'due': {for (final word in words) word.entry.id: word.dueAt},
    'pronunciation': {
      for (final word in words)
        word.entry.id: word.pronunciationProgress?.grade?.name,
    },
    'words': {
      for (final word in words)
        word.entry.id: {'word': word.entry.word, 'meaning': word.entry.meaning},
    },
  };
}

void _expectHealthy(String path, {required int linked}) {
  final db = sqlite3.open(path);
  try {
    expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    expect(db.select('PRAGMA user_version').single.values.single, 3);
    expect(
      db.select('SELECT COUNT(*) AS n FROM notion_word_links').single['n'],
      linked,
    );
    expect(
      db.select('SELECT COUNT(*) AS n FROM notion_word_links WHERE page_id=?', [
        blankPage,
      ]).single['n'],
      0,
    );
    expect(
      db.select('SELECT COUNT(*) AS n FROM review_events').single['n'],
      isA<int>(),
    );
  } finally {
    db.close();
  }
}

final class _IdleStore implements NotionSyncStore {
  @override
  Future<ImportResult> applyNotionBatch({
    required String sourceId,
    required List<NotionWord> words,
    required DateTime? expectedWatermark,
    required DateTime? watermark,
    required DateTime syncedAt,
  }) async => const ImportResult(0, 0, 0);

  @override
  Future<NotionSyncState> readNotionState(String sourceId) async =>
      const NotionSyncState();
}
