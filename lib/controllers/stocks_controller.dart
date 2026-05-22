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

  Future<void> loadStocksByRegion(String regionCode) async {
    _isLoading.value = true;
    _error.value = null;
    _selectedRegion.value = regionCode;

    try {
      final list = await ApiService.getStocksByRegion(regionCode);
      _stocks.assignAll(list);
      _filteredStocks.assignAll(list);
    } catch (e) {
      _error.value = e.toString();
      _stocks.clear();
      _filteredStocks.clear();
    } finally {
      _isLoading.value = false;
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

  /// Filters by Shariah grade letter — A, B, C, or F.
  void filterByGrade(String? grade) {
    if (grade == null || grade.isEmpty) {
      _filteredStocks.assignAll(_stocks);
    } else {
      _filteredStocks.assignAll(_stocks.where((s) {
        final g = s['shariah_status']?['grade']?.toString() ?? '';
        return g.toUpperCase() == grade.toUpperCase();
      }));
    }
  }

  void clearFilter() => _filteredStocks.assignAll(_stocks);

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
