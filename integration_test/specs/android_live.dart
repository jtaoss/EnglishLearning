import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/pronunciation/pronunciation_services.dart';
import 'package:english_learning/features/pronunciation/local_audio_cache.dart';
import 'package:english_learning/features/pronunciation/pronunciation_content.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/features/pronunciation/pronunciation_session.dart';
import 'package:english_learning/integrations/notion/android_notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import '../../test/support/portable_notion_fixture.dart';
import 'pronunciation.dart' show OfflineTestBundle;

const mobileEnabled = bool.fromEnvironment('ANDROID_ACCEPTANCE');
const fixtureToken = 'fixture_android_keystore_not_a_real_token';
const namespace = 'phone_acceptance_v1';
Future<String> mobileRoot() async =>
    '${(await getApplicationSupportDirectory()).path}/device_acceptance';
Future<void> mobileReport(String name, Object value) async {
  final folder = Directory(await mobileRoot());
  await folder.create(recursive: true);
  await File('${folder.path}/$name')
      .writeAsString(jsonEncode(value), flush: true);
}

Future<void> mobileWait(WidgetTester tester, Finder finder) async {
  for (var n = 0; n < 2400; n++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('Bounded Android UI wait');
}

void main() {
  testWidgets(
    'Android live lifecycle: actual Home and foreground preserve cached learning',
    (tester) async {
      expect(
        (await tester.runAsync(
          () =>
              AndroidNotionCredentials.channel.invokeMethod<String>('package'),
        ))!,
        'dev.personal.englishlearning.acceptance',
      );
      final root = (await tester.runAsync(mobileRoot))!;
      final previous = jsonDecode(
        (await tester.runAsync(
          () => File('$root/live-result.json').readAsString(),
        ))!,
      ) as Map;
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(previous['database'] as String),
      ))!;
      addTearDown(repo.close);
      await tester.pumpWidget(
        EnglishLearningApp(
          repository: SharedPreferencesSettingsRepository(),
          logger: AppLogger(),
          config: AppConfig.developmentPreset(),
          learningRepository: repo,
          notionMobile: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await mobileWait(tester, find.text('共 100 词 · 当前 86 词'));
      await tester.runAsync(
        () => mobileReport('lifecycle-ready.json', {'pid': pid}),
      );
      await tester.runAsync(() async {
        final ack = File('$root/lifecycle-$pid.ack');
        for (var n = 0; n < 1200 && !await ack.exists(); n++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          await ack.exists(),
          true,
          reason: 'Requires actual external ADB Home/foreground actions',
        );
      });
      await mobileWait(tester, find.text('共 100 词 · 当前 86 词'));
      expect((await tester.runAsync(repo.readWords))!.length, 100);
      expect((await tester.runAsync(repo.reviewEventCount))!, 3);
      expect(find.byKey(const Key('import-csv-file')), findsNothing);
      await tester.runAsync(
        () => mobileReport('lifecycle-result.json', {
          'pid': pid,
          'external_home_and_foreground_acknowledged': true,
          'cached_words': 100,
          'meaning_events': 3,
          'mobile_csv_ui_absent': true,
        }),
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: !mobileEnabled,
  );

  testWidgets(
    'Android live edges: native stop, refused socket and mobile sync-only UI',
    (tester) async {
      expect(
        (await tester.runAsync(
          () =>
              AndroidNotionCredentials.channel.invokeMethod<String>('package'),
        ))!,
        'dev.personal.englishlearning.acceptance',
      );
      final root = (await tester.runAsync(mobileRoot))!;
      final receipt = jsonDecode(
        (await tester.runAsync(
          () => File('$root/live-result.json').readAsString(),
        ))!,
      ) as Map;
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(receipt['database'] as String),
      ))!;
      addTearDown(repo.close);
      final before = (await tester.runAsync(repo.readWords))!
          .map(
            (w) => [
              w.entry.id,
              w.status,
              w.reviewCount,
              w.dueAt?.toIso8601String(),
            ],
          )
          .toList();
      final services = PronunciationServices(store: repo, logger: AppLogger());
      final catalog = (await tester.runAsync(services.catalog))!;
      final content = catalog.entries.values.first;
      final session = (await tester.runAsync(
        () => services.open(content.id, content.word),
      ))!;
      session.confirmReading();
      await tester.runAsync(() async {
        final playing = session.play();
        for (
          var n = 0;
          n < 200 && session.phase != PlaybackPhase.playing;
          n++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(session.phase, PlaybackPhase.playing);
        await session.stop();
        await playing;
        expect(session.phase, PlaybackPhase.stopped);
        expect(session.canAssess, false);
      });
      session.dispose();
      final csv = await rootBundle.loadString(
        'assets/vocabulary/verified100.csv',
      );
      final creds = AndroidNotionCredentials(testNamespace: 'network_edges');
      await tester.runAsync(
        () => creds.save(
          NotionAccount(dataSourceId: notionPilotSource, token: fixtureToken),
        ),
      );
      addTearDown(creds.delete);
      final sockets = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:9';
      final client = IOClient(sockets);
      addTearDown(client.close);
      final sync = NotionSyncService(
        store: repo,
        credentials: creds,
        api: NotionReadApi(
          client,
          timeout: const Duration(seconds: 3),
          delay: (_) async {},
        ),
        loadScope: () async => NotionScope(csv),
      );
      await tester.runAsync(() async {
        await expectLater(sync.sync(), throwsA(isA<NotionFailure>()));
      });
      await tester.pumpWidget(
        EnglishLearningApp(
          repository: SharedPreferencesSettingsRepository(),
          logger: AppLogger(),
          config: AppConfig.developmentPreset(),
          learningRepository: repo,
          pronunciationServices: services,
          notionMobile: true,
          notionService: sync,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('import-csv-file')), findsNothing);
      expect(find.byKey(const Key('import-verified100')), findsNothing);
      await tester.ensureVisible(find.text('Notion 只读同步'));
      await tester.tap(find.text('Notion 只读同步'));
      await tester.pump(const Duration(milliseconds: 300));
      await mobileWait(tester, find.text('连接凭据：已安全保存'));
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('notion-source')))
            .enabled,
        false,
      );
      await tester.ensureVisible(find.byKey(const Key('notion-sync')));
      await tester.tap(find.byKey(const Key('notion-sync')));
      await mobileWait(tester, find.byKey(const Key('notion-error')));
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        (await tester.runAsync(repo.readWords))!
            .map(
              (w) => [
                w.entry.id,
                w.status,
                w.reviewCount,
                w.dueAt?.toIso8601String(),
              ],
            )
            .toList(),
        before,
      );
      await tester.runAsync(
        () => mobileReport('edge-result.json', {
          'native_player_started_then_stopped': true,
          'actual_socket_connection_failure':
              'loopback proxy port 9; Wi-Fi not disabled',
          'manual_csv_ui_absent': true,
          'readonly_sync_error_ui': true,
          'all_meaning_ratings_and_dates_preserved': true,
          'physical_network_disconnect': false,
        }),
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: !mobileEnabled,
  );

  testWidgets(
    'Android live acceptance: Keystore, 100 words, native six audio and isolated read-only sync',
    (tester) async {
      final package = (await tester.runAsync(
        () => AndroidNotionCredentials.channel.invokeMethod<String>('package'),
      ))!;
      expect(package, 'dev.personal.englishlearning.acceptance');
      final root = (await tester.runAsync(mobileRoot))!;
      await tester.runAsync(() => Directory(root).create(recursive: true));
      final creds = AndroidNotionCredentials(testNamespace: namespace);
      await tester.runAsync(creds.delete);
      await tester.runAsync(
        () => creds.save(
          NotionAccount(dataSourceId: notionPilotSource, token: fixtureToken),
        ),
      );
      expect((await tester.runAsync(creds.read))!.token, fixtureToken);
      final inspection = (await tester.runAsync(
        () => AndroidNotionCredentials.channel.invokeMapMethod<String, Object?>(
          'test_inspect',
          {'test_namespace': namespace, 'probe': fixtureToken},
        ),
      ))!;
      expect(inspection['plaintext_absent'], true);
      expect(inspection['key_non_exportable'], true);
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(
          '$root/phone-${DateTime.now().microsecondsSinceEpoch}.sqlite3',
        ),
      ))!;
      addTearDown(repo.close);
      final csv = await rootBundle.loadString(
        'assets/vocabulary/verified100.csv',
      );
      final audioBundle = OfflineTestBundle();
      final services = PronunciationServices(
        store: repo,
        logger: AppLogger(),
        cache: LocalAudioCache(bundle: audioBundle),
      );
      await tester.pumpWidget(
        EnglishLearningApp(
          repository: SharedPreferencesSettingsRepository(),
          logger: AppLogger(),
          config: AppConfig.developmentPreset(),
          learningRepository: repo,
          pronunciationServices: services,
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.byKey(const Key('import-verified100')));
      // Import uses the existing UI key; lookup by its stable visible label if needed.
      await tester.tap(find.text('导入 100 词样本'));
      await mobileWait(tester, find.text('新增 100，更新 0，未变 0'));
      await tester.tap(find.text('导入 100 词样本'));
      await mobileWait(tester, find.text('新增 0，更新 0，未变 100'));
      final words = (await tester.runAsync(repo.readWords))!
          .where((w) => w.entry.libraryClass == '主学习')
          .take(3)
          .toList();
      for (var i = 0; i < 3; i++) {
        final tile = find.byKey(ValueKey('word-${words[i].entry.id}'));
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const Key('meaning')), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('reveal-answer')));
        await tester.tap(find.byKey(const Key('reveal-answer')));
        await tester.pump();
        final grade = find.byKey(
          ValueKey('grade-${ReviewGrade.values[i].name}'),
        );
        await tester.ensureVisible(grade);
        await tester.tap(grade);
        await mobileWait(tester, find.byKey(const Key('review-saved')));
        await tester.ensureVisible(find.text('返回词库'));
        await tester.tap(find.text('返回词库'));
        await tester.pump(const Duration(milliseconds: 400));
      }
      final meaningBefore = (await tester.runAsync(repo.readWords))!
          .map(
            (w) => [
              w.entry.id,
              w.status,
              w.reviewCount,
              w.dueAt?.toIso8601String(),
            ],
          )
          .toList();
      await tester.ensureVisible(find.byKey(const Key('open-pronunciation')));
      await tester.tap(find.byKey(const Key('open-pronunciation')));
      await tester.pump(const Duration(milliseconds: 400));
      final catalog = (await tester.runAsync(services.catalog))!;
      final playback = <String>[];
      for (final c in catalog.entries.values) {
        final row = find.byKey(ValueKey('pronunciation-word-${c.id}'));
        await tester.ensureVisible(row);
        await tester.tap(row);
        await tester.pump(const Duration(milliseconds: 300));
        await mobileWait(tester, find.byKey(const Key('confirm-self-reading')));
        await tester.ensureVisible(
          find.byKey(const Key('confirm-self-reading')),
        );
        await tester.tap(find.byKey(const Key('confirm-self-reading')));
        await tester.pump();
        for (var n = 0; n < (c.word == 'tree' ? 2 : 1); n++) {
          await tester.ensureVisible(
            find.byKey(const Key('play-pronunciation')),
          );
          await tester.tap(find.byKey(const Key('play-pronunciation')));
          await mobileWait(tester, find.text('播放完成，请对照后自评'));
          playback.add('${c.word}-$n');
          if (c.word == 'tree') audioBundle.unavailable = true;
        }
        audioBundle.unavailable = false;
        await tester.ensureVisible(
          find.byKey(const ValueKey('pronunciation-grade-familiar')),
        );
        await tester.tap(
          find.byKey(const ValueKey('pronunciation-grade-familiar')),
        );
        await mobileWait(tester, find.byKey(const Key('pronunciation-saved')));
        await tester.pageBack();
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(
        (await tester.runAsync(repo.readWords))!
            .map(
              (w) => [
                w.entry.id,
                w.status,
                w.reviewCount,
                w.dueAt?.toIso8601String(),
              ],
            )
            .toList(),
        meaningBefore,
      );
      var offline = false;
      var queries = 0;
      final pages = mobilePages(NotionScope(csv).entries);
      final client = MockClient((request) async {
        expect(request.url.host, 'api.notion.com');
        expect(request.followRedirects, false);
        if (offline) {
          throw const SocketException('controlled transport offline');
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode(mobileSchema()),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(request.url.path, '/v1/data_sources/$notionPilotSource/query');
        queries++;
        return http.Response(
          jsonEncode({
            'object': 'list',
            'results': pages,
            'has_more': false,
            'next_cursor': null,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final sync = NotionSyncService(
        store: repo,
        credentials: creds,
        api: NotionReadApi(client, delay: (_) async {}),
        loadScope: () async => NotionScope(csv),
      );
      await tester.runAsync(sync.sync);
      await tester.runAsync(sync.sync);
      offline = true;
      await tester.runAsync(() async {
        try {
          await sync.sync();
          fail('Expected offline');
        } on NotionFailure {
          /* Controlled fixture transport. */
        }
      });
      offline = false;
      await tester.runAsync(sync.sync);
      expect((await tester.runAsync(repo.readWords))!.length, 100);
      expect(
        (await tester.runAsync(repo.readWords))!
            .map(
              (w) => [
                w.entry.id,
                w.status,
                w.reviewCount,
                w.dueAt?.toIso8601String(),
              ],
            )
            .toList(),
        meaningBefore,
      );
      await tester.runAsync(
        () => mobileReport('live-result.json', {
          'platform': Platform.operatingSystem,
          'pid': pid,
          'database': repo.path,
          'isolated_package': package,
          'words': 100,
          'meaning_reviews': 3,
          'audio_native_completed': playback,
          'cached_tree_replay_with_asset_source_unavailable': true,
          'pronunciation_self_assessments': 6,
          'meaning_and_due_dates_preserved': true,
          'keystore': inspection,
          'readonly_sync': 'synthetic HTTP fixture on physical Android',
          'query_count': queries,
          'no_real_token_used': true,
          'offline_transport':
              'injected SocketException; not physical disconnection',
        }),
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: !mobileEnabled,
  );

  testWidgets(
    'Android live cold: learning and Keystore survive actual process replacement',
    (tester) async {
      expect(
        (await tester.runAsync(
          () =>
              AndroidNotionCredentials.channel.invokeMethod<String>('package'),
        ))!,
        'dev.personal.englishlearning.acceptance',
      );
      final root = (await tester.runAsync(mobileRoot))!;
      final previous = jsonDecode(
        (await tester.runAsync(
          () => File('$root/live-result.json').readAsString(),
        ))!,
      ) as Map;
      expect(pid, isNot(previous['pid']));
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(previous['database'] as String),
      ))!;
      addTearDown(repo.close);
      final rows = (await tester.runAsync(repo.readWords))!;
      expect(rows.length, 100);
      expect(rows.where((w) => w.reviewCount == 1).length, 3);
      expect((await tester.runAsync(repo.reviewEventCount))!, 3);
      final catalog = (await tester.runAsync(PronunciationCatalog.load))!;
      for (final id in catalog.entries.keys) {
        final progress = (await tester.runAsync(
          () => repo.readPronunciation(id),
        ))!;
        expect(progress.grade, PronunciationGrade.familiar);
        expect(progress.assessedAt, isNotNull);
      }
      final creds = AndroidNotionCredentials(testNamespace: namespace);
      expect((await tester.runAsync(creds.read))!.token, fixtureToken);
      await tester.runAsync(
        () => AndroidNotionCredentials.channel.invokeMethod<void>(
          'test_corrupt',
          {'test_namespace': namespace},
        ),
      );
      await tester.runAsync(() async {
        try {
          await creds.read();
          fail('Corruption must fail closed');
        } on NotionFailure {
          /* No plaintext fallback. */
        }
      });
      await tester.runAsync(creds.delete);
      await tester.runAsync(
        () => mobileReport('cold-result.json', {
          'pid': pid,
          'previous_pid': previous['pid'],
          'words': 100,
          'meaning_events': 3,
          'pronunciation_states_restored': 6,
          'keystore_restored': true,
          'corruption_rejected': true,
          'test_credential_deleted': true,
        }),
      );
    },
    skip: !mobileEnabled,
  );
}
