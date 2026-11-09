import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/app/open_learning_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';

class _Offline extends HttpOverrides {
  int requests = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests++;
    throw StateError('Cloud snapshot acceptance is offline.');
  }
}

void main() {
  const source = String.fromEnvironment('P3_CLOUD_CSV');
  const sizeText = String.fromEnvironment('P3_CLOUD_SIZE');
  const directory = String.fromEnvironment('P3_CLOUD_REPORT_DIR');
  const coldReceipt = String.fromEnvironment('P3_CLOUD_COLD_REPORT');
  const populatePersonal = bool.fromEnvironment('P3_CLOUD_POPULATE_PERSONAL');
  testWidgets(
    'real Notion connector CSV to Windows SQLite expansion and repeat import',
    (tester) async {
      final size = int.parse(sizeText);
      expect([200, 500], contains(size));
      final folder = Directory(directory);
      await tester.runAsync(() => folder.create(recursive: true));
      final csv = (await tester.runAsync(() => File(source).readAsString()))!;
      final cloudEntries = VocabularyCsv.parse(csv);
      expect(cloudEntries.length, size);
      final expectedCsv = await rootBundle.loadString(
        'assets/vocabulary/reviewed500.csv',
      );
      final expected = {
        for (final e in VocabularyCsv.parse(expectedCsv).take(size))
          e.id: e.fields,
      };
      for (final e in cloudEntries) {
        expect(e.fields, expected[e.id]);
      }
      final previous = size == 500
          ? jsonDecode(
              (await tester.runAsync(
                () => File('$directory/cloud-200.json').readAsString(),
              ))!,
            ) as Map<String, dynamic>
          : null;
      final path =
          previous?['db_path'] as String? ??
          '$directory/snapshot-${DateTime.now().microsecondsSinceEpoch}.sqlite3';
      var repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(path),
      ))!;
      var closed = false;
      final originalOverride = HttpOverrides.current;
      final offline = _Offline();
      HttpOverrides.global = offline;
      addTearDown(() async {
        HttpOverrides.global = originalOverride;
        if (!closed) await repo.close();
      });
      if (size == 200) {
        final oldCsv = await rootBundle.loadString(
          'assets/vocabulary/verified100.csv',
        );
        await tester.runAsync(() => repo.importCsv(oldCsv));
        final big = (await tester.runAsync(repo.readWords))!
            .singleWhere((w) => w.entry.word == 'big');
        final at = DateTime.utc(2026, 11, 9, 4);
        await tester.runAsync(
          () => repo.recordReview(big.entry.id, ReviewGrade.familiar, at),
        );
        await tester.runAsync(
          () => repo.recordPronunciation(
            entryId: big.entry.id,
            grade: PronunciationGrade.familiar,
            audioAssetId: 'p3-snapshot-isolated-sentinel',
            attemptId: 'p3-snapshot-sentinel',
            at: at,
          ),
        );
      }
      final before = (await tester.runAsync(repo.readWords))!;
      final bigBefore = before.singleWhere((w) => w.entry.word == 'big');
      final events = (await tester.runAsync(repo.reviewEventCount))!;
      final imported = (await tester.runAsync(() => repo.importCsv(csv)))!;
      expect(imported.inserted, size - before.length);
      Future<void> check() async {
        final words = await repo.readWords();
        expect(words.length, size);
        expect(words.map((w) => w.entry.id).toSet().length, size);
        for (final word in words) {
          expect(word.entry.fields, expected[word.entry.id]);
        }
        final big = words.singleWhere((w) => w.entry.id == bigBefore.entry.id);
        expect(big.status, bigBefore.status);
        expect(big.reviewCount, bigBefore.reviewCount);
        expect(big.lastReviewedAt, bigBefore.lastReviewedAt);
        expect(big.dueAt, bigBefore.dueAt);
        final pronunciation = await repo.readPronunciation(big.entry.id);
        expect(pronunciation.grade, PronunciationGrade.familiar);
        expect(pronunciation.assessedAt, DateTime.utc(2026, 11, 9, 4));
        expect(pronunciation.dueAt, DateTime.utc(2026, 11, 10, 4));
        expect(await repo.reviewEventCount(), events);
      }

      await tester.runAsync(check);
      final repeat = (await tester.runAsync(() => repo.importCsv(csv)))!;
      expect(repeat.inserted, 0);
      expect(repeat.updated, 0);
      expect(repeat.unchanged, size);
      await tester.runAsync(check);
      await tester.runAsync(repo.close);
      closed = true;
      repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(path),
      ))!;
      closed = false;
      await tester.runAsync(check);
      expect(offline.requests, 0);
      await tester.runAsync(
        () => File('$directory/cloud-$size.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'transport':
                'actual Notion connector direct rows → CSV → Windows SQLite',
            'source_csv': source,
            'size': size,
            'pid': pid,
            'db_path': path,
            'before_words': before.length,
            'inserted': imported.inserted,
            'updated': imported.updated,
            'repeat_inserted': repeat.inserted,
            'repeat_updated': repeat.updated,
            'repeat_unchanged': repeat.unchanged,
            'all_content_fields_equal': true,
            'stable_ids_unique': true,
            'meaning_and_pronunciation_preserved': true,
            'meaning_events': events,
            'disk_reopen_passed': true,
            'http_requests': offline.requests,
            'formal_personal_database_opened': false,
            'real_events_uploaded': 0,
            'direct_notion_api_sync':
                'not exercised; user credential unavailable',
          }),
          flush: true,
        ),
      );
    },
    skip:
        source.isEmpty ||
        sizeText.isEmpty ||
        directory.isEmpty ||
        populatePersonal,
  );

  testWidgets(
    'populate actual Windows word library from audited cloud CSV without creating study events',
    (tester) async {
      final csv = (await tester.runAsync(() => File(source).readAsString()))!;
      final entries = VocabularyCsv.parse(csv);
      expect(entries.length, 500);
      final expected = {for (final e in entries) e.id: e.fields};
      final repo = (await tester.runAsync(openLearningRepository))!;
      addTearDown(repo.close);
      Map<String, List<Map<String, Object?>>> progress() {
        final db = sqlite3.open(repo.path, mode: OpenMode.readOnly);
        try {
          return {
            for (final table in [
              'learning_progress',
              'review_events',
              'pronunciation_progress',
              'pronunciation_events',
            ])
              table: db
                  .select('SELECT * FROM $table ORDER BY 1')
                  .map((r) => Map<String, Object?>.from(r))
                  .toList(),
          };
        } finally {
          db.close();
        }
      }

      final before = (await tester.runAsync(() async => progress()))!;
      final oldWords = (await tester.runAsync(repo.readWords))!;
      final imported = (await tester.runAsync(() => repo.importCsv(csv)))!;
      final after = (await tester.runAsync(() async => progress()))!;
      for (final table in before.keys) {
        if (table == 'learning_progress') {
          for (final row in before[table]!) {
            expect(
              after[table]!.singleWhere(
                (r) => r['entry_id'] == row['entry_id'],
              ),
              row,
            );
          }
        } else {
          expect(after[table], before[table]);
        }
      }
      final words = (await tester.runAsync(repo.readWords))!;
      final oldIds = oldWords.map((w) => w.entry.id).toSet();
      for (final w in words.where((w) => expected.containsKey(w.entry.id))) {
        expect(w.entry.fields, expected[w.entry.id]);
        if (!oldIds.contains(w.entry.id)) {
          expect(w.status, 'untested');
          expect(w.reviewCount, 0);
          expect(w.dueAt, isNull);
          expect(w.lastReviewedAt, isNull);
          expect(w.pronunciationProgress?.grade, isNull);
        }
      }
      expect(
        words
            .map((w) => w.entry.id)
            .toSet()
            .intersection(expected.keys.toSet())
            .length,
        500,
      );
      final repeat = (await tester.runAsync(() => repo.importCsv(csv)))!;
      expect(repeat.inserted, 0);
      expect(repeat.updated, 0);
      expect(repeat.unchanged, 500);
      expect((await tester.runAsync(() async => progress()))!, after);
      await tester.runAsync(
        () => File('$directory/personal-cloud-import.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'pid': pid,
            'db_path': repo.path,
            'before_words': oldWords.length,
            'after_words': words.length,
            'inserted': imported.inserted,
            'updated': imported.updated,
            'repeat_inserted': 0,
            'repeat_updated': 0,
            'repeat_unchanged': 500,
            'all_cloud_content_fields_equal': true,
            'existing_personal_state_preserved': true,
            'new_words_untested': true,
            'meaning_events_created': 0,
            'pronunciation_events_created': 0,
            'real_events_uploaded': 0,
            'transport': 'actual Notion connector direct rows → CSV → existing importCsv repository method',
          }),
          flush: true,
        ),
      );
    },
    skip: !populatePersonal || source.isEmpty || directory.isEmpty,
  );

  testWidgets(
    'independent process restores real cloud snapshot content and isolated grades offline',
    (tester) async {
      final data = jsonDecode(
        (await tester.runAsync(() => File(coldReceipt).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(data['status'], 'PASS');
      expect(data['pid'], isNot(pid));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(data['db_path'] as String),
      ))!;
      addTearDown(repo.close);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, data['size']);
      final csv = await rootBundle.loadString(
        'assets/vocabulary/reviewed500.csv',
      );
      final expected = {
        for (final e in VocabularyCsv.parse(csv).take(data['size'] as int))
          e.id: e.fields,
      };
      for (final w in words) {
        expect(w.entry.fields, expected[w.entry.id]);
      }
      final big = words.singleWhere((w) => w.entry.word == 'big');
      expect(big.status, 'familiar');
      expect(big.reviewCount, 1);
      expect(big.dueAt, DateTime.utc(2026, 11, 10, 4));
      expect(
        (await tester.runAsync(() => repo.readPronunciation(big.entry.id)))!
            .grade,
        PronunciationGrade.familiar,
      );
      expect(
        await tester.runAsync(repo.reviewEventCount),
        data['meaning_events'],
      );
      await tester.runAsync(
        () => File('$coldReceipt.cold.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'previous_pid': data['pid'],
            'pid': pid,
            'size': words.length,
            'all_content_fields_equal': true,
            'meaning_and_pronunciation_restored': true,
            'http_requests': 0,
            'formal_personal_database_opened': false,
          }),
          flush: true,
        ),
      );
    },
    skip: coldReceipt.isEmpty,
  );
}
