import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/features/vocabulary/vocabulary_page.dart';

import '../support/memory_settings_repository.dart';
import 'fixtures.dart';

final class MemoryLearningRepository implements LearningRepository {
  MemoryLearningRepository({bool empty = false}) {
    words = empty
        ? []
        : [
            for (final e in [
              entryFields(),
              entryFields(id: 'test-beta', word: 'beta', meaning: '第二个'),
              entryFields(id: 'test-paused', word: 'paused', library: '暂缓'),
            ])
              StudyWord(
                entry: VocabularyEntry(e),
                status: 'untested',
                pronunciationStatus: '未测试',
                reviewCount: 0,
              ),
          ];
  }
  late List<StudyWord> words;
  int events = 0;
  bool failRead = false;
  Completer<void>? holdReview;
  @override
  Future<List<StudyWord>> readWords() async {
    if (failRead) throw StateError('simulated read failure');
    return List.of(words);
  }

  @override
  Future<ImportResult> importCsv(String csv) async {
    final entries = VocabularyCsv.parse(csv);
    final existing = words.map((w) => w.entry.id).toSet();
    var inserted = 0;
    for (final entry in entries) {
      if (existing.add(entry.id)) {
        words.add(
          StudyWord(
            entry: entry,
            status: 'untested',
            pronunciationStatus: '未测试',
            reviewCount: 0,
          ),
        );
        inserted++;
      }
    }
    return ImportResult(inserted, 0, entries.length - inserted);
  }

  @override
  Future<void> recordReview(String id, ReviewGrade grade, DateTime at) async {
    events++;
    await holdReview?.future;
  }

  @override
  Future<int> reviewEventCount() async => events;
  @override
  Future<void> close() async {}
}

Future<void> openWords(
  WidgetTester tester,
  MemoryLearningRepository repository,
) async {
  await tester.pumpWidget(
    EnglishLearningApp(
      repository: MemorySettingsRepository(),
      logger: AppLogger(),
      config: AppConfig.developmentPreset(),
      learningRepository: repository,
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('open-vocabulary')));
  await tester.tap(find.byKey(const Key('open-vocabulary')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'meaning is hidden, rating requires reveal, repeated clicks save once and next word hides answer',
    (tester) async {
      final repository = MemoryLearningRepository();
      await openWords(tester, repository);
      expect(find.text('paused'), findsNothing);
      expect(find.text('第一个'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('word-test-alpha')));
      await tester.pumpAndSettle();
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
      expect(find.text('第一个'), findsOneWidget);
      repository.holdReview = Completer<void>();
      repository.failRead =
          true; // Acknowledged rating must not need a second read.
      await tester.tap(find.byKey(ReviewPage.gradeKey(ReviewGrade.mastered)));
      await tester.pump();
      await tester.tap(find.byKey(ReviewPage.gradeKey(ReviewGrade.mastered)));
      await tester.pump();
      expect(repository.events, 1);
      repository.holdReview!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-saved')), findsOneWidget);
      await tester.tap(find.byKey(const Key('next-word')));
      await tester.pumpAndSettle();
      expect(find.text('beta'), findsOneWidget);
      expect(find.byKey(const Key('meaning')), findsNothing);
      expect(find.byKey(ReviewPage.revealKey), findsOneWidget);
    },
  );
  testWidgets('100 word CSV import and repeat import report stable counts', (
    tester,
  ) async {
    final repository = MemoryLearningRepository(empty: true);
    await openWords(tester, repository);
    await tester.tap(find.byKey(VocabularyPage.sampleImportKey));
    await tester.pumpAndSettle();
    expect(repository.words.length, 100);
    await tester.tap(find.byKey(VocabularyPage.sampleImportKey));
    await tester.pumpAndSettle();
    expect(repository.words.length, 100);
    expect(find.text('新增 0，更新 0，未变 100'), findsOneWidget);
  });
  for (final size in [const Size(320, 320), const Size(1440, 900)]) {
    testWidgets('word list fits $size at 2x text scale', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openWords(tester, MemoryLearningRepository());
      expect(tester.takeException(), isNull);
      expect(find.byKey(VocabularyPage.classFilterKey), findsOneWidget);
      expect(find.byKey(const Key('word-list')), findsOneWidget);
    });
  }
}
