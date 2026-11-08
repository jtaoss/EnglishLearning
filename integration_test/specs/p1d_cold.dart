import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';

import 'local_learning.dart' show mount;
import 'p1d_common.dart';

void main() {
  testWidgets(
    'P1-D cold learning: fifteen grades and six pronunciation states survive a new process',
    (tester) async {
      final receipt = jsonDecode(
        (await tester.runAsync(
          () => File('$p1dDirectory/learning-result.json').readAsString(),
        ))!,
      ) as Map<String, dynamic>;
      expect(receipt['pid'], isNot(pid));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(p1dDatabase),
      ))!;
      addTearDown(repo.close);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, 100);
      expect(
        (await tester.runAsync(() async => snapshotTables(p1dDatabase)))!,
        receipt['progress_snapshot'],
      );
      for (final row
          in (receipt['ratings'] as List).cast<Map<String, dynamic>>()) {
        final word = words.singleWhere((w) => w.entry.id == row['id']);
        expect(word.status, row['grade']);
        expect(word.dueAt!.toIso8601String(), row['due_at']);
      }
      var selfAssessments = 0;
      for (final word in words) {
        if ((await tester.runAsync(
              () => repo.readPronunciation(word.entry.id),
            ))!.grade !=
            null) {
          selfAssessments++;
        }
      }
      expect(selfAssessments, 6);
      await mount(tester, repo);
      expect(find.byKey(const Key('word-list')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await saveP1d(tester, 'cold-learning-result.json', {
        'previous_pid': receipt['pid'],
        'pid': pid,
        'words': 100,
        'graded_words_restored': 15,
        'pronunciation_self_assessments': selfAssessments,
        'all_progress_and_due_dates_exact': true,
        'offline_list_restored': true,
      });
    },
    skip: p1dDirectory.isEmpty,
  );
}
