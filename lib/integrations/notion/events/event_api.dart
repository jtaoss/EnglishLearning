import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../notion_models.dart';
import 'event_model.dart';

/// Fixed official host; create has no automatic retry. No request logging.
final class EventApi {
  EventApi(
    this.client, {
    this.timeout = const Duration(seconds: 20),
    this.pageSize = 100,
    Future<void> Function(Duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;
  final http.Client client;
  final Duration timeout;
  final int pageSize;
  final Future<void> Function(Duration) delay;
  DateTime? _lastRequest;
  void _scope(NotionAccount account) {
    if (account.dataSourceId != eventSandboxSource) {
      throw const EventFailure('sandbox_scope');
    }
  }

  Future<Map<String, dynamic>> _request(
    NotionAccount account,
    String path, {
    Map<String, Object?>? body,
    bool create = false,
  }) async {
    _scope(account);
    // A single queue, below the smallest documented plan budget; 429 still wins.
    if (_lastRequest != null) {
      final rest =
          const Duration(milliseconds: 450) -
          DateTime.now().difference(_lastRequest!);
      if (rest > Duration.zero) await delay(rest);
    }
    _lastRequest = DateTime.now();
    try {
      final request =
          http.Request(
              body == null ? 'GET' : 'POST',
              Uri.https('api.notion.com', path),
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
          if (bytes.length > 2 * 1024 * 1024) throw const FormatException();
        }
      })().timeout(timeout);
      if (response.statusCode == 429 || response.statusCode == 529) {
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        throw EventFailure(
          'rate_limited',
          retryAfter: Duration(
            seconds: seconds == null || seconds < 0 ? 60 : seconds,
          ),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw EventFailure(
          response.statusCode == 401
              ? 'unauthorized'
              : [403, 404].contains(response.statusCode)
              ? 'inaccessible'
              : response.statusCode >= 500
              ? 'server_error'
              : 'rejected',
          ambiguous: create && response.statusCode >= 500,
        );
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic>) throw const FormatException();
      return json;
    } on EventFailure {
      rethrow;
    } on TimeoutException {
      throw EventFailure('timeout', ambiguous: create);
    } on SocketException {
      throw EventFailure('offline', ambiguous: create);
    } on http.ClientException {
      throw EventFailure('connection', ambiguous: create);
    } catch (_) {
      throw EventFailure('invalid_response', ambiguous: create);
    }
  }

  Future<void> validate(NotionAccount account) async {
    final schema = await _request(
      account,
      '/v1/data_sources/$eventSandboxSource',
    );
    final desc =
        (schema['description'] as List?)
            ?.map((r) => r['plain_text'] ?? r['text']?['content'] ?? '')
            .join() ??
        '';
    if (schema['id'] != eventSandboxSource ||
        !desc.contains('P2A_SIMULATION_ONLY')) {
      throw const EventFailure('sandbox_schema');
    }
    final props = schema['properties'] as Map? ?? {};
    const expected = {
      'Event ID': 'title',
      'Word ID': 'rich_text',
      'Learning Type': 'select',
      'Grade': 'rich_text',
      'Occurred At': 'date',
      'Device ID': 'rich_text',
      'Device Sequence': 'number',
      'Schema Version': 'number',
      'Algorithm Version': 'rich_text',
      'Payload Hash': 'rich_text',
      'Test Batch': 'rich_text',
      'Simulated': 'checkbox',
    };
    for (final e in expected.entries) {
      if (props[e.key]?['type'] != e.value) {
        throw const EventFailure('sandbox_schema');
      }
    }
  }

  Future<List<Map<String, dynamic>>> find(
    NotionAccount account, {
    String? eventId,
  }) async {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    String? cursor;
    do {
      final page = await _request(
        account,
        '/v1/data_sources/$eventSandboxSource/query',
        body: {
          'page_size': pageSize,
          'filter': {
            'and': [
              {
                'property': 'Test Batch',
                'rich_text': {'equals': eventTestBatch},
              },
              if (eventId != null)
                {
                  'property': 'Event ID',
                  'title': {'equals': eventId},
                },
            ],
          },
          'start_cursor': ?cursor,
        },
      );
      final rows = page['results'];
      if ((page['request_status'] as Map?)?['type'] == 'incomplete') {
        throw const EventFailure('incomplete_query');
      }
      if (rows is! List || page['has_more'] is! bool) {
        throw const EventFailure('invalid_pagination');
      }
      result.addAll(rows.cast<Map<String, dynamic>>());
      if (result.length > 1000) throw const EventFailure('query_bound');
      if (page['has_more'] == false) break;
      cursor = page['next_cursor'] as String?;
      if (cursor == null || cursor.isEmpty || !seen.add(cursor)) {
        throw const EventFailure('invalid_pagination');
      }
    } while (true);
    return result;
  }

  Future<Map<String, dynamic>> create(
    NotionAccount account,
    LearningEvent event,
  ) => _request(
    account,
    '/v1/pages',
    create: true,
    body: {
      'parent': {
        'type': 'data_source_id',
        'data_source_id': eventSandboxSource,
      },
      'properties': properties(event),
    },
  );
  static Map<String, Object> properties(LearningEvent event) {
    Map<String, Object> text(String value) => {
      'rich_text': [
        {
          'type': 'text',
          'text': {'content': value},
        },
      ],
    };
    return {
      'Event ID': {
        'title': [
          {
            'type': 'text',
            'text': {'content': event.id},
          },
        ],
      },
      'Word ID': text(event.wordId),
      'Learning Type': {
        'select': {'name': event.type},
      },
      'Grade': text(event.grade),
      'Occurred At': {
        'date': {'start': event.occurredAt.toUtc().toIso8601String()},
      },
      'Device ID': text(eventDevice),
      'Device Sequence': {'number': event.sequence},
      'Schema Version': {'number': 1},
      'Algorithm Version': text('simulation-v1'),
      'Payload Hash': text(event.hash),
      'Test Batch': text(eventTestBatch),
      'Simulated': {'checkbox': true},
    };
  }

  static bool matches(Map<String, dynamic> page, LearningEvent event) {
    try {
      final parent = page['parent'] as Map;
      if (parent['data_source_id'] != eventSandboxSource ||
          page['archived'] == true ||
          page['in_trash'] == true ||
          !notionIdPattern.hasMatch(page['id'] as String)) {
        return false;
      }
      final p = page['properties'] as Map;
      String text(String name, String type) => (p[name][type] as List)
          .map((r) => r['plain_text'] ?? r['text']['content'])
          .join();
      return text('Event ID', 'title') == event.id &&
          text('Word ID', 'rich_text') == event.wordId &&
          p['Learning Type']['select']['name'] == event.type &&
          text('Grade', 'rich_text') == event.grade &&
          DateTime.parse(p['Occurred At']['date']['start'] as String)
              .isAtSameMomentAs(event.occurredAt) &&
          text('Device ID', 'rich_text') == eventDevice &&
          p['Device Sequence']['number'] == event.sequence &&
          p['Schema Version']['number'] == 1 &&
          text('Algorithm Version', 'rich_text') == 'simulation-v1' &&
          text('Payload Hash', 'rich_text') == event.hash &&
          text('Test Batch', 'rich_text') == eventTestBatch &&
          p['Simulated']['checkbox'] == true;
    } catch (_) {
      return false;
    }
  }
}
