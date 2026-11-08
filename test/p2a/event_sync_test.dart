import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/events/event_api.dart';
import 'package:english_learning/integrations/notion/events/event_model.dart';
import 'package:english_learning/integrations/notion/events/event_store.dart';
import 'package:english_learning/integrations/notion/events/event_uploader.dart';

import '../p1c/support.dart' show MemoryCredentials, testToken, noDelay;

Map<String, dynamic> schemaFixture() => {
  'id': eventSandboxSource,
  'description': [
    {'plain_text': 'P2A_SIMULATION_ONLY'},
  ],
  'properties': {
    for (final e in EventApi.properties(events.first).entries)
      e.key: {'type': (e.value as Map).keys.first},
  },
};
final events = LearningEvent.generate(
  List.generate(12, (i) => 'existing-word-$i'),
);
Map<String, dynamic> remotePage(LearningEvent e, int n) => {
  'id': '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}',
  'parent': {'data_source_id': eventSandboxSource},
  'archived': false,
  'properties': EventApi.properties(e),
};
http.Response jsonReply(
  Object value, {
  int status = 200,
  Map<String, String>? headers,
}) => http.Response(jsonEncode(value), status, headers: headers ?? const {});

class EventServer {
  final pages = <Map<String, dynamic>>[];
  int creates = 0, queries = 0, gets = 0;
  String? fault;
  Completer<void>? hold;
  Future<http.Response> call(http.Request req) async {
    if (req.method == 'GET') {
      gets++;
      if (fault == 'preflight429') {
        fault = null;
        return jsonReply({}, status: 429, headers: {'retry-after': '120'});
      }
      if (fault == 'offline') throw const SocketException('fixture only');
      return jsonReply(schemaFixture());
    }
    final body = jsonDecode(req.body) as Map;
    if (req.url.path.endsWith('/query')) {
      queries++;
      if (hold != null) await hold!.future;
      if (fault == 'queryTimeout') {
        fault = null;
        throw TimeoutException('fixture');
      }
      final conditions = (body['filter']['and'] as List)
          .cast<Map<dynamic, dynamic>>();
      final id = conditions
          .where((c) => c['property'] == 'Event ID')
          .firstOrNull?['title']['equals'];
      final matches = pages
          .where(
            (p) =>
                id == null ||
                ((p['properties']
                        as Map)['Event ID']['title'][0]['text']['content'] ==
                    id),
          )
          .toList();
      final start = int.tryParse(body['start_cursor'] as String? ?? '') ?? 0;
      final size = body['page_size'] as int;
      final stop = (start + size).clamp(0, matches.length);
      return jsonReply({
        'results': matches.sublist(start, stop),
        'has_more': stop < matches.length,
        'next_cursor': stop < matches.length ? '$stop' : null,
      });
    }
    if (fault == 'create429' || fault == 'create529') {
      final status = fault == 'create429' ? 429 : 529;
      fault = null;
      return jsonReply({}, status: status, headers: {'retry-after': '90'});
    }
    if (fault == 'server500') {
      fault = null;
      return jsonReply({}, status: 500);
    }
    creates++;
    final page = {
      'id': '00000000-0000-4000-8000-${creates.toString().padLeft(12, '0')}',
      'parent': body['parent'],
      'archived': false,
      'properties': body['properties'],
    };
    pages.add(page);
    if (fault == 'lostResponse') {
      fault = null;
      throw TimeoutException('committed then response lost');
    }
    return jsonReply(page);
  }
}

