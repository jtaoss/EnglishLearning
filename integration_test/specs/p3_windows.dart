import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';

import '../../test/support/memory_settings_repository.dart';
import 'local_learning.dart' show captureFrame;

const _enabled = bool.fromEnvironment('P3_WINDOWS');
const _reportDirectory = String.fromEnvironment('P3_REPORT_DIR');
const _coldReport = String.fromEnvironment('P3_COLD_REPORT');

class _Offline extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('P3 native acceptance blocks HTTP; use local resources.');
  }
}

Future<void> _wait(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
  await captureFrame(tester, Directory(_reportDirectory), 'p3-timeout');
  await tester.runAsync(
    () => File('$_reportDirectory/timeout-text.json').writeAsString(
      jsonEncode(
        tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList(),
      ),
    ),
  );
  fail('P3 timed out waiting for $finder');
}

void main() {
  testWidgets(
    'P3 Windows 500-word offline learning, native replay and disk recovery',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('english_p3_native_'),
      ))!;
      final report = Directory(_reportDirectory);
      await tester.runAsync(() => report.create(recursive: true));
      final path = '${directory.path}/isolated.sqlite3';
      var repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(path),
      ))!;
      final offline = _Offline();
      final previous = HttpOverrides.current;
      HttpOverrides.global = offline;
      final at = DateTime.utc(2026, 11, 9, 2);
      try {
        final csv = await rootBundle.loadString(
          'assets/vocabulary/reviewed500.csv',
        );
        final entries = VocabularyCsv.parse(csv);
        await tester.runAsync(() => repo.importCsv(csv));
        final first = entries.first;
        await tester.runAsync(
          () => repo.recordReview(first.id, ReviewGrade.mastered, at),
        );
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
              ),
            ),
          ),
        );
        await _wait(tester, find.byKey(const Key('start-due-review')));
        await tester.tap(find.byKey(const Key('open-vocabulary')));
        await _wait(tester, find.byKey(const Key('vocabulary-search')));
        await tester.enterText(
          find.byKey(const Key('vocabulary-search')),
          'about',
        );
        final about = entries.singleWhere((e) => e.word == 'about');
        await _wait(tester, find.byKey(ValueKey('word-${about.id}')));
        await tester.tap(find.byKey(ValueKey('word-${about.id}')));
        await _wait(tester, find.byKey(const Key('confirm-self-reading')));
        expect(find.byKey(const Key('meaning')), findsNothing);
        await tester.tap(find.byKey(const Key('confirm-self-reading')));
        await _wait(tester, find.byKey(const Key('audio-missing')));
        await captureFrame(tester, report, 'p3-missing-audio-reading');
        final reading = find.byKey(
          const ValueKey('pronunciation-grade-needsPractice'),
        );
        await tester.ensureVisible(reading);
        await tester.tap(reading);
        await _wait(tester, find.byKey(const Key('pronunciation-saved')));
        await tester.tap(reading);
        await tester.ensureVisible(find.byKey(ReviewPage.revealKey));
        await tester.tap(find.byKey(ReviewPage.revealKey));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(about.fields['example_en']!), findsOneWidget);
        final grade = find.byKey(ReviewPage.gradeKey(ReviewGrade.mastered));
        await tester.ensureVisible(grade);
        await tester.tap(grade);
        await _wait(tester, find.byKey(const Key('review-saved')));
        await captureFrame(tester, report, 'p3-meaning-and-reading-saved');
        await tester.ensureVisible(find.text('返回词库'));
        await tester.tap(find.text('返回词库'));
        await _wait(tester, find.byKey(const Key('vocabulary-search')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('vocabulary-search')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('vocabulary-search')),
          'side',
        );
        await tester.pumpAndSettle();
        await captureFrame(tester, report, 'p3-side-search');
        final side = entries.singleWhere((e) => e.word == 'side');
        await _wait(tester, find.byKey(ValueKey('word-${side.id}')));
        await tester.tap(find.byKey(ValueKey('word-${side.id}')));
        await _wait(tester, find.byKey(const Key('confirm-self-reading')));
        await tester.tap(find.byKey(const Key('confirm-self-reading')));
        await _wait(tester, find.byKey(const Key('play-pronunciation')));
        for (var replay = 0; replay < 2; replay++) {
          final play = find.byKey(const Key('play-pronunciation'));
          await tester.ensureVisible(play);
          await tester.tap(play);
          await _wait(tester, find.text('播放完成，请对照后自评'));
          expect(find.byKey(const Key('pronunciation-error')), findsNothing);
        }
        final confident = find.byKey(
          const ValueKey('pronunciation-grade-confident'),
        );
        await tester.ensureVisible(confident);
        await tester.tap(confident);
        await _wait(tester, find.byKey(const Key('pronunciation-saved')));
        await captureFrame(tester, report, 'p3-native-audio-replayed');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(repo.close);
        repo = (await tester.runAsync(
          () => SqliteLearningRepository.open(path),
        ))!;
        final words = (await tester.runAsync(repo.readWords))!;
        expect(words.length, 500);
        expect(
          words.map((w) => w.entry.id).toSet(),
          entries.map((e) => e.id).toSet(),
        );
        final saved = words.singleWhere((w) => w.entry.id == about.id);
        expect(saved.status, 'mastered');
        expect(saved.dueAt, at.add(const Duration(days: 7)));
        expect(
          saved.pronunciationProgress!.grade,
          PronunciationGrade.needsPractice,
        );
        expect(
          saved.pronunciationProgress!.dueAt,
          at.add(const Duration(minutes: 10)),
        );
        expect(
          (await tester.runAsync(() => repo.importCsv(csv)))!.unchanged,
          500,
        );
        expect(offline.attempts, 0);
        await tester.runAsync(
          () => File('${report.path}/native-report.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'synthetic_learning_records': true,
              'pid': pid,
              'isolated_database': path,
              'reviewed_at_utc': at.toIso8601String(),
              'about_id': about.id,
              'side_id': side.id,
              'word_count': 500,
              'meaning_saved': true,
              'reading_saved_without_audio': true,
              'native_audio_replays': 2,
              'restart_restored': true,
              'duplicate_import_unchanged': 500,
              'http_attempts': offline.attempts,
              'live_notion_500_verified': false,
              'personal_database_opened': false,
            }),
            flush: true,
          ),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(repo.close);
        HttpOverrides.global = previous;
      }
    },
    skip: !Platform.isWindows || !_enabled || _reportDirectory.isEmpty,
  );

  testWidgets(
    'P3 Windows cold process restores saved grades and prioritizes pronunciation due',
    (tester) async {
      final previousReport = jsonDecode(
        (await tester.runAsync(() => File(_coldReport).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(previousReport['synthetic_learning_records'], true);
      expect(previousReport['pid'], isNot(pid));
      final path = previousReport['isolated_database'] as String;
      expect(File(path).uri.pathSegments.last, 'isolated.sqlite3');
      expect(Directory(path).parent.path, contains('english_p3_native_'));
      final at = DateTime.parse(previousReport['reviewed_at_utc'] as String);
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(path),
      ))!;
      final offline = _Offline();
      final oldOverrides = HttpOverrides.current;
      HttpOverrides.global = offline;
      try {
        final words = (await tester.runAsync(repo.readWords))!;
        expect(words.length, 500);
        final about = words.singleWhere(
          (w) => w.entry.id == previousReport['about_id'],
        );
        expect(about.status, 'mastered');
        expect(about.reviewCount, 1);
        expect(about.dueAt, at.add(const Duration(days: 7)));
        expect(
          about.pronunciationProgress!.grade,
          PronunciationGrade.needsPractice,
        );
        expect(
          words
              .singleWhere((w) => w.entry.id == previousReport['side_id'])
              .pronunciationProgress!
              .grade,
          PronunciationGrade.confident,
        );
        final before = (await tester.runAsync(repo.reviewEventCount))!;
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('native-capture-root'),
            child: EnglishLearningApp(
              repository: MemorySettingsRepository(),
              logger: AppLogger(),
              config: AppConfig.developmentPreset(),
              learningRepository: repo,
              clock: () => at.add(const Duration(minutes: 11)),
              pronunciationServices: PronunciationServices(
                store: repo,
                logger: AppLogger(),
              ),
            ),
          ),
        );
        await _wait(tester, find.byKey(const Key('start-due-review')));
        await tester.tap(find.byKey(const Key('start-due-review')));
        await _wait(tester, find.byKey(const Key('pronunciation-status')));
        expect(
          tester.widget<Text>(find.byKey(const Key('review-word'))).data,
          'about',
        );
        expect(find.text('发音自评：再练习'), findsOneWidget);
        expect(find.byKey(const Key('meaning')), findsNothing);
        await captureFrame(
          tester,
          Directory(_reportDirectory),
          'p3-cold-restored',
        );
        expect((await tester.runAsync(repo.reviewEventCount))!, before);
        expect(offline.attempts, 0);
        await tester.runAsync(
          () => File('$_reportDirectory/cold-report.json').writeAsString(
            jsonEncode({
              'pid': pid,
              'previous_pid': previousReport['pid'],
              'word_count': 500,
              'independent_process': true,
              'grades_restored': true,
              'due_word': 'about',
              'meaning_hidden': true,
              'history_unchanged': true,
              'http_attempts': 0,
            }),
            flush: true,
          ),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(repo.close);
        HttpOverrides.global = oldOverrides;
      }
    },
    skip:
        !Platform.isWindows || _coldReport.isEmpty || _reportDirectory.isEmpty,
  );
}
