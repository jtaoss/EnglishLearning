import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/app_metadata.dart';
import 'package:english_learning/app/app_router.dart';
import 'package:english_learning/app/app_settings.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/review/review_session_page.dart';
import 'package:english_learning/features/review/study_queue.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';

import '../support/memory_settings_repository.dart';

final class _TestLearningRepo implements LearningRepository {
  _TestLearningRepo([this.words = const []]);

  List<StudyWord> words;
  int events = 0;

  @override
  Future<List<StudyWord>> readWords() async => List.of(words);

  @override
  Future<void> recordReview(String id, ReviewGrade grade, DateTime at) async {
    events++;
    final index = words.indexWhere((w) => w.entry.id == id);
    if (index >= 0) {
      final prev = words[index];
      words[index] = StudyWord(
        entry: prev.entry,
        status: grade.name,
        pronunciationStatus: prev.pronunciationStatus,
        reviewCount: prev.reviewCount + 1,
        lastReviewedAt: at.toUtc(),
        dueAt: ReviewSchedule.nextDue(grade, at),
        pronunciationProgress: prev.pronunciationProgress,
      );
    }
  }

  @override
  Future<ImportResult> importCsv(String csv) async =>
      const ImportResult(0, 0, 0);

  @override
  Future<int> reviewEventCount() async => events;

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final baseTime = DateTime.utc(2026, 11, 12, 10, 0, 0);

  group('P6-B Study Queue & Metrics Unit Tests', () {
    test('untested words are never counted as due meaning reviews', () {
      final words = [
        _sampleWord('w1', 'apple', '高频词', status: 'untested', reviewCount: 0),
        _sampleWord('w2', 'banana', '基础词', status: 'untested', reviewCount: 0),
        _sampleWord(
          'w3',
          'cherry',
          '中频词',
          status: 'mastered',
          reviewCount: 1,
          dueAt: baseTime.subtract(const Duration(hours: 2)),
        ),
        _sampleWord(
          'w4',
          'date',
          '低频词',
          status: 'familiar',
          reviewCount: 1,
          dueAt: baseTime.add(const Duration(days: 1)),
        ),
      ];

      final dueQueue = dueMeaningReviewQueue(words, baseTime);
      expect(dueQueue, hasLength(1));
      expect(dueQueue.single.entry.word, 'cherry');

      final stats = ReviewDashboardStats.fromWords(words, baseTime);
      expect(stats.totalCount, 4);
      expect(stats.dueReviewCount, 1);
      expect(stats.remainingReviewCount, 1);
      expect(stats.notYetDueCount, 1); // 'date'
      expect(stats.untestedCount, 2);
      expect(stats.newLearnableCount, 2);
      expect(stats.studiedCount, 2);
    });

    test('due queue orders strictly by overdue time ascending', () {
      final words = [
        _sampleWord(
          'w-recent',
          'recent',
          '高频词',
          status: 'mastered',
          reviewCount: 1,
          dueAt: baseTime.subtract(const Duration(minutes: 5)),
        ),
        _sampleWord(
          'w-oldest',
          'oldest',
          '补充词',
          status: 'forgotten',
          reviewCount: 2,
          dueAt: baseTime.subtract(const Duration(days: 3)),
        ),
        _sampleWord(
          'w-middle',
          'middle',
          '基础词',
          status: 'familiar',
          reviewCount: 1,
          dueAt: baseTime.subtract(const Duration(hours: 5)),
        ),
      ];

      final queue = dueMeaningReviewQueue(words, baseTime);
      expect(queue.map((w) => w.entry.word).toList(), [
        'oldest',
        'middle',
        'recent',
      ]);
    });

    test('weak queue includes only forgotten and familiar words in order', () {
      final words = [
        _sampleWord(
          'w-fam',
          'familiarWord',
          '基础词',
          status: 'familiar',
          reviewCount: 1,
          lastReviewedAt: baseTime.subtract(const Duration(days: 1)),
        ),
        _sampleWord(
          'w-for',
          'forgottenWord',
          '高频词',
          status: 'forgotten',
          reviewCount: 2,
          lastReviewedAt: baseTime.subtract(const Duration(hours: 1)),
        ),
        _sampleWord(
          'w-mas',
          'masteredWord',
          '高频词',
          status: 'mastered',
          reviewCount: 3,
        ),
        _sampleWord('w-unt', 'untestedWord', '中频词', status: 'untested'),
      ];

      final weakQueue = weakMeaningWordQueue(words, baseTime);
      expect(weakQueue.map((w) => w.entry.word).toList(), [
        'forgottenWord',
        'familiarWord',
      ]);
    });

    test('isReviewedOnLocalDay accurately matches local calendar day', () {
      final localNow = DateTime(2026, 11, 12, 14, 30);
      final sameDayMorning = DateTime(2026, 11, 12, 8, 15).toUtc();
      final previousDayNight = DateTime(2026, 11, 11, 23, 59).toUtc();
      final nextDayDawn = DateTime(2026, 11, 13, 0, 5).toUtc();

      expect(isReviewedOnLocalDay(sameDayMorning, localNow), isTrue);
      expect(isReviewedOnLocalDay(previousDayNight, localNow), isFalse);
      expect(isReviewedOnLocalDay(nextDayDawn, localNow), isFalse);
    });

    test(
      'ReviewSchedule calculates exact intervals and preserves stability',
      () {
        final t = DateTime.utc(2026, 11, 12, 12, 0, 0);
        expect(
          ReviewSchedule.nextDue(ReviewGrade.mastered, t),
          t.add(const Duration(days: 7)),
        );
        expect(
          ReviewSchedule.nextDue(ReviewGrade.familiar, t),
          t.add(const Duration(days: 1)),
        );
        expect(
          ReviewSchedule.nextDue(ReviewGrade.forgotten, t),
          t.add(const Duration(minutes: 10)),
        );
      },
    );
  });

