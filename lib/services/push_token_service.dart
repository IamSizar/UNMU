import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'auth_service.dart';

/// Per-device push-notification token plumbing.
///
/// Today this service does the minimum useful thing: it asks iOS for
/// notification permission, fetches the FCM token, and prints it to the
/// debug console. Tomorrow (next phase) the same token will get POSTed
/// to the backend so the admin dashboard can broadcast.
///
/// Why a singleton service: token refresh fires asynchronously from
/// Firebase whenever Apple/Google rotate the underlying APNs/FCM
/// identifier. We listen exactly once at app boot and dedupe by value
/// so subsequent boots don't spam the log.
class PushTokenService {
  PushTokenService._();
  static final PushTokenService instance = PushTokenService._();

  /// How long to wait for iOS to hand us an APNs token before giving
  /// up on this boot cycle. 10 s is generous — first launches on a
  /// physical device typically resolve in well under 2 s.
  static const Duration _kApnsWaitTimeout = Duration(seconds: 10);

  String? _lastToken;
  StreamSubscription<String>? _refreshSub;
  bool _booted = false;

  /// Called once from main.dart AFTER Firebase.initializeApp completes.
  /// Safe to call again — extra invocations no-op.
  ///
  /// On iOS the call sequence is:
  ///
  ///   1. requestPermission — user is prompted (or silently denied if
  ///      previously declined). Without `granted` or `provisional` we
  ///      still try to get a token; iOS may issue one if Background App
  ///      Refresh is enabled, but won't deliver alerts until permission
  ///      is granted.
  ///   2. getAPNSToken — bridges the iOS APNs token into Firebase. This
  ///      call CAN return null on the iOS Simulator (no real APNs) — we
  ///      log and continue rather than crash.
  ///   3. getToken — the FCM token we actually care about. This is the
  ///      string that uniquely identifies this device-app install pair.
  ///
  /// On Android getToken works directly without the APNs intermediate.
  Future<void> bootstrap() async {
    if (_booted) return;
    _booted = true;

    // Diagnostic banner — prints platform + simulator detection so the
    // log makes it obvious why APNs might not arrive. The simulator
    // exposes `SIMULATOR_DEVICE_NAME` as an env var that real devices
    // don't have, so we use it as a cheap probe with no plugin cost.
    if (Platform.isIOS) {
      final isSimulator =
          Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
      debugPrint('[push] platform=iOS  simulator=$isSimulator  '
          'name=${Platform.environment['SIMULATOR_DEVICE_NAME'] ?? "real device"}');
      if (isSimulator) {
        debugPrint(
          '[push] ⚠️  Running on iOS Simulator — APNs cannot be issued '
          'here, ever. FCM token will not resolve until you run on a '
          'physical iPhone.',
        );
      }
    } else if (Platform.isAndroid) {
      debugPrint('[push] platform=Android — FCM works without an APNs step.');
    }

    final messaging = FirebaseMessaging.instance;

    // iOS permission prompt. Defaults to alert + badge + sound; we
    // skip provisional / criticalAlert until we have a real reason to
    // use them. Android ignores this (permission is granted-by-default
    // up to Android 12 and prompted automatically afterwards).
    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('[push] iOS permission status: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('[push] requestPermission failed: $e');
    }

    // Foreground banner display: by default iOS suppresses banner
    // notifications while the app is in foreground (the message IS
    // delivered to onMessage, just no visual UI). Most social apps
    // override this so reels chat / mentions etc. still pop a banner
    // while the user is browsing. Android always shows banners; this
    // call is a no-op there.
    try {
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('[push] setForegroundNotificationPresentationOptions failed: $e');
    }

    // Foreground message arrival — log it so you can see what's being
    // delivered even when the system suppresses the banner (helpful for
    // debugging delivery without staring at the iPhone screen).
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[push] foreground message: title=${msg.notification?.title} '
          'body=${msg.notification?.body} data=${msg.data}');
    });

    // iOS: wait for APNs token before asking Firebase for the FCM token.
    // iOS hands APNs to the app asynchronously — on first launch it's
    // typically not ready for 0.5–2 seconds AFTER permission is granted.
    // Calling getToken() before APNs lands triggers the
    // `[firebase_messaging/apns-token-not-set]` PlatformException we hit
    // in production.
    //
    // Poll with 500 ms backoff up to [_kApnsWaitTimeout]. On the iOS
    // Simulator APNs never arrives, so we stop after the timeout and
    // continue (FCM token request will then fail and we log gracefully).
    // No-op on Android, which doesn't have an APNs intermediate step.
    if (Platform.isIOS) {
      await _waitForAPNs();
    }

    // The actual FCM token we send to the backend.
    await _refreshAndPrint();

    // Token can rotate (Apple/Google policies). Re-print + re-send
    // whenever Firebase reports a new value.
    _refreshSub?.cancel();
    _refreshSub = messaging.onTokenRefresh.listen((token) {
      _handleNewToken(token);
    });
  }

  /// Fetch + log the current token. Caller can also use this on demand
  /// (e.g. user signed in fresh and we want to re-register).
  ///
  /// One retry on failure: iOS sometimes still hasn't fully wired APNs
  /// even after [_waitForAPNs] succeeded (race between the system
  /// callback and Firebase's internal channel). A second attempt
  /// 500 ms later virtually always succeeds.
  Future<String?> _refreshAndPrint() async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        _handleNewToken(token);
        return token;
      } catch (e) {
        debugPrint('[push] getToken attempt $attempt failed: $e');
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    return null;
  }

  /// Wait up to [_kApnsWaitTimeout] for iOS to issue an APNs token.
  /// Returns the token (and logs it) on success; returns null after the
  /// timeout. Polls every 250 ms — cheap, since most real devices
  /// resolve in under 2 s on first launch.
  Future<String?> _waitForAPNs() async {
    final messaging = FirebaseMessaging.instance;
    final deadline = DateTime.now().add(_kApnsWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final apns = await messaging.getAPNSToken();
        if (apns != null && apns.isNotEmpty) {
          debugPrint('[push] APNs token: $apns');
          return apns;
        }
      } catch (e) {
        debugPrint('[push] getAPNSToken poll failed: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    debugPrint(
      '[push] APNs token still null after ${_kApnsWaitTimeout.inSeconds}s '
      '— likely simulator (no APNs) or push entitlement / provisioning '
      'profile is missing. FCM token won\'t resolve on iOS until APNs '
      'arrives.',
    );
    return null;
  }

  void _handleNewToken(String? token) {
    if (token == null || token.isEmpty) {
      debugPrint('[push] token is null/empty — no APNs link yet?');
      return;
    }
    if (token == _lastToken) return; // dedupe identical refreshes
    _lastToken = token;
    // FCM tokens are ~163 chars. `debugPrint` rate-limits long strings
    // and `flutter run`'s console truncates wrapped lines, so we use
    // raw `print` with a banner that's impossible to miss when scrolling
    // the log. The banner makes it trivial to grep / copy in one swoop.
    // ignore: avoid_print
    print('\n'
        '╔════════════ FCM TOKEN ════════════╗\n'
        '$token\n'
        '╚═══════════════════════════════════╝\n');
    // Fire-and-forget upload to the backend so the admin "Send to all"
    // broadcast can fan out to this device. Failure is non-fatal — on
    // next launch / token refresh we'll try again.
    unawaited(_sendTokenToBackend(token));
  }

  /// POSTs the FCM token to /api/me/push-token. No-op when the user
  /// isn't signed in yet (token gets re-sent automatically next time
  /// the service refreshes — onTokenRefresh or next bootstrap).
  Future<void> _sendTokenToBackend(String token) async {
    try {
      final authToken = await AuthService.getToken();
      if (authToken == null || authToken.isEmpty) {
        debugPrint('[push] backend register skipped — not signed in yet');
        return;
      }
      final platform = Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : 'web';
      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/me/push-token'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $authToken',
            },
            body: json.encode({'token': token, 'platform': platform}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        debugPrint('[push] backend register OK');
      } else {
        debugPrint('[push] backend register failed: '
            '${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('[push] backend register error: $e');
    }
  }

  /// Force-register the device's current token with the backend.
  ///
  /// Call this right after a successful sign-in / sign-up / email-verify /
  /// OAuth. The FCM token is fetched at app boot — almost always BEFORE the
  /// user authenticates — so the boot-time [_sendTokenToBackend] no-ops with
  /// "not signed in yet" and the token never reaches the server. Without a
  /// re-send on auth, a freshly-registered device is never mapped to the
  /// user and pushes silently never arrive.
  ///
  /// Unlike [_handleNewToken] this deliberately does NOT dedupe against
  /// [_lastToken]: the token value is usually unchanged across a login — it's
  /// the *auth state* that changed — so we must send it anyway. The backend
  /// upserts, so a duplicate POST is harmless.
  ///
  /// If no token has resolved yet (e.g. the user signed in on a fast first
  /// launch before APNs landed), we kick off a fresh fetch instead; the user
  /// is authenticated by then, so [_handleNewToken] will send it on arrival.
  Future<void> registerWithBackend() async {
    final token = _lastToken;
    if (token != null && token.isNotEmpty) {
      await _sendTokenToBackend(token);
    } else {
      await _refreshAndPrint();
    }
  }

  /// Exposed for the upcoming "send to backend" phase. Returns null
  /// until [bootstrap] has run + iOS has issued an APNs token.
  String? get currentToken => _lastToken;

  /// Defensive cleanup if the service ever gets torn down (Phoenix
  /// rebirth, etc.). Not currently called from anywhere — listed for
  /// completeness.
  void dispose() {
    _refreshSub?.cancel();
    _refreshSub = null;
    _booted = false;
  }
}
