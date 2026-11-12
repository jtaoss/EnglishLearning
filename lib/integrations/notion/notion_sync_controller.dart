import 'package:flutter/foundation.dart';
import 'package:english_learning/features/vocabulary/vocabulary_csv.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';
import 'package:english_learning/integrations/notion/notion_sync_service.dart';

final class NotionSyncController extends ChangeNotifier {
  NotionSyncController(
    this.service, {
    required this.refreshVocabulary,
    this.storageLabel = 'Windows 凭据管理器',
    this.isMobile = false,
  });
  final String storageLabel;
  final bool isMobile;
  final NotionSyncService service;
  final Future<bool> Function() refreshVocabulary;
  bool busy = false, configured = false, _disposed = false;
  String sourceId = notionPilotSource;
  int scopeLength = 500;
  bool scopeLoaded = false;
  int targetSize = 100;
  String? message, error;
  NotionSyncState state = const NotionSyncState();
  List<int> get selectableSizes => NotionScope.selectableSizes(scopeLength);

  void selectSize(int size) {
    if (busy || _disposed || !selectableSizes.contains(size)) return;
    targetSize = size;
    _notify();
  }

  Future<void> restore() => _perform(() async {
    final account = await service.credentials.read();
    configured = account != null;
    if (account != null) sourceId = account.dataSourceId;
    state = await service.store.readNotionState(sourceId);
    final scope = await service.loadScope();
    scopeLength = scope.entries.length;
    scopeLoaded = true;
    if (!isMobile) {
      if (scopeLength == VocabularyCsv.maxEntries) {
        targetSize = VocabularyCsv.maxEntries;
      } else {
        final available = state.linkedWords == 0
            ? scopeLength
            : state.linkedWords;
        targetSize = available > 200
            ? 500
            : available > 100
            ? 200
            : 100;
      }
    }
  });

  Future<void> save(String source, String token) => _perform(() async {
    final account = NotionAccount(
      dataSourceId: source.trim(),
      token: token.trim(),
    );
    await service.credentials.save(account);
    sourceId = account.dataSourceId;
    configured = true;
    state = await service.store.readNotionState(sourceId);
    message = '已存入 $storageLabel。可以开始同步。';
  });

  Future<void> forget() => _perform(() async {
    await service.credentials.delete();
    configured = false;
    message = '已删除本机连接凭据，本地词库和学习记录仍保留。';
  });

  Future<void> sync({bool full = false}) => _perform(() async {
    final result = await service.sync(
      full: full,
      limit: isMobile ? 100 : targetSize,
    );
    state = await service.store.readNotionState(sourceId);
    message = '${result.message}。本地共关联 ${state.linkedWords} 词。';
    final refreshed = await refreshVocabulary();
    if (!refreshed) message = '$message 词条已保存，请返回词库后刷新显示。';
  });

  Future<void> _perform(Future<void> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    error = null;
    message = null;
    _notify();
    try {
      await action();
    } on NotionFailure catch (failure) {
      error = failure.message;
    } catch (_) {
      error = '操作未完成，原有本地数据已保留，请重试。';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
