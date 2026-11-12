import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';

import '../p1a/learning_flow_test.dart' show MemoryLearningRepository;
import '../p1a/fixtures.dart';
import '../support/memory_settings_repository.dart';

Future<void> mount(
  WidgetTester tester,
  MemoryLearningRepository repo, {
  DateTime Function()? clock,
}) async {
  await tester.pumpWidget(
    EnglishLearningApp(
      repository: MemorySettingsRepository(),
      logger: AppLogger(),
      config: AppConfig.developmentPreset(),
      learningRepository: repo,
      clock: clock,
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('open-vocabulary')));
  await tester.tap(find.byKey(const Key('open-vocabulary')));
  await tester.pumpAndSettle();
}

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      '${mobile ? 'Android' : 'Windows'} CSV entry policy is applied through app routes',
      (tester) async {
        await tester.pumpWidget(
          EnglishLearningApp(
            repository: MemorySettingsRepository(),
            logger: AppLogger(),
            config: AppConfig.developmentPreset(),
            learningRepository: MemoryLearningRepository(),
            notionMobile: mobile,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            mobile ? '首次使用请在词库中连接 Notion' : '首次使用可导入 100 词 CSV',
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(find.byKey(const Key('open-vocabulary')));
        await tester.tap(find.byKey(const Key('open-vocabulary')));
        await tester.pumpAndSettle();
        for (final key in ['import-csv-file', 'import-verified100']) {
          expect(find.byKey(Key(key)), mobile ? findsNothing : findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final item in [
    (const Size(320, 568), 2.0),
    (const Size(360, 640), 1.3),
    (const Size(393, 852), 2.0),
    (const Size(640, 360), 2.0),
  ]) {
    testWidgets(
      'Android layout ${item.$1} at ${item.$2}x supports reveal and rating',
      (tester) async {
        tester.view.physicalSize = item.$1;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = item.$2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repo = MemoryLearningRepository();
        final first = repo.words.first;
        repo.words[0] = StudyWord(
          entry: VocabularyEntry({
            ...first.entry.fields,
            'part_of_speech': '名词；动词',
            'usage_note': '这是区分不同词性和语境的说明。' * 8,
          }),
          status: first.status,
          pronunciationStatus: first.pronunciationStatus,
          reviewCount: 0,
        );
        await mount(tester, repo);
        await tester.tap(find.byKey(const ValueKey('word-test-alpha')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('part-of-speech')), findsNothing);
        await tester.ensureVisible(find.byKey(ReviewPage.revealKey));
        await tester.tap(find.byKey(ReviewPage.revealKey));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('part-of-speech')), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(ReviewPage.gradeKey(ReviewGrade.familiar)),
        );
        await tester.tap(find.byKey(ReviewPage.gradeKey(ReviewGrade.familiar)));
        await tester.pumpAndSettle();
        expect(repo.events, 1);
        expect(find.byKey(const Key('review-saved')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  test('due comparisons include the exact instant across UTC/local date boundaries', () {
    final due = DateTime.parse('2026-11-08T00:00:00+08:00');
    final word = StudyWord(
      entry: VocabularyEntry(entryFields()),
      status: 'familiar',
      pronunciationStatus: '未测试',
      reviewCount: 1,
      dueAt: due.toUtc(),
    );
    expect(word.isDue(due.subtract(const Duration(microseconds: 1))), isFalse);
    expect(word.isDue(due), isTrue);
    expect(word.isDue(due.add(const Duration(microseconds: 1))), isTrue);
  });
  for (final resume in [false, true]) {
    testWidgets(
      'due list refreshes ${resume ? 'on foreground resume' : 'on its minute clock'}',
      (tester) async {
        var now = DateTime.utc(2026, 11, 7, 23, 59, 40);
        final repo = MemoryLearningRepository();
        repo.words = [
          StudyWord(
            entry: VocabularyEntry(entryFields()),
            status: 'familiar',
            pronunciationStatus: '未测试',
            reviewCount: 1,
            dueAt: now.add(const Duration(seconds: 20)),
          ),
        ];
        await mount(tester, repo, clock: () => now);
        await tester.tap(find.text('仅看未测试 / 到期'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('word-test-alpha')), findsNothing);
        now = now.add(const Duration(seconds: 20));
        if (resume) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
        } else {
          await tester.pump(const Duration(minutes: 1));
          await tester.pumpAndSettle();
        }
        expect(find.byKey(const ValueKey('word-test-alpha')), findsOneWidget);
      },
    );
  }
  testWidgets('reopened studied card displays its persisted next review', (
    tester,
  ) async {
    final repo = MemoryLearningRepository();
    repo.words = [
      StudyWord(
        entry: VocabularyEntry(entryFields()),
        status: 'familiar',
        pronunciationStatus: '未测试',
        reviewCount: 1,
        dueAt: DateTime.utc(2026, 11, 8, 12),
      ),
    ];
    await mount(tester, repo);
    await tester.tap(find.byKey(const ValueKey('word-test-alpha')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('persisted-due')), findsOneWidget);
    expect(find.byKey(const Key('meaning')), findsNothing);
  });
}
