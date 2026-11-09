import 'package:english_learning/core/storage/learning_repository.dart';
import 'package:english_learning/integrations/notion/notion_api.dart';
import 'package:english_learning/integrations/notion/notion_credentials.dart';
import 'package:english_learning/integrations/notion/notion_models.dart';

final class NotionSyncService {
  NotionSyncService({
    required this.store,
    required this.credentials,
    required this.api,
    required this.loadScope,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final NotionSyncStore store;
  final NotionCredentials credentials;
  final NotionReadApi api;
  final Future<NotionScope> Function() loadScope;
  final DateTime Function() clock;
  bool _syncing = false;

  Future<ImportResult> sync({bool full = false, int? limit}) async {
    if (_syncing) throw const NotionFailure('同步正在进行，请等待完成。');
    _syncing = true;
    try {
      final account = await credentials.read();
      if (account == null) throw const NotionFailure('尚未配置只读集成，请先安全保存密钥。');
      final reviewed = await loadScope();
      final scope = limit == null ? reviewed : reviewed.take(limit);
      final old = await store.readNotionState(account.dataSourceId);
      final source = await api.schema(account);
      NotionFields.validateSchema(source, account.dataSourceId);
      // A larger approved scope needs a complete read, including older pages.
      final first =
          old.watermark == null ||
          full ||
          old.linkedWords < scope.entries.length;
      final records = <NotionWord>[];
      final pages = <String>{}, ids = <String>{};
      var watermark = old.watermark;
      // Notion compound filters allow at most 100 conditions per group.
      // Commit only after every group and every page has passed validation.
      for (var offset = 0; offset < scope.entries.length; offset += 100) {
        final group = scope.entries.skip(offset).take(100);
        final idFilter = {
          'or': [
            for (final e in group)
              {
                'property': '词条ID',
                'rich_text': {'equals': e.id},
              },
          ],
        };
        final cursors = <String>{};
        String? cursor;
        for (var pageNumber = 0; ; pageNumber++) {
          if (pageNumber >= 10) {
            throw const NotionFailure('Notion 分页超过本阶段限制，整批未同步。');
          }
          await api.delay(const Duration(milliseconds: 350));
          final page = await api.query(account, {
            'page_size': 100,
            'is_archived': false,
            'sorts': [
              {'timestamp': 'last_edited_time', 'direction': 'ascending'},
            ],
            'filter': first
                ? idFilter
                : {
                    'and': [
                      idFilter,
                      {
                        'timestamp': 'last_edited_time',
                        'last_edited_time': {
                          'on_or_after': old.watermark!
                              .subtract(const Duration(minutes: 2))
                              .toIso8601String(),
                        },
                      },
                    ],
                  },
            'start_cursor': ?cursor,
          });
          final rows = page['results'];
          if (page['object'] != 'list' ||
              rows is! List ||
              page['has_more'] is! bool) {
            throw const NotionFailure('Notion 分页响应异常，整批未同步。');
          }
          for (final row in rows) {
            if (row is! Map<String, dynamic>) {
              throw const NotionFailure('Notion 返回无效词条，整批未同步。');
            }
            final word = NotionFields.read(row, scope, account.dataSourceId);
            if (!pages.add(word.pageId) || !ids.add(word.entry.id)) {
              throw const NotionFailure('Notion 存在重复页面或稳定 ID，请先人工核对；整批未同步。');
            }
            records.add(word);
            if (records.length > scope.entries.length) {
              throw const NotionFailure('同步超出已核验词库范围，整批未同步。');
            }
            if (watermark == null || word.editedAt.isAfter(watermark)) {
              watermark = word.editedAt;
            }
          }
          if (page['has_more'] == false) break;
          final next = page['next_cursor'];
          if (next is! String || next.isEmpty || !cursors.add(next)) {
            throw const NotionFailure('Notion 分页游标异常，整批未同步。');
          }
          cursor = next;
        }
      }
      if (first && ids.length != scope.entries.length) {
        throw NotionFailure(
          '${scope.entries.length} 词核对未完整返回，请检查词库扩容是否已完成、授权、稳定 ID 或归档状态。原数据已保留。',
        );
      }
      return await store.applyNotionBatch(
        sourceId: account.dataSourceId,
        words: records,
        expectedWatermark: old.watermark,
        watermark: watermark,
        syncedAt: clock().toUtc(),
      );
    } on NotionFailure {
      rethrow;
    } catch (_) {
      throw const NotionFailure('同步未完成，本地词库和学习记录已保留，请重试。');
    } finally {
      _syncing = false;
    }
  }
}
