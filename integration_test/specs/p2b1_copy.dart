import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:english_learning/app/english_learning_app.dart';
import 'package:english_learning/core/config/app_config.dart';
import 'package:english_learning/core/logging/app_logger.dart';
import 'package:english_learning/core/settings/settings_repository.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/integrations/notion/journal/copy_journal_sync.dart';

import '../../test/p2b1/support.dart'
    show MemoryJournalCloud, snapshotTables, eventPayload;
import 'p1d_common.dart' show openListWord;
import 'local_learning.dart' show captureFrame;

const b1Root = String.fromEnvironment('P2B1_ROOT');
String get copyPath => '$b1Root/private/learning-copy.sqlite3';
String get cloudPath => '$b1Root/private/simulated-cloud.json';
Future<void> saveB1(String name, Object value) =>
    File('$b1Root/evidence/native/$name')
        .writeAsString(jsonEncode(value), flush: true);

class DiskCloud extends MemoryJournalCloud {
  bool pause = false;
  static Future<DiskCloud> load() async {
    final c = DiskCloud();
    final file = File(cloudPath);
    if (await file.exists()) {
      final data = jsonDecode(await file.readAsString()) as Map;
      c.creates = data['creates'] as int;
      for (final e in data['events'] as List) {
        c.events.add(
          CopyCloudEvent(
            e['remote_id'] as String,
            (e['payload'] as Map).cast<String, Object?>(),
          ),
        );
      }
    }
    return c;
  }

  @override
  Future<CopyCloudEvent> create(Map<String, Object?> payload) async {
    creates++;
    final event = CopyCloudEvent('disk-mock-page-$creates', Map.of(payload));
    events.add(event);
    await File(cloudPath).writeAsString(
      jsonEncode({
        'creates': creates,
        'events': events
            .map((e) => {'remote_id': e.remoteId, 'payload': e.payload})
            .toList(),
      }),
      flush: true,
    );
    if (pause) {
      await saveB1('committed-before-exit.json', {
        'pid': pid,
        'cloud_kind': 'disk-backed simulation; no Notion write',
        'mock_events': events.length,
        'local_ack_paused': true,
      });
      await Completer<void>().future;
    }
    if (lostResponse) {
      lostResponse = false;
      throw TimeoutException('controlled simulated response loss');
    }
    return event;
  }
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var n = 0; n < 300; n++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('Bounded wait for copy learning UI');
}

