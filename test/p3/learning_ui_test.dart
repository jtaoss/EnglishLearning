import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_controller.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';

import '../p1a/learning_flow_test.dart' show MemoryLearningRepository;
import '../p1b/pronunciation_test.dart'
    show MemoryPronunciationStore, ControlledPlayer, FakeAudioCache, content;
import '../support/memory_settings_repository.dart';

void main() {
  final pack = VocabularyCsv.parse(
    File('assets/vocabulary/reviewed500.csv').readAsStringSync(),
  );
  final at = DateTime.utc(2026, 11, 9, 1);
  testWidgets(
    'inline recording playback blocks opening a second player until completion',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entry = pack.singleWhere((e) => e.word == 'side');
      final repo = MemoryLearningRepository();
      repo.words = [
        StudyWord(
          entry: entry,
          status: 'untested',
          pronunciationStatus: '未测试',
          reviewCount: 0,
        ),
      ];
      final controller = VocabularyController(repo, AppLogger());
      final player = ControlledPlayer();
      try {
        await controller.refresh();
        final services = PronunciationServices(
          store: MemoryPronunciationStore(),
          logger: AppLogger(),
          catalogLoader: () async => PronunciationCatalog([content('side')]),
          cache: FakeAudioCache(),
          playerFactory: () => player,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReviewPage(
              entryId: entry.id,
              controller: controller,
              hasPronunciation: true,
              pronunciationServices: services,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('confirm-self-reading')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('play-pronunciation')));
        await tester.tap(find.byKey(const Key('play-pronunciation')));
        await tester.pump();
        expect(player.plays, 1);
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('word-pronunciation')))
              .onPressed,
          isNull,
        );
        player.complete();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(find.byKey(const Key('word-pronunciation')))
              .onPressed,
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox());
        expect(player.disposals, 1);
      } finally {
        controller.dispose();
      }
    },
  );
  testWidgets(
    'a new word without audio supports self-reading, separate rating, answer and natural example',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final entry = pack.singleWhere((e) => e.word == 'about');
      final repo = MemoryLearningRepository();
      repo.words = [
        StudyWord(
          entry: entry,
          status: 'untested',
          pronunciationStatus: '未测试',
          reviewCount: 0,
        ),
      ];
      final controller = VocabularyController(
        repo,
        AppLogger(),
        clock: () => at,
      );
      try {
        await controller.refresh();
        final reading = MemoryPronunciationStore();
        final services = PronunciationServices(
          store: reading,
          logger: AppLogger(),
          catalogLoader: () async => PronunciationCatalog([]),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ReviewPage(
              entryId: entry.id,
              controller: controller,
              pronunciationServices: services,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(entry.meaning), findsNothing);
        expect(find.byKey(const Key('example-en')), findsNothing);
        expect(find.byKey(const Key('phonics-note')), findsNothing);
        await tester.tap(find.byKey(const Key('confirm-self-reading')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('phonics-note')), findsOneWidget);
        expect(find.byKey(const Key('audio-missing')), findsOneWidget);
        final pronunciation = find.byKey(
          const ValueKey('pronunciation-grade-needsPractice'),
        );
        await tester.ensureVisible(pronunciation);
        await tester.tap(pronunciation);
        await tester.pumpAndSettle();
        expect(reading.writes, 1);
        expect(reading.progress.grade, PronunciationGrade.needsPractice);
        expect(reading.progress.dueAt, at.add(const Duration(minutes: 10)));
        await tester.tap(pronunciation);
        await tester.pumpAndSettle();
        expect(reading.writes, 1);
        expect(repo.events, 0);
        await tester.ensureVisible(find.byKey(ReviewPage.revealKey));
        await tester.tap(find.byKey(ReviewPage.revealKey));
        await tester.pumpAndSettle();
        expect(find.text(entry.meaning), findsOneWidget);
        expect(find.text(entry.fields['example_en']!), findsOneWidget);
        final meaning = find.byKey(ReviewPage.gradeKey(ReviewGrade.mastered));
        await tester.ensureVisible(meaning);
        await tester.tap(meaning);
        await tester.pumpAndSettle();
        expect(repo.events, 1);
        expect(reading.writes, 1);
        expect(
          controller.find(entry.id)!.dueAt,
          at.add(const Duration(days: 7)),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        controller.dispose();
      }
    },
  );

  testWidgets(
    '500-word library remains lazy, searches late alphabet words and opens a card with hidden meaning',
    (tester) async {
      final repo = MemoryLearningRepository();
      repo.words = [
        for (final entry in pack)
          StudyWord(
            entry: entry,
            status: 'untested',
            pronunciationStatus: '未测试',
            reviewCount: 0,
          ),
      ];
      await tester.pumpWidget(
        EnglishLearningApp(
          repository: MemorySettingsRepository(),
          logger: AppLogger(),
          config: AppConfig.developmentPreset(),
          learningRepository: repo,
          clock: () => at,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('start-due-review')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('open-vocabulary')));
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile).evaluate().length, lessThan(100));
      await tester.enterText(find.byKey(const Key('vocabulary-search')), 'zoo');
      await tester.pumpAndSettle();
      final zoo = pack.singleWhere((e) => e.word == 'zoo');
      await tester.ensureVisible(find.byKey(ValueKey('word-${zoo.id}')));
      await tester.tap(find.byKey(ValueKey('word-${zoo.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-word')), findsOneWidget);
      expect(find.text(zoo.meaning), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
