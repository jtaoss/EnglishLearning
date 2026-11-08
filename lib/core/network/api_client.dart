import 'dart:async';
import 'dart:convert';

import 'package:english_learning/core/network/api_exception.dart';
import 'package:http/http.dart' as http;

/// Small JSON client.
///
/// Callers supply the [http.Client] and the [Uri]. This type has no base URL,
/// no credentials, and it does not write requests or response bodies to a log.
final class ApiClient {
  ApiClient({required this.client, this.timeout = const Duration(seconds: 10)});

  final http.Client client;
  final Duration timeout;

  static const _jsonHeaders = <String, String>{
    'content-type': 'application/json',
  };

  Future<Map<String, Object?>> getJson(Uri uri) {
    return _send(() => client.get(uri));
  }

  Future<Map<String, Object?>> postJson(
    Uri uri, {
    Map<String, Object?> body = const <String, Object?>{},
  }) {
    return _send(
      () => client.post(uri, headers: _jsonHeaders, body: jsonEncode(body)),
    );
  }

  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() send,
  ) async {
    final http.Response response;
    try {
      response = await send().timeout(timeout);
    } on TimeoutException {
      throw const ApiTimeoutException();
    } on http.ClientException {
      throw const ApiNetworkException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiStatusException(response.statusCode);
    }
    return _decode(response.body);
  }

  Map<String, Object?> _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const ApiParseException();
      }
      return Map<String, Object?>.from(decoded);
    } on ApiParseException {
      rethrow;
    } on FormatException {
      throw const ApiParseException();
    }
  }
}
