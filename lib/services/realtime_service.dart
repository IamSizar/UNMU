import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import 'auth_service.dart';

/// One server-pushed event over the WebSocket.
class RealtimeEvent {
  final String type;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  const RealtimeEvent({
    required this.type,
    required this.data,
    required this.timestamp,
  });

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) => RealtimeEvent(
        type: json['type'] as String? ?? '',
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );

  @override
  String toString() => 'RealtimeEvent($type, $data)';
}

/// Thin WebSocket client that connects to `/api/ws?token=...` on the Go
/// backend, decodes incoming JSON events, and emits them through a stream.
///
/// Reconnects automatically with capped exponential backoff. The
/// [RealtimeController] (GetX) wraps this and dispatches events to the rest
/// of the app.
class RealtimeService {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  int _retry = 0;

  final _events = StreamController<RealtimeEvent>.broadcast();
  Stream<RealtimeEvent> get events => _events.stream;

  bool _connected = false;
  bool get isConnected => _connected;

  /// Open the connection. Reads the JWT from [AuthService.getToken]; aborts
  /// if no token is present (anonymous users get no WS).
  ///
  /// Sprint-C step 12 — pre-flight check that the JWT isn't already
  /// expired. If it is, we delete the stale token + skip the connect
  /// entirely. This avoids a tight reconnect loop on app start when
  /// the user's last session is older than the JWT TTL (one day).
  Future<void> connect() async {
    final token = await AuthService.getToken();
    if (token == null || token.isEmpty) return;
    if (token.startsWith('test-token-')) {
      // Local-only fake token from the old loginTest path — backend will
      // reject it, so don't even try (avoids reconnect loops).
      return;
    }
    if (_isJwtExpired(token)) {
      // Drop the stale token so the auth controller's bootstrap
      // path treats us as logged-out instead of replaying it.
      await AuthService.logout();
      return;
    }

    _disconnect();
    final uri = _buildUri(token);
    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        _onMessage,
        // Typed signature so the debugger's "break on uncaught"
        // doesn't pause inside this catch on every transient
        // WebSocket error — the stream contract considers an
        // onError callback as having handled the error.
        onError: (Object error, StackTrace stackTrace) async {
          _connected = false;
          // Sprint-C step 12 — if the upgrade was rejected as 401
          // the token is stale. Drop it locally so subsequent
          // calls don't loop forever with the same bad credential.
          if (error.toString().contains('401')) {
            await AuthService.logout();
            return;
          }
          _scheduleReconnect();
        },
        onDone: () {
          _connected = false;
          _scheduleReconnect();
        },
        // Cancel subscription on first error so we don't keep
        // receiving events on a dead channel before the reconnect
        // takes over.
        cancelOnError: true,
      );
      _connected = true;
      // NOTE: `_retry` is intentionally NOT reset here. The socket
      // is only optimistically up — actual handshake completes
      // async. Resetting on the first received message (see
      // _onMessage) is the correct point.
    } catch (_) {
      _connected = false;
      _scheduleReconnect();
    }
  }

  /// True when [token] is a JWT we can parse and its `exp` claim is
  /// already in the past. Best-effort — malformed JWTs return false
  /// so we still try to connect (server will reject and we'll fall
  /// through to the 401 handler in the onError above).
  static bool _isJwtExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      // Pad base64url so dart's decode doesn't choke.
      String pad(String s) {
        final mod = s.length % 4;
        if (mod == 0) return s;
        return s + ('=' * (4 - mod));
      }
      final payload = utf8.decode(base64Url.decode(pad(parts[1])));
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is! num) return false;
      final expMs = (exp.toInt()) * 1000;
      return DateTime.now().millisecondsSinceEpoch >= expMs;
    } catch (_) {
      return false;
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _disconnect();
  }

  void _disconnect() {
    _connected = false;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _onMessage(dynamic raw) {
    // Treat the first received frame as proof the handshake
    // completed — only at that point do we reset the retry counter
    // so a tight reconnect loop can't reset it on a half-open
    // connection that fails immediately after.
    if (_retry != 0) _retry = 0;
    try {
      final str = raw is String ? raw : utf8.decode(raw as List<int>);
      final json = jsonDecode(str) as Map<String, dynamic>;
      if (_events.isClosed) return;
      _events.add(RealtimeEvent.fromJson(json));
    } catch (_) {
      // Malformed — drop silently.
    }
  }

  void _scheduleReconnect() {
    _disconnect();
    _retry++;
    final delay = Duration(seconds: _retry > 6 ? 30 : (1 << _retry));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  /// Build ws(s)://host:port/api/ws?token=...
  Uri _buildUri(String token) {
    final base = Uri.parse(ApiConfig.baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '${base.path}/ws',
      queryParameters: {'token': token},
    );
  }
}
