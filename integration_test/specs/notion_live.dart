import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

/// Requires a user-configured read-only credential. No secrets in test arguments.
void main() {
  const enabled = bool.fromEnvironment('P1C_LIVE');
  const reportDir = String.fromEnvironment('P1C_REPORT_DIR');
  testWidgets(
    'live Notion API to isolated Windows SQLite, repeat sync and local state preservation',
    (tester) async {
      final vault = WindowsNotionCredentials();
      expect(
        await tester.runAsync(vault.read),
        isNotNull,
        reason: '请先在程序内保存只读集成凭据。',
      );
      final folder = (await tester.runAsync(
        () => Directory(reportDir).create(recursive: true),
      ))!;
      final dbPath =
          '${folder.path}/notion-live-${DateTime.now().microsecondsSinceEpoch}.sqlite3';
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(dbPath),
      ))!;
      addTearDown(repo.close);
      final client = http.Client();
      addTearDown(client.close);
      final service = NotionSyncService(
        store: repo,
        credentials: vault,
        api: NotionReadApi(client),
        loadScope: () async => NotionScope(
          await rootBundle.loadString('assets/vocabulary/verified100.csv'),
        ),
      );
      final first = (await tester.runAsync(service.sync))!;
      expect(first.inserted, 100);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, 100);
      expect(
        words.every((w) => w.status == 'untested' && w.reviewCount == 0),
        true,
      );
      final big = words.singleWhere((w) => w.entry.word == 'big');
      final at = DateTime.now().toUtc();
      await tester.runAsync(
        () => repo.recordReview(big.entry.id, ReviewGrade.familiar, at),
      );
      await tester.runAsync(
        () => repo.recordPronunciation(
          entryId: big.entry.id,
          grade: PronunciationGrade.familiar,
          audioAssetId: 'p1c-live-preservation-sentinel',
          attemptId: 'live-${at.microsecondsSinceEpoch}',
          at: at,
        ),
      );
      final second = (await tester.runAsync(service.sync))!;
      expect(second.inserted, 0);
      expect(second.updated, 0);
      expect((await tester.runAsync(repo.readWords))!.length, 100);
      final after = (await tester.runAsync(repo.readWords))!
          .singleWhere((w) => w.entry.id == big.entry.id);
      expect(after.reviewCount, 1);
      expect(after.status, 'familiar');
      expect(
        (await tester.runAsync(() => repo.readPronunciation(big.entry.id)))!
            .grade,
        PronunciationGrade.familiar,
      );
      expect(await tester.runAsync(repo.reviewEventCount), 1);
      final checkpoint = (await tester.runAsync(
        () => repo.readNotionState(notionPilotSource),
      ))!;
      await tester.runAsync(
        () => File('${folder.path}/notion-live-result.json').writeAsString(
          jsonEncode({
            'evidence_kind': 'live Notion API with user-saved credential; isolated SQLite; no Notion writes',
            'pid': pid,
            'db_path': dbPath,
            'word_id': big.entry.id,
            'count': 100,
            'first': {
              'inserted': first.inserted,
              'updated': first.updated,
              'unchanged': first.unchanged,
            },
            'repeat': {
              'inserted': second.inserted,
              'updated': second.updated,
              'unchanged': second.unchanged,
            },
            'watermark': checkpoint.watermark?.toIso8601String(),
            'meaning_events': 1,
            'pronunciation_preserved': true,
            'api_version': notionApiVersion,
          }),
          flush: true,
        ),
      );
    },
    skip: !enabled || reportDir.isEmpty,
  );
}
