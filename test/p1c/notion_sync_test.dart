import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late SqliteLearningRepository repo;
  late Map<String, dynamic> data;
  late List<Map<String, dynamic>> pages;
  late MemoryCredentials credentials;
  final clock = DateTime.utc(2026, 11, 8, 4);
  NotionSyncService service(http.Client client) => NotionSyncService(
    store: repo,
    credentials: credentials,
    api: NotionReadApi(client, delay: noDelay),
    loadScope: () async => testScope(),
    clock: () => clock,
  );
  MockClient client({
    Future<http.Response> Function(http.Request)? query,
  }) => MockClient((request) async {
    expect(request.url.host, 'api.notion.com');
    expect(request.url.scheme, 'https');
    expect(request.followRedirects, false);
    expect(request.headers['Authorization'], 'Bearer $testToken');
    expect(request.headers['Notion-Version'], notionApiVersion);
    expect(request.url.path, startsWith('/v1/data_sources/$notionPilotSource'));
    if (request.method == 'GET') return jsonResponse(data['schema']);
    expect(request.method, 'POST');
    expect(request.url.path, endsWith('/query'));
    return query == null ? jsonResponse(listResponse(pages)) : query(request);
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('notion_sync_');
    repo = await SqliteLearningRepository.open(
      '${directory.path}/study.sqlite3',
    );
    data = snapshot();
    pages = (data['pages'] as List).cast<Map<String, dynamic>>();
    credentials = MemoryCredentials(testAccount());
  });
  tearDown(() async {
    await repo.close();
    await directory.delete(recursive: true);
  });

  test('100 synthetic API fixtures preserve all CSV identities and fields', () {
    final scope = testScope();
    expect(scope.entries.length, 100);
    for (final page in pages) {
      final row = NotionFields.read(page, scope, notionPilotSource);
      expect(
        row.entry.fields,
        scope.entries.singleWhere((e) => e.id == row.entry.id).fields,
      );
    }
  });

  test('first paginated sync inserts exactly 100 untested words, repeat is idempotent', () async {
    final requests = <Map<String, dynamic>>[];
    final api = client(
      query: (request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        requests.add(body);
        return jsonResponse(
          body['start_cursor'] == null
              ? listResponse(pages.take(60).toList(), next: 'page-two')
              : listResponse(pages.skip(60).toList()),
        );
      },
    );
    final sync = service(api);
    expect((await sync.sync()).inserted, 100);
    expect((await sync.sync()).unchanged, 100);
    final words = await repo.readWords();
    expect(words.length, 100);
    expect(
      words.every(
        (w) => w.status == 'untested' && w.reviewCount == 0 && w.dueAt == null,
      ),
      true,
    );
    expect(await repo.reviewEventCount(), 0);
    expect((await repo.readNotionState(notionPilotSource)).linkedWords, 100);
    expect(requests.first['filter']['or'].length, 100);
    expect(
      requests[2]['filter']['and'][1]['last_edited_time']['on_or_after'],
      '2026-11-08T02:58:00.000Z',
    );
    expect(requests.first.containsKey('properties'), false);
  });

  test('incremental content update and CSV refresh preserve meaning and pronunciation history', () async {
    final sync = service(client());
    await sync.sync();
    final big = pages.singleWhere(
      (p) => p['properties']['单词']['title'][0]['plain_text'] == 'big',
    );
    final id = NotionFields.read(big, testScope(), notionPilotSource).entry.id;
    await repo.recordReview(id, ReviewGrade.mastered, clock);
    await repo.recordPronunciation(
      entryId: id,
      grade: PronunciationGrade.confident,
      audioAssetId: 'test-audio',
      attemptId: 'existing-assessment',
      at: clock,
    );
    final before = (await repo.readWords()).singleWhere(
      (w) => w.entry.id == id,
    );
    setText(big, '中文词义', '大的；体积较大的（同步测试）');
    big['last_edited_time'] = '2026-11-08T03:01:00.000Z';
    final increment = service(
      client(query: (_) async => jsonResponse(listResponse([big]))),
    );
    expect((await increment.sync()).updated, 1);
    expect((await increment.sync()).unchanged, 1);
    final after = (await repo.readWords()).singleWhere((w) => w.entry.id == id);
    expect(after.status, before.status);
    expect(after.reviewCount, 1);
    expect(after.dueAt, before.dueAt);
    expect(await repo.reviewEventCount(), 1);
    expect(
      (await repo.readPronunciation(id)).grade,
      PronunciationGrade.confident,
    );
    // A CSV edit cannot trick the sync hash into skipping the cloud content.
    await repo.importCsv(
      File('assets/vocabulary/verified100.csv').readAsStringSync(),
    );
    expect((await increment.sync()).updated, 1);
    expect(
      (await repo.readWords())
          .singleWhere((w) => w.entry.id == id)
          .entry
          .meaning,
      contains('同步测试'),
    );
    await repo.close();
    repo = await SqliteLearningRepository.open(
      '${directory.path}/study.sqlite3',
    );
    expect(
      (await repo.readWords()).singleWhere((w) => w.entry.id == id).reviewCount,
      1,
    );
    expect(
      (await repo.readPronunciation(id)).grade,
      PronunciationGrade.confident,
    );
    expect((await repo.readNotionState(notionPilotSource)).linkedWords, 100);
  });

  test(
    'later-page network failure rolls back the entire batch and checkpoint',
    () async {
      await service(client()).sync();
      final old = await repo.readNotionState(notionPilotSource);
      final changed = copyJson(pages.first);
      setText(changed, '中文词义', '未提交内容');
      final broken = service(
        client(
          query: (request) async {
            if ((jsonDecode(request.body) as Map).containsKey('start_cursor')) {
              throw http.ClientException(
                'secret must never be exposed $testToken',
              );
            }
            return jsonResponse(listResponse([changed], next: 'unavailable'));
          },
        ),
      );
      await expectLater(
        broken.sync(),
        throwsA(
          isA<NotionFailure>().having(
            (e) => e.message,
            'safe',
            isNot(contains(testToken)),
          ),
        ),
      );
      expect(
        (await repo.readNotionState(notionPilotSource)).watermark,
        old.watermark,
      );
      expect(
        (await repo.readWords()).any((w) => w.entry.meaning == '未提交内容'),
        false,
      );
      expect((await repo.readWords()).length, 100);
    },
  );

  test(
    'duplicate stable IDs on different pages fail before any write',
    () async {
      final duplicate = copyJson(pages.first)
        ..['id'] = '11111111-1111-4111-8111-111111111111';
      pages = [...pages, duplicate];
      await expectLater(
        service(client()).sync(),
        throwsA(isA<NotionFailure>()),
      );
      expect(await repo.readWords(), isEmpty);
      expect((await repo.readNotionState(notionPilotSource)).watermark, isNull);
    },
  );

  test('missing page, repeated cursor and incomplete initial snapshot are rejected', () async {
    await expectLater(
      service(
        client(
          query: (_) async =>
              jsonResponse(listResponse(pages.take(99).toList())),
        ),
      ).sync(),
      throwsA(isA<NotionFailure>()),
    );
    final empty = service(
      client(
        query: (_) async => jsonResponse(listResponse([], next: 'same-cursor')),
      ),
    );
    await expectLater(empty.sync(), throwsA(isA<NotionFailure>()));
    expect(await repo.readWords(), isEmpty);
  });

  for (final kind in [
    '2025',
    'verification',
    'head',
    'scope',
    'parent',
    'type',
    'truncated',
    'timezone',
  ]) {
    test(
      'reject invalid remote $kind without changing the local cache',
      () async {
        final page = pages.first;
        switch (kind) {
          case '2025':
            page['properties']['PETS3 2025收录状态']['select']['name'] = '官方已收录';
          case 'verification':
            page['properties']['原书核验状态']['select']['name'] = '待核验';
          case 'head':
            page['properties']['单词']['title'][0]['plain_text'] = 'wrong';
          case 'scope':
            setText(page, '词条ID', 'not-in-approved-scope');
          case 'parent':
            page['parent']['data_source_id'] = 'wrong-source';
          case 'type':
            page['properties']['中文词义']['type'] = 'number';
          case 'truncated':
            page['properties']['中文词义']['has_more'] = true;
          case 'timezone':
            page['last_edited_time'] = '2026-11-08T03:00:00';
        }
        await expectLater(
          service(client()).sync(),
          throwsA(isA<NotionFailure>()),
        );
        expect(await repo.readWords(), isEmpty);
      },
    );
  }

  test('renamed schema field fails safely and keeps imported CSV available offline', () async {
    await repo.importCsv(
      File('assets/vocabulary/verified100.csv').readAsStringSync(),
    );
    (data['schema']['properties'] as Map).remove('原书分类');
    await expectLater(service(client()).sync(), throwsA(isA<NotionFailure>()));
    expect((await repo.readWords()).length, 100);
    expect((await repo.readNotionState(notionPilotSource)).syncedAt, isNull);
  });

  test(
    'recreated page mapping conflict preserves all old words and progress',
    () async {
      await service(client()).sync();
      final before = await repo.readNotionState(notionPilotSource);
      pages.first['id'] = '11111111-1111-4111-8111-111111111111';
      await expectLater(
        service(client()).sync(),
        throwsA(isA<NotionFailure>()),
      );
      expect(
        (await repo.readNotionState(notionPilotSource)).syncedAt,
        before.syncedAt,
      );
      expect((await repo.readWords()).length, 100);
    },
  );

  test('stale expected checkpoint is refused transactionally', () async {
    await service(client()).sync();
    await expectLater(
      repo.applyNotionBatch(
        sourceId: notionPilotSource,
        words: [],
        expectedWatermark: null,
        watermark: clock,
        syncedAt: clock,
      ),
      throwsA(isA<NotionFailure>()),
    );
    expect(
      (await repo.readNotionState(notionPilotSource)).watermark,
      DateTime.utc(2026, 11, 8, 3),
    );
  });

  test(
    'schema v2 migration leaves existing rows and legacy states intact',
    () async {
      await repo.importCsv(
        File('assets/vocabulary/verified100.csv').readAsStringSync(),
      );
      final id = (await repo.readWords()).first.entry.id;
      await repo.recordReview(id, ReviewGrade.familiar, clock);
      await repo.close();
      final raw = sqlite3.open('${directory.path}/study.sqlite3');
      raw.execute('DROP TABLE notion_word_links');
      raw.execute('DROP TABLE notion_sync_state');
      raw.execute('PRAGMA user_version=2');
      final before = raw
          .select('SELECT * FROM learning_progress ORDER BY entry_id')
          .map((r) => r.values.toList())
          .toList();
      raw.close();
      repo = await SqliteLearningRepository.open(
        '${directory.path}/study.sqlite3',
      );
      final check = sqlite3.open('${directory.path}/study.sqlite3');
      expect(
        check
            .select('SELECT * FROM learning_progress ORDER BY entry_id')
            .map((r) => r.values.toList())
            .toList(),
        before,
      );
      expect(check.select('PRAGMA user_version').single.values.single, 3);
      check.close();
      expect(await repo.reviewEventCount(), 1);
    },
  );

  test('rate limiting retries using Retry-After and never leaks response credentials', () async {
    var calls = 0;
    final waits = <Duration>[];
    final api = NotionReadApi(
      MockClient((_) async {
        calls++;
        return calls < 3
            ? jsonResponse(
                {'secret': testToken},
                status: 429,
                headers: {'retry-after': '2'},
              )
            : jsonResponse(data['schema']);
      }),
      delay: (d) async {
        waits.add(d);
      },
    );
    await api.schema(testAccount());
    expect(calls, 3);
    expect(waits, [const Duration(seconds: 2), const Duration(seconds: 2)]);
    final capped = NotionReadApi(
      MockClient(
        (_) async => jsonResponse(
          {'secret': testToken},
          status: 529,
          headers: {'retry-after': '61'},
        ),
      ),
      delay: noDelay,
    );
    await expectLater(
      capped.schema(testAccount()),
      throwsA(
        isA<NotionFailure>().having(
          (e) => e.toString(),
          'redacted',
          isNot(contains(testToken)),
        ),
      ),
    );
  });

  for (final status in [301, 401, 403, 404, 500]) {
    test('HTTP $status errors are safe and preserve all local data', () async {
      final api = NotionReadApi(
        MockClient((_) async => http.Response(testToken, status)),
        delay: noDelay,
      );
      await expectLater(
        api.schema(testAccount()),
        throwsA(
          isA<NotionFailure>().having(
            (e) => e.message,
            'redacted',
            isNot(contains(testToken)),
          ),
        ),
      );
      expect(await repo.readWords(), isEmpty);
    });
  }

  test('oversized and malformed responses fail safely', () async {
    for (final body in ['{bad json', 'x' * (2 * 1024 * 1024 + 1)]) {
      final api = NotionReadApi(
        MockClient((_) async => http.Response(body, 200)),
        delay: noDelay,
      );
      await expectLater(
        api.schema(testAccount()),
        throwsA(isA<NotionFailure>()),
      );
    }
  });

  test(
    'no credentials and repeated sync clicks do not issue extra network calls',
    () async {
      credentials.account = null;
      var calls = 0;
      final waiting = Completer<http.Response>();
      final api = MockClient((_) {
        calls++;
        return waiting.future;
      });
      final sync = service(api);
      await expectLater(sync.sync(), throwsA(isA<NotionFailure>()));
      expect(calls, 0);
      credentials.account = testAccount();
      final first = sync.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await expectLater(sync.sync(), throwsA(isA<NotionFailure>()));
      waiting.complete(http.Response('', 401));
      await expectLater(first, throwsA(isA<NotionFailure>()));
      expect(calls, 1);
    },
  );

  test('credential method channel is the only persistence path and errors are redacted', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? stored;
    final methods = <String>[];
    messenger.setMockMethodCallHandler(WindowsNotionCredentials.channel, (
      call,
    ) async {
      methods.add(call.method);
      switch (call.method) {
        case 'write':
          stored = (call.arguments as Map)['value'] as String;
          return null;
        case 'read':
          return stored;
        case 'delete':
          stored = null;
          return null;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        WindowsNotionCredentials.channel,
        null,
      ),
    );
    final vault = WindowsNotionCredentials(testNamespace: 'unit');
    await vault.save(testAccount());
    expect((await vault.read())!.token, testToken);
    expect(testAccount().toString(), isNot(contains(testToken)));
    await vault.delete();
    expect(await vault.read(), isNull);
    expect(methods, ['write', 'read', 'delete', 'read']);
    messenger.setMockMethodCallHandler(
      WindowsNotionCredentials.channel,
      (_) async => throw PlatformException(code: 'failure', message: testToken),
    );
    await expectLater(
      vault.read(),
      throwsA(
        isA<NotionFailure>().having(
          (e) => e.message,
          'safe',
          isNot(contains(testToken)),
        ),
      ),
    );
  });
}
