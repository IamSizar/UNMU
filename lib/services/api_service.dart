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

  // Add a real holding (shares + average buy price) — the watchlist's
  // addToPortfolio() posts stock_id only, which the backend stores as an
  // unvalued row (shares/avg_buy_price left NULL). This is the same
  // endpoint with the fields the Portfolio screen actually needs filled in.
  static Future<bool> addHoldingToPortfolio(
    String token,
    int stockId,
    double shares,
    double avgBuyPrice,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/user/portfolio'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'stock_id': stockId,
          'shares': shares,
          'avg_buy_price': avgBuyPrice,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Compliance certificate — see backend/internal/handlers/public.go's
  // GetComplianceCertificate. Public endpoint, no auth token needed.
  static Future<CertificateResult> getComplianceCertificate(
    String ticker,
    String exchange,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/stocks/$ticker/certificate')
          .replace(queryParameters: {'exchange': exchange});
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        return CertificateResult(data: json.decode(response.body));
      }
      // 404 = no screening on record for this stock (or stock not found)
      // — a distinct, non-retryable case from a network/server failure.
      return CertificateResult(data: null, notFound: response.statusCode == 404);
    } catch (e) {
      return const CertificateResult(data: null, notFound: false);
    }
  }

  // Referral program — see backend/internal/handlers/referral.go.
  static Future<Map<String, dynamic>?> getMyReferralCode(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/referrals/my-code'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) return json.decode(response.body);
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<int?> getReferralCount(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/referrals/stats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['referralCount'] as num?)?.toInt();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Returns (success, message) — message is either the success confirmation
  // or a user-facing error string from the backend (invalid code, already
  // redeemed, self-referral), so the caller can show it directly.
  static Future<(bool, String)> redeemReferralCode(String token, String code) async {
    http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/referrals/redeem'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({'code': code}),
      );
    } catch (e) {
      return (false, 'Network error — check your connection and try again');
    }

    // Decoded separately from the request itself, so a malformed body
    // (a proxy error page, an empty 502) reports as "unexpected response"
    // rather than being indistinguishable from a network failure.
    Map<String, dynamic>? data;
    try {
      data = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // fall through with data == null
    }

    if (response.statusCode == 200) {
      return (true, data?['message']?.toString() ?? '');
    }
    return (false, data?['error']?.toString() ?? 'Unexpected response — try again');
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

  // Calculate Zakat — cash/goldGrams/silverGrams/otherAssets are optional
  // extra assets the backend has no other record of; the backend combines
  // them with the caller's Halal portfolio value and only charges zakat
  // once the total meets the nisab threshold (see backend/internal/
  // handlers/tools.go's CalculateZakat doc comment for the methodology).
  static Future<Map<String, dynamic>?> calculateZakat(
    String token, {
    double cash = 0,
    double goldGrams = 0,
    double silverGrams = 0,
    double otherAssets = 0,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/tools/zakat').replace(
        queryParameters: {
          'cash': cash.toString(),
          'gold_grams': goldGrams.toString(),
          'silver_grams': silverGrams.toString(),
          'other_assets': otherAssets.toString(),
        },
      );
      final response = await http.get(
        uri,
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

/// Result of ApiService.getComplianceCertificate — distinguishes "no
/// screening on record" (notFound: true, a 404, not retryable with the
/// same request) from a transient network/server failure (data == null,
/// notFound == false, retry might succeed).
class CertificateResult {
  const CertificateResult({required this.data, this.notFound = false});
  final Map<String, dynamic>? data;
  final bool notFound;
}
