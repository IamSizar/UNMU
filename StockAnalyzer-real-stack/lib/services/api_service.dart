import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiService {
  static String get baseUrl => ApiConfig.baseUrl;

  // Search stocks
  static Future<List<Map<String, dynamic>>> searchStocks(String query) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/search?q=$query'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['stocks'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Get stock details
  static Future<Map<String, dynamic>?> getStockDetails(
    String ticker,
    String exchange,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/stocks/$ticker?exchange=$exchange'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get stocks by region
  static Future<List<Map<String, dynamic>>> getStocksByRegion(
    String regionCode, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      // Note: This endpoint may need to be added to the backend
      final response = await http.get(
        Uri.parse(
          '$baseUrl/regions/$regionCode/stocks?limit=$limit&offset=$offset',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['stocks'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Get ads by region
  static Future<List<Map<String, dynamic>>> getAds(String regionCode) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/ads?region_code=$regionCode'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['ads'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Get region stats
  static Future<Map<String, dynamic>> getRegionStats() async {
    try {
      final regions = ['US', 'GCC', 'MENA', 'EU', 'ASIA', 'CN', 'GLOBAL'];
      Map<String, dynamic> stats = {};

      for (var region in regions) {
        final stocks = await getStocksByRegion(region, limit: 100);
        final halalCount = stocks
            .where((s) => s['shariah_status']?['status'] == 'HALAL')
            .length;
        final haramCount = stocks
            .where(
              (s) =>
                  s['shariah_status']?['status'] == 'HARAM' ||
                  s['shariah_status']?['status'] == 'NOT_HALAL',
            )
            .length;

        stats[region] = {
          'total': stocks.length,
          'halal': halalCount,
          'haram': haramCount,
        };
      }

      return stats;
    } catch (e) {
      return {};
    }
  }

  // User portfolio (watchlist) - requires auth
  static Future<List<Map<String, dynamic>>> getUserPortfolio(
    String token,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/portfolio'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['portfolio'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Add to portfolio
  static Future<bool> addToPortfolio(String token, int stockId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/user/portfolio'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'stock_id': stockId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Remove from portfolio
  static Future<bool> removeFromPortfolio(String token, int stockId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/user/portfolio/$stockId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get notifications
  static Future<List<Map<String, dynamic>>> getNotifications(
    String token,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['notifications'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Calculate Zakat
  static Future<Map<String, dynamic>?> calculateZakat(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/tools/zakat'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Calculate DCA
  static Future<Map<String, dynamic>?> calculateDCA(
    double monthlyAmount,
    int years,
    double rate,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/tools/dca?monthly=$monthlyAmount&years=$years&rate=$rate',
        ),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get Fear and Greed Index
  static Future<Map<String, dynamic>?> getFearAndGreedIndex() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/market/fear-greed'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get Market Indexes
  static Future<List<Map<String, dynamic>>> getMarketIndexes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/market/indexes'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(json.decode(response.body));
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Get Exchange Rate
  static Future<double?> getExchangeRate(String from, String to) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/market/exchange-rate?from=$from&to=$to'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['rate'] as num?)?.toDouble();
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
