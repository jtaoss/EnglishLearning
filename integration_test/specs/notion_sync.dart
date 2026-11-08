import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import 'local_learning.dart' show waitFor, captureFrame;

const fixtureCredential = 'ntn_native_fixture_not_a_real_credential';

void main() {
  const snapshotPath = String.fromEnvironment('P1C_SNAPSHOT_PATH');
  const reportDir = String.fromEnvironment('P1C_REPORT_DIR');
  testWidgets(
    'Windows Notion cloud-content replay: secure vault, repeat sync, offline review and persistence',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory(reportDir).create(recursive: true),
      ))!;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final path = '${directory.path}/notion-$stamp.sqlite3';
      final namespace = 'p1c-$stamp';
      final vault = WindowsNotionCredentials(testNamespace: namespace);
      await tester.runAsync(
        () => vault.save(
          NotionAccount(
            dataSourceId: notionPilotSource,
            token: fixtureCredential,
          ),
        ),
      );
      expect((await tester.runAsync(vault.read))!.token, fixtureCredential);
      final data = jsonDecode(
        (await tester.runAsync(() => File(snapshotPath).readAsString()))!,
      ) as Map<String, dynamic>;
      final pages = data['pages'] as List;
      var offline = false, requests = 0;
      final client = MockClient((request) async {
        requests++;
        if (offline) throw http.ClientException('offline acceptance probe');
        final Object? body;
        if (request.method == 'GET') {
          body = data['schema'];
        } else {
          final query = jsonDecode(request.body) as Map;
          final first = query['start_cursor'] == null;
          body = {
            'object': 'list',
            'results': first
                ? pages.take(55).toList()
                : pages.skip(55).toList(),
            'has_more': first,
            'next_cursor': first ? 'next' : null,
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(path),
      ))!;
      addTearDown(repo.close);
      final service = NotionSyncService(
        store: repo,
        credentials: vault,
        api: NotionReadApi(client, delay: (_) async {}),
        loadScope: () async => NotionScope(
          await rootBundle.loadString('assets/vocabulary/verified100.csv'),
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('native-capture-root'),
          child: EnglishLearningApp(
            repository: SharedPreferencesSettingsRepository(),
            logger: AppLogger(),
            config: AppConfig.developmentPreset(),
            learningRepository: repo,
            notionService: service,
            pronunciationServices: PronunciationServices(
              store: repo,
              logger: AppLogger(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-notion-sync')));
      await tester.pumpAndSettle();
      await waitFor(tester, find.text('连接凭据：已安全保存'));
      await tester.tap(find.byKey(const Key('notion-sync')));
      await waitFor(tester, find.textContaining('新增 100，更新 0，未变 0'));
      expect((await tester.runAsync(repo.readWords))!.length, 100);
      await tester.tap(find.byKey(const Key('notion-sync')));
      await waitFor(tester, find.textContaining('新增 0，更新 0，未变 100'));
      final screenshot = await captureFrame(
        tester,
        directory,
        'notion-repeat-$stamp',
      );
      final words = (await tester.runAsync(repo.readWords))!;
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
          audioAssetId: 'p1c-preservation-sentinel',
          attemptId: 'p1c-sentinel-$stamp',
          at: at,
        ),
      );
      await tester.runAsync(service.sync);
      expect((await tester.runAsync(repo.reviewEventCount)), 1);
      expect(
        (await tester.runAsync(() => repo.readPronunciation(big.entry.id)))!
            .grade,
        PronunciationGrade.familiar,
      );
      offline = true;
      await tester.tap(find.byKey(const Key('notion-sync')));
      await waitFor(tester, find.byKey(const Key('notion-error')));
      expect(find.textContaining('可离线继续学习'), findsOneWidget);
      expect((await tester.runAsync(repo.readWords))!.length, 100);
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Learn an existing word using only cached SQLite after the network fails.
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('word-${big.entry.id}')),
        100,
        scrollable: find.descendant(
          of: find.byKey(const Key('word-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(ValueKey('word-${big.entry.id}')));
      await tester.pumpAndSettle();
      expect(find.text(big.entry.meaning), findsNothing);
      final reveal = find.byKey(const Key('reveal-answer'));
      await tester.ensureVisible(reveal);
      await tester.tap(reveal);
      await tester.pumpAndSettle();
      expect(find.text(big.entry.meaning), findsOneWidget);
      final grade = find.byKey(const Key('grade-mastered'));
      await tester.ensureVisible(grade);
      await tester.tap(grade);
      await waitFor(tester, find.byKey(const Key('review-saved')));
      expect((await tester.runAsync(repo.reviewEventCount)), 2);
      final finalWords = (await tester.runAsync(repo.readWords))!;
      final current = finalWords.singleWhere((w) => w.entry.id == big.entry.id);
      expect(current.reviewCount, 2);
      expect(
        (await tester.runAsync(() => repo.readPronunciation(big.entry.id)))!
            .grade,
        PronunciationGrade.familiar,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => File('${directory.path}/notion-replay-result.json').writeAsString(
          jsonEncode({
            'evidence_kind': 'real Windows, native credential manager and SQLite; authenticated cloud content replayed through simulated HTTP; not live Notion API',
            'pid': pid,
            'db_path': path,
            'credential_namespace': namespace,
            'word_id': big.entry.id,
            'count': finalWords.length,
            'requests': requests,
            'repeat_no_duplicates': true,
            'meaning_events': 2,
            'pronunciation_preserved': true,
            'offline_ui_learning': true,
            'frame': screenshot,
          }),
          flush: true,
        ),
      );
    },
    skip: snapshotPath.isEmpty || reportDir.isEmpty,
  );
}
