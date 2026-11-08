import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:english_learning/integrations/notion/events/event_api.dart';
import 'package:english_learning/integrations/notion/events/event_model.dart';
import 'package:english_learning/integrations/notion/events/event_store.dart';
import 'package:english_learning/integrations/notion/events/event_sandbox_controller.dart';
import 'package:english_learning/integrations/notion/events/event_sandbox_page.dart';

import '../p1c/support.dart' show MemoryCredentials, testToken, noDelay;
import 'event_sync_test.dart' show EventServer;

/// UI-state double only. Disk durability/locking use real SQLite in protocol/native tests.
class UiQueue implements EventQueueStore {
  final rows = <String, QueuedEvent>{};
  Completer<void>? hold;
  @override
  String get path => 'unused-ui-double';
  @override
  Future<void> enqueue(List<LearningEvent> events) async {
    if (hold != null) await hold!.future;
    for (final e in events) {
      rows.putIfAbsent(e.id, () => QueuedEvent(e, 'pending', null, 0, null));
    }
  }

  @override
  Future<List<QueuedEvent>> read() async => rows.values.toList();
  @override
  Future<void> close() async {}
  @override
  Future<DateTime?> deferredUntil() async => null;
  @override
  Future<void> deferUntil(DateTime at) async {}
  @override
  Future<void> update(
    String id,
    String state, {
    DateTime? next,
    String? remoteId,
    String? error,
    bool begin = false,
  }) async => throw UnimplementedError();
}

void main() {
  testWidgets(
    'Windows simulation UI hides and clears secret, saves locally and blocks duplicate clicks',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = UiQueue();
      final credentials = MemoryCredentials();
      final server = EventServer();
      final c = EventSandboxController(
        openStore: () async => store,
        credentials: credentials,
        api: EventApi(MockClient(server.call), delay: noDelay),
        loadIds: () async => List.generate(12, (i) => 'word-$i'),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(home: EventSandboxPage(controller: c)),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('event-sync')))
            .onPressed,
        isNull,
      );
      final input = find.byKey(const Key('event-token'));
      expect(tester.widget<TextField>(input).obscureText, true);
      await tester.enterText(input, testToken);
      await tester.tap(find.byKey(const Key('event-save')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.text(testToken), findsNothing);
      store.hold = Completer<void>();
      await tester.tap(find.byKey(const Key('event-seed')));
      await tester.pump();
      expect(c.busy, true);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('event-sync')))
            .onPressed,
        isNull,
      );
      store.hold!.complete();
      await tester.pumpAndSettle();
      expect(c.rows.length, 24);
      expect(server.creates, 0);
      expect(find.textContaining('不上传你的真实学习历史'), findsOneWidget);
      await tester.tap(find.byKey(const Key('event-seed')));
      await tester.pumpAndSettle();
      expect(c.rows.length, 24);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
