import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

/// Observes endpoint/method counts only; never logs credentials or payloads.
class _ReadRequests extends http.BaseClient {
  final _client = http.Client();
  int count = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    expect(request.url.host, 'api.notion.com');
    expect(request.url.scheme, 'https');
    expect(
      request.method == 'GET' ||
          (request.method == 'POST' && request.url.path.endsWith('/query')),
      true,
    );
    count++;
    return _client.send(request);
  }

  @override
  void close() => _client.close();
}

void main() {
  const sizeText = String.fromEnvironment('P3_LIVE_SIZE');
  const reportDir = String.fromEnvironment('P3_LIVE_REPORT_DIR');
  const coldReceipt = String.fromEnvironment('P3_LIVE_COLD_REPORT');
  testWidgets(
    'P3 actual Notion read API expansion and idempotency with isolated progress',
    (tester) async {
      final size = int.parse(sizeText);
      expect([200, 500], contains(size));
      final folder = Directory(reportDir);
      await tester.runAsync(() => folder.create(recursive: true));
      final vault = WindowsNotionCredentials();
      final account = await tester.runAsync(vault.read);
      expect(account, isNotNull, reason: '先在程序内安全保存只读配置。');
      expect(account!.dataSourceId, notionPilotSource);
      final csv = await rootBundle.loadString(
        'assets/vocabulary/reviewed500.csv',
      );
      final scope = NotionScope(csv).take(size);
      final expected = {for (final e in scope.entries) e.id: e.fields};
      final previousFile = File('${folder.path}/live-200.json');
      final previous = size == 500
          ? jsonDecode((await tester.runAsync(previousFile.readAsString))!)
                as Map<String, dynamic>
          : null;
      final dbPath =
          previous?['db_path'] as String? ??
          '${folder.path}/live-${DateTime.now().microsecondsSinceEpoch}.sqlite3';
      var repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(dbPath),
      ))!;
      var closed = false;
      addTearDown(() async {
        if (!closed) await repo.close();
      });
      final at = DateTime.utc(2026, 11, 9, 4);
      if (size == 200) {
        final oldCsv = await rootBundle.loadString(
          'assets/vocabulary/verified100.csv',
        );
        await tester.runAsync(() => repo.importCsv(oldCsv));
        final big = (await tester.runAsync(repo.readWords))!
            .singleWhere((w) => w.entry.word == 'big');
        await tester.runAsync(
          () => repo.recordReview(big.entry.id, ReviewGrade.familiar, at),
        );
        await tester.runAsync(
          () => repo.recordPronunciation(
            entryId: big.entry.id,
            grade: PronunciationGrade.familiar,
            audioAssetId: 'p3-isolated-preservation-sentinel',
            attemptId: 'p3-live-preservation',
            at: at,
          ),
        );
      }
      final before = (await tester.runAsync(repo.readWords))!;
      final big = before.singleWhere((w) => w.entry.word == 'big');
      final meaningEvents = (await tester.runAsync(repo.reviewEventCount))!;
      final client = _ReadRequests();
      addTearDown(client.close);
      final service = NotionSyncService(
        store: repo,
        credentials: vault,
        api: NotionReadApi(client),
        loadScope: () async => NotionScope(csv),
      );
      final first = (await tester.runAsync(() => service.sync(limit: size)))!;
      expect(first.inserted, size - before.length);
      Future<void> check() async {
        final words = await repo.readWords();
        expect(words.length, size);
        expect(words.map((w) => w.entry.id).toSet().length, size);
        for (final word in words) {
          expect(
            word.entry.fields,
            expected[word.entry.id],
            reason: word.entry.word,
          );
        }
        final kept = words.singleWhere((w) => w.entry.id == big.entry.id);
        expect(kept.status, big.status);
        expect(kept.reviewCount, big.reviewCount);
        expect(kept.lastReviewedAt, big.lastReviewedAt);
        expect(kept.dueAt, big.dueAt);
        final pronunciation = await repo.readPronunciation(big.entry.id);
        expect(pronunciation.grade, PronunciationGrade.familiar);
        expect(pronunciation.assessedAt, at);
        expect(pronunciation.dueAt, at.add(const Duration(days: 1)));
        expect(await repo.reviewEventCount(), meaningEvents);
        expect(
          (await repo.readNotionState(notionPilotSource)).linkedWords,
          size,
        );
      }

      await tester.runAsync(check);
      final repeat = (await tester.runAsync(
        () => service.sync(full: true, limit: size),
      ))!;
      expect(repeat.inserted, 0);
      expect(repeat.updated, 0);
      expect(repeat.unchanged, size);
      final incremental = (await tester.runAsync(
        () => service.sync(limit: size),
      ))!;
      expect(incremental.inserted, 0);
      expect(incremental.updated, 0);
      await tester.runAsync(check);
      await tester.runAsync(repo.close);
      closed = true;
      repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(dbPath),
      ))!;
      closed = false;
      await tester.runAsync(check);
      await tester.runAsync(
        () => File('${folder.path}/live-$size.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'evidence_kind': 'actual HTTPS Notion API; isolated Windows SQLite',
            'size': size,
            'pid': pid,
            'db_path': dbPath,
            'before_words': before.length,
            'inserted': first.inserted,
            'updated': first.updated,
            'repeat_inserted': repeat.inserted,
            'repeat_updated': repeat.updated,
            'repeat_unchanged': repeat.unchanged,
            'all_content_fields_equal': true,
            'stable_ids_unique': true,
            'meaning_and_pronunciation_preserved': true,
            'meaning_events': meaningEvents,
            'disk_reopen_passed': true,
            'read_api_requests': client.count,
            'cloud_mutations': 0,
            'formal_personal_database_opened': false,
            'real_events_uploaded': 0,
            'api_version': notionApiVersion,
          }),
          flush: true,
        ),
      );
    },
    skip: sizeText.isEmpty || reportDir.isEmpty,
    timeout: const Timeout(Duration(minutes: 4)),
  );
  testWidgets(
    'P3 new process restores actual cloud cache and independent grades offline',
    (tester) async {
      final data = jsonDecode(
        (await tester.runAsync(() => File(coldReceipt).readAsString()))!,
      ) as Map<String, dynamic>;
      expect(data['status'], 'PASS');
      expect(data['pid'], isNot(pid));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(data['db_path'] as String),
      ))!;
      addTearDown(repo.close);
      final words = (await tester.runAsync(repo.readWords))!;
      expect(words.length, data['size']);
      final csv = await rootBundle.loadString(
        'assets/vocabulary/reviewed500.csv',
      );
      final expected = {
        for (final e in VocabularyCsv.parse(csv).take(data['size'] as int))
          e.id: e.fields,
      };
      for (final word in words) {
        expect(word.entry.fields, expected[word.entry.id]);
      }
      final big = words.singleWhere((w) => w.entry.word == 'big');
      expect(big.status, 'familiar');
      expect(big.reviewCount, 1);
      expect(big.dueAt, DateTime.utc(2026, 11, 10, 4));
      expect(
        (await tester.runAsync(() => repo.readPronunciation(big.entry.id)))!
            .grade,
        PronunciationGrade.familiar,
      );
      expect(
        await tester.runAsync(repo.reviewEventCount),
        data['meaning_events'],
      );
      await tester.runAsync(
        () => File('$coldReceipt.cold.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'previous_pid': data['pid'],
            'pid': pid,
            'size': words.length,
            'all_content_fields_equal': true,
            'meaning_and_pronunciation_restored': true,
            'http_requests': 0,
            'formal_personal_database_opened': false,
          }),
          flush: true,
        ),
      );
    },
    skip: coldReceipt.isEmpty,
  );
}
