import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

import '../config/api_config.dart';

class PromoService {
  static String get baseUrl => '${ApiConfig.baseUrl}/promo';

  // Validate promo code. [context] ('expert' | 'community') lets the server
  // enforce a scoped code so an expert-only code is rejected on a community
  // purchase and vice-versa. The validate is a PREVIEW only — the actual
  // discount + redemption happen server-side when the subscription is created
  // (the subscribe endpoint takes the same code).
  static Future<Map<String, dynamic>> validatePromo(
    String code, {
    String context = '',
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'valid': false, 'message': 'Please login first'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/validate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'code': code,
          if (context.isNotEmpty) 'context': context,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error =
            json.decode(response.body)['error'] ?? 'Validation failed';
        return {'valid': false, 'message': error};
      }
    } catch (e) {
      return {'valid': false, 'message': 'Connection error: $e'};
    }
  }
}
