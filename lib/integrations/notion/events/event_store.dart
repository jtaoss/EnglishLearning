import 'dart:convert';
import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';

import 'event_model.dart';

/// A separate SQLite file: cannot update meaning/pronunciation/personal tables.
abstract interface class EventQueueStore {
  String get path;
  Future<void> enqueue(List<LearningEvent> events);
  Future<List<QueuedEvent>> read();
  Future<DateTime?> deferredUntil();
  Future<void> deferUntil(DateTime at);
  Future<void> update(
    String id,
    String state, {
    DateTime? next,
    String? remoteId,
    String? error,
    bool begin = false,
  });
  Future<void> close();
}

final class EventStore implements EventQueueStore {
  EventStore._(this.path);
  @override
  final String path;
  Future<void> _tail = Future<void>.value();
  bool _closed = false;
  static Future<EventStore> open(String path) async {
    final store = EventStore._(path);
    await store._run('init');
    return store;
  }

  Future<Object?> _run(String action, [List<Object?> args = const []]) {
    if (_closed) return Future.error(StateError('Simulation store closed'));
    final p = path;
    final result = _tail.then(
      (_) => Isolate.run(() => _execute(p, action, args)),
    );
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<void> enqueue(List<LearningEvent> events) async {
    await _run('enqueue', events.map((e) => jsonEncode(e.payload)).toList());
  }

  @override
  Future<List<QueuedEvent>> read() async =>
      ((await _run('read')) as List).map((row) {
        final r = row as List;
        final e = LearningEvent.decode(r[0] as String);
        if (e.hash != r[1]) throw const EventFailure('local_hash_mismatch');
        return QueuedEvent(
          e,
          r[2] as String,
          r[3] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(r[3] as int, isUtc: true),
          r[4] as int,
          r[5] as String?,
        );
      }).toList();
  @override
  Future<DateTime?> deferredUntil() async {
    final value = await _run('deferred');
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value as int, isUtc: true);
  }

  @override
  Future<void> deferUntil(DateTime at) async {
    await _run('defer', [at.toUtc().millisecondsSinceEpoch]);
  }

  @override
  Future<void> update(
    String id,
    String state, {
    DateTime? next,
    String? remoteId,
    String? error,
    bool begin = false,
  }) async {
    await _run('update', [
      id,
      state,
      next?.toUtc().millisecondsSinceEpoch,
      remoteId,
      error,
      begin ? 1 : 0,
    ]);
  }

  @override
  Future<void> close() async {
    _closed = true;
    await _tail;
  }
}

Object? _execute(String path, String action, List<Object?> args) {
  final db = sqlite3.open(path);
  try {
    db.execute('PRAGMA foreign_keys=ON');
    db.execute('PRAGMA busy_timeout=5000');
    if (action == 'init') {
      final version =
          db.select('PRAGMA user_version').single.values.single as int;
      final names = db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .map((r) => r['name'])
          .toSet();
      if (version == 0 && names.isEmpty) {
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute(
            'CREATE TABLE simulation_events(event_id TEXT PRIMARY KEY NOT NULL, word_id TEXT NOT NULL, learning_type TEXT NOT NULL, grade TEXT NOT NULL, occurred_utc INTEGER NOT NULL, payload_json TEXT NOT NULL, payload_hash TEXT NOT NULL, device_sequence INTEGER UNIQUE NOT NULL)',
          );
          db.execute(
            "CREATE TABLE event_outbox(event_id TEXT PRIMARY KEY REFERENCES simulation_events(event_id), state TEXT NOT NULL CHECK(state IN ('pending','sending','uncertain','synced','conflict','blocked')), next_attempt_utc INTEGER, attempts INTEGER NOT NULL DEFAULT 0, remote_page_id TEXT, last_error_code TEXT)",
          );
          db.execute('PRAGMA user_version=1');
          db.execute(
            'CREATE TABLE event_sync_control(singleton INTEGER PRIMARY KEY CHECK(singleton=1), deferred_until_utc INTEGER)',
          );
          db.execute('INSERT INTO event_sync_control VALUES(1,NULL)');
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } else if (version != 1 ||
          names.length != 3 ||
          !names.containsAll({
            'simulation_events',
            'event_outbox',
            'event_sync_control',
          })) {
        throw const EventFailure('not_a_simulation_database');
      }
      return null;
    }
    if (action == 'enqueue') {
      db.execute('BEGIN IMMEDIATE');
      try {
        for (final value in args) {
          final e = LearningEvent.decode(value as String);
          final old = db.select(
            'SELECT payload_hash FROM simulation_events WHERE event_id=?',
            [e.id],
          );
          if (old.isNotEmpty && old.single['payload_hash'] != e.hash) {
            throw const EventFailure('local_id_conflict');
          }
          db.execute(
            'INSERT OR IGNORE INTO simulation_events VALUES(?,?,?,?,?,?,?,?)',
            [
              e.id,
              e.wordId,
              e.type,
              e.grade,
              e.occurredAt.toUtc().millisecondsSinceEpoch,
              value,
              e.hash,
              e.sequence,
            ],
          );
          db.execute(
            "INSERT OR IGNORE INTO event_outbox(event_id,state) VALUES(?,'pending')",
            [e.id],
          );
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
      return null;
    }
    if (action == 'deferred') {
      return db
          .select(
            'SELECT deferred_until_utc FROM event_sync_control WHERE singleton=1',
          )
          .single
          .values
          .single;
    }
    if (action == 'defer') {
      db.execute(
        'UPDATE event_sync_control SET deferred_until_utc=MAX(COALESCE(deferred_until_utc,0),?) WHERE singleton=1',
        args,
      );
      return null;
    }
    if (action == 'read') {
      return db
          .select(
            'SELECT e.payload_json,e.payload_hash,o.state,o.next_attempt_utc,o.attempts,o.remote_page_id FROM simulation_events e JOIN event_outbox o USING(event_id) ORDER BY e.device_sequence',
          )
          .map((r) => r.values.toList())
          .toList();
    }
    if (action == 'update') {
      db.execute(
        'UPDATE event_outbox SET state=?,next_attempt_utc=?,remote_page_id=COALESCE(?,remote_page_id),last_error_code=?,attempts=attempts+? WHERE event_id=?',
        [args[1], args[2], args[3], args[4], args[5], args[0]],
      );
      if (db.updatedRows != 1) throw const EventFailure('missing_local_event');
      return null;
    }
    throw StateError('Unknown simulation operation');
  } finally {
    db.close();
  }
}