void main() {
  late Directory folder;
  late EventStore store;
  late EventServer server;
  late DateTime now;
  late MockClient client;
  final credentials = MemoryCredentials(
    NotionAccount(dataSourceId: eventSandboxSource, token: testToken),
  );
  setUp(() async {
    folder = await Directory.systemTemp.createTemp('p2a_event_test_');
    store = await EventStore.open('${folder.path}/simulation.sqlite3');
    server = EventServer();
    now = DateTime.utc(2026, 11, 8, 12);
    client = MockClient(server.call);
  });
  tearDown(() async {
    await store.close();
    client.close();
    await folder.delete(recursive: true);
  });
  EventUploader uploader() => EventUploader(
    store: store,
    api: EventApi(client, delay: noDelay),
    credentials: credentials,
    clock: () => now,
  );

  test('atomic local queue: 24 stable IDs survive repeated generation and reopening', () async {
    await store.enqueue(events);
    await store.enqueue(events);
    final before = (await store.read()).map((r) => r.event.hash).toList();
    await store.close();
    store = await EventStore.open('${folder.path}/simulation.sqlite3');
    expect((await store.read()).map((r) => r.event.hash), before);
    expect((await store.read()).length, 24);
    final original = events.first;
    final conflict = LearningEvent(
      id: original.id,
      wordId: original.wordId,
      type: original.type,
      grade: 'forgotten',
      occurredAt: original.occurredAt,
      sequence: 1,
    );
    await expectLater(store.enqueue([conflict]), throwsA(isA<EventFailure>()));
    expect((await store.read()).map((r) => r.event.hash), before);
  });
  test(
    'personal schema is rejected without changing any personal grade or word',
    () async {
      final path = '${folder.path}/personal.sqlite3';
      final personal = await SqliteLearningRepository.open(path);
      await personal.importCsv(
        File('assets/vocabulary/verified100.csv').readAsStringSync(),
      );
      final wordId = (await personal.readWords()).first.entry.id;
      final at = DateTime.utc(2026, 11, 8, 12);
      await personal.recordReview(wordId, ReviewGrade.familiar, at);
      await personal.recordPronunciation(
        entryId: wordId,
        grade: PronunciationGrade.confident,
        audioAssetId: 'test-only',
        attemptId: 'test-existing-assessment',
        at: at,
      );
      final bytes = await File(path).readAsBytes();
      await expectLater(EventStore.open(path), throwsA(isA<EventFailure>()));
      expect(await File(path).readAsBytes(), bytes);
      expect((await personal.readWords()).length, 100);
      expect((await personal.readWords()).first.status, 'familiar');
      expect(
        (await personal.readWords()).first.dueAt,
        at.add(const Duration(days: 1)),
      );
      expect(
        (await personal.readPronunciation(wordId)).grade,
        PronunciationGrade.confident,
      );
      await personal.close();
    },
  );
  test(
    '24 creates, replay and new uploader do not duplicate; audit paginates',
    () async {
      await store.enqueue(events);
      await uploader().sync();
      await uploader().sync();
      expect(server.creates, 24);
      expect((await store.read()).every((r) => r.state == 'synced'), true);
      final api = EventApi(client, pageSize: 5, delay: noDelay);
      final all = await api.find(credentials.account!);
      expect(all.length, 24);
      expect(all.map((p) => p['id']).toSet().length, 24);
    },
  );
  test(
    'offline and persisted cooldown survive restart before recovery',
    () async {
      await store.enqueue(events);
      server.fault = 'offline';
      await expectLater(uploader().sync(), throwsA(isA<EventFailure>()));
      expect((await store.read()).every((r) => r.state == 'pending'), true);
      await store.close();
      store = await EventStore.open('${folder.path}/simulation.sqlite3');
      server.fault = null;
      final calls = server.gets;
      await uploader().sync();
      expect(server.gets, calls);
      now = now.add(const Duration(minutes: 2));
      await uploader().sync();
      expect(server.creates, 24);
    },
  );
  test(
    'schema Retry-After longer than ten seconds persists and is not bypassed',
    () async {
      await store.enqueue([events.first]);
      server.fault = 'preflight429';
      await expectLater(uploader().sync(), throwsA(isA<EventFailure>()));
      expect(
        (await store.read()).single.nextAttempt,
        now.add(const Duration(seconds: 120)),
      );
      now = now.add(const Duration(seconds: 119));
      await uploader().sync();
      expect(server.gets, 1);
      now = now.add(const Duration(seconds: 1));
      await uploader().sync();
      expect(server.creates, 1);
    },
  );
  for (final fault in ['create429', 'create529']) {
    test(
      '$fault schedules safe retry, never sends during Retry-After',
      () async {
        await store.enqueue([events.first]);
        server.fault = fault;
        await uploader().sync();
        final row = (await store.read()).single;
        expect(row.state, 'pending');
        expect(server.creates, 0);
        expect(row.nextAttempt, now.add(const Duration(seconds: 90)));
        now = now.add(const Duration(seconds: 89));
        await uploader().sync();
        expect(server.creates, 0);
        now = now.add(const Duration(seconds: 1));
        await uploader().sync();
        expect(server.creates, 1);
      },
    );
  }
  test('server committed but response lost: restart reconciles; no second POST create', () async {
    await store.enqueue(events);
    server.fault = 'lostResponse';
    await uploader().sync();
    expect(server.creates, 24);
    expect((await store.read()).where((r) => r.state == 'uncertain').length, 1);
    await store.close();
    store = await EventStore.open('${folder.path}/simulation.sqlite3');
    now = now.add(const Duration(minutes: 2));
    await uploader().sync();
    expect(server.creates, 24);
    expect((await store.read()).every((r) => r.state == 'synced'), true);
  });
  test('create 5xx or crash intent with empty query stays uncertain and never recreates', () async {
    await store.enqueue([events.first]);
    server.fault = 'server500';
    await uploader().sync();
    expect((await store.read()).single.state, 'uncertain');
    for (var i = 0; i < 3; i++) {
      now = now.add(const Duration(minutes: 2));
      await uploader().sync();
    }
    expect(server.creates, 0);
    expect((await store.read()).single.state, 'uncertain');
    await store.update(events.first.id, 'sending');
    await uploader().sync();
    expect(server.creates, 0);
  });
  test(
    'query timeout is safe to retry and never marks an unsent event as synced',
    () async {
      await store.enqueue([events.first]);
      server.fault = 'queryTimeout';
      await uploader().sync();
      expect((await store.read()).single.state, 'pending');
      expect(server.creates, 0);
      now = now.add(const Duration(minutes: 2));
      await uploader().sync();
      expect(server.creates, 1);
    },
  );
  test('duplicate event IDs or same ID changed grade/hash are conflicts, not overwritten', () async {
    await store.enqueue(events.take(2).toList());
    server.pages.addAll([
      remotePage(events[0], 1),
      remotePage(events[0], 2),
      remotePage(events[1], 3),
    ]);
    (server.pages.last['properties'] as Map)['Grade'] = {
      'rich_text': [
        {
          'text': {'content': 'changed'},
        },
      ],
    };
    await uploader().sync();
    expect(server.creates, 0);
    expect((await store.read()).every((r) => r.state == 'conflict'), true);
  });
  test(
    'same service and independent service are serialized by the writer lock',
    () async {
      await store.enqueue([events.first]);
      server.hold = Completer<void>();
      final first = uploader();
      final running = first.sync();
      for (var i = 0; i < 100 && server.queries == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await expectLater(first.sync(), throwsA(isA<EventFailure>()));
      await expectLater(uploader().sync(), throwsA(isA<EventFailure>()));
      server.hold!.complete();
      await running;
      expect(server.creates, 1);
    },
  );
  test(
    'official target allowlist rejects production credentials before any HTTP',
    () async {
      final api = EventApi(client, delay: noDelay);
      await expectLater(
        api.create(
          NotionAccount(dataSourceId: notionPilotSource, token: testToken),
          events.first,
        ),
        throwsA(isA<EventFailure>()),
      );
      expect(server.creates + server.queries + server.gets, 0);
    },
  );
  test(
    'persisted global rate limit also blocks newly enqueued events',
    () async {
      await store.enqueue([events.first]);
      server.fault = 'create429';
      await uploader().sync();
      await store.enqueue([events[1]]);
      final calls = server.gets + server.queries;
      await uploader().sync();
      expect(server.gets + server.queries, calls);
      expect(server.creates, 0);
      await store.close();
      store = await EventStore.open('${folder.path}/simulation.sqlite3');
      now = now.add(const Duration(seconds: 90));
      await uploader().sync();
      expect(server.creates, 2);
    },
  );
}
