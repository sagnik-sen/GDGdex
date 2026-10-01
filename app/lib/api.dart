import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final int status;
  final String message;
  final String? code;
  ApiException(this.status, this.message, [this.code]);
  @override
  String toString() => message;
}

/// Same-origin API client. Auth is an HttpOnly session cookie the browser sends automatically.
class Api {
  static final _client = http.Client();

  /// Logged-in member (null = signed out). Screens listen to this.
  static final me = ValueNotifier<Json?>(null);

  static Future<Json> get(String path) => _send('GET', path);
  static Future<Json> post(String path, [Object? body]) => _send('POST', path, body);
  static Future<Json> patch(String path, Object body) => _send('PATCH', path, body);

  static Future<Json> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.base.resolve('/api/$path'));
    if (body != null) {
      req.headers['content-type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(const Duration(seconds: 12)));
    } on TimeoutException {
      throw ApiException(0, 'Network is slow — tap to try again.', 'NETWORK');
    } catch (_) {
      throw ApiException(0, "Can't reach GDGdex. Check your connection and retry.", 'NETWORK');
    }
    final Json data = res.body.startsWith('{') ? jsonDecode(res.body) : {};
    if (res.statusCode >= 400) {
      if (res.statusCode == 401) me.value = null;
      throw ApiException(res.statusCode, data['error'] ?? 'Something went wrong (${res.statusCode}).', data['code']);
    }
    return data;
  }

  static Future<Json?> refreshMe() async {
    try {
      return me.value = await get('me');
    } on ApiException catch (e) {
      if (e.status == 401) return null;
      rethrow;
    }
  }

  static Future<void> login(String email, String regNo) async =>
      me.value = await post('login', {'email': email, 'regNo': regNo});

  static Future<void> logout() async {
    await post('logout').catchError((_) => <String, dynamic>{});
    me.value = null;
  }
}
