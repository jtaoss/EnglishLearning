import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';

import 'local_learning.dart' show mount;

void main() {
  const report = String.fromEnvironment('P1C_RESTART_REPORT');
  testWidgets(
    'fresh Windows process restores Notion cache, local grades and native secure credential',
    (tester) async {
      final data = jsonDecode(
        (await tester.runAsync(() => File(report).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(data['pid'], isNot(pid));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(data['db_path'] as String),
      ))!;
      addTearDown(repo.close);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, 100);
      final word = words.singleWhere((w) => w.entry.id == data['word_id']);
      expect(word.status, 'mastered');
      expect(word.reviewCount, 2);
      expect(word.dueAt, isNotNull);
      expect(
        (await tester.runAsync(() => repo.readPronunciation(word.entry.id)))!
            .grade,
        PronunciationGrade.familiar,
      );
      expect(await tester.runAsync(repo.reviewEventCount), 2);
      expect(
        (await tester.runAsync(() => repo.readNotionState(notionPilotSource)))!
            .linkedWords,
        100,
      );
      final vault = WindowsNotionCredentials(
        testNamespace: data['credential_namespace'] as String,
      );
      final credential = await tester.runAsync(vault.read);
      expect(credential, isNotNull);
      expect(credential!.dataSourceId, notionPilotSource);
      await tester.runAsync(vault.delete);
      expect(await tester.runAsync(vault.read), isNull);
      await mount(tester, repo);
      expect(find.byKey(const Key('word-list')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => File('$report.cold-restart.json').writeAsString(
          jsonEncode({
            'previous_pid': data['pid'],
            'new_pid': pid,
            'words': 100,
            'meaning_events': 2,
            'meaning_status': 'mastered',
            'pronunciation_status': 'familiar',
            'credential_persisted_and_test_key_removed': true,
            'offline_ui_loaded': true,
          }),
          flush: true,
        ),
      );
    },
    skip: report.isEmpty,
  );
}
