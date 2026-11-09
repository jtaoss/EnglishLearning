import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import '../p1c/support.dart';

String pack() => File('assets/vocabulary/reviewed500.csv').readAsStringSync();
String csvFor(Iterable<VocabularyEntry> entries) {
  final columns = [...VocabularyCsv.columns, ...VocabularyCsv.optionalColumns];
  return Csv().encode([
    columns,
    for (final e in entries) [for (final c in columns) e.fields[c] ?? ''],
  ]);
}

Map<String, dynamic> pageFor(VocabularyEntry entry, int index) => {
  'object': 'page',
  'id': '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  'parent': {'data_source_id': notionPilotSource},
  'last_edited_time': '2026-11-09T00:00:00Z',
  'properties': {
    for (final field in {
      ...NotionFields.mapping,
      ...NotionFields.extensions,
    }.entries)
      field.value: NotionFields.type(field.key) == 'select'
          ? {
              'type': 'select',
              'select': {'name': entry.fields[field.key] ?? ''},
            }
          : {
              'type': NotionFields.type(field.key),
              NotionFields.type(field.key): [
                {'plain_text': entry.fields[field.key] ?? ''},
              ],
            },
  },
};

void main() {
  final entries = VocabularyCsv.parse(pack());
  final at = DateTime.utc(2026, 11, 9, 1);
  late Directory directory;
  late SqliteLearningRepository repo;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('english_p3_');
    repo = await SqliteLearningRepository.open(
      '${directory.path}/learning.sqlite3',
    );
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });

  test('500 reviewed identities retain old IDs, all are learnable and missing audio is explicit', () {
    final old = VocabularyCsv.parse(
      File('assets/vocabulary/verified100.csv').readAsStringSync(),
    );
    expect(entries.length, 500);
    expect(entries.take(100).map((e) => e.id), old.map((e) => e.id));
    expect(entries.every((e) => e.libraryClass != '暂缓'), isTrue);
    expect(entries.every((e) => e.fields['pets2025_status'] == '待核实'), isTrue);
    expect(
      entries.every(
        (e) => [
          'example_en',
          'example_zh',
          'syllables',
          'stress',
          'phonics_note',
          'reading_review_status',
          'learning_priority',
        ].every((k) => e.fields[k]!.isNotEmpty),
      ),
      isTrue,
    );
    expect(entries.where((e) => e.fields['audio_source']!.isEmpty).length, 494);
    expect(
      entries.where((e) => e.fields['audio_source']!.isNotEmpty).length,
      6,
    );
    expect(
      entries.map((e) => e.word).toSet().containsAll([
        'May',
        'may',
        'March',
        'march',
        'résumé',
        'resume',
      ]),
      isTrue,
    );
  });

  test('100 -> 200 -> 500 expansion preserves all personal fields and survives disk restart', () async {
    await repo.importCsv(
      File('assets/vocabulary/verified100.csv').readAsStringSync(),
    );
    final first = entries.first;
    await repo.recordReview(first.id, ReviewGrade.mastered, at);
    await repo.recordPronunciation(
      entryId: first.id,
      grade: PronunciationGrade.needsPractice,
      audioAssetId: 'self-reading:${first.id}',
      attemptId: 'p3-attempt',
      at: at,
    );
    final before = (await repo.readWords()).singleWhere(
      (w) => w.entry.id == first.id,
    );
    expect((await repo.importCsv(csvFor(entries.take(200)))).inserted, 100);
    expect((await repo.importCsv(pack())).inserted, 300);
    expect((await repo.importCsv(pack())).unchanged, 500);
    await repo.close();
    repo = await SqliteLearningRepository.open(
      '${directory.path}/learning.sqlite3',
    );
    final words = await repo.readWords();
    expect(words.length, 500);
    final after = words.singleWhere((w) => w.entry.id == first.id);
    expect(after.status, before.status);
    expect(after.reviewCount, before.reviewCount);
    expect(after.lastReviewedAt, before.lastReviewedAt);
    expect(after.dueAt, before.dueAt);
    expect(
      after.pronunciationProgress!.grade,
      PronunciationGrade.needsPractice,
    );
    expect(
      after.pronunciationProgress!.dueAt,
      at.add(const Duration(minutes: 10)),
    );
    expect(await repo.reviewEventCount(), 1);
    final db = sqlite3.open(repo.path);
    expect(db.select('PRAGMA user_version').single.values.single, 3);
    expect(
      db.select('SELECT COUNT(*) AS n FROM pronunciation_events').single['n'],
      1,
    );
    db.close();
  });

  test(
    'every one of 500 selected words can record a meaning review offline',
    () async {
      await repo.importCsv(pack());
      for (final entry in entries) {
        await repo.recordReview(entry.id, ReviewGrade.familiar, at);
      }
      final words = await repo.readWords();
      expect(
        words.every(
          (w) =>
              w.reviewCount == 1 &&
              w.status == 'familiar' &&
              w.dueAt == at.add(const Duration(days: 1)),
        ),
        isTrue,
      );
      expect(await repo.reviewEventCount(), 500);
    },
  );

  test('independent pronunciation due enters the review queue and duplicate attempt does not create another event', () async {
    await repo.importCsv(pack());
    final first = entries.first;
    await repo.recordReview(first.id, ReviewGrade.mastered, at);
    for (var i = 0; i < 2; i++) {
      await repo.recordPronunciation(
        entryId: first.id,
        grade: PronunciationGrade.needsPractice,
        audioAssetId: 'self-reading:${first.id}',
        attemptId: 'same-attempt',
        at: at,
      );
    }
    final controller = VocabularyController(
      repo,
      AppLogger(),
      clock: () => at.add(const Duration(minutes: 11)),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.find(first.id)!.isDue(controller.nowUtc), isFalse);
    expect(
      controller.dueWords(controller.nowUtc).any((w) => w.entry.id == first.id),
      isTrue,
    );
    expect(controller.find(first.id)!.status, 'mastered');
    final db = sqlite3.open(repo.path);
    expect(
      db.select('SELECT COUNT(*) AS n FROM pronunciation_events').single['n'],
      1,
    );
    db.close();
  });

  for (final failLast in [false, true]) {
    test(
      '500-word grouped paginated Notion sync ${failLast ? 'rolls back the entire incomplete expansion' : 'preserves state and repeated sync is idempotent'}',
      () async {
        await repo.importCsv(csvFor(entries.take(100)));
        await repo.recordReview(entries.first.id, ReviewGrade.mastered, at);
        final schema = Map<String, dynamic>.from(snapshot()['schema'] as Map);
        schema['properties'] = {
          for (final f in {
            ...NotionFields.mapping,
            ...NotionFields.extensions,
          }.entries)
            f.value: {'type': NotionFields.type(f.key)},
        };
        var queries = 0;
        final client = MockClient((request) async {
          if (request.method == 'GET') return jsonResponse(schema);
          queries++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final filter = body['filter'] as Map;
          final conditions =
              (filter['or'] ?? (filter['and'] as List).first['or']) as List;
          expect(conditions.length, lessThanOrEqualTo(100));
          final ids = conditions
              .map((dynamic c) => (c as Map)['rich_text']['equals'])
              .toSet();
          var group = entries.where((e) => ids.contains(e.id)).toList();
          if (failLast && ids.contains(entries.last.id)) {
            group = group.take(99).toList();
          }
          final second = body['start_cursor'] != null;
          final part = second ? group.skip(60) : group.take(60);
          return jsonResponse(
            listResponse([
              for (final e in part) pageFor(e, entries.indexOf(e) + 1),
            ], next: !second && group.length > 60 ? 'next' : null),
          );
        });
        final service = NotionSyncService(
          store: repo,
          credentials: MemoryCredentials(testAccount()),
          api: NotionReadApi(client, delay: noDelay),
          loadScope: () async => NotionScope(pack()),
          clock: () => at,
        );
        if (failLast) {
          await expectLater(service.sync(), throwsA(isA<NotionFailure>()));
          expect((await repo.readWords()).length, 100);
          expect(
            (await repo.readNotionState(notionPilotSource)).watermark,
            isNull,
          );
        } else {
          expect((await service.sync()).inserted, 400);
          expect((await service.sync()).unchanged, 500);
          expect(queries, 20);
          final words = await repo.readWords();
          expect(words.length, 500);
          final expected = {
            for (final entry in entries) entry.id: entry.fields,
          };
          for (final word in words) {
            expect(word.entry.fields, expected[word.entry.id]);
          }
          expect(
            words.singleWhere((w) => w.entry.id == entries.first.id).status,
            'mastered',
          );
          expect(
            (await repo.readNotionState(notionPilotSource)).linkedWords,
            500,
          );
        }
        expect(await repo.reviewEventCount(), 1);
        client.close();
      },
    );
  }
}
