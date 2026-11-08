import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/vocabulary/vocabulary_page.dart';

import 'local_learning.dart' show mount, waitFor;

void main() {
  const source = String.fromEnvironment('RESTART_SOURCE_REPORT');
  testWidgets(
    'cold native process restart preserves studied word and due date',
    (tester) async {
      final previous = jsonDecode(
        (await tester.runAsync(() => File(source).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(pid, isNot(previous['native_process_id']));
      final repository = (await tester.runAsync(
        () => SqliteLearningRepository.open(previous['database'] as String),
      ))!;
      addTearDown(repository.close);
      final words = (await tester.runAsync(repository.readWords))!;
      final target = words.singleWhere(
        (w) => w.entry.id == previous['persisted_stable_id'],
      );
      expect(words.length, 100);
      expect(target.status, previous['persisted_status']);
      expect(target.dueAt!.toIso8601String(), previous['persisted_due_utc']);
      await mount(tester, repository);
      await tester.tap(find.byKey(ValueKey('word-${target.entry.id}')));
      await tester.pumpAndSettle();
      expect(find.text('词义学习：眼熟'), findsOneWidget);
      expect(target.pronunciationStatus, '未测试');
      expect(find.byKey(const Key('persisted-due')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(VocabularyPage.sampleImportKey));
      await waitFor(tester, find.text('新增 0，更新 0，未变 100'));
      expect(await tester.runAsync(repository.reviewEventCount), 1);
      await tester.runAsync(
        () => File('$source.cold-restart.json').writeAsString(
          jsonEncode({
            'native_process_id': pid,
            'previous_process_id': previous['native_process_id'],
            'different_native_process': true,
            'words': 100,
            'status': target.status,
            'due_utc': target.dueAt!.toIso8601String(),
            'due_visible_after_restart': true,
            'events_after_reimport': 1,
            'personal_database_used': false,
          }),
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    skip: source.isEmpty,
  );
}
