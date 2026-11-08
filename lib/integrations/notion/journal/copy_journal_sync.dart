import 'dart:async';
import 'dart:io';

import 'package:english_learning/core/storage/copy_learning_journal.dart';
import 'package:english_learning/core/storage/sqlite_learning_repository.dart';

import '../events/event_model.dart' show EventFailure;

/// Contract for isolated protocol tests. No production HTTP or credentials here.
abstract interface class CopyJournalCloud {
  Future<List<CopyCloudEvent>> find(String eventId);
  Future<CopyCloudEvent> create(Map<String, Object?> event);
  Future<CopyJournalPage> page(String? cursor);
}

final class CopyCloudEvent {
  const CopyCloudEvent(this.remoteId, this.payload);
  final String remoteId;
  final Map<String, Object?> payload;
}

final class CopyJournalPage {
  const CopyJournalPage(this.events, {this.next, this.incomplete = false});
  final List<CopyCloudEvent> events;
  final String? next;
  final bool incomplete;
}

/// P2-B1 round trip: upload synthetic copy events, receive into a review inbox.
final class CopyJournalSync {
  CopyJournalSync({
    required this.repository,
    required this.cloud,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    if (!repository.isIsolatedCopy) throw StateError('只允许隔离副本同步验证。');
  }
  final SqliteLearningRepository repository;
  final CopyJournalCloud cloud;
  final DateTime Function() clock;
  bool _busy = false;
  Future<void> sync() async {
    if (_busy) throw const EventFailure('busy');
    _busy = true;
    RandomAccessFile? lock;
    try {
      lock = await File('${repository.path}.journal-sync.lock')
          .open(mode: FileMode.append);
      await lock.lock(FileLock.exclusive);
      final deferred = await repository.journalDeferredUntil();
      if (deferred != null &&
          deferred > clock().toUtc().millisecondsSinceEpoch) {
        return;
      }
      final records = await repository.readJournal();
      for (final row in records) {
        if (['synced', 'conflict'].contains(row['state'])) continue;
        final next = row['next_attempt_utc'] as int?;
        if (next != null && next > clock().toUtc().millisecondsSinceEpoch) {
          continue;
        }
        final payload = (row['payload'] as Map).cast<String, Object?>();
        final id = payload['event_id'] as String;
        if (payload['origin'] != 'simulation_test' ||
            journalPayloadHash(payload) != row['hash']) {
          throw const EventFailure('unsafe_journal_payload');
        }
        final wasUnknown = ['sending', 'uncertain'].contains(row['state']);
        var creating = false;
        try {
          final remote = await cloud.find(id);
          if (remote.length > 1 ||
              remote.length == 1 &&
                  journalPayloadHash(remote.single.payload) != row['hash']) {
            await repository.receiveJournalEvents(
              remote.map((e) => e.payload).toList(),
            );
            await repository.setJournalState(
              id,
              'conflict',
              error: 'remote_difference',
            );
            continue;
          }
          if (remote.length == 1) {
            await repository.receiveJournalEvents(
              remote.map((e) => e.payload).toList(),
            );
            await repository.setJournalState(
              id,
              'synced',
              remoteId: remote.single.remoteId,
            );
            continue;
          }
          if (wasUnknown) {
            await repository.setJournalState(
              id,
              'uncertain',
              next: clock().toUtc().add(const Duration(seconds: 60)),
              error: 'absence_not_proof',
            );
            continue;
          }
          await repository.setJournalState(id, 'sending');
          creating = true;
          final created = await cloud.create(payload);
          if (created.remoteId.isEmpty ||
              journalPayloadHash(created.payload) != row['hash']) {
            throw const EventFailure(
              'invalid_create_response',
              ambiguous: true,
            );
          }
          await repository.setJournalState(
            id,
            'synced',
            remoteId: created.remoteId,
          );
        } catch (error) {
          final definiteRejection =
              error is EventFailure &&
              error.code == 'rate_limited' &&
              !error.ambiguous;
          final ambiguous = wasUnknown || creating && !definiteRejection;
          final retry = error is EventFailure ? error.retryAfter : null;
          await repository.setJournalState(
            id,
            ambiguous ? 'uncertain' : 'pending',
            next: clock().toUtc().add(retry ?? const Duration(seconds: 30)),
            error: ambiguous ? 'unknown_write' : 'read_or_connection_failure',
          );
          if (error is EventFailure && error.code == 'rate_limited') {
            await repository.deferJournalUntil(
              clock().toUtc().add(retry ?? const Duration(seconds: 60)),
            );
            return;
          }
        }
      }
      // Stage EVERY page before one transaction; a mid-page failure writes none.
      final incoming = <Map<String, Object?>>[];
      final seen = <String>{};
      String? cursor;
      do {
        final batch = await cloud.page(cursor);
        if (batch.incomplete) throw const EventFailure('incomplete_query');
        incoming.addAll(batch.events.map((e) => e.payload));
        if (incoming.length > 1000) {
          throw const EventFailure('copy_query_bound');
        }
        cursor = batch.next;
        if (cursor != null && (cursor.isEmpty || !seen.add(cursor))) {
          throw const EventFailure('invalid_pagination');
        }
      } while (cursor != null);
      await repository.receiveJournalEvents(incoming);
    } finally {
      if (lock != null) {
        try {
          await lock.unlock();
        } catch (_) {}
        await lock.close();
      }
      _busy = false;
    }
  }
}
