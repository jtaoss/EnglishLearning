import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_controller.dart';
import 'package:english_learning/integrations/notion/notion_sync_page.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import 'support.dart';

class WidgetSyncStore implements NotionSyncStore {
  int writes = 0;
  @override
  Future<NotionSyncState> readNotionState(String source) async =>
      NotionSyncState(linkedWords: writes == 0 ? 0 : 100);
  @override
  Future<ImportResult> applyNotionBatch({
    required String sourceId,
    required List<NotionWord> words,
    required DateTime? expectedWatermark,
    required DateTime? watermark,
    required DateTime syncedAt,
  }) async {
    writes++;
    return ImportResult(writes == 1 ? 100 : 0, 0, writes == 1 ? 0 : 100);
  }
}

void main() {
  testWidgets('Android narrow UI locks source and clears secure token input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final credentials = MemoryCredentials();
    final controller = NotionSyncController(
      NotionSyncService(
        store: WidgetSyncStore(),
        credentials: credentials,
        api: NotionReadApi(
          MockClient((_) async => throw StateError('No HTTP expected')),
          delay: noDelay,
        ),
        loadScope: () async => testScope(),
      ),
      refreshVocabulary: () async => true,
      storageLabel: 'Android 系统 Keystore',
      isMobile: true,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: NotionSyncPage(controller: controller)),
    );
    expect(
      tester.widget<TextField>(find.byKey(const Key('notion-source'))).enabled,
      false,
    );
    final token = find.byKey(const Key('notion-token'));
    expect(tester.widget<TextField>(token).obscureText, true);
    expect(
      tester.widget<TextField>(token).enableIMEPersonalizedLearning,
      false,
    );
    await tester.enterText(token, testToken);
    await tester.ensureVisible(find.byKey(const Key('notion-save')));
    await tester.tap(find.byKey(const Key('notion-save')));
    await tester.pumpAndSettle();
    expect(credentials.writes, 1);
    expect(tester.widget<TextField>(token).controller!.text, isEmpty);
    expect(find.text(testToken), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Windows connection UI hides credentials, clears input and blocks duplicate clicks',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final credentials = MemoryCredentials();
      final store = WidgetSyncStore();
      final gate = Completer<void>();
      var queried = 0, refreshed = 0;
      final data = snapshot();
      final service = NotionSyncService(
        store: store,
        credentials: credentials,
        api: NotionReadApi(
          MockClient((request) async {
            if (request.method == 'GET') return jsonResponse(data['schema']);
            queried++;
            await gate.future;
            return jsonResponse(listResponse(data['pages'] as List));
          }),
          delay: noDelay,
        ),
        loadScope: () async => testScope(),
      );
      final controller = NotionSyncController(
        service,
        refreshVocabulary: () async {
          refreshed++;
          return true;
        },
      );
      addTearDown(controller.dispose);
      await controller.restore();
      await tester.pumpWidget(
        MaterialApp(home: NotionSyncPage(controller: controller)),
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('notion-sync')))
            .onPressed,
        isNull,
      );
      final input = find.byKey(const Key('notion-token'));
      expect(tester.widget<TextField>(input).obscureText, true);
      expect(tester.widget<TextField>(input).enableSuggestions, false);
      await tester.enterText(input, testToken);
      await tester.tap(find.byKey(const Key('notion-save')));
      await tester.pumpAndSettle();
      expect(credentials.writes, 1);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.text(testToken), findsNothing);
      expect(find.text('连接凭据：已安全保存'), findsOneWidget);
      await tester.tap(find.byKey(const Key('notion-sync')));
      await tester.pump();
      expect(controller.busy, true);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('notion-sync')))
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(queried, 1);
      expect(store.writes, 1);
      expect(refreshed, 1);
      expect(find.textContaining('新增 100，更新 0，未变 0'), findsOneWidget);
      await tester.tap(find.byKey(const Key('notion-forget')));
      await tester.pumpAndSettle();
      expect(credentials.account, isNull);
      expect(store.writes, 1);
      expect(find.text('连接凭据：尚未配置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid credentials show useful error and never persist the input',
    (tester) async {
      final credentials = MemoryCredentials();
      final controller = NotionSyncController(
        NotionSyncService(
          store: WidgetSyncStore(),
          credentials: credentials,
          api: NotionReadApi(
            MockClient((_) async => throw StateError('no requests expected')),
            delay: noDelay,
          ),
          loadScope: () async => testScope(),
        ),
        refreshVocabulary: () async => true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: NotionSyncPage(controller: controller)),
      );
      await tester.enterText(find.byKey(const Key('notion-token')), 'bad');
      await tester.ensureVisible(find.byKey(const Key('notion-save')));
      await tester.tap(find.byKey(const Key('notion-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notion-error')), findsOneWidget);
      expect(credentials.writes, 0);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('notion-token')))
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
