/// Failure from [ApiClient] that does not include request or response bodies.
sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ApiNetworkException extends ApiException {
  const ApiNetworkException() : super('The network request failed.');
}

final class ApiTimeoutException extends ApiException {
  const ApiTimeoutException() : super('The request timed out.');
}

final class ApiStatusException extends ApiException {
  const ApiStatusException(this.statusCode)
    : super('The server returned an HTTP error.');

  final int statusCode;
}

final class ApiParseException extends ApiException {
  const ApiParseException() : super('The response was not a JSON object.');
}
