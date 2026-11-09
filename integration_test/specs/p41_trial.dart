import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/local_speech.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';

import '../../test/support/memory_settings_repository.dart';

const ttsSamples = [
  'object',
  'increase',
  'address',
  'use',
  'separate',
  'beloved',
  'elementary',
  'database',
  'resume',
  'résumé',
  'read',
  'lead',
  'overhaul',
  'combat',
  'fifteen',
  'interesting',
  'convenience',
  'texture',
];
const humanSamples = ['big', 'tree', 'side', 'carry', 'notice', 'autumn'];
const contextSamples = {
  'object',
  'increase',
  'address',
  'use',
  'separate',
  'beloved',
  'resume',
  'résumé',
  'read',
  'lead',
  'overhaul',
  'combat',
};

class _Offline extends HttpOverrides {
  int requests = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    requests++;
    throw StateError('P4.1 offline playback rejects HTTP.');
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
  final errors = find.byKey(const Key('pronunciation-error'));
  if (errors.evaluate().isNotEmpty) {
    debugPrint('P41 playback error: ${tester.widget<Text>(errors).data}');
  }
  fail('P4.1 native condition timed out.');
}

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  const enabled = bool.fromEnvironment('P41_TRIAL');
  const folder = String.fromEnvironment('P41_REPORT_DIR');
  const cold = String.fromEnvironment('P41_COLD_REPORT');
  testWidgets(
    '18 TTS and 6 human native playbacks; private trial gates',
    (tester) async {
      final isolated = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('english_p41_trial_'),
      ))!;
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open('${isolated.path}/trial.sqlite3'),
      ))!;
      addTearDown(repo.close);
      final csv = await rootBundle.loadString(
        'assets/vocabulary/reviewed500.csv',
      );
      final entries = VocabularyCsv.parse(csv);
      await tester.runAsync(() => repo.importCsv(csv));
      final voice = (await tester.runAsync(WindowsLocalSpeech().voice))!;
      final at = DateTime.now().toUtc();
      final offline = _Offline(), previous = HttpOverrides.current;
      HttpOverrides.global = offline;
      addTearDown(() => HttpOverrides.global = previous);
      await tester.pumpWidget(
        EnglishLearningApp(
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
      );
      await _wait(
        tester,
        () => find.byKey(const Key('start-due-review')).evaluate().isNotEmpty,
      );
      final results = <Map<String, Object?>>[];
      final stored = <Map<String, Object?>>[];
      for (final word in [...ttsSamples, ...humanSamples, 'about']) {
        debugPrint('P41 checking $word');
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
        void hidden() {
          expect(find.byKey(const Key('meaning')), findsNothing);
          expect(find.byKey(const Key('example-en')), findsNothing);
          expect(find.byKey(const Key('example-zh')), findsNothing);
          expect(find.text(entry.meaning), findsNothing);
          for (final name in ['mastered', 'familiar', 'forgotten']) {
            expect(
              tester
                  .widget<OutlinedButton>(find.byKey(ValueKey('grade-$name')))
                  .onPressed,
              isNull,
            );
          }
        }

        hidden();
        final isHuman = humanSamples.contains(word);
        if (word != 'about') {
          await _tap(tester, 'confirm-self-reading');
          hidden(); // Hints must not reveal Chinese definitions or examples.
          final key = isHuman ? 'play-pronunciation' : 'play-local-tts';
          final rating = find.byKey(
            const ValueKey('pronunciation-grade-confident'),
          );
          expect(tester.widget<OutlinedButton>(rating).onPressed, isNull);
          final started = DateTime.now();
          await _tap(tester, key);
          await _wait(
            tester,
            () => tester.widget<OutlinedButton>(rating).onPressed != null,
          );
          final isolatedMs = DateTime.now().difference(started).inMilliseconds;
          if (contextSamples.contains(word)) {
            await _tap(tester, 'play-local-tts-context');
            await _wait(
              tester,
              () => tester.widget<OutlinedButton>(rating).onPressed != null,
            );
          }
          hidden();
          results.add({
            'entry_id': entry.id,
            'word': word,
            'source_type': isHuman ? 'human' : 'local_tts',
            'native_completed': true,
            'isolated_playback_ms': isolatedMs,
            'context_completed': contextSamples.contains(word),
            'answer_hidden_after_hints_and_playback': true,
            'personal_hearing_confirmation': 'pending',
          });
        }
        if (word == 'object' || word == 'increase' || word == 'about') {
          if (word != 'about') {
            await _tap(
              tester,
              word == 'object'
                  ? 'pronunciation-grade-needsPractice'
                  : 'pronunciation-grade-confident',
            );
            await _wait(
              tester,
              () => find
                  .byKey(const Key('pronunciation-saved'))
                  .evaluate()
                  .isNotEmpty,
            );
            expect(
              (await tester.runAsync(repo.readWords))!
                  .singleWhere((w) => w.entry.id == entry.id)
                  .status,
              'untested',
            );
          }
          final pronunciation = (await tester.runAsync(
            () => repo.readPronunciation(entry.id),
          ))!;
          await _tap(tester, 'reveal-answer');
          expect(find.text(entry.meaning), findsOneWidget);
          final grade = word == 'object' ? 'familiar' : 'forgotten';
          await _tap(tester, 'grade-$grade');
          await _wait(
            tester,
            () => find.byKey(const Key('review-saved')).evaluate().isNotEmpty,
          );
          final after = (await tester.runAsync(repo.readWords))!
              .singleWhere((w) => w.entry.id == entry.id);
          expect(after.status, grade);
          expect(after.reviewCount, 1);
          final p = (await tester.runAsync(
            () => repo.readPronunciation(entry.id),
          ))!;
          expect(p.grade, pronunciation.grade);
          expect(p.assessedAt, pronunciation.assessedAt);
          if (word == 'about') expect(p.grade, isNull);
          stored.add({
            'id': entry.id,
            'word': word,
            'meaning': grade,
            'meaning_due': after.dueAt!.toIso8601String(),
            'pronunciation': p.grade?.name,
            'pronunciation_at': p.assessedAt?.toIso8601String(),
            'pronunciation_due': p.dueAt?.toIso8601String(),
            'source': p.sourceId,
          });
        }
      }
      expect(await tester.runAsync(repo.reviewEventCount), 3);
      expect(offline.requests, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await Directory(folder).create(recursive: true);
        await File('$folder/trial.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'pid': pid,
            'db_path': repo.path,
            'created_utc': at.toIso8601String(),
            'word_count': 500,
            'tts_sample_count': 18,
            'human_sample_count': 6,
            'voice': voice.name,
            'locale': voice.locale,
            'playbacks': results,
            'isolated_records': stored,
            'http_requests': offline.requests,
            'formal_personal_database_opened': false,
            'real_events_uploaded': 0,
            'meaning_only_without_listening': true,
            'human_hearing_confirmation':
                'pending; completion is not an acoustic assessment',
          }),
          flush: true,
        );
      });
    },
    skip: !enabled || folder.isEmpty,
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets('new process restores trial ratings, dates and due-first queue', (
    tester,
  ) async {
    final data = jsonDecode(
      (await tester.runAsync(() => File(cold).readAsString()))!,
    ) as Map<String, dynamic>;
    expect(data['pid'], isNot(pid));
    final repo = (await tester.runAsync(
      () => SqliteLearningRepository.open(data['db_path'] as String),
    ))!;
    addTearDown(repo.close);
    final offline = _Offline(), previous = HttpOverrides.current;
    HttpOverrides.global = offline;
    addTearDown(() => HttpOverrides.global = previous);
    final words = (await tester.runAsync(repo.readWords))!;
    expect(words.length, 500);
    for (final raw in data['isolated_records'] as List) {
      final r = raw as Map;
      final word = words.singleWhere((w) => w.entry.id == r['id']);
      expect(word.status, r['meaning']);
      expect(word.reviewCount, 1);
      expect(word.dueAt!.toIso8601String(), r['meaning_due']);
      final p = (await tester.runAsync(
        () => repo.readPronunciation(word.entry.id),
      ))!;
      expect(p.grade?.name, r['pronunciation']);
      expect(p.assessedAt?.toIso8601String(), r['pronunciation_at']);
      expect(p.dueAt?.toIso8601String(), r['pronunciation_due']);
      expect(p.sourceId, r['source']);
    }
    final at = DateTime.parse(data['created_utc'] as String)
        .add(const Duration(days: 8));
    final controller = VocabularyController(repo, AppLogger(), clock: () => at);
    await tester.runAsync(controller.refresh);
    final studied = (data['isolated_records'] as List)
        .map((r) => (r as Map)['id'])
        .toSet();
    expect(
      controller
          .dueWords(at, libraryClass: null)
          .take(3)
          .map((w) => w.entry.id)
          .toSet(),
      studied,
    );
    controller.dispose();
    expect(await tester.runAsync(repo.reviewEventCount), 3);
    expect(offline.requests, 0);
    await tester.runAsync(
      () => File('$cold.cold.json').writeAsString(
        jsonEncode({
          'status': 'PASS',
          'pid': pid,
          'previous_pid': data['pid'],
          'word_count': 500,
          'isolated_records_restored': 3,
          'independent_ratings_dates_and_source_preserved': true,
          'due_before_497_new': true,
          'http_requests': offline.requests,
          'formal_personal_database_opened': false,
          'real_events_uploaded': 0,
        }),
        flush: true,
      ),
    );
  }, skip: cold.isEmpty);
}
