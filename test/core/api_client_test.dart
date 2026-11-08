import 'package:english_learning/core/network/api_client.dart';
import 'package:english_learning/core/network/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';

void main() {
  final endpoint = Uri.parse('https://example.test/status');

  test('reads a JSON object', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url, endpoint);
      return Response('{"items":["Alpha"]}', 200);
    });
    addTearDown(client.close);
    final api = ApiClient(client: client);

    final body = await api.getJson(endpoint);

    expect(body['items'], <String>['Alpha']);
  });

  test('sends a JSON post body', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.headers['content-type'], 'application/json');
      expect(request.body, '{"name":"Alpha"}');
      return Response('{"ok":true}', 201);
    });
    addTearDown(client.close);
    final api = ApiClient(client: client);

    final body = await api.postJson(endpoint, body: const {'name': 'Alpha'});

    expect(body['ok'], isTrue);
  });

  test('maps a client failure to a network error', () async {
    final client = MockClient((request) async {
      throw ClientException('down');
    });
    addTearDown(client.close);
    final api = ApiClient(client: client);

    await expectLater(
      api.getJson(endpoint),
      throwsA(isA<ApiNetworkException>()),
    );
  });

  test('maps a slow response to a timeout', () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return Response('{}', 200);
    });
    addTearDown(client.close);
    final api = ApiClient(
      client: client,
      timeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      api.getJson(endpoint),
      throwsA(isA<ApiTimeoutException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
  });

  test('maps an HTTP error status', () async {
    final client = MockClient((request) async => Response('nope', 503));
    addTearDown(client.close);
    final api = ApiClient(client: client);

    await expectLater(
      api.getJson(endpoint),
      throwsA(
        isA<ApiStatusException>().having(
          (error) => error.statusCode,
          'statusCode',
          503,
        ),
      ),
    );
  });

  test('maps invalid JSON to a parse error', () async {
    final client = MockClient((request) async => Response('not-json', 200));
    addTearDown(client.close);
    final api = ApiClient(client: client);

    await expectLater(api.getJson(endpoint), throwsA(isA<ApiParseException>()));
  });

  test('maps a JSON list to a parse error', () async {
    final client = MockClient((request) async => Response('[1]', 200));
    addTearDown(client.close);
    final api = ApiClient(client: client);

    await expectLater(api.getJson(endpoint), throwsA(isA<ApiParseException>()));
  });
}
