import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:english_learning/app/app_theme.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/events/event_model.dart';
import 'package:english_learning/integrations/notion/events/event_store.dart';
import 'package:english_learning/integrations/notion/events/event_api.dart';
import 'package:english_learning/integrations/notion/events/event_uploader.dart';
import 'package:english_learning/integrations/notion/events/event_sandbox_controller.dart';
import 'package:english_learning/integrations/notion/events/event_sandbox_page.dart';

import 'local_learning.dart' show captureFrame;

const evidence = String.fromEnvironment('P2A_DIR');
Future<String> sandboxPath() async => p.join(
  (await getApplicationSupportDirectory()).path,
  'english_learning_p2a_simulation.sqlite3',
);
Future<List<String>> verifiedIds() async => NotionScope(
  await rootBundle.loadString('assets/vocabulary/verified100.csv'),
).entries.map((e) => e.id).toList();
Future<void> receipt(String name, Object data) =>
    File('$evidence/$name').writeAsString(jsonEncode(data), flush: true);

/// Real official HTTP except clearly classified one-shot fault injection.
final class EventFaultClient extends http.BaseClient {
  final http.Client delegate = http.Client();
  final Map<String, int> sequences;
  EventFaultClient(List<LearningEvent> events)
    : sequences = {for (final e in events) e.id: e.sequence};
  String mode = 'none';
  final used = <String>{};
  final records = <Map<String, Object?>>[];
  @override
  Future<http.StreamedResponse> send(http.BaseRequest original) async {
    if (original.url.host != 'api.notion.com' ||
        original.url.scheme != 'https') {
      throw StateError('Unexpected host');
    }
    final request = original as http.Request;
    final body = request.body.isEmpty ? null : jsonDecode(request.body) as Map;
    final create = request.url.path == '/v1/pages';
    String? id;
    if (create) {
      id =
          body!['properties']['Event ID']['title'][0]['text']['content']
              as String;
    }
    if (request.url.path.endsWith('/query')) {
      final f = (body!['filter']['and'] as List).cast<Map<dynamic, dynamic>>();
      id =
          f
                  .where((e) => e['property'] == 'Event ID')
                  .firstOrNull?['title']['equals']
              as String?;
    }
    final seq = sequences[id];
    final tag = '$mode/$seq/${create ? 'create' : 'query'}';
    if (mode == 'safe-failures' && used.add(tag)) {
      if (seq == 6 && !create) {
        records.add({'fault': 'controlled_offline', 'sequence': seq});
        throw const SocketException('synthetic fault');
      }
      if (seq == 7 && !create) {
        records.add({'fault': 'controlled_query_timeout', 'sequence': seq});
        throw TimeoutException('synthetic timeout');
      }
      if (seq == 8 && create) {
        records.add({
          'fault': 'controlled_429',
          'sequence': seq,
          'retry_after': 12,
        });
        return http.StreamedResponse(
          Stream.value(utf8.encode('{}')),
          429,
          headers: {'retry-after': '12'},
        );
      }
    }
    final forward = http.Request(request.method, request.url)
      ..followRedirects = false
      ..headers.addAll(request.headers)
      ..body = request.body;
    final response = await delegate.send(forward);
    final bytes = await response.stream.toBytes();
    final record = <String, Object?>{
      'method': request.method,
      'create': create,
      'sequence': seq,
      'status': response.statusCode,
    };
    if (!create && request.method == 'POST' && response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(bytes)) as Map;
      record['rows'] = (data['results'] as List).length;
      record['has_more'] = data['has_more'];
      record['cursor'] = body?['start_cursor'] != null;
    }
    records.add(
      record,
    ); // No credentials, headers, payloads or response bodies.
    if (mode == 'lost-and-exit' &&
        create &&
        response.statusCode >= 200 &&
        response.statusCode < 300) {
      if (seq == 9) {
        records.add({
          'fault': 'discarded_actual_success_response',
          'sequence': 9,
        });
        throw TimeoutException('committed response intentionally lost');
      }
      if (seq == 10) {
        await receipt('committed-before-exit.json', {
          'pid': pid,
          'sequence': 10,
          'actual_remote_http_status': response.statusCode,
          'local_ack_deliberately_paused': true,
        });
        await Completer<void>()
            .future; // Harness closes this isolated test process.
      }
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close() => delegate.close();
}

Future<void> settleController(
  WidgetTester tester,
  EventSandboxController c,
) async {
  for (var n = 0; n < 1200 && c.busy; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(c.busy, false, reason: 'Bounded wait for native event queue');
  expect(c.error, isNull);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> clickSync(WidgetTester tester, EventSandboxController c) async {
  await tester.ensureVisible(find.byKey(const Key('event-sync')));
  await tester.tap(find.byKey(const Key('event-sync')));
  await settleController(tester, c);
}

void main() {
  testWidgets(
    'P2-A live preparation: five smoke writes then durable offline timeout and rate-limit queue',
    (tester) async {
      final path = (await tester.runAsync(sandboxPath))!;
      final store = (await tester.runAsync(() => EventStore.open(path)))!;
      final ids = await verifiedIds();
      final events = LearningEvent.generate(ids);
      final client = EventFaultClient(events);
      final credentials = WindowsNotionCredentials(eventSandbox: true);
      final c = EventSandboxController(
        openStore: () async => store,
        credentials: credentials,
        api: EventApi(client),
        loadIds: () async => ids,
      );
      addTearDown(c.dispose);
      await tester.runAsync(() => store.enqueue(events.take(5).toList()));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: EventSandboxPage(controller: c),
        ),
      );
      await settleController(tester, c);
      expect(c.configured, true);
      await clickSync(tester, c);
      expect(c.rows.where((r) => r.state == 'synced').length, 5);
      final remote = (await tester.runAsync(
        () async =>
            EventApi(client, pageSize: 5).find((await credentials.read())!),
      ))!;
      expect(remote.length, 5);
      client.mode = 'safe-failures';
      await tester.ensureVisible(find.byKey(const Key('event-seed')));
      await tester.tap(find.byKey(const Key('event-seed')));
      await settleController(tester, c);
      expect(c.rows.length, 24);
      await clickSync(tester, c);
      expect(c.rows.where((r) => r.state == 'synced').length, 5);
      expect(c.rows.where((r) => r.state == 'pending').length, 19);
      final creates = client.records.where((r) => r['create'] == true).length;
      await clickSync(
        tester,
        c,
      ); // Cooldown rows skipped, later rows may safely upload.
      expect(
        client.records
            .where((r) => r['sequence'] == 8 && r['create'] == true)
            .length,
        0,
      );
      await tester.runAsync(
        () => receipt('prepared.json', {
          'pid': pid,
          'db_path': path,
          'local_events': 24,
          'first_smoke_remote_count': remote.length,
          'safe_failures': [
            'offline before create',
            'query timeout',
            '429 Retry-After=12',
          ],
          'creates_before_repeat': creates,
          'rows': c.rows
              .map(
                (r) => {
                  'id': r.event.id,
                  'hash': r.event.hash,
                  'state': r.state,
                },
              )
              .toList(),
          'requests': client.records,
        }),
      );
      await tester.runAsync(
        () => File('$evidence/simulated-events.json')
            .writeAsString(jsonEncode(events.map((e) => e.payload).toList())),
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: evidence.isEmpty,
  );

  testWidgets(
    'P2-A live interruption: lost success response then exit before acknowledgement',
    (tester) async {
      final path = (await tester.runAsync(sandboxPath))!;
      final store = (await tester.runAsync(() => EventStore.open(path)))!;
      final events = LearningEvent.generate(await verifiedIds());
      final client = EventFaultClient(events)..mode = 'lost-and-exit';
      final uploader = EventUploader(
        store: store,
        api: EventApi(client),
        credentials: WindowsNotionCredentials(eventSandbox: true),
      );
      await tester.runAsync(
        () => receipt('interruption-started.json', {
          'pid': pid,
          'ids': events.map((e) => e.id).toList(),
        }),
      );
      await tester.runAsync(uploader.sync);
      fail('Harness must stop isolated process before local acknowledgement');
    },
    skip: evidence.isEmpty,
  );

  testWidgets(
    'P2-A live recovery: reconcile interrupted create, repeat, paginate and preserve all event IDs',
    (tester) async {
      final path = (await tester.runAsync(sandboxPath))!;
      final store = (await tester.runAsync(() => EventStore.open(path)))!;
      final events = LearningEvent.generate(await verifiedIds());
      final client = EventFaultClient(events);
      final credentials = WindowsNotionCredentials(eventSandbox: true);
      final before = (await tester.runAsync(store.read))!;
      expect(before.map((r) => r.event.id), events.map((e) => e.id));
      expect(before.where((r) => r.state == 'sending').length, 1);
      final c = EventSandboxController(
        openStore: () async => store,
        credentials: credentials,
        api: EventApi(client),
        loadIds: verifiedIds,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('native-capture-root'),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: EventSandboxPage(controller: c),
          ),
        ),
      );
      await settleController(tester, c);
      await clickSync(tester, c);
      expect(c.rows.length, 24);
      expect(c.rows.every((r) => r.state == 'synced'), true);
      await clickSync(tester, c);
      final api = EventApi(client, pageSize: 5);
      final account = (await tester.runAsync(credentials.read))!;
      final remote = (await tester.runAsync(() => api.find(account)))!;
      expect(remote.length, 24);
      final matched = <String>{};
      for (final e in events) {
        final hits = remote.where((p) => EventApi.matches(p, e)).toList();
        expect(hits.length, 1);
        matched.add(e.id);
      }
      expect(matched.length, 24);
      expect(
        client.records.where(
          (r) => r['create'] == true && [9, 10].contains(r['sequence']),
        ),
        isEmpty,
      );
      final frame = await captureFrame(
        tester,
        Directory(evidence),
        'events-recovered',
      );
      await tester.runAsync(
        () => receipt('recovery.json', {
          'pid': pid,
          'local_events': 24,
          'remote_events': remote.length,
          'unique_remote_events': matched.length,
          'all_synced': true,
          'stable_ids_unchanged': true,
          'no_recreate_for_9_or_10': true,
          'requests': client.records,
          'frame': frame,
        }),
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: evidence.isEmpty,
  );
}
