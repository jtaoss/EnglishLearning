import 'dart:io';
import 'dart:math';

import '../notion_credentials.dart';
import 'event_api.dart';
import 'event_model.dart';
import 'event_store.dart';

/// Single Windows writer. Unknown creates are reconciled, never blindly retried.
final class EventUploader {
  EventUploader({
    required this.store,
    required this.api,
    required this.credentials,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final EventQueueStore store;
  final EventApi api;
  final NotionCredentials credentials;
  final DateTime Function() clock;
  bool _busy = false;
  Future<String> sync() async {
    if (_busy) throw const EventFailure('busy');
    _busy = true;
    RandomAccessFile? lock;
    try {
      lock = await File('${store.path}.upload.lock')
          .open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
      } catch (_) {
        throw const EventFailure('busy');
      }
      final deferred = await store.deferredUntil();
      if (deferred != null && deferred.isAfter(clock().toUtc())) {
        return 'Notion 限流等待中，下次可重试 ${deferred.toLocal()}。本地模拟事件已保留。';
      }
      final account = await credentials.read();
      if (account == null) throw const EventFailure('no_credentials');
      final queue = await store.read();
      final eligible = queue
          .where(
            (r) =>
                !['synced', 'conflict', 'blocked'].contains(r.state) &&
                (r.nextAttempt == null ||
                    !r.nextAttempt!.isAfter(clock().toUtc())),
          )
          .toList();
      if (eligible.isEmpty) return '本地模拟事件 ${queue.length} 条；没有可立即上传的事件。';
      try {
        await api.validate(account);
      } on EventFailure catch (error) {
        final next = clock().toUtc().add(
          error.retryAfter ?? const Duration(seconds: 30),
        );
        if (error.retryAfter != null) await store.deferUntil(next);
        for (final r in eligible) {
          await store.update(
            r.event.id,
            r.state,
            next: next,
            error: error.code,
            begin: true,
          );
        }
        rethrow;
      }
      for (final row in queue) {
        if (row.state == 'synced' ||
            row.state == 'conflict' ||
            row.state == 'blocked') {
          continue;
        }
        if (row.nextAttempt != null &&
            row.nextAttempt!.isAfter(clock().toUtc())) {
          continue;
        }
        final e = row.event;
        final unknown = row.state == 'sending' || row.state == 'uncertain';
        var sending = false;
        try {
          final found = await api.find(account, eventId: e.id);
          if (found.length > 1 ||
              (found.length == 1 && !EventApi.matches(found.single, e))) {
            await store.update(e.id, 'conflict', error: 'remote_id_conflict');
            continue;
          }
          if (found.length == 1) {
            await store.update(
              e.id,
              'synced',
              remoteId: found.single['id'] as String,
            );
            continue;
          }
          if (unknown) {
            await store.update(
              e.id,
              'uncertain',
              next: clock().toUtc().add(const Duration(seconds: 60)),
              error: 'absence_not_proof',
            );
            continue;
          }
          // Commit intent BEFORE network. Crash here => reconcile-only on restart.
          await store.update(e.id, 'sending', begin: true);
          sending = true;
          final created = await api.create(account, e);
          if (!EventApi.matches(created, e)) {
            throw const EventFailure(
              'invalid_create_response',
              ambiguous: true,
            );
          }
          await store.update(e.id, 'synced', remoteId: created['id'] as String);
        } on EventFailure catch (error) {
          final state = unknown || sending && error.ambiguous
              ? 'uncertain'
              : [
                  'unauthorized',
                  'inaccessible',
                  'rejected',
                  'sandbox_scope',
                  'sandbox_schema',
                ].contains(error.code)
              ? 'blocked'
              : 'pending';
          final backoff =
              error.retryAfter ??
              Duration(seconds: min(3600, 5 * (1 << min(row.attempts + 1, 9))));
          if (error.retryAfter != null) {
            await store.deferUntil(clock().toUtc().add(backoff));
          }
          await store.update(
            e.id,
            state,
            next: clock().toUtc().add(backoff),
            error: error.code,
            begin: !sending,
          );
          if (error.code == 'rate_limited' ||
              ['unauthorized', 'inaccessible'].contains(error.code)) {
            break;
          }
        } catch (_) {
          // Includes local acknowledgement failure AFTER successful remote create.
          await store.update(e.id, 'uncertain', error: 'interrupted_ack');
          break;
        }
      }
      final rows = await store.read();
      int count(String s) => rows.where((r) => r.state == s).length;
      return '模拟事件 ${rows.length} 条：已同步 ${count('synced')}，待重试 ${count('pending')}，待对账 ${count('uncertain') + count('sending')}，冲突 ${count('conflict')}，受阻 ${count('blocked')}。';
    } on EventFailure {
      rethrow;
    } catch (_) {
      throw const EventFailure('safe_storage_or_connection_error');
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
