import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notion_credentials.dart';
import '../notion_models.dart';
import 'event_api.dart';
import 'event_model.dart';
import 'event_store.dart';
import 'event_uploader.dart';

final class EventSandboxController extends ChangeNotifier {
  EventSandboxController({
    required this.openStore,
    required this.credentials,
    required this.api,
    required this.loadIds,
  });
  final Future<EventQueueStore> Function() openStore;
  final NotionCredentials credentials;
  final EventApi api;
  final Future<List<String>> Function() loadIds;
  EventQueueStore? _store;
  EventUploader? _uploader;
  bool busy = false, configured = false, _disposed = false;
  List<QueuedEvent> rows = [];
  String? message, error;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _action(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      _store ??= await openStore();
      _uploader ??= EventUploader(
        store: _store!,
        api: api,
        credentials: credentials,
      );
      await action();
      rows = await _store!.read();
      configured = await credentials.read() != null;
    } on EventFailure catch (e) {
      error = switch (e.code) {
        'no_credentials' => '请安全保存独立测试集成凭据。',
        'rate_limited' => 'Notion 限流，已保存下次重试时间，请稍后重试。',
        'busy' => '另一个同步任务正在运行，请稍后重试。',
        'sandbox_scope' || 'sandbox_schema' => '目标不是已核定的模拟事件测试库，未写入。',
        'unauthorized' || 'inaccessible' => '测试集成无法访问目标库，请检查凭据和授权。',
        _ => '实验暂未完成，本地事件已保留。请检查连接后重试或对账。',
      };
      if (_store != null) {
        rows = await _store!.read();
      }
    } catch (_) {
      error = '无法安全打开实验数据或连接配置，个人学习库未被操作。';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> restore() => _action(() async {});
  Future<void> seed() => _action(() async {
    await _store!.enqueue(LearningEvent.generate(await loadIds()));
    message = '24 条模拟事件已先保存 SQLite，尚未修改任何个人学习记录。';
  });
  Future<void> sync() => _action(() async {
    message = await _uploader!.sync();
  });
  Future<void> save(String token) => _action(() async {
    await credentials.save(
      NotionAccount(dataSourceId: eventSandboxSource, token: token),
    );
    message = '测试集成凭据已安全保存，词库只读集成保持独立。';
  });
  @override
  void dispose() {
    _disposed = true;
    unawaited(_store?.close() ?? Future<void>.value());
    api.client.close();
    super.dispose();
  }
}
