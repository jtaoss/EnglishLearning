import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:english_learning/integrations/notion/notion_models.dart';

/// Only the official HTTPS read endpoints are implemented. Never follows redirects.
final class NotionReadApi {
  NotionReadApi(
    this.client, {
    this.timeout = const Duration(seconds: 20),
    Future<void> Function(Duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;
  final http.Client client;
  final Duration timeout;
  final Future<void> Function(Duration) delay;

  Future<Map<String, dynamic>> schema(NotionAccount account) =>
      _request(account, null);
  Future<Map<String, dynamic>> query(
    NotionAccount account,
    Map<String, Object?> body,
  ) => _request(account, body);

  Future<Map<String, dynamic>> _request(
    NotionAccount account,
    Map<String, Object?>? body,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final request =
            http.Request(
                body == null ? 'GET' : 'POST',
                Uri.https(
                  'api.notion.com',
                  '/v1/data_sources/${account.dataSourceId}${body == null ? '' : '/query'}',
                ),
              )
              ..followRedirects = false
              ..headers.addAll({
                'Authorization': 'Bearer ${account.token}',
                'Notion-Version': notionApiVersion,
                'Content-Type': 'application/json',
              });
        if (body != null) request.body = jsonEncode(body);
        final response = await client.send(request).timeout(timeout);
        final bytes = <int>[];
        await (() async {
          await for (final chunk in response.stream) {
            bytes.addAll(chunk);
            if (bytes.length > 2 * 1024 * 1024) {
              throw const NotionFailure('Notion 响应超过本阶段大小限制，原数据已保留。');
            }
          }
        })().timeout(timeout);
        if (response.statusCode == 429 || response.statusCode == 529) {
          final seconds =
              int.tryParse(response.headers['retry-after'] ?? '') ?? 2;
          if (attempt < 2 && seconds >= 0 && seconds <= 10) {
            await delay(Duration(seconds: seconds));
            continue;
          }
          throw const NotionFailure('Notion 请求受到限流，请稍后重试。本地词库仍可使用。');
        }
        if (response.statusCode >= 500 && attempt < 2) {
          await delay(Duration(seconds: attempt + 1));
          continue;
        }
        switch (response.statusCode) {
          case 200:
            break;
          case 401:
            throw const NotionFailure('Notion 密钥无效或已撤销，请重新安全保存。');
          case 403:
          case 404:
            throw const NotionFailure('无法读取目标词库。请在 Notion 中连接只读集成，并检查数据源 ID。');
          default:
            throw const NotionFailure('Notion 请求未成功，请检查连接和字段设置后重试。');
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        return decoded;
      } on NotionFailure {
        rethrow;
      } on TimeoutException {
        throw const NotionFailure('Notion 连接超时，本地数据已保留，可离线继续学习。');
      } on SocketException {
        throw const NotionFailure('网络连接不可用，本地数据已保留，可离线继续学习。');
      } on http.ClientException {
        throw const NotionFailure('网络连接不可用，本地数据已保留，可离线继续学习。');
      } catch (_) {
        throw const NotionFailure('Notion 响应无法安全读取，本地数据已保留。');
      }
    }
    throw const NotionFailure('Notion 请求暂时无法完成，请稍后重试。');
  }
}
