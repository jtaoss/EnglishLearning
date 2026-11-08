import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_page.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';

import 'local_learning.dart' show waitFor;

void main() {
  const source = String.fromEnvironment('P1B_RESTART_REPORT');
  testWidgets(
    'fresh native pronunciation process restores self-assessments without changing meaning progress',
    (tester) async {
      final report = jsonDecode(
        (await tester.runAsync(() => File(source).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(report['pid'], isNot(pid));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(report['db_path'] as String),
      ))!;
      addTearDown(repo.close);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, 6);
      expect(
        words.every(
          (w) =>
              w.status == 'untested' && w.reviewCount == 0 && w.dueAt == null,
        ),
        true,
      );
      for (final id in (report['word_ids'] as List).cast<String>()) {
        expect(
          (await tester.runAsync(() => repo.readPronunciation(id)))!.grade,
          PronunciationGrade.familiar,
        );
      }
      expect(await tester.runAsync(repo.reviewEventCount), 0);
      final word = words.first;
      await tester.pumpWidget(
        MaterialApp(
          home: PronunciationPage(
            entryId: word.entry.id,
            word: word.entry.word,
            services: PronunciationServices(store: repo, logger: AppLogger()),
          ),
        ),
      );
      await waitFor(tester, find.text('发音自评：基本会读'));
      expect(find.byKey(const Key('confirm-self-reading')), findsOneWidget);
      expect(find.byKey(const Key('phonics-note')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => File('$source.cold-restart.json').writeAsString(
          jsonEncode({
            'previous_pid': report['pid'],
            'new_pid': pid,
            'six_self_assessments_restored': true,
            'meaning_statuses_untested': true,
            'meaning_review_events': 0,
            'ui_status_restored': true,
          }),
          flush: true,
        ),
      );
    },
    skip: source.isEmpty,
  );
}
