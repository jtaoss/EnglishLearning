import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import 'local_learning.dart' show captureFrame;
import 'p1d_common.dart';

enum BoundaryFault { none, offline, refused, inaccessibleSource, secondPage }

/// Test-only transport. Forwards credentials only to the original official host.
final class BoundaryClient extends http.BaseClient {
  final http.Client delegate = http.Client();
  final requests = <Map<String, Object?>>[];
  BoundaryFault _fault = BoundaryFault.none;
  int _queries = 0;
  void setFault(BoundaryFault value) {
    _fault = value;
    _queries = 0;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest original) async {
    if (_fault == BoundaryFault.offline) {
      throw const SocketException('P1-D controlled offline');
    }
    if (_fault == BoundaryFault.refused) {
      throw http.ClientException('P1-D controlled connection failure');
    }
    if (original.method == 'POST' &&
        _fault == BoundaryFault.secondPage &&
        ++_queries == 2) {
      throw const SocketException('P1-D failure after one actual API page');
    }
    if (original.url.host != 'api.notion.com' ||
        original.url.scheme != 'https') {
      throw StateError('Unexpected destination');
    }
    final uri =
        _fault == BoundaryFault.inaccessibleSource && original.method == 'GET'
        ? Uri.https(
            'api.notion.com',
            '/v1/data_sources/11111111-1111-4111-8111-111111111111',
          )
        : original.url;
    final forward = http.Request(original.method, uri)
      ..followRedirects = false
      ..headers.addAll(original.headers);
    final record = <String, Object?>{
      'method': original.method,
      'fault': _fault.name,
    };
    if (original is http.Request && original.method == 'POST') {
      final body = jsonDecode(original.body) as Map<String, dynamic>;
      if (_fault == BoundaryFault.secondPage) body['page_size'] = 5;
      forward.body = jsonEncode(body);
      record['page_size'] = body['page_size'];
      record['cursor_present'] = body['start_cursor'] != null;
      record['incremental_filter'] =
          ((body['filter'] as Map)['and'] as List?)
              ?.whereType<Map<dynamic, dynamic>>()
              .any((f) => f['timestamp'] == 'last_edited_time') ??
          false;
    }
    final response = await delegate.send(forward);
    final bytes = await response.stream.toBytes();
    record['status'] = response.statusCode;
    if (original.method == 'POST' && response.statusCode == 200) {
      final json = jsonDecode(utf8.decode(bytes)) as Map;
      record['returned_rows'] = (json['results'] as List).length;
      record['has_more'] = json['has_more'];
    }
    requests.add(record); // No headers, tokens, raw request or response bodies.
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      response.statusCode,
      headers: response.headers,
      contentLength: bytes.length,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => delegate.close();
}

Future<void> syncThroughPage(
  WidgetTester tester, {
  bool full = false,
  bool error = false,
}) async {
  final key = full ? 'notion-full-sync' : 'notion-sync';
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await waitP1d(
    tester,
    find.byKey(Key(error ? 'notion-error' : 'notion-result')),
  );
  await tester.pumpAndSettle();
}

void main() {
  const marker = String.fromEnvironment('P1D_MARKER');
  testWidgets(
    'P1-D live sync: actual remote edit, protected grades and failure recovery',
    (tester) async {
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(p1dDatabase),
      ))!;
      addTearDown(repo.close);
      final before = (await tester.runAsync(
        () async => snapshotTables(p1dDatabase),
      ))!;
      final originalBig = (await tester.runAsync(repo.readWords))!
          .singleWhere((w) => w.entry.word == 'big');
      final client = BoundaryClient();
      addTearDown(client.close);
      final service = NotionSyncService(
        store: repo,
        credentials: WindowsNotionCredentials(),
        api: NotionReadApi(client),
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-notion-sync')));
      await tester.pumpAndSettle();
      await waitP1d(tester, find.text('连接凭据：已安全保存'));
      var updated = false;
      for (var attempt = 0; attempt < 4 && !updated; attempt++) {
        await syncThroughPage(tester);
        final big = (await tester.runAsync(repo.readWords))!
            .singleWhere((w) => w.entry.word == 'big');
        updated = big.entry.fields['usage_note']!.contains(marker);
        if (!updated) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 2)),
          );
        }
      }
      expect(
        updated,
        true,
        reason: 'Actual remote marker did not arrive through the API',
      );
      final updateMessage = tester
          .widget<Text>(find.byKey(const Key('notion-result')))
          .data;
      expect(updateMessage, startsWith('新增 0，更新 1，'));
      expect(
        (await tester.runAsync(() async => snapshotTables(p1dDatabase)))!,
        before,
      );
      final changed = (await tester.runAsync(repo.readWords))!
          .singleWhere((w) => w.entry.word == 'big');
      expect(changed.entry.id, originalBig.entry.id);
      expect(changed.dueAt, originalBig.dueAt);
      await syncThroughPage(tester);
      final repeated = tester
          .widget<Text>(find.byKey(const Key('notion-result')))
          .data;
      expect(repeated, startsWith('新增 0，更新 0，'));
      final frame = await captureFrame(
        tester,
        Directory(p1dDirectory),
        'live-content-updated',
      );
      final errors = <Map<String, Object?>>[];
      for (final fault in [
        BoundaryFault.offline,
        BoundaryFault.refused,
        BoundaryFault.inaccessibleSource,
        BoundaryFault.secondPage,
      ]) {
        final allBefore = (await tester.runAsync(
          () async => snapshotTables(p1dDatabase, all: true),
        ))!;
        client.setFault(fault);
        await syncThroughPage(
          tester,
          full: fault == BoundaryFault.secondPage,
          error: true,
        );
        final text = tester
            .widget<Text>(find.byKey(const Key('notion-error')))
            .data;
        expect(
          (await tester.runAsync(
            () async => snapshotTables(p1dDatabase, all: true),
          ))!,
          allBefore,
        );
        errors.add({
          'mode': fault.name,
          'message': text,
          'all_tables_and_watermark_unchanged': true,
          'evidence': fault == BoundaryFault.inaccessibleSource
              ? 'actual official API 404'
              : fault == BoundaryFault.secondPage
              ? 'actual first page then injected SocketException'
              : 'controlled transport exception',
        });
      }
      // An ordinary card can still be revealed while transport failure is active.
      client.setFault(BoundaryFault.offline);
      final beforeLocalView = client.requests.length;
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openListWord(tester, originalBig.entry.id);
      expect(find.byKey(const Key('meaning')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('reveal-answer')));
      await tester.tap(find.byKey(const Key('reveal-answer')));
      await tester.pumpAndSettle();
      expect(find.text(originalBig.entry.meaning), findsOneWidget);
      expect(client.requests.length, beforeLocalView);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('open-notion-sync')));
      await tester.tap(find.byKey(const Key('open-notion-sync')));
      await tester.pumpAndSettle();
      client.setFault(BoundaryFault.none);
      await syncThroughPage(tester);
      expect(
        tester.widget<Text>(find.byKey(const Key('notion-result'))).data,
        startsWith('新增 0，更新 0，'),
      );
      expect((await tester.runAsync(repo.readWords))!.length, 100);
      expect(
        (await tester.runAsync(() async => snapshotTables(p1dDatabase)))!,
        before,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await saveP1d(tester, 'live-sync-result.json', {
        'pid': pid,
        'marker': marker,
        'update_message': updateMessage,
        'repeat_message': repeated,
        'word_id': originalBig.entry.id,
        'meaning_status_preserved': originalBig.status,
        'due_utc_preserved': originalBig.dueAt?.toIso8601String(),
        'all_four_progress_tables_exact': true,
        'words': 100,
        'offline_card_reveal': true,
        'failures': errors,
        'requests': client.requests,
        'frame': frame,
        'original_big_content': originalBig.entry.fields,
        'progress_snapshot': before,
      });
    },
    skip: p1dDirectory.isEmpty || marker.isEmpty,
  );

  const restore = bool.fromEnvironment('P1D_RESTORE');
  testWidgets(
    'P1-D restore: original cloud content returns without changing practice records',
    (tester) async {
      final receipt = jsonDecode(
        (await tester.runAsync(
          () => File('$p1dDirectory/live-sync-result.json').readAsString(),
        ))!,
      ) as Map<String, dynamic>;
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.open(p1dDatabase),
      ))!;
      addTearDown(repo.close);
      final client = BoundaryClient();
      addTearDown(client.close);
      final service = NotionSyncService(
        store: repo,
        credentials: WindowsNotionCredentials(),
        api: NotionReadApi(client),
        loadScope: () async => NotionScope(
          await rootBundle.loadString('assets/vocabulary/verified100.csv'),
        ),
      );
      var restored = false;
      final outcomes = <String>[];
      for (var attempt = 0; attempt < 4 && !restored; attempt++) {
        outcomes.add((await tester.runAsync(service.sync))!.message);
        final big = (await tester.runAsync(repo.readWords))!
            .singleWhere((w) => w.entry.id == receipt['word_id']);
        restored =
            jsonEncode(big.entry.fields) ==
            jsonEncode(receipt['original_big_content']);
        if (!restored) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(seconds: 2)),
          );
        }
      }
      expect(restored, true);
      expect(
        (await tester.runAsync(() async => snapshotTables(p1dDatabase)))!,
        receipt['progress_snapshot'],
      );
      expect((await tester.runAsync(repo.readWords))!.length, 100);
      await saveP1d(tester, 'restore-result.json', {
        'pid': pid,
        'previous_pid': receipt['pid'],
        'original_content_restored': true,
        'four_progress_tables_preserved': true,
        'words': 100,
        'outcomes': outcomes,
        'requests': client.requests,
      });
    },
    skip: p1dDirectory.isEmpty || !restore,
  );
}
