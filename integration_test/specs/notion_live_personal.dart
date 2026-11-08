import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/app/open_learning_repository.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import 'local_learning.dart' show waitFor, captureFrame;

Future<void> _waitForSync(WidgetTester tester) async {
  for (var i = 0; i < 600; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byKey(const Key('notion-result')).evaluate().isNotEmpty ||
        find.byKey(const Key('notion-error')).evaluate().isNotEmpty) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  }
  fail('Timed out waiting for live Notion sync result.');
}

Map<String, List<Map<String, Object?>>> _progressSnapshot(String path) {
  final database = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    return {
      for (final table in [
        'learning_progress',
        'review_events',
        'pronunciation_progress',
        'pronunciation_events',
      ])
        table: database
            .select('SELECT * FROM $table ORDER BY 1')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
    };
  } finally {
    database.close();
  }
}

/// Authorized real user cache population; never creates simulated personal grades.
void main() {
  const enabled = bool.fromEnvironment('P1C_POPULATE_PERSONAL');
  const reportDir = String.fromEnvironment('P1C_REPORT_DIR');
  testWidgets(
    'live Notion personal Windows cache sync preserves every existing personal learning record',
    (tester) async {
      final folder = (await tester.runAsync(
        () => Directory(reportDir).create(recursive: true),
      ))!;
      final repo = (await tester.runAsync(openLearningRepository))!;
      addTearDown(repo.close);
      final before = (await tester.runAsync(
        () async => _progressSnapshot(repo.path),
      ))!;
      final oldWords = (await tester.runAsync(repo.readWords))!;
      final oldIds = oldWords.map((word) => word.entry.id).toSet();
      final account = await tester.runAsync(WindowsNotionCredentials().read);
      expect(account, isNotNull);
      expect(account!.dataSourceId, notionPilotSource);
      final client = http.Client();
      addTearDown(client.close);
      final scope = NotionScope(
        await rootBundle.loadString('assets/vocabulary/verified100.csv'),
      );
      final service = NotionSyncService(
        store: repo,
        credentials: WindowsNotionCredentials(),
        api: NotionReadApi(client),
        loadScope: () async => scope,
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('native-capture-root'),
          child: EnglishLearningApp(
            repository: SharedPreferencesSettingsRepository(),
            logger: AppLogger(),
            config: AppConfig.developmentPreset(),
            learningRepository: repo,
            pronunciationServices: PronunciationServices(
              store: repo,
              logger: AppLogger(),
            ),
            notionService: service,
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
      await _waitForSync(tester);
      expect(find.byKey(const Key('notion-error')), findsNothing);
      final firstMessage = tester
          .widget<Text>(find.byKey(const Key('notion-result')))
          .data;
      final firstWords = (await tester.runAsync(repo.readWords))!;
      expect(
        firstWords
            .map((word) => word.entry.id)
            .toSet()
            .containsAll(scope.heads.keys),
        true,
      );
      expect(firstWords.length, oldIds.union(scope.heads.keys.toSet()).length);
      final added = firstWords
          .where((word) => !oldIds.contains(word.entry.id))
          .toList();
      expect(
        added.every(
          (word) =>
              word.status == 'untested' &&
              word.reviewCount == 0 &&
              word.dueAt == null,
        ),
        true,
      );
      for (final word in added) {
        expect(
          (await tester.runAsync(() => repo.readPronunciation(word.entry.id)))!
              .label,
          '未测试',
        );
      }
      await tester.tap(find.byKey(const Key('notion-sync')));
      await _waitForSync(tester);
      expect(find.byKey(const Key('notion-error')), findsNothing);
      final repeatMessage = tester
          .widget<Text>(find.byKey(const Key('notion-result')))
          .data;
      expect(repeatMessage, startsWith('新增 0，更新 0，'));
      final finalWords = (await tester.runAsync(repo.readWords))!;
      expect(finalWords.length, firstWords.length);
      final after = (await tester.runAsync(
        () async => _progressSnapshot(repo.path),
      ))!;
      expect(after['review_events'], before['review_events']);
      expect(after['pronunciation_progress'], before['pronunciation_progress']);
      expect(after['pronunciation_events'], before['pronunciation_events']);
      for (final row in before['learning_progress']!) {
        expect(
          after['learning_progress']!.singleWhere(
            (candidate) => candidate['entry_id'] == row['entry_id'],
          ),
          row,
        );
      }
      final frame = await captureFrame(tester, folder, 'personal-live-synced');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => File('${folder.path}/notion-personal-result.json').writeAsString(
          jsonEncode({
            'evidence_kind': 'live Notion API and actual personal SQLite, driven through Windows UI',
            'pid': pid,
            'db_path': repo.path,
            'before_words': oldWords.length,
            'after_words': finalWords.length,
            'added_untested_words': added.length,
            'first_message': firstMessage,
            'repeat_message': repeatMessage,
            'sample_ids_present': 100,
            'duplicate_ids': 0,
            'existing_progress_preserved': true,
            'synthetic_personal_reviews_created': false,
            'meaning_events_before': before['review_events']!.length,
            'meaning_events_after': after['review_events']!.length,
            'pronunciation_events_before':
                before['pronunciation_events']!.length,
            'pronunciation_events_after': after['pronunciation_events']!.length,
            'frame': frame,
          }),
          flush: true,
        ),
      );
    },
    skip: !enabled || reportDir.isEmpty,
  );
}
