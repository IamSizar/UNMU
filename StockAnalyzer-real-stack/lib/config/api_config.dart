import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  // Toggle this to false when you deploy to Railway
  static const bool useLocalBackend = false;
  
  // Replace this with your actual Railway app URL once deployed
  // e.g., 'https://halalstocks-production.up.railway.app'
  static const String railwayUrl = 'https://humble-consideration-production-b17c.up.railway.app/api';

  static String get baseUrl {
    if (!useLocalBackend) return railwayUrl;
    
    if (kIsWeb) return 'http://127.0.0.1:8080/api';
    if (Platform.isAndroid) return 'http://10.0.2.2:8080/api';
    return 'http://127.0.0.1:8080/api';
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
