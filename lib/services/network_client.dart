import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Runs [send], with a timeout and one automatic retry on a transient
/// failure (a network blip, a timeout, or a 5xx from the server) - never
/// on a 4xx, which won't succeed a second time. Shared by [getWithRetry]
/// and [postFormWithRetry] so both translate failures into the same
/// plain, user-facing [Exception] messages.
Future<http.Response> _sendWithRetry(
  Future<http.Response> Function() send,
  Duration timeout,
) async {
  Object? lastError;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final response = await send().timeout(timeout);
      if (response.statusCode >= 500 && attempt == 0) {
        continue; // one retry for a transient server-side failure
      }
      return response;
    } on SocketException catch (e) {
      lastError = e;
    } on TimeoutException catch (e) {
      lastError = e;
    } on http.ClientException catch (e) {
      lastError = e;
    }
  }

  if (lastError is SocketException) {
    throw Exception(
      'No internet connection. Check your network and try again.',
    );
  }
  if (lastError is TimeoutException) {
    throw Exception(
      'The request timed out. Check your connection and try again.',
    );
  }
  throw Exception('Network error: $lastError');
}

/// A GET request with a timeout and one automatic retry - see
/// [_sendWithRetry].
Future<http.Response> getWithRetry(
  Uri uri, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 12),
}) {
  return _sendWithRetry(() => http.get(uri, headers: headers), timeout);
}

/// A form-encoded POST request with a timeout and one automatic retry -
/// see [_sendWithRetry]. Some APIs (Overpass in particular) are pickier
/// about GET requests carrying a large query string than about the
/// equivalent POST body, so this exists as an alternative to
/// [getWithRetry] for those calls.
Future<http.Response> postFormWithRetry(
  Uri uri, {
  required Map<String, String> body,
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 12),
}) {
  return _sendWithRetry(() => http.post(uri, body: body, headers: headers), timeout);
}