  group('P6-B Widget & Flow Tests', () {
    testWidgets('Home Review Center displays empty hint when 0 words are due', (
      tester,
    ) async {
      final repo = _TestLearningRepo([
        _sampleWord('w1', 'cat', '高频词', status: 'untested'),
        _sampleWord('w2', 'dog', '基础词', status: 'untested'),
      ]);
      final controller = VocabularyController(
        repo,
        AppLogger(),
        clock: () => baseTime,
      );
      try {
        await controller.refresh();

        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: AppRouter.create(
              appSettings: AppSettings(repository: MemorySettingsRepository()),
              vocabularyController: controller,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 0 due reviews: displays the required empty state hint
        expect(find.byKey(const Key('no-due-review-hint')), findsOneWidget);
        expect(find.text('今天暂无到期复习，先去学习一些新词吧。'), findsOneWidget);

        // Required metrics are visible
        expect(find.byKey(const Key('metric-due-review')), findsOneWidget);
        expect(
          tester.widget<Text>(find.byKey(const Key('metric-due-review'))).data,
          '0',
        );
        expect(find.byKey(const Key('metric-completed-today')), findsOneWidget);
        expect(
          find.byKey(const Key('metric-remaining-review')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('metric-not-yet-due')), findsOneWidget);
        expect(find.byKey(const Key('metric-weak-words')), findsOneWidget);

        // start-new-words button is prominent
        expect(find.byKey(const Key('start-new-words')), findsOneWidget);
        expect(find.byKey(const Key('start-due-review')), findsOneWidget);
      } finally {
        controller.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets(
      'Mode 1: Due Review Session progresses, supports keyboard shortcuts, and completes',
      (tester) async {
        final repo = _TestLearningRepo([
          _sampleWord(
            'w1',
            'abandon',
            '高频词',
            status: 'mastered',
            reviewCount: 1,
            dueAt: baseTime.subtract(const Duration(hours: 3)),
          ),
          _sampleWord(
            'w2',
            'ability',
            '基础词',
            status: 'familiar',
            reviewCount: 1,
            dueAt: baseTime.subtract(const Duration(hours: 1)),
          ),
        ]);
        final controller = VocabularyController(
          repo,
          AppLogger(),
          clock: () => baseTime,
        );
        try {
          await controller.refresh();

          await tester.pumpWidget(
            MaterialApp.router(
              routerConfig: AppRouter.create(
                appSettings: AppSettings(
                  repository: MemorySettingsRepository(),
                ),
                vocabularyController: controller,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Taps start due review
          await tester.tap(find.byKey(const Key('start-due-review')));
          await tester.pumpAndSettle();

          // Card 1: abandon
          expect(find.text('abandon'), findsOneWidget);
          expect(find.byKey(const Key('meaning')), findsNothing);
          expect(
            find.byKey(const Key('session-progress-text')),
            findsOneWidget,
          );
          expect(find.textContaining('当前第 1 词 / 共 2 词'), findsOneWidget);

          // Rating keys 1/2/3 before reveal should not fire
          await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
          await tester.pumpAndSettle();
          expect(repo.events, 0);

          // Space key reveals answer
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('meaning')), findsOneWidget);
          expect(find.byKey(const Key('rating-guidance')), findsOneWidget);

          // Press '1' for forgotten (10 min)
          await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
          await tester.pumpAndSettle();
          expect(repo.events, 1);

          // Automatically advances to Card 2: ability
          expect(find.text('ability'), findsOneWidget);
          expect(find.byKey(const Key('meaning')), findsNothing);
          expect(find.textContaining('当前第 2 词 / 共 2 词'), findsOneWidget);

          // Click reveal button
          await tester.tap(find.byKey(ReviewPage.revealKey));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('meaning')), findsOneWidget);

          // Press '3' for mastered (7 days)
          await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
          await tester.pumpAndSettle();
          expect(repo.events, 2);

          // Session completes!
          expect(
            find.byKey(const Key('review-session-complete')),
            findsOneWidget,
          );
          expect(find.textContaining('今日到期复习已完成'), findsOneWidget);
          expect(
            find.byKey(const Key('summary-mastered-count')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('summary-forgotten-count')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('session-back-home')), findsOneWidget);

          // Return home
          await tester.tap(find.byKey(const Key('session-back-home')));
          await tester.pumpAndSettle();
          expect(find.text(AppMetadata.title), findsOneWidget);
        } finally {
          controller.dispose();
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets(
      'Mode 2: Weak Word Consolidation defaults to temporary practice without touching formal SQLite ratings',
      (tester) async {
        final repo = _TestLearningRepo([
          _sampleWord(
            'w-weak',
            'perseverance',
            '中频词',
            status: 'forgotten',
            reviewCount: 3,
            dueAt: baseTime.add(const Duration(days: 2)),
          ),
        ]);
        final controller = VocabularyController(
          repo,
          AppLogger(),
          clock: () => baseTime,
        );
        try {
          await controller.refresh();

          await tester.pumpWidget(
            MaterialApp(
              home: ReviewSessionPage(
                controller: controller,
                mode: ReviewSessionMode.weak,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Weak mode banner
          expect(
            find.byKey(const Key('weak-temp-mode-banner')),
            findsOneWidget,
          );
          expect(find.text('perseverance'), findsOneWidget);

          // Reveal answer
          await tester.tap(find.byKey(ReviewPage.revealKey));
          await tester.pumpAndSettle();

          // Temporary practice buttons are shown
          expect(
            find.byKey(const Key('weak-practice-remembered')),
            findsOneWidget,
          );
          expect(find.byKey(const Key('weak-practice-again')), findsOneWidget);

          // Click temporary remembered
          await tester.ensureVisible(
            find.byKey(const Key('weak-practice-remembered')),
          );
          await tester.tap(find.byKey(const Key('weak-practice-remembered')));
          await tester.pumpAndSettle();

          // No SQLite review events written!
          expect(repo.events, 0);

          // Finished session displays summary
          expect(
            find.byKey(const Key('weak-session-complete')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('summary-temp-remembered')),
            findsOneWidget,
          );
        } finally {
          controller.dispose();
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('Keyboard shortcuts are ignored when text field has focus', (
      tester,
    ) async {
      final repo = _TestLearningRepo([
        _sampleWord(
          'w1',
          'apple',
          '高频词',
          status: 'mastered',
          reviewCount: 1,
          dueAt: baseTime.subtract(const Duration(hours: 1)),
        ),
      ]);
      final controller = VocabularyController(
        repo,
        AppLogger(),
        clock: () => baseTime,
      );
      final searchFocus = FocusNode();
      final searchController = TextEditingController();

      try {
        await controller.refresh();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  TextField(
                    focusNode: searchFocus,
                    controller: searchController,
                    key: const Key('dummy-input'),
                  ),
                  Expanded(
                    child: ReviewSessionPage(
                      controller: controller,
                      mode: ReviewSessionMode.due,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Focus the text field
        await tester.tap(find.byKey(const Key('dummy-input')));
        await tester.pumpAndSettle();
        expect(searchFocus.hasFocus, isTrue);

        // Press Space while text input has focus: should not reveal answer
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('meaning')), findsNothing);
      } finally {
        searchFocus.dispose();
        searchController.dispose();
        controller.dispose();
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets(
      'Android mobile layout 360x640 at 1.5x scale supports review session reveal and rating without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final repo = _TestLearningRepo([
          _sampleWord(
            'w1',
            'incomprehensibility',
            '高频词',
            status: 'familiar',
            reviewCount: 1,
            dueAt: baseTime.subtract(const Duration(hours: 1)),
          ),
        ]);
        final controller = VocabularyController(
          repo,
          AppLogger(),
          clock: () => baseTime,
        );
        try {
          await controller.refresh();

          await tester.pumpWidget(
            MaterialApp(
              home: ReviewSessionPage(
                controller: controller,
                mode: ReviewSessionMode.due,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('incomprehensibility'), findsOneWidget);
          await tester.ensureVisible(find.byKey(ReviewPage.revealKey));
          await tester.tap(find.byKey(ReviewPage.revealKey));
          await tester.pumpAndSettle();

          final gradeMastered = find.byKey(
            ReviewPage.gradeKey(ReviewGrade.mastered),
          );
          await tester.ensureVisible(gradeMastered);
          await tester.tap(gradeMastered);
          await tester.pumpAndSettle();

          expect(repo.events, 1);
          expect(
            find.byKey(const Key('review-session-complete')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          controller.dispose();
          await tester.pumpWidget(const SizedBox());
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    test(
      'Isolated SQLite database preserves ratings and queue after restart',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'english_p6b_test_',
        );
        final dbPath = '${directory.path}/test_p6b.sqlite3';

        final csv = [
          VocabularyCsv.columns.join(','),
          _csvLine('SG25-01', 'overdueWord', '高频词', '10'),
          _csvLine('SG25-02', 'untestedWord', '基础词', '20'),
        ].join('\n');

        var repo = await SqliteLearningRepository.open(dbPath);
        await repo.importCsv(csv);

        // Initially both untested
        var words = await repo.readWords();
        expect(dueMeaningReviewQueue(words, baseTime), isEmpty);

        // Rate word 1 as familiar
        await repo.recordReview('SG25-01', ReviewGrade.familiar, baseTime);
        await repo.close();

        // Re-open DB
        repo = await SqliteLearningRepository.open(dbPath);
        words = await repo.readWords();

        final word1 = words.singleWhere((w) => w.entry.id == 'SG25-01');
        expect(word1.status, 'familiar');
        expect(word1.reviewCount, 1);
        expect(word1.dueAt, baseTime.add(const Duration(days: 1)));

        // Fast forward 2 days: word1 is due, word2 is untested
        final futureTime = baseTime.add(const Duration(days: 2));
        final dueQueue = dueMeaningReviewQueue(words, futureTime);
        expect(dueQueue, hasLength(1));
        expect(dueQueue.single.entry.id, 'SG25-01');

        final weakQueue = weakMeaningWordQueue(words, futureTime);
        expect(weakQueue, hasLength(1));
        expect(weakQueue.single.entry.id, 'SG25-01');

        await repo.close();
        await directory.delete(recursive: true);
      },
    );
  });
}

StudyWord _sampleWord(
  String id,
  String word,
  String category, {
  String libraryClass = '主学习',
  String status = 'untested',
  int reviewCount = 0,
  DateTime? dueAt,
  DateTime? lastReviewedAt,
}) {
  return StudyWord(
    entry: VocabularyEntry({
      'entry_id': id,
      'word': word,
      'meaning_zh': '$word 的中文含义',
      'library_class': libraryClass,
      'book_category': category,
      'part_of_speech': 'n.',
      'learning_priority': 'P1',
      'source_file': '2025考研英语词汇闪过.pdf',
      'source_id': 'src',
      'source_pdf_pages': '10',
      'source_index_pages': '10',
      'book_verification': '已核验',
      'pets2015_status': '已收录',
      'pets2025_status': '待核验',
      'meaning_review_status': '已核验',
      'example_en': 'This is an example sentence for $word.',
      'example_zh': '这是 $word 的例句。',
    }),
    status: status,
    pronunciationStatus: '未测试',
    reviewCount: reviewCount,
    dueAt: dueAt,
    lastReviewedAt: lastReviewedAt,
  );
}

String _csvLine(String id, String word, String category, String page) =>
    '$id,$word,义,$category,2025考研英语词汇闪过.pdf,src,$page,1,已核验,已核验,已收录,待核实,主学习';