void main() {
  testWidgets(
    'P2-B1 copy preparation: migrate actual backup, UI learning, offline persistence and simulated upload',
    (tester) async {
      final before = (await tester.runAsync(
        () async => snapshotTables(copyPath),
      ))!;
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.openIsolatedCopy(copyPath),
      ))!;
      addTearDown(repo.close);
      expect(
        (await tester.runAsync(() async => snapshotTables(copyPath)))!,
        before,
      );
      expect((await tester.runAsync(repo.readJournal))!, isEmpty);
      final words = (await tester.runAsync(repo.readWords))!
          .where((w) => w.entry.libraryClass == '主学习')
          .take(4)
          .toList();
      final at = DateTime.utc(2026, 11, 9, 15, 59, 30);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('native-capture-root'),
          child: EnglishLearningApp(
            repository: SharedPreferencesSettingsRepository(),
            logger: AppLogger(),
            config: AppConfig.developmentPreset(),
            learningRepository: repo,
            clock: () => at,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const Key('open-vocabulary')));
      await tester.pump(const Duration(milliseconds: 500));
      for (var i = 0; i < 3; i++) {
        await openListWord(tester, words[i].entry.id);
        expect(find.byKey(const Key('meaning')), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('reveal-answer')));
        await tester.tap(find.byKey(const Key('reveal-answer')));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(
          find.byKey(ValueKey('grade-${ReviewGrade.values[i].name}')),
        );
        await tester.tap(
          find.byKey(ValueKey('grade-${ReviewGrade.values[i].name}')),
        );
        await waitFor(tester, find.byKey(const Key('review-saved')));
        await tester.ensureVisible(find.text('返回词库'));
        await tester.tap(find.text('返回词库'));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(
          () => repo.recordPronunciation(
            entryId: words[i].entry.id,
            grade: PronunciationGrade.values[i],
            audioAssetId: 'isolated-storage-fixture',
            attemptId: 'copy-pron-$i',
            at: at,
          ),
        );
      }
      final cloud = (await tester.runAsync(DiskCloud.load))!..offline = true;
      await tester.runAsync(
        () => repo.recordReview(
          words[3].entry.id,
          ReviewGrade.familiar,
          at,
          operationId: 'offline-copy-action',
        ),
      );
      final protected = (await tester.runAsync(
        () async => snapshotTables(copyPath),
      ))!;
      await tester.runAsync(() async {
        try {
          await CopyJournalSync(repository: repo, cloud: cloud).sync();
          fail('Expected offline');
        } on SocketException {
          /* Expected controlled offline transport. */
        }
      });
      expect(
        (await tester.runAsync(() async => snapshotTables(copyPath)))!,
        protected,
      );
      cloud.offline = false;
      cloud.lostResponse = true;
      await tester.runAsync(
        () => CopyJournalSync(
          repository: repo,
          cloud: cloud,
          clock: () => DateTime.now().toUtc().add(const Duration(hours: 1)),
        ).sync(),
      );
      final rows = (await tester.runAsync(repo.readJournal))!;
      expect(rows.length, 7);
      expect(cloud.creates, 7);
      expect(rows.where((r) => r['state'] == 'uncertain').length, 1);
      final frame = await captureFrame(
        tester,
        Directory('$b1Root/evidence/native'),
        'copy-learning',
      );
      await tester.runAsync(
        () => saveB1('prepared.json', {
          'pid': pid,
          'words': 100,
          'legacy_tables_unchanged_on_migration': true,
          'events': 7,
          'ids': rows.map((r) => eventPayload(r)['event_id']).toList(),
          'mock_creates': cloud.creates,
          'cloud_kind': 'disk-backed simulation',
          'personal_history_uploaded': false,
          'frame': frame,
        }),
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: b1Root.isEmpty,
  );

  testWidgets(
    'P2-B1 interruption: isolated process exits after simulated commit before SQLite acknowledgement',
    (tester) async {
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.openIsolatedCopy(copyPath),
      ))!;
      final cloud = (await tester.runAsync(DiskCloud.load))!..pause = true;
      final word = (await tester.runAsync(repo.readWords))!.first;
      await tester.runAsync(
        () => repo.recordReview(
          word.entry.id,
          ReviewGrade.forgotten,
          DateTime.utc(2026, 11, 9, 16),
          operationId: 'interrupted-copy-action',
        ),
      );
      await tester.runAsync(
        () => CopyJournalSync(
          repository: repo,
          cloud: cloud,
          clock: () => DateTime.now().toUtc().add(const Duration(hours: 2)),
        ).sync(),
      );
      fail('Expected harness to close this isolated test process');
    },
    skip: b1Root.isEmpty,
  );

  testWidgets(
    'P2-B1 recovery: persisted event IDs, readback quarantine and ratings survive new process',
    (tester) async {
      final repo = (await tester.runAsync(
        () => SqliteLearningRepository.openIsolatedCopy(copyPath),
      ))!;
      addTearDown(repo.close);
      final before = (await tester.runAsync(
        () async => snapshotTables(copyPath),
      ))!;
      final cloud = (await tester.runAsync(DiskCloud.load))!;
      final rows = (await tester.runAsync(repo.readJournal))!;
      expect(rows.length, 8);
      expect(rows.where((r) => r['state'] == 'sending').length, 1);
      final ids = rows.map((r) => eventPayload(r)['event_id']).toList();
      final creates = cloud.creates;
      final sync = CopyJournalSync(
        repository: repo,
        cloud: cloud,
        clock: () => DateTime.now().toUtc().add(const Duration(hours: 3)),
      );
      await tester.runAsync(sync.sync);
      await tester.runAsync(sync.sync);
      expect(cloud.creates, creates);
      expect(
        (await tester.runAsync(repo.readJournal))!
            .every((r) => r['state'] == 'synced'),
        true,
      );
      expect(
        (await tester.runAsync(() async => snapshotTables(copyPath)))!,
        before,
      );
      final first = cloud.events.first;
      cloud.events[0] = CopyCloudEvent(first.remoteId, {
        ...first.payload,
        'grade': first.payload['grade'] == 'mastered'
            ? 'forgotten'
            : 'mastered',
      });
      await tester.runAsync(sync.sync);
      expect(
        (await tester.runAsync(() async => snapshotTables(copyPath)))!,
        before,
      );
      expect(
        (await tester.runAsync(repo.readJournal))!.first['state'],
        'conflict',
      );
      await tester.runAsync(
        () => saveB1('recovery.json', {
          'pid': pid,
          'words': 100,
          'events': 8,
          'stable_ids': ids,
          'mock_creates_before': creates,
          'mock_creates_after': cloud.creates,
          'repeat_no_duplicates': true,
          'ratings_and_due_dates_unchanged': true,
          'remote_difference_quarantined': true,
          'cloud_kind': 'disk-backed simulation; no Notion requests',
          'personal_history_uploaded': false,
        }),
      );
    },
    skip: b1Root.isEmpty,
  );
}
