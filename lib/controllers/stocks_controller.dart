import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../services/api_service.dart';

/// Stock browser state — region selection, filtering, market data.
/// Replaces the old `StocksProvider`.
class StocksController extends GetxController {
  // ── full + filtered list ──
  final RxList<Map<String, dynamic>> _stocks = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> _filteredStocks =
      <Map<String, dynamic>>[].obs;

  /// What screens render. Always reflects the latest filter.
  List<Map<String, dynamic>> get stocks => _filteredStocks;

  final RxString _selectedRegion = 'GLOBAL'.obs;
  final RxBool _isLoading = false.obs;
  final RxnString _error = RxnString();

  String get selectedRegion => _selectedRegion.value;
  bool get isLoading => _isLoading.value;
  String? get error => _error.value;

  /// Per-region result cache. Switching to an already-loaded region paints
  /// its stocks INSTANTLY (no skeleton) while a silent background refresh
  /// fetches fresh data — so flipping between GLOBAL / US / GCC feels instant
  /// after the first visit instead of re-hitting the network every time.
  final Map<String, List<Map<String, dynamic>>> _cacheByRegion = {};

  /// The grade filter currently applied (null = show all). Tracked here so a
  /// background refresh re-applies it instead of wiping the user's filter.
  String? _activeGrade;

  /// Load (or switch to) a region. Shows cached stocks immediately when
  /// available; only the first visit to a region shows the skeleton.
  /// [force] = true (pull-to-refresh) always does a network fetch.
  Future<void> loadStocksByRegion(String regionCode, {bool force = false}) async {
    _selectedRegion.value = regionCode;
    _error.value = null;
    // A region switch clears any active grade filter (the screen resets its
    // chip too), so we start from the full list for the new region.
    _activeGrade = null;

    final cached = _cacheByRegion[regionCode];
    if (cached != null && !force) {
      // Instant: paint the cached list, no skeleton, refresh quietly.
      _stocks.assignAll(cached);
      _filteredStocks.assignAll(cached);
      _isLoading.value = false;
      unawaited(_fetchRegion(regionCode));
      return;
    }
    // First visit (or forced) — only show the skeleton when there's nothing
    // cached to display yet.
    if (cached == null) _isLoading.value = true;
    await _fetchRegion(regionCode);
  }

  /// Network fetch for one region. Caches the result and applies it to the
  /// visible list only if that region is still selected (guards against a
  /// fast region switch landing stale data on the wrong screen).
  Future<void> _fetchRegion(String regionCode) async {
    try {
      final list = await ApiService.getStocksByRegion(regionCode);
      _cacheByRegion[regionCode] = list;
      if (_selectedRegion.value == regionCode) {
        _stocks.assignAll(list);
        _applyActiveFilter();
      }
    } catch (e) {
      // Only surface an error when we have nothing cached to fall back on —
      // a failed background refresh keeps the cached list on screen.
      if (_selectedRegion.value == regionCode &&
          _cacheByRegion[regionCode] == null) {
        _error.value = e.toString();
        _stocks.clear();
        _filteredStocks.clear();
      }
    } finally {
      if (_selectedRegion.value == regionCode) _isLoading.value = false;
    }
  }

  /// Re-apply the active grade filter to [_filteredStocks] from [_stocks].
  void _applyActiveFilter() {
    final g = _activeGrade;
    if (g == null || g.isEmpty) {
      _filteredStocks.assignAll(_stocks);
    } else {
      _filteredStocks.assignAll(_stocks.where((s) {
        final sg = s['shariah_status']?['grade']?.toString() ?? '';
        return sg.toUpperCase() == g.toUpperCase();
      }));
    }
  }

  void filterStocks(String query) {
    if (query.isEmpty) {
      _filteredStocks.assignAll(_stocks);
    } else {
      final q = query.toLowerCase();
      _filteredStocks.assignAll(_stocks.where((s) {
        final name = s['name']?.toString().toLowerCase() ?? '';
        final ticker = s['ticker']?.toString().toLowerCase() ?? '';
        return name.contains(q) || ticker.contains(q);
      }));
    }
  }

  void filterByStatus(String? status) {
    if (status == null || status.isEmpty) {
      _filteredStocks.assignAll(_stocks);
    } else {
      _filteredStocks.assignAll(_stocks.where((s) {
        final ss = s['shariah_status']?['status']?.toString() ?? '';
        return ss.toUpperCase() == status.toUpperCase();
      }));
    }
  }

  /// Filters by Shariah grade letter — A, B, C, or F. Remembers the choice
  /// in [_activeGrade] so a background region refresh re-applies it.
  void filterByGrade(String? grade) {
    _activeGrade = (grade == null || grade.isEmpty) ? null : grade;
    _applyActiveFilter();
  }

  void clearFilter() {
    _activeGrade = null;
    _filteredStocks.assignAll(_stocks);
  }

  // ── market indexes ──
  final RxList<Map<String, dynamic>> _marketIndexes =
      <Map<String, dynamic>>[].obs;
  List<Map<String, dynamic>> get marketIndexes => _marketIndexes;

  Future<void> loadMarketIndexes() async {
    try {
      final data = await ApiService.getMarketIndexes();
      _marketIndexes.assignAll(data);
    } catch (e) {
      debugPrint('Error loading market indexes: $e');
    }
  }

  // ── fear & greed ──
  final Rxn<Map<String, dynamic>> _fearAndGreedData =
      Rxn<Map<String, dynamic>>();
  Map<String, dynamic>? get fearAndGreedData => _fearAndGreedData.value;

  Future<void> loadMarketSentiment() async {
    try {
      final data = await ApiService.getFearAndGreedIndex();
      if (data != null) _fearAndGreedData.value = data;
    } catch (e) {
      debugPrint('Error loading market sentiment: $e');
    }
  }

  // ── auto-refresh (premium only) ──
  Timer? _marketTimer;

  void startMarketUpdates(bool isPremium) {
    _marketTimer?.cancel();
    if (!isPremium) return;
    _marketTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadMarketIndexes();
      loadMarketSentiment();
    });
  }

  void stopMarketUpdates() {
    _marketTimer?.cancel();
    _marketTimer = null;
  }

  @override
  void onClose() {
    stopMarketUpdates();
    super.onClose();
  }
}
