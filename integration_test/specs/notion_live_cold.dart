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
  const receipt = String.fromEnvironment('P1C_LIVE_RESTART_REPORT');
  testWidgets(
    'fresh live Notion process restores actual API cache and independent learning records',
    (tester) async {
      final data = jsonDecode(
        (await tester.runAsync(() => File(receipt).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(data['evidence_kind'], contains('live Notion API'));
      expect(data['pid'], isNot(pid));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(data['db_path'] as String),
      ))!;
      addTearDown(repo.close);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, 100);
      expect(words.map((w) => w.entry.id).toSet().length, 100);
      final word = words.singleWhere((w) => w.entry.id == data['word_id']);
      expect(word.status, 'familiar');
      expect(word.reviewCount, 1);
      expect(word.dueAt, isNotNull);
      expect(await tester.runAsync(repo.reviewEventCount), 1);
      expect(
        (await tester.runAsync(() => repo.readPronunciation(word.entry.id)))!
            .grade,
        PronunciationGrade.familiar,
      );
      expect(
        (await tester.runAsync(() => repo.readNotionState(notionPilotSource)))!
            .linkedWords,
        100,
      );
      // Read the production key, without changing or deleting it.
      final account = await tester.runAsync(WindowsNotionCredentials().read);
      expect(account, isNotNull);
      expect(account!.dataSourceId, notionPilotSource);
      // No HTTP service is mounted: the list is rendered entirely from disk.
      await mount(tester, repo);
      expect(find.byKey(const Key('word-list')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => File('$receipt.cold-restart.json').writeAsString(
          jsonEncode({
            'previous_pid': data['pid'],
            'new_pid': pid,
            'cached_words': 100,
            'unique_ids': 100,
            'meaning_events': 1,
            'meaning_status': 'familiar',
            'pronunciation_status': 'familiar',
            'production_credential_readable': true,
            'production_credential_modified': false,
            'offline_list_restored_without_http': true,
          }),
          flush: true,
        ),
      );
    },
    skip: receipt.isEmpty,
  );

  const personalReceipt = String.fromEnvironment('P1C_PERSONAL_RESTART_REPORT');
  testWidgets(
    'fresh live Notion personal process restores actual user cache without creating study history',
    (tester) async {
      final data = jsonDecode(
        (await tester.runAsync(() => File(personalReceipt).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(data['pid'], isNot(pid));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(data['db_path'] as String),
      ))!;
      addTearDown(repo.close);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, data['after_words']);
      expect(words.map((word) => word.entry.id).toSet().length, words.length);
      final eventCount = (await tester.runAsync(repo.reviewEventCount))!;
      expect(eventCount, data['meaning_events_after']);
      final state = (await tester.runAsync(
        () => repo.readNotionState(notionPilotSource),
      ))!;
      expect(state.linkedWords, 100);
      final credential = await tester.runAsync(WindowsNotionCredentials().read);
      expect(credential, isNotNull);
      expect(credential!.dataSourceId, notionPilotSource);
      if (data['before_words'] == 0) {
        expect(
          words.every(
            (word) =>
                word.status == 'untested' &&
                word.reviewCount == 0 &&
                word.dueAt == null,
          ),
          true,
        );
      }
      await mount(tester, repo);
      expect(find.byKey(const Key('word-list')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => File('$personalReceipt.cold-restart.json').writeAsString(
          jsonEncode({
            'previous_pid': data['pid'],
            'new_pid': pid,
            'personal_cached_words': words.length,
            'linked_sample_words': state.linkedWords,
            'meaning_events': eventCount,
            'new_sample_words_untested': data['before_words'] == 0
                ? words.every((word) => word.status == 'untested')
                : null,
            'production_credential_readable': true,
            'production_credential_modified': false,
            'offline_list_restored_without_http': true,
          }),
          flush: true,
        ),
      );
    },
    skip: personalReceipt.isEmpty,
  );
}
