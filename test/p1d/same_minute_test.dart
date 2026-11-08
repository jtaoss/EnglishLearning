import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/features/review/review_schedule.dart';
import 'package:english_learning/features/pronunciation/pronunciation_store.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

import '../p1c/support.dart';

void main() {
  test('same-minute cloud edits update content twice while grades and due dates remain exact', () async {
    final folder = await Directory.systemTemp.createTemp('p1d_same_minute_');
    final repo = await SqliteLearningRepository.open(
      '${folder.path}/learning.sqlite3',
    );
    addTearDown(() async {
      await repo.close();
      await folder.delete(recursive: true);
    });
    final data = snapshot();
    final pages = (data['pages'] as List).cast<Map<String, dynamic>>();
    final big = pages.singleWhere(
      (p) => p['properties']['单词']['title'][0]['plain_text'] == 'big',
    );
    var first = true;
    final client = MockClient((request) async {
      if (request.method == 'GET') return jsonResponse(data['schema']);
      final result = listResponse(first ? pages : [big]);
      first = false;
      return jsonResponse(result);
    });
    addTearDown(client.close);
    final service = NotionSyncService(
      store: repo,
      credentials: MemoryCredentials(testAccount()),
      api: NotionReadApi(client, delay: noDelay),
      loadScope: () async => testScope(),
    );
    await service.sync();
    final id = NotionFields.read(big, testScope(), notionPilotSource).entry.id;
    final at = DateTime.utc(2026, 11, 8, 15, 59, 30);
    await repo.recordReview(id, ReviewGrade.familiar, at);
    await repo.recordPronunciation(
      entryId: id,
      grade: PronunciationGrade.familiar,
      audioAssetId: 'test-audio',
      attemptId: 'same-minute-preservation',
      at: at,
    );
    final before = (await repo.readWords()).singleWhere(
      (w) => w.entry.id == id,
    );
    final watermark = (await repo.readNotionState(notionPilotSource)).watermark;
    for (final note in ['first edit', 'second edit']) {
      setText(
        big,
        '用法说明',
        note,
      ); // Intentionally keep identical remote timestamp.
      expect((await service.sync()).updated, 1);
      final after = (await repo.readWords()).singleWhere(
        (w) => w.entry.id == id,
      );
      expect(after.entry.fields['usage_note'], note);
      expect(after.status, before.status);
      expect(after.reviewCount, before.reviewCount);
      expect(after.dueAt, before.dueAt);
      expect(after.lastReviewedAt, before.lastReviewedAt);
      expect(
        (await repo.readNotionState(notionPilotSource)).watermark,
        watermark,
      );
      expect(
        (await repo.readPronunciation(id)).grade,
        PronunciationGrade.familiar,
      );
      expect(await repo.reviewEventCount(), 1);
    }
  });
}
