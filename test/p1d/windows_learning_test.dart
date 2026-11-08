import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/features/learning_progress/study_word.dart';
import 'package:english_learning/features/vocabulary/vocabulary_entry.dart';
import 'package:english_learning/features/vocabulary/vocabulary_page.dart';
import 'package:english_learning/features/review/review_page.dart';
import 'package:english_learning/features/review/review_schedule.dart';

import '../p1a/fixtures.dart';
import '../p1a/learning_flow_test.dart'
    show MemoryLearningRepository, openWords;

StudyWord word(String id, String text, String library) => StudyWord(
  entry: VocabularyEntry(entryFields(id: id, word: text, library: library)),
  status: 'untested',
  pronunciationStatus: '未测试',
  reviewCount: 0,
);

Future<void> extensionList(
  WidgetTester tester,
  MemoryLearningRepository repo,
) async {
  await openWords(tester, repo);
  await tester.tap(find.byKey(VocabularyPage.classFilterKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text('扩展').last);
  await tester.pumpAndSettle();
}

Future<void> rate(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(ReviewPage.revealKey));
  await tester.tap(find.byKey(ReviewPage.revealKey));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(ReviewPage.gradeKey(ReviewGrade.familiar)),
  );
  await tester.tap(find.byKey(ReviewPage.gradeKey(ReviewGrade.familiar)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Windows returning from a rated card preserves library and due filters',
    (tester) async {
      final repo = MemoryLearningRepository();
      repo.words = [
        word('main', 'alpha', '主学习'),
        word('extension', 'beta', '扩展'),
      ];
      await extensionList(tester, repo);
      await tester.tap(find.text('仅看未测试 / 到期'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('word-extension')));
      await tester.pumpAndSettle();
      await rate(tester);
      await tester.ensureVisible(find.text('返回词库'));
      await tester.tap(find.text('返回词库'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(VocabularyPage.classFilterKey),
            )
            .value,
        '扩展',
      );
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
      expect(repo.events, 1);
    },
  );

  testWidgets(
    'Windows next word stays in the current learning library and hides the answer',
    (tester) async {
      final repo = MemoryLearningRepository();
      repo.words = [
        word('main', 'alpha', '主学习'),
        word('extension1', 'beta', '扩展'),
        word('extension2', 'gamma', '扩展'),
      ];
      await extensionList(tester, repo);
      await tester.tap(find.byKey(const ValueKey('word-extension1')));
      await tester.pumpAndSettle();
      await rate(tester);
      await tester.ensureVisible(find.byKey(const Key('next-word')));
      await tester.tap(find.byKey(const Key('next-word')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('review-word'))).data,
        'gamma',
      );
      expect(find.byKey(const Key('meaning')), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(ReviewPage.gradeKey(ReviewGrade.mastered)),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Windows narrow window and 150 percent text keeps reveal, grading and return reachable',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repo = MemoryLearningRepository();
      await openWords(tester, repo);
      await tester.ensureVisible(find.byKey(const ValueKey('word-test-alpha')));
      await tester.tap(find.byKey(const ValueKey('word-test-alpha')));
      await tester.pumpAndSettle();
      await rate(tester);
      await tester.ensureVisible(find.text('返回词库'));
      await tester.tap(find.text('返回词库'));
      await tester.pumpAndSettle();
      expect(repo.events, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
