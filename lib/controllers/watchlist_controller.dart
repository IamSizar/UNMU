import 'package:get/get.dart';

import '../services/api_service.dart';

/// User's followed stocks. Replaces the old `WatchlistProvider`.
///
/// Reactive surface: [watchlist], [isLoading], [error] — observe via `Obx`.
class WatchlistController extends GetxController {
  final RxList<Map<String, dynamic>> _watchlist = <Map<String, dynamic>>[].obs;
  final RxBool _isLoading = false.obs;
  final RxnString _error = RxnString();

  /// Plain getters — Obx-tracked because they read the underlying Rx.
  List<Map<String, dynamic>> get watchlist => _watchlist;
  bool get isLoading => _isLoading.value;
  String? get error => _error.value;

  Future<void> loadWatchlist(String? token) async {
    if (token == null) {
      _watchlist.clear();
      return;
    }

    _isLoading.value = true;
    _error.value = null;
    try {
      final list = await ApiService.getUserPortfolio(token);
      _watchlist.assignAll(list);
    } catch (e) {
      _error.value = e.toString();
      _watchlist.clear();
    } finally {
      _isLoading.value = false;
    }
  }

  Future<bool> addToWatchlist(String? token, int stockId) async {
    if (token == null) return false;
    try {
      final ok = await ApiService.addToPortfolio(token, stockId);
      if (ok) await loadWatchlist(token);
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> removeFromWatchlist(String? token, int stockId) async {
    if (token == null) return false;
    try {
      final ok = await ApiService.removeFromPortfolio(token, stockId);
      if (ok) await loadWatchlist(token);
      return ok;
    } catch (_) {
      return false;
    }
  }

  bool isInWatchlist(int stockId) =>
      _watchlist.any((item) => item['stock_id'] == stockId);
}
