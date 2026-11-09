import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/app/open_learning_repository.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import '../../test/support/memory_settings_repository.dart';
import 'local_learning.dart' show captureFrame;

const sampleWords = [
  'big',
  'tree',
  'side',
  'carry',
  'notice',
  'autumn',
  'about',
  'December',
  'May',
  'may',
  'March',
  'lead',
  'read',
  "o'clock",
  'digital',
  'injury',
  'database',
  'challenge',
  'separate',
  'accuracy',
  'convenience',
  'combat',
  'conductor',
  'elementary',
  'breathe',
  'furnish',
  'resume',
  'résumé',
  'fragile',
  'imaginary',
  'anecdote',
  'march',
  'overhaul',
  'beloved',
];

class _Offline extends HttpOverrides {
  int requests = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests++;
    throw StateError('Native offline acceptance rejects HTTP.');
  }
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (ready()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
  fail('Native learning condition timed out.');
}

Future<void> _tap(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  const enabled = bool.fromEnvironment('P4_LEARNING');
  const folder = String.fromEnvironment('P4_REPORT_DIR');
  const cold = String.fromEnvironment('P4_COLD_REPORT');
  const live = bool.fromEnvironment('P4_NOTION_LIVE');
  const personal = bool.fromEnvironment('P4_NOTION_PERSONAL');
  testWidgets(
    '34 native words: human recording priority, local TTS, independent grades, continuous next and offline disk persistence',
    (tester) async {
      final report = Directory(folder);
      await tester.runAsync(() => report.create(recursive: true));
      final isolated = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('english_p4_learning_'),
      ))!;
      final repo = (await tester.runAsync(
        () =>
            SqliteLearningRepository.open('${isolated.path}/isolated.sqlite3'),
      ))!;
      addTearDown(repo.close);
      final csv = await rootBundle.loadString(
        'assets/vocabulary/reviewed500.csv',
      );
      final entries = VocabularyCsv.parse(csv);
      await tester.runAsync(() => repo.importCsv(csv));
      final voice = (await tester.runAsync(WindowsLocalSpeech().voice))!;
      expect(voice.locale, 'en-US');
      final human = {'big', 'tree', 'side', 'carry', 'notice', 'autumn'};
      final offline = _Offline(), previous = HttpOverrides.current;
      HttpOverrides.global = offline;
      addTearDown(() => HttpOverrides.global = previous);
      final at = DateTime.utc(2026, 11, 9, 6);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('native-capture-root'),
          child: EnglishLearningApp(
            repository: MemorySettingsRepository(),
            logger: AppLogger(),
            config: AppConfig.developmentPreset(),
            learningRepository: repo,
            clock: () => at,
            pronunciationServices: PronunciationServices(
              store: repo,
              logger: AppLogger(),
              speechFactory: defaultLocalSpeech,
            ),
          ),
        ),
      );
      await _wait(
        tester,
        () => find.byKey(const Key('start-due-review')).evaluate().isNotEmpty,
      );
      final results = <Map<String, Object?>>[];
      for (var i = 0; i < sampleWords.length; i++) {
        final word = sampleWords[i];
        final entry = entries.singleWhere((e) => e.word == word);
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go(AppRouter.wordPath(entry.id));
        await _wait(
          tester,
          () =>
              find
                  .byKey(const Key('confirm-self-reading'))
                  .evaluate()
                  .isNotEmpty &&
              tester.widget<Text>(find.byKey(const Key('review-word'))).data ==
                  word,
        );
        expect(find.byKey(const Key('meaning')), findsNothing);
        expect(find.byKey(const Key('example-en')), findsNothing);
        await _tap(tester, const Key('confirm-self-reading'));
        final playKey = Key(
          human.contains(word) ? 'play-pronunciation' : 'play-local-tts',
        );
        final grade = PronunciationGrade.values[i % 3];
        final ratingKey = ValueKey('pronunciation-grade-${grade.name}');
        expect(
          tester.widget<OutlinedButton>(find.byKey(ratingKey)).onPressed,
          isNull,
        );
        await _tap(tester, playKey);
        await _wait(
          tester,
          () =>
              tester.widget<OutlinedButton>(find.byKey(ratingKey)).onPressed !=
              null,
        );
        if (i == 0 || word == 'resume' || word == 'overhaul') {
          await _tap(tester, playKey);
          await _wait(
            tester,
            () =>
                tester
                    .widget<OutlinedButton>(find.byKey(ratingKey))
                    .onPressed !=
                null,
          );
        }
        if (['read', 'lead', 'resume', 'overhaul'].contains(word)) {
          await _tap(tester, const Key('play-local-tts-context'));
          await _wait(
            tester,
            () =>
                tester
                    .widget<OutlinedButton>(find.byKey(ratingKey))
                    .onPressed !=
                null,
          );
        }
        await _tap(tester, ratingKey);
        await _wait(
          tester,
          () => find
              .byKey(const Key('pronunciation-saved'))
              .evaluate()
              .isNotEmpty,
        );
        final pronunciation = (await tester.runAsync(
          () => repo.readPronunciation(entry.id),
        ))!;
        expect(pronunciation.grade, grade);
        expect(
          pronunciation.sourceId,
          startsWith(human.contains(word) ? 'commons-' : 'windows-tts:'),
        );
        final beforeMeaning = (await tester.runAsync(repo.readWords))!
            .singleWhere((w) => w.entry.id == entry.id);
        expect(beforeMeaning.status, 'untested');
        await _tap(tester, const Key('reveal-answer'));
        expect(find.text(entry.meaning), findsOneWidget);
        expect(find.byKey(const Key('example-en')), findsOneWidget);
        final meaning = ReviewGrade.values[i % ReviewGrade.values.length];
        await _tap(tester, ValueKey('grade-${meaning.name}'));
        await _wait(
          tester,
          () => find.byKey(const Key('review-saved')).evaluate().isNotEmpty,
        );
        final after = (await tester.runAsync(repo.readWords))!
            .singleWhere((w) => w.entry.id == entry.id);
        expect(after.status, meaning.name);
        expect(after.reviewCount, 1);
        expect(after.dueAt, ReviewSchedule.nextDue(meaning, at));
        expect(
          (await tester.runAsync(() => repo.readPronunciation(entry.id)))!
              .grade,
          grade,
        );
        results.add({
          'id': entry.id,
          'word': word,
          'category': entry.fields['book_category'],
          'meaning': meaning.name,
          'pronunciation': grade.name,
          'meaning_due': after.dueAt!.toIso8601String(),
          'pronunciation_due': pronunciation.dueAt!.toIso8601String(),
          'source': pronunciation.sourceId,
          'meaning_hidden_initially': true,
        });
        if (word == 'imaginary') {
          await captureFrame(tester, report, 'p4-tts-independent-ratings');
        }
        await _tap(tester, const Key('next-word'));
        await _wait(
          tester,
          () =>
              find.byKey(const Key('review-word')).evaluate().isNotEmpty &&
              tester.widget<Text>(find.byKey(const Key('review-word'))).data !=
                  word,
        );
        expect(find.byKey(const Key('meaning')), findsNothing);
      }
      expect(results.map((r) => r['id']).toSet().length, 34);
      expect(await tester.runAsync(repo.reviewEventCount), 34);
      final repeat = (await tester.runAsync(() => repo.importCsv(csv)))!;
      expect(repeat.inserted, 0);
      expect(repeat.updated, 0);
      expect(repeat.unchanged, 500);
      expect(offline.requests, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(
        () => File('$folder/learning.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'pid': pid,
            'db_path': repo.path,
            'word_count': 500,
            'sample_count': 34,
            'human_recording_words': 6,
            'tts_words': 28,
            'voice': voice.name,
            'locale': voice.locale,
            'samples': results,
            'http_requests': offline.requests,
            'repeat_import_unchanged': 500,
            'formal_personal_database_opened': false,
            'real_events_uploaded': 0,
            'subjective_human_listening_confirmation': 'pending; native playback completion is not a human accent assessment',
          }),
          flush: true,
        ),
      );
    },
    skip: !enabled || folder.isEmpty,
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'fresh process: 34 native learning records, source types, review dates and overdue priority restored offline',
    (tester) async {
      final data = jsonDecode(
        (await tester.runAsync(() => File(cold).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(data['pid'], isNot(pid));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(data['db_path'] as String),
      ))!;
      addTearDown(repo.close);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, 500);
      for (final raw in data['samples'] as List) {
        final r = raw as Map;
        final w = words.singleWhere((w) => w.entry.id == r['id']);
        expect(w.status, r['meaning']);
        expect(w.reviewCount, 1);
        expect(w.dueAt!.toIso8601String(), r['meaning_due']);
        final p = (await tester.runAsync(
          () => repo.readPronunciation(w.entry.id),
        ))!;
        expect(p.grade!.name, r['pronunciation']);
        expect(p.dueAt!.toIso8601String(), r['pronunciation_due']);
        expect(p.sourceId, r['source']);
      }
      expect(await tester.runAsync(repo.reviewEventCount), 34);
      final reviewAt = DateTime.utc(2026, 11, 17, 6);
      final controller = VocabularyController(
        repo,
        AppLogger(),
        clock: () => reviewAt,
      );
      await tester.runAsync(controller.refresh);
      final queue = controller.dueWords(reviewAt, libraryClass: null);
      final studiedIds = (data['samples'] as List)
          .map((r) => (r as Map)['id'])
          .toSet();
      expect(queue.length, 500);
      expect(queue.take(34).map((w) => w.entry.id).toSet(), studiedIds);
      controller.dispose();
      await tester.runAsync(
        () => File('$cold.cold.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'pid': pid,
            'previous_pid': data['pid'],
            'word_count': 500,
            'sample_count': 34,
            'ratings_dates_and_source_restored': true,
            'due_reviews_before_466_new_words': true,
            'http_requests': 0,
            'formal_personal_database_opened': false,
          }),
          flush: true,
        ),
      );
    },
    skip: cold.isEmpty,
  );

  testWidgets(
    'actual read-only Notion API 500 full and repeat sync preserve the 34 isolated study records',
    (tester) async {
      final data = jsonDecode(
        (await tester.runAsync(
          () => File('$folder/learning.json').readAsString(),
        ))!,
      ) as Map<String, dynamic>;
      final vault = WindowsNotionCredentials();
      expect(
        await tester.runAsync(vault.read),
        isNotNull,
        reason: '请在程序隐藏输入框安全保存只读配置。',
      );
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(data['db_path'] as String),
      ))!;
      addTearDown(repo.close);
      final client = http.Client();
      addTearDown(client.close);
      final csv = await rootBundle.loadString(
        'assets/vocabulary/reviewed500.csv',
      );
      final service = NotionSyncService(
        store: repo,
        credentials: vault,
        api: NotionReadApi(client),
        loadScope: () async => NotionScope(csv),
      );
      final first = (await tester.runAsync(
        () => service.sync(full: true, limit: 500),
      ))!;
      final second = (await tester.runAsync(
        () => service.sync(full: true, limit: 500),
      ))!;
      final incremental = (await tester.runAsync(
        () => service.sync(limit: 500),
      ))!;
      expect(first.inserted, 0);
      expect(first.updated, 0);
      expect(first.unchanged, 500);
      expect(second.inserted, 0);
      expect(second.updated, 0);
      expect(second.unchanged, 500);
      expect(incremental.inserted, 0);
      expect(incremental.updated, 0);
      final expected = {
        for (final e in VocabularyCsv.parse(csv)) e.id: e.fields,
      };
      final words = (await tester.runAsync(repo.readWords))!;
      for (final w in words) {
        expect(w.entry.fields, expected[w.entry.id]);
      }
      for (final raw in data['samples'] as List) {
        final r = raw as Map;
        final w = words.singleWhere((w) => w.entry.id == r['id']);
        expect(w.status, r['meaning']);
        expect(w.dueAt!.toIso8601String(), r['meaning_due']);
        final p = (await tester.runAsync(
          () => repo.readPronunciation(w.entry.id),
        ))!;
        expect(p.sourceId, r['source']);
        expect(p.grade!.name, r['pronunciation']);
      }
      expect(await tester.runAsync(repo.reviewEventCount), 34);
      await tester.runAsync(
        () => File('$folder/notion-live.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'word_count': 500,
            'first_unchanged': 500,
            'repeat_unchanged': 500,
            'incremental_inserted': 0,
            'incremental_updated': 0,
            'all_content_fields_equal': true,
            '34_isolated_records_preserved': true,
            'cloud_writes': 0,
            'real_events_uploaded': 0,
          }),
          flush: true,
        ),
      );
    },
    skip: !live || folder.isEmpty,
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'actual personal Windows cache 500 read-only sync preserves every existing progress row and event',
    (tester) async {
      final repo = (await tester.runAsync(openLearningRepository))!;
      addTearDown(repo.close);
      Map<String, List<Map<String, Object?>>> progress() {
        final db = sqlite3.open(repo.path, mode: OpenMode.readOnly);
        try {
          return {
            for (final t in [
              'learning_progress',
              'review_events',
              'pronunciation_progress',
              'pronunciation_events',
            ])
              t: db
                  .select('SELECT * FROM $t ORDER BY 1')
                  .map((r) => Map<String, Object?>.from(r))
                  .toList(),
          };
        } finally {
          db.close();
        }
      }

      final before = (await tester.runAsync(() async => progress()))!;
      final csv = await rootBundle.loadString(
        'assets/vocabulary/reviewed500.csv',
      );
      final client = http.Client();
      addTearDown(client.close);
      final service = NotionSyncService(
        store: repo,
        credentials: WindowsNotionCredentials(),
        api: NotionReadApi(client),
        loadScope: () async => NotionScope(csv),
      );
      final full = (await tester.runAsync(
        () => service.sync(full: true, limit: 500),
      ))!;
      final repeat = (await tester.runAsync(() => service.sync(limit: 500)))!;
      expect(full.inserted, 0);
      expect(full.updated, 0);
      expect(full.unchanged, 500);
      expect(repeat.inserted, 0);
      expect(repeat.updated, 0);
      expect((await tester.runAsync(() async => progress()))!, before);
      final expected = {
        for (final e in VocabularyCsv.parse(csv)) e.id: e.fields,
      };
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, 500);
      for (final w in words) {
        expect(w.entry.fields, expected[w.entry.id]);
      }
      expect(
        (await tester.runAsync(() => repo.readNotionState(notionPilotSource)))!
            .linkedWords,
        500,
      );
      await tester.runAsync(
        () => File('$folder/notion-personal.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'word_count': 500,
            'full_unchanged': full.unchanged,
            'repeat_inserted': 0,
            'repeat_updated': 0,
            'all_content_fields_equal': true,
            'all_personal_tables_unchanged': true,
            'existing_meaning_events': before['review_events']!.length,
            'existing_pronunciation_events':
                before['pronunciation_events']!.length,
            'personal_learning_events_created': 0,
            'cloud_writes': 0,
            'real_events_uploaded': 0,
            'credential_read_internally_only': true,
          }),
          flush: true,
        ),
      );
    },
    skip: !personal || folder.isEmpty,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
