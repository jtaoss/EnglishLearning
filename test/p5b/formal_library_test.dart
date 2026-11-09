import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/features/vocabulary/vocabulary_page.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import '../p1a/learning_flow_test.dart' show MemoryLearningRepository;
import '../p1c/support.dart';

const formalPath = 'docs/p5a/public/formal_learning_vocabulary.csv';

String formalCsv() => File(formalPath).readAsStringSync();

List<List<String>> decodeCsv(String path) {
  final text = File(path).readAsStringSync();
  final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  return Csv(fieldDelimiter: ',', dynamicTyping: false)
      .decode(body)
      .map((row) => row.map((value) => value as String).toList())
      .where((row) => !(row.length == 1 && row.single.trim().isEmpty))
      .toList();
}

Set<String> idsIn(String path) {
  final rows = decodeCsv(path);
  final id = rows.first.indexOf('entry_id');
  return rows.skip(1).map((row) => row[id].trim()).toSet();
}

String csvFor(Iterable<VocabularyEntry> entries) {
  final columns = [...VocabularyCsv.columns, ...VocabularyCsv.optionalColumns];
  return Csv().encode([
    columns,
    for (final entry in entries)
      [for (final column in columns) entry.fields[column] ?? ''],
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

VocabularyController formalController() {
  final repository = MemoryLearningRepository(empty: true);
  repository.words = [
    for (final entry in VocabularyCsv.parse(formalCsv()))
      StudyWord(
        entry: entry,
        status: 'untested',
        pronunciationStatus: '未测试',
        reviewCount: 0,
      ),
  ];
  return VocabularyController(
    repository,
    AppLogger(),
    clock: () => DateTime.utc(2026, 11, 9, 1),
  );
}

void main() {
  final entries = VocabularyCsv.parse(formalCsv());
  final reviewed = VocabularyCsv.parse(
    File('assets/vocabulary/reviewed500.csv').readAsStringSync(),
  );
  final at = DateTime.utc(2026, 11, 9, 1);

  test(
    'formal library keeps stable IDs and excludes pending or deferred heads',
    () {
      final selected = idsIn('docs/p5a/public/selected_vocabulary.csv');
      final pending = idsIn('docs/p5a/public/manual_review.csv');
      final deferred = idsIn('docs/p5a/public/deferred_vocabulary.csv');
      final formalIds = entries.map((entry) => entry.id).toSet();
      expect(
        File(formalPath).lengthSync(),
        lessThanOrEqualTo(VocabularyCsv.maxBytes),
      );
      expect(File(formalPath).lengthSync(), greaterThan(1024 * 1024));
      expect(entries.length, VocabularyCsv.maxEntries);
      expect(formalIds.length, entries.length);
      expect(
        entries.map((entry) => entry.wordKey).toSet().length,
        entries.length,
      );
      expect(selected.length, 5331);
      expect(formalIds.containsAll(selected), isTrue);
      expect(formalIds.difference(selected).length, 1);
      expect(formalIds.containsAll(reviewed.map((entry) => entry.id)), isTrue);
      expect(reviewed.length, 500);
      final reviewedById = {for (final entry in reviewed) entry.id: entry};
      for (final entry in entries.where(
        (entry) => reviewedById.containsKey(entry.id),
      )) {
        expect(entry.fields, reviewedById[entry.id]!.fields);
      }
      expect(formalIds.intersection(pending), isEmpty);
      expect(formalIds.intersection(deferred), isEmpty);
      expect(pending.length, 194);
      expect(deferred.length, 27);
      expect(
        entries.where((entry) => entry.libraryClass == '主学习').length,
        4259,
      );
      expect(entries.where((entry) => entry.libraryClass == '扩展').length, 1073);
      expect(entries.where((entry) => entry.libraryClass == '暂缓'), isEmpty);
      expect(
        entries.every((entry) => entry.fields['book_verification'] == '已核验'),
        isTrue,
      );
      expect(
        entries.every((entry) => entry.fields['pets2025_status'] == '待核实'),
        isTrue,
      );
      expect(
        entries.map((entry) => entry.word).toSet().containsAll([
          'May',
          'may',
          'March',
          'march',
        ]),
        isTrue,
      );
      expect(
        () => VocabularyCsv.parse(
          File('docs/p5a/public/manual_review.csv').readAsStringSync(),
        ),
        throwsFormatException,
      );
      expect(
        () => VocabularyCsv.parse(
          File('docs/p5a/public/deferred_vocabulary.csv').readAsStringSync(),
        ),
        throwsFormatException,
      );
      expect(
        File('lib/main.dart')
            .readAsStringSync()
            .contains('assets/vocabulary/reviewed500.csv'),
        isTrue,
      );
    },
  );

  test('isolated formal import preserves ratings across restart and content upsert', () async {
    final directory = await Directory.systemTemp.createTemp('english_p5b_');
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final path = '${directory.path}/learning.sqlite3';
    var repo = await SqliteLearningRepository.open(path);
    addTearDown(repo.close);
    expect((await repo.importCsv(formalCsv())).inserted, entries.length);
    final samples = [
      entries.firstWhere((entry) => entry.libraryClass == '主学习'),
      entries.firstWhere((entry) => entry.libraryClass == '扩展'),
      entries.firstWhere((entry) => entry.word == 'may'),
    ];
    await repo.recordReview(samples[0].id, ReviewGrade.mastered, at);
    await repo.recordReview(samples[1].id, ReviewGrade.familiar, at);
    await repo.recordReview(samples[2].id, ReviewGrade.forgotten, at);
    expect((await repo.importCsv(formalCsv())).unchanged, entries.length);
    final changed = VocabularyEntry({
      ...samples[0].fields,
      'meaning_zh': '${samples[0].meaning}（隔离核对）',
    });
    final replacement = [
      for (final entry in entries) entry.id == changed.id ? changed : entry,
    ];
    expect((await repo.importCsv(csvFor(replacement))).updated, 1);
    await repo.close();
    repo = await SqliteLearningRepository.open(path);
    final words = await repo.readWords();
    expect(words.length, entries.length);
    final byId = {for (final word in words) word.entry.id: word};
    expect(byId[samples[0].id]!.status, 'mastered');
    expect(byId[samples[0].id]!.dueAt, at.add(const Duration(days: 7)));
    expect(byId[samples[0].id]!.reviewCount, 1);
    expect(byId[samples[0].id]!.entry.meaning, changed.meaning);
    expect(byId[samples[1].id]!.status, 'familiar');
    expect(byId[samples[1].id]!.dueAt, at.add(const Duration(days: 1)));
    expect(byId[samples[2].id]!.status, 'forgotten');
    expect(byId[samples[2].id]!.dueAt, at.add(const Duration(minutes: 10)));
    expect(
      words.where((word) => word.reviewCount == 0).length,
      entries.length - 3,
    );
    expect(await repo.reviewEventCount(), 3);
    final db = sqlite3.open(path);
    try {
      expect(db.select('PRAGMA integrity_check').single.values.single, 'ok');
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      expect(db.select('PRAGMA user_version').single.values.single, 3);
      final counts = db
          .select(
            'SELECT COUNT(*) AS rows, COUNT(DISTINCT entry_id) AS ids, COUNT(DISTINCT word_key) AS keys FROM vocabulary',
          )
          .single;
      expect(counts['rows'], entries.length);
      expect(counts['ids'], entries.length);
      expect(counts['keys'], entries.length);
      expect(
        db.select('SELECT COUNT(*) AS n FROM learning_progress').single['n'],
        entries.length,
      );
      final content = jsonDecode(
        db
                .select('SELECT content_json FROM vocabulary LIMIT 1')
                .single['content_json']
            as String,
      ) as Map<String, dynamic>;
      expect(content.keys, isNot(contains('status')));
      expect(content.keys, isNot(contains('due_utc')));
      expect(content.keys, isNot(contains('review_count')));
    } finally {
      db.close();
    }
  });

  testWidgets(
    'formal library can be searched and filtered without showing meanings',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = formalController();
      await controller.refresh();
      final target = entries.singleWhere(
        (entry) => entry.word == 'straightforward',
      );
      await tester.pumpWidget(
        MaterialApp(home: VocabularyPage(controller: controller)),
      );
      // The vocabulary clock ticks every minute. pumpAndSettle would follow
      // that timer forever, so frames are advanced by a bounded duration.
      await tester.pump();
      expect(find.text('共 ${entries.length} 词 · 当前 4259 词'), findsOneWidget);
      expect(find.text(target.meaning), findsNothing);
      await tester.enterText(
        find.byKey(const Key('vocabulary-search')),
        target.word,
      );
      await tester.pump();
      expect(find.text('共 ${entries.length} 词 · 当前 1 词'), findsOneWidget);
      expect(find.text(target.word), findsWidgets);
      expect(find.text(target.meaning), findsNothing);
      await tester.enterText(find.byKey(const Key('vocabulary-search')), '');
      await tester.pump();
      await tester.tap(find.byKey(VocabularyPage.classFilterKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('扩展').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('共 ${entries.length} 词 · 当前 1073 词'), findsOneWidget);
      await tester.tap(find.text('仅看未测试 / 到期'));
      await tester.pump();
      expect(find.text('共 ${entries.length} 词 · 当前 1073 词'), findsOneWidget);
      controller.dispose();
    },
  );

  testWidgets('one formal card hides its meaning until the grade is saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = formalController();
    await controller.refresh();
    final word = controller.words.firstWhere(
      (item) => item.entry.libraryClass == '扩展',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewPage(controller: controller, entryId: word.entry.id),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('meaning')), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(ReviewPage.gradeKey(ReviewGrade.mastered)),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(ReviewPage.revealKey));
    await tester.pump();
    expect(find.text(word.entry.meaning), findsOneWidget);
    await tester.tap(find.byKey(ReviewPage.gradeKey(ReviewGrade.familiar)));
    await tester.pump();
    expect(find.byKey(const Key('review-saved')), findsOneWidget);
    final saved = controller.find(word.entry.id)!;
    expect(saved.status, 'familiar');
    expect(saved.reviewCount, 1);
    expect(saved.dueAt, at.add(const Duration(days: 1)));
    expect(saved.lastReviewedAt, at);
    controller.dispose();
  });

  test('grouped formal sync is idempotent and keeps personal state', () async {
    final directory = await Directory.systemTemp.createTemp(
      'english_p5b_sync_',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final path = '${directory.path}/learning.sqlite3';
    var repo = await SqliteLearningRepository.open(path);
    addTearDown(repo.close);
    final schema = Map<String, dynamic>.from(snapshot()['schema'] as Map);
    schema['properties'] = {
      for (final field in {
        ...NotionFields.mapping,
        ...NotionFields.extensions,
      }.entries)
        field.value: {'type': NotionFields.type(field.key)},
    };
    var queries = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') return jsonResponse(schema);
      queries++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['page_size'], 100);
      final filter = body['filter'] as Map;
      final conditions =
          (filter['or'] ?? (filter['and'] as List).first['or']) as List;
      expect(conditions.length, lessThanOrEqualTo(100));
      final ids = conditions
          .map((dynamic item) => (item as Map)['rich_text']['equals'])
          .toSet();
      final group = entries.where((entry) => ids.contains(entry.id)).toList();
      expect(group.length, ids.length);
      return jsonResponse(
        listResponse([
          for (final entry in group) pageFor(entry, entries.indexOf(entry) + 1),
        ]),
      );
    });
    final service = NotionSyncService(
      store: repo,
      credentials: MemoryCredentials(testAccount()),
      api: NotionReadApi(client, delay: noDelay),
      loadScope: () async => NotionScope(formalCsv()),
      clock: () => at,
    );
    expect((await service.sync()).inserted, entries.length);
    await repo.recordReview(entries.first.id, ReviewGrade.mastered, at);
    expect((await service.sync()).unchanged, entries.length);
    expect(queries, (entries.length / 100).ceil() * 2);
    await repo.close();
    repo = await SqliteLearningRepository.open(path);
    final words = await repo.readWords();
    expect(words.length, entries.length);
    expect(
      words.singleWhere((word) => word.entry.id == entries.first.id).status,
      'mastered',
    );
    expect(
      words.singleWhere((word) => word.entry.id == entries.first.id).dueAt,
      at.add(const Duration(days: 7)),
    );
    expect(
      (await repo.readNotionState(notionPilotSource)).linkedWords,
      entries.length,
    );
    expect(await repo.reviewEventCount(), 1);
    client.close();
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'an incomplete formal sync writes nothing and keeps the isolated library',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'english_p5b_rollback_',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final repo = await SqliteLearningRepository.open(
        '${directory.path}/learning.sqlite3',
      );
      addTearDown(repo.close);
      await repo.importCsv(formalCsv());
      await repo.recordReview(entries.first.id, ReviewGrade.forgotten, at);
      final schema = Map<String, dynamic>.from(snapshot()['schema'] as Map);
      schema['properties'] = {
        for (final field in {
          ...NotionFields.mapping,
          ...NotionFields.extensions,
        }.entries)
          field.value: {'type': NotionFields.type(field.key)},
      };
      final client = MockClient((request) async {
        if (request.method == 'GET') return jsonResponse(schema);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final filter = body['filter'] as Map;
        final conditions =
            (filter['or'] ?? (filter['and'] as List).first['or']) as List;
        final ids = conditions
            .map((dynamic item) => (item as Map)['rich_text']['equals'])
            .toSet();
        final group = entries.where((entry) => ids.contains(entry.id)).toList();
        final visible = ids.contains(entries.last.id)
            ? group.take(group.length - 1)
            : group;
        return jsonResponse(
          listResponse([
            for (final entry in visible)
              pageFor(entry, entries.indexOf(entry) + 1),
          ]),
        );
      });
      final service = NotionSyncService(
        store: repo,
        credentials: MemoryCredentials(testAccount()),
        api: NotionReadApi(client, delay: noDelay),
        loadScope: () async => NotionScope(formalCsv()),
        clock: () => at,
      );
      await expectLater(service.sync(), throwsA(isA<NotionFailure>()));
      expect((await repo.readWords()).length, entries.length);
      expect(
        (await repo.readWords())
            .singleWhere((word) => word.entry.id == entries.first.id)
            .status,
        'forgotten',
      );
      expect((await repo.readNotionState(notionPilotSource)).watermark, isNull);
      expect((await repo.readNotionState(notionPilotSource)).linkedWords, 0);
      client.close();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'syncing the accepted 500 does not delete the other local words or ratings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'english_p5b_partial_',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final repo = await SqliteLearningRepository.open(
        '${directory.path}/learning.sqlite3',
      );
      addTearDown(repo.close);
      await repo.importCsv(formalCsv());
      final extra = entries.firstWhere(
        (entry) => !reviewed.any((old) => old.id == entry.id),
      );
      await repo.recordReview(reviewed.first.id, ReviewGrade.mastered, at);
      await repo.recordReview(extra.id, ReviewGrade.familiar, at);
      final schema = Map<String, dynamic>.from(snapshot()['schema'] as Map);
      schema['properties'] = {
        for (final field in {
          ...NotionFields.mapping,
          ...NotionFields.extensions,
        }.entries)
          field.value: {'type': NotionFields.type(field.key)},
      };
      final client = MockClient((request) async {
        if (request.method == 'GET') return jsonResponse(schema);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final filter = body['filter'] as Map;
        final conditions =
            (filter['or'] ?? (filter['and'] as List).first['or']) as List;
        expect(conditions.length, lessThanOrEqualTo(100));
        final ids = conditions
            .map((dynamic item) => (item as Map)['rich_text']['equals'])
            .toSet();
        final group = reviewed
            .where((entry) => ids.contains(entry.id))
            .toList();
        return jsonResponse(
          listResponse([
            for (final entry in group)
              pageFor(entry, reviewed.indexOf(entry) + 1),
          ]),
        );
      });
      final service = NotionSyncService(
        store: repo,
        credentials: MemoryCredentials(testAccount()),
        api: NotionReadApi(client, delay: noDelay),
        loadScope: () async => NotionScope(
          File('assets/vocabulary/reviewed500.csv').readAsStringSync(),
        ),
        clock: () => at,
      );
      expect((await service.sync()).unchanged, reviewed.length);
      final words = await repo.readWords();
      expect(words.length, entries.length);
      expect(
        words.singleWhere((word) => word.entry.id == reviewed.first.id).status,
        'mastered',
      );
      expect(
        words.singleWhere((word) => word.entry.id == extra.id).status,
        'familiar',
      );
      expect(
        (await repo.readNotionState(notionPilotSource)).linkedWords,
        reviewed.length,
      );
      client.close();
    },
  );
}
