import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

import '../config/api_config.dart';

class PromoService {
  static String get baseUrl => '${ApiConfig.baseUrl}/promo';

  // Validate promo code
  static Future<Map<String, dynamic>> validatePromo(String code) async {
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
        body: json.encode({'code': code}),
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
