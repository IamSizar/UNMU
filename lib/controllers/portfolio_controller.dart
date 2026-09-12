import 'package:get/get.dart';

import '../services/api_service.dart';
import 'watchlist_controller.dart';

/// User's real, valued holdings — shares + average buy price per stock.
///
/// Distinct from [WatchlistController]: both read/write the same backend
/// `user_portfolios` table (see backend/internal/handlers/user.go), but the
/// watchlist writes stock_id-only rows (shares/avg_buy_price left NULL),
/// while this controller only surfaces and adds rows with real shares > 0
/// — i.e. an actual position, not just something being tracked.
///
/// Reactive surface: [holdings], [isLoading], [error] — observe via `Obx`.
class PortfolioController extends GetxController {
  final RxList<Map<String, dynamic>> _holdings = <Map<String, dynamic>>[].obs;
  final RxBool _isLoading = false.obs;
  final RxnString _error = RxnString();

  List<Map<String, dynamic>> get holdings => _holdings;
  bool get isLoading => _isLoading.value;
  String? get error => _error.value;

  /// Sum of shares * avg_buy_price across all holdings — a cost-basis
  /// total, not a live market value (the backend has no live-price field
  /// wired to this endpoint yet).
  double get totalCostBasis => _holdings.fold(
        0.0,
        (sum, h) =>
            sum +
            ((h['shares'] as num?)?.toDouble() ?? 0) *
                ((h['avg_buy_price'] as num?)?.toDouble() ?? 0),
      );

  Future<void> loadPortfolio(String? token) async {
    if (token == null) {
      _holdings.clear();
      return;
    }

    _isLoading.value = true;
    _error.value = null;
    try {
      final list = await ApiService.getUserPortfolio(token);
      // Real holdings only — a watchlist-only row has shares NULL/0. Note:
      // this is a client-side heuristic on a shared table (watchlist and
      // portfolio both write user_portfolios), not a server-side flag —
      // a fully-sold position (shares reset to 0) would also disappear
      // from this list, which is the accepted v1 tradeoff.
      _holdings.assignAll(
        list.where((item) => ((item['shares'] as num?)?.toDouble() ?? 0) > 0),
      );
    } catch (e) {
      _error.value = e.toString();
      _holdings.clear();
    } finally {
      _isLoading.value = false;
    }
  }

  Future<bool> addHolding(
    String? token,
    int stockId,
    double shares,
    double avgBuyPrice,
  ) async {
    if (token == null) return false;
    try {
      final ok = await ApiService.addHoldingToPortfolio(
        token,
        stockId,
        shares,
        avgBuyPrice,
      );
      if (ok) {
        await loadPortfolio(token);
        _refreshWatchlistIfPresent(token);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeHolding(String? token, int stockId) async {
    if (token == null) return false;
    try {
      final ok = await ApiService.removeFromPortfolio(token, stockId);
      if (ok) {
        await loadPortfolio(token);
        _refreshWatchlistIfPresent(token);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // Watchlist and Portfolio both read/write the same backend
  // user_portfolios table (see backend/internal/handlers/user.go), so an
  // add/remove here needs to invalidate WatchlistController's independent
  // cache too, or the Watchlist screen shows stale state until its own
  // manual reload.
  void _refreshWatchlistIfPresent(String? token) {
    if (Get.isRegistered<WatchlistController>()) {
      Get.find<WatchlistController>().loadWatchlist(token);
    }
  }
}
