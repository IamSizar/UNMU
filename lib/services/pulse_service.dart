import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../controllers/auth_controller.dart';
import '../models/pulse_item.dart';
import 'auth_service.dart';

/// =============================================================================
/// pulse_service.dart — HTTP layer for UNMU Pulse (`/api/pulse/*`).
///
/// Everything goes through the abstract [PulseApi] so the controller and the
/// screens can be tested with a fake (no network). [HttpPulseApi] is the real
/// implementation.
///
/// Failures are classified, not thrown, because the UI treats them differently
/// (spec: errors are designed, not dumped):
///   offline      — no connection / timeout  → "check your connection", Retry
///   unauthorized — token rejected           → the app signs the user out
///   notFound     — item gone / not public   → "this item isn't available"
///   server       — anything else            → "something went wrong", Retry
/// =============================================================================

/// Why a request failed, in terms the UI cares about.
enum PulseFailure { offline, unauthorized, notFound, server }

/// A value or a failure — never both.
class PulseResult<T> {
  final T? data;
  final PulseFailure? failure;

  const PulseResult.ok(T this.data) : failure = null;
  const PulseResult.fail(PulseFailure this.failure) : data = null;

  bool get ok => failure == null;
}

/// What the Pulse screens need from the backend.
abstract class PulseApi {
  Future<PulseResult<PulseDay>> today();
  Future<PulseResult<PulseDay>> day(String date);
  Future<PulseResult<PulseItem>> item(int id);

  /// Past items, newest day first. [from] / [to] are YYYY-MM-DD, inclusive.
  Future<PulseResult<PulsePage>> archive({
    String? from,
    String? to,
    String? query,
    int offset = 0,
    int limit = 30,
  });

  Future<PulseResult<PulsePage>> saved({int offset = 0, int limit = 30});
  Future<bool> save(int itemId);
  Future<bool> unsave(int itemId);

  /// Fire-and-forget analytics. Never throws; failures are ignored.
  Future<void> recordEvent(String event, {int? itemId});
}

/// Analytics event names accepted by the backend (pulse_events CHECK).
abstract final class PulseEvent {
  static const viewDay = 'view_day';
  static const openItem = 'open_item';
  static const readComplete = 'read_complete';
  static const save = 'save';
  static const unsave = 'unsave';
  static const share = 'share';
  static const openSource = 'open_source';
  static const openStock = 'open_stock';
}

class HttpPulseApi implements PulseApi {
  static String get _base => ApiConfig.baseUrl;
  static const _timeout = Duration(seconds: 15);

  Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Runs a GET and maps the response into a [PulseResult].
  Future<PulseResult<T>> _get<T>(
    String path,
    T Function(Map<String, dynamic> json) parse,
  ) async {
    try {
      final res = await http
          .get(Uri.parse('$_base$path'), headers: await _headers())
          .timeout(_timeout);
      return await _handle(res, parse);
    } on TimeoutException {
      return const PulseResult.fail(PulseFailure.offline);
    } catch (_) {
      // SocketException / ClientException / handshake errors: no usable link.
      return const PulseResult.fail(PulseFailure.offline);
    }
  }

  Future<PulseResult<T>> _handle<T>(
    http.Response res,
    T Function(Map<String, dynamic> json) parse,
  ) async {
    if (res.statusCode == 401) {
      // Token expired or revoked: let the app sign the user out cleanly.
      if (Get.isRegistered<AuthController>()) {
        await Get.find<AuthController>().handleAuthFailure();
      }
      return const PulseResult.fail(PulseFailure.unauthorized);
    }
    if (res.statusCode == 404) {
      return const PulseResult.fail(PulseFailure.notFound);
    }
    if (res.statusCode != 200) {
      return const PulseResult.fail(PulseFailure.server);
    }
    try {
      final body = json.decode(utf8.decode(res.bodyBytes));
      if (body is! Map<String, dynamic>) {
        return const PulseResult.fail(PulseFailure.server);
      }
      return PulseResult.ok(parse(body));
    } catch (_) {
      return const PulseResult.fail(PulseFailure.server);
    }
  }

  @override
  Future<PulseResult<PulseDay>> today() =>
      _get('/pulse/today', PulseDay.fromJson);

  @override
  Future<PulseResult<PulseDay>> day(String date) =>
      _get('/pulse/days/$date', PulseDay.fromJson);

  @override
  Future<PulseResult<PulseItem>> item(int id) async {
    final res = await _get<PulseItem?>(
      '/pulse/items/$id',
      PulseItem.tryFromJson,
    );
    if (!res.ok) return PulseResult.fail(res.failure!);
    final item = res.data;
    // A 200 whose body we cannot read as an item counts as a server problem.
    return item == null
        ? const PulseResult.fail(PulseFailure.server)
        : PulseResult.ok(item);
  }

  @override
  Future<PulseResult<PulsePage>> archive({
    String? from,
    String? to,
    String? query,
    int offset = 0,
    int limit = 30,
  }) {
    final params = <String, String>{
      if (from != null) 'from': from,
      if (to != null) 'to': to,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'offset': '$offset',
      'limit': '$limit',
    };
    final qs = Uri(queryParameters: params).query;
    return _get('/pulse/archive?$qs', PulsePage.fromJson);
  }

  @override
  Future<PulseResult<PulsePage>> saved({int offset = 0, int limit = 30}) =>
      _get('/pulse/saved?offset=$offset&limit=$limit', PulsePage.fromJson);

  Future<bool> _send(String method, String path, [Object? body]) async {
    try {
      final uri = Uri.parse('$_base$path');
      final headers = await _headers();
      final http.Response res;
      if (method == 'POST') {
        res = await http
            .post(
              uri,
              headers: headers,
              body: body == null ? null : json.encode(body),
            )
            .timeout(_timeout);
      } else {
        res = await http.delete(uri, headers: headers).timeout(_timeout);
      }
      if (res.statusCode == 401 && Get.isRegistered<AuthController>()) {
        await Get.find<AuthController>().handleAuthFailure();
      }
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> save(int itemId) => _send('POST', '/pulse/items/$itemId/save');

  @override
  Future<bool> unsave(int itemId) =>
      _send('DELETE', '/pulse/items/$itemId/save');

  @override
  Future<void> recordEvent(String event, {int? itemId}) async {
    await _send('POST', '/pulse/events', {
      'event': event,
      if (itemId != null) 'itemId': itemId,
    });
  }
}
