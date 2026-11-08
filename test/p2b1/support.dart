import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';
import 'package:english_learning/integrations/notion/journal/copy_journal_sync.dart';
import 'package:english_learning/integrations/notion/events/event_model.dart'
    show EventFailure;

void writePermit(String copy, String original) {
  File('$copy.copy-permit.json').writeAsStringSync(
    jsonEncode({
      'role': 'isolated_learning_copy',
      'simulation_only': true,
      'copy_path': File(copy).absolute.path,
      'protected_path': File(original).absolute.path,
    }),
  );
}

Map<String, String> snapshotTables(String path, {bool all = false}) {
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  try {
    final names = all
        ? db
              .select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
              )
              .map((r) => r['name'] as String)
              .toList()
        : [
            'vocabulary',
            'learning_progress',
            'review_events',
            'pronunciation_progress',
            'pronunciation_events',
            'notion_sync_state',
            'notion_word_links',
          ];
    return {
      for (final n in names)
        n: jsonEncode(
          db
              .select('SELECT * FROM $n ORDER BY 1')
              .map((r) => r.values.toList())
              .toList(),
        ),
    };
  } finally {
    db.close();
  }
}

Map<String, Object?> eventPayload(Map<String, Object?> row) =>
    (row['payload'] as Map).cast<String, Object?>();

class MemoryJournalCloud implements CopyJournalCloud {
  final events = <CopyCloudEvent>[];
  int creates = 0, finds = 0, pages = 0;
  bool offline = false,
      lostResponse = false,
      crashBeforeAck = false,
      secondPageFailure = false,
      incomplete = false,
      createRateLimit = false;
  Completer<void>? holdAfterCreate;
  Future<void> Function()? committed;
  @override
  Future<List<CopyCloudEvent>> find(String id) async {
    finds++;
    if (offline) throw const SocketException('controlled offline');
    return events.where((e) => e.payload['event_id'] == id).toList();
  }

  @override
  Future<CopyCloudEvent> create(Map<String, Object?> e) async {
    if (createRateLimit) {
      createRateLimit = false;
      throw const EventFailure(
        'rate_limited',
        retryAfter: Duration(seconds: 120),
      );
    }
    creates++;
    final created = CopyCloudEvent('mock-page-$creates', Map.of(e));
    events.add(created);
    if (committed != null) await committed!();
    if (holdAfterCreate != null) await holdAfterCreate!.future;
    if (lostResponse) {
      lostResponse = false;
      throw TimeoutException('controlled committed response loss');
    }
    return created;
  }

  @override
  Future<CopyJournalPage> page(String? cursor) async {
    pages++;
    if (offline) throw const SocketException('controlled offline');
    if (cursor != null && secondPageFailure) {
      throw const SocketException('controlled mid-page failure');
    }
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + 2).clamp(0, events.length);
    return CopyJournalPage(
      events.sublist(start, end),
      next: end < events.length ? '$end' : null,
      incomplete: incomplete,
    );
  }
}

Future<SqliteLearningRepository> reopenCopy(String path) =>
    SqliteLearningRepository.openIsolatedCopy(path);
