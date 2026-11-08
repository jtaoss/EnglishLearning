import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/core/storage/copy_learning_journal.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/integrations/notion/journal/copy_journal_sync.dart';

import '../p1a/fixtures.dart';
import 'support.dart';

void main() {
  late Directory dir;
  late String copy;
  late SqliteLearningRepository repo;
  late MemoryJournalCloud cloud;
  late DateTime now;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('p2b1_sync_');
    final original = '${dir.path}/original.sqlite3';
    copy = '${dir.path}/copy.sqlite3';
    final old = await SqliteLearningRepository.open(original);
    await old.importCsv(encodeEntries([entryFields()]));
    await old.close();
    File(original).copySync(copy);
    writePermit(copy, original);
    repo = await reopenCopy(copy);
    cloud = MemoryJournalCloud();
    now = DateTime.utc(2026, 11, 9);
  });
  tearDown(() async {
    await repo.close();
    final path = dir.resolveSymbolicLinksSync().toLowerCase();
    if (!path.startsWith(
      '${Directory.systemTemp.resolveSymbolicLinksSync().toLowerCase()}${Platform.pathSeparator}p2b1_sync_',
    )) {
      throw StateError('Unsafe cleanup');
    }
    await dir.delete(recursive: true);
  });
  CopyJournalSync sync() =>
      CopyJournalSync(repository: repo, cloud: cloud, clock: () => now);
  Future<void> learn(int n) async {
    for (var i = 0; i < n; i++) {
      if (i.isEven) {
        await repo.recordReview(
          'test-alpha',
          ReviewGrade.values[(i ~/ 2) % 3],
          now.add(Duration(minutes: i)),
          operationId: 'action-$i',
        );
      } else {
        await repo.recordPronunciation(
          entryId: 'test-alpha',
          grade: PronunciationGrade.values[(i ~/ 2) % 3],
          audioAssetId: 'fixture',
          attemptId: 'attempt-$i',
          at: now.add(Duration(minutes: i)),
        );
      }
    }
  }

  test('24 copy learning operations upload and round-trip without changing local ratings or due dates', () async {
    await learn(24);
    final before = snapshotTables(copy);
    final ids = (await repo.readJournal())
        .map((r) => eventPayload(r)['event_id'])
        .toList();
    await sync().sync();
    await sync().sync();
    expect(cloud.creates, 24);
    expect(cloud.events.length, 24);
    expect(snapshotTables(copy), before);
    expect(
      (await repo.readJournal()).every((r) => r['state'] == 'synced'),
      true,
    );
    await repo.close();
    repo = await reopenCopy(copy);
    await sync().sync();
    expect(cloud.creates, 24);
    expect(
      (await repo.readJournal()).map((r) => eventPayload(r)['event_id']),
      ids,
    );
    expect(snapshotTables(copy), before);
  });
  test('offline learning is durable, failure retains events, restart uploads after recovery', () async {
    cloud.offline = true;
    await learn(4);
    final before = snapshotTables(copy);
    await expectLater(sync().sync(), throwsA(isA<SocketException>()));
    expect((await repo.readJournal()).length, 4);
    expect(snapshotTables(copy), before);
    await repo.close();
    repo = await reopenCopy(copy);
    cloud.offline = false;
    now = now.add(const Duration(minutes: 5));
    await sync().sync();
    expect(cloud.creates, 4);
    expect(snapshotTables(copy), before);
  });
  test('successful write with lost response reconciles after restart and never recreates', () async {
    await learn(1);
    cloud.lostResponse = true;
    await sync().sync();
    expect(cloud.creates, 1);
    expect((await repo.readJournal()).single['state'], 'uncertain');
    await repo.close();
    repo = await reopenCopy(copy);
    now = now.add(const Duration(minutes: 5));
    await sync().sync();
    expect(cloud.creates, 1);
    expect((await repo.readJournal()).single['state'], 'synced');
  });
  test('committed sending intent with no visible remote event remains uncertain, not blindly recreated', () async {
    await learn(1);
    final e = (await repo.readJournal()).single;
    await repo.setJournalState(
      eventPayload(e)['event_id'] as String,
      'sending',
    );
    await sync().sync();
    expect(cloud.creates, 0);
    expect((await repo.readJournal()).single['state'], 'uncertain');
  });
  test(
    'remote changed grade and unknown events are inbox evidence only',
    () async {
      await learn(1);
      final local = eventPayload((await repo.readJournal()).single);
      final before = snapshotTables(copy);
      cloud.events.add(
        CopyCloudEvent('different', {...local, 'grade': 'forgotten'}),
      );
      cloud.events.add(
        CopyCloudEvent('other', {
          ...local,
          'event_id': 'remote-other',
          'grade': 'mastered',
        }),
      );
      await sync().sync();
      expect(snapshotTables(copy), before);
      expect((await repo.readJournal()).single['state'], 'conflict');
      expect(cloud.creates, 0);
      final db = sqlite3.open(copy);
      expect(
        db
            .select(
              "SELECT COUNT(*) n FROM journal_inbox WHERE state='requires_review'",
            )
            .single['n'],
        2,
      );
      db.close();
    },
  );
  test('duplicate remote identities block confirmation without replacing events or ratings', () async {
    await learn(1);
    final e = eventPayload((await repo.readJournal()).single);
    cloud.events.addAll([CopyCloudEvent('a', e), CopyCloudEvent('b', e)]);
    final before = snapshotTables(copy);
    await sync().sync();
    expect((await repo.readJournal()).single['state'], 'conflict');
    expect(snapshotTables(copy), before);
    expect(cloud.creates, 0);
  });
  test('snapshot and foreign provenance are quarantined; simulation cannot be inserted into personal repo', () async {
    final before = snapshotTables(copy);
    cloud.events.add(
      CopyCloudEvent('unknown', {
        'event_id': 'foreign',
        'origin': 'new_learning_event',
        'word_id': 'test-alpha',
        'grade': 'mastered',
      }),
    );
    await sync().sync();
    expect(await repo.readJournal(), isEmpty);
    expect(snapshotTables(copy), before);
    final db = sqlite3.open(copy);
    expect(
      db.select('SELECT state FROM journal_inbox').single['state'],
      'quarantined',
    );
    db.close();
    expect(personalEventUploadEnabled, false);
  });
  test(
    'second-page failure stages no partial inbox updates, then recovers',
    () async {
      await learn(6);
      await sync().sync();
      final db = sqlite3.open(copy);
      db.execute('DELETE FROM journal_inbox');
      db.close();
      final before = snapshotTables(copy, all: true);
      cloud.secondPageFailure = true;
      await expectLater(sync().sync(), throwsA(isA<SocketException>()));
      expect(snapshotTables(copy, all: true), before);
      cloud.secondPageFailure = false;
      await sync().sync();
      expect(cloud.creates, 6);
    },
  );
  test('incomplete query fails safely rather than treating a capped query as complete', () async {
    cloud.incomplete = true;
    final before = snapshotTables(copy, all: true);
    await expectLater(sync().sync(), throwsA(anything));
    expect(snapshotTables(copy, all: true), before);
  });
  test('Retry-After persists across restart and prevents all cloud traffic during cooldown', () async {
    await learn(2);
    cloud.createRateLimit = true;
    await sync().sync();
    expect(cloud.creates, 0);
    expect((await repo.readJournal()).first['state'], 'pending');
    await repo.close();
    repo = await reopenCopy(copy);
    final calls = cloud.finds + cloud.pages;
    await sync().sync();
    expect(cloud.finds + cloud.pages, calls);
    now = now.add(const Duration(seconds: 120));
    await sync().sync();
    expect(cloud.creates, 2);
  });
  test(
    'payload hash ignores JSON property order and keeps exact event values',
    () async {
      await learn(1);
      final e = eventPayload((await repo.readJournal()).single);
      final reversed = {for (final k in e.keys.toList().reversed) k: e[k]};
      cloud.events.add(CopyCloudEvent('reordered', reversed));
      await sync().sync();
      expect(cloud.creates, 0);
      expect((await repo.readJournal()).single['state'], 'synced');
    },
  );
  test(
    'invalid second inbox record rolls back the entire receipt transaction',
    () async {
      final before = snapshotTables(copy, all: true);
      await expectLater(
        repo.receiveJournalEvents([
          {'event_id': 'first', 'origin': 'simulation_test'},
          {'origin': 'simulation_test'},
        ]),
        throwsFormatException,
      );
      expect(snapshotTables(copy, all: true), before);
    },
  );
}
