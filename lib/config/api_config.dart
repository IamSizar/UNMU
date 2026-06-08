import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // Always use the live Railway backend (real production data) for EVERY build
  // — device, simulator, debug, release, and TestFlight. Set to `true` only if
  // you want to develop against the local Mac backend instead.
  static const bool useLocalBackend = false;

  // Live Railway backend (project UNMU).
  static const String railwayUrl = 'https://backend-production-c908.up.railway.app/api';

  /// LAN IP of the dev Mac running the Go backend. Replace this when you
  /// move to a different Wi-Fi or your router hands out a new DHCP lease.
  /// Used for real-device builds (iPhone / physical Android) so the phone
  /// can reach the laptop on the same Wi-Fi.
  static const String devMacLanIp = '192.168.1.75';

  static String get baseUrl {
    if (!useLocalBackend) return railwayUrl;

    // Web: served from the same Mac, localhost is fine.
    if (kIsWeb) return 'http://127.0.0.1:8080/api';

    // Android emulator: 10.0.2.2 is the special host-loopback address.
    // Real Android device on Wi-Fi: use the Mac's LAN IP instead.
    if (Platform.isAndroid) return 'http://$devMacLanIp:8080/api';

    // iOS: the SIMULATOR shares the Mac's network stack, so 127.0.0.1
    // reaches the backend reliably regardless of Wi-Fi / DHCP changes (and
    // even when the macOS firewall blocks inbound to the LAN IP). A real
    // iPhone has no localhost route to the Mac, so it falls back to the
    // Mac's LAN IP. The iOS simulator injects SIMULATOR_* env vars into the
    // app process, which is how we tell the two apart at runtime.
    final isIosSimulator =
        Platform.environment.containsKey('SIMULATOR_DEVICE_NAME');
    return isIosSimulator
        ? 'http://127.0.0.1:8080/api'
        : 'http://$devMacLanIp:8080/api';
  }

  // Endpoints
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String regions = '/regions';
  static const String stocksByRegion = '/regions';
  static const String shariahCheck = '/shariah/check';
  static const String userProfile = '/user/profile';
  static const String portfolio = '/user/portfolio';
  static const String notifications = '/user/notifications';
  static const String zakat = '/tools/zakat';
  static const String dca = '/tools/dca';
  static const String ads = '/ads';
  static const String validatePromo = '/promo/validate';
}
