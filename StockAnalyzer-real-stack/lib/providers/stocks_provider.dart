import 'package:flutter/material.dart';
import 'dart:async';
import '../services/api_service.dart';

class StocksProvider with ChangeNotifier {
  List<Map<String, dynamic>> _stocks = [];
  List<Map<String, dynamic>> _filteredStocks = [];
  String _selectedRegion = 'GLOBAL';
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get stocks => _filteredStocks;
  String get selectedRegion => _selectedRegion;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadStocksByRegion(String regionCode) async {
    _isLoading = true;
    _error = null;
    _selectedRegion = regionCode;
    notifyListeners();

    try {
      _stocks = await ApiService.getStocksByRegion(regionCode);
      _filteredStocks = _stocks;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _stocks = [];
      _filteredStocks = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void filterStocks(String query) {
    if (query.isEmpty) {
      _filteredStocks = _stocks;
    } else {
      final lowerQuery = query.toLowerCase();
      _filteredStocks = _stocks.where((stock) {
        final name = stock['name']?.toString().toLowerCase() ?? '';
        final ticker = stock['ticker']?.toString().toLowerCase() ?? '';
        return name.contains(lowerQuery) || ticker.contains(lowerQuery);
      }).toList();
    }
    notifyListeners();
  }

  void filterByStatus(String? status) {
    if (status == null || status.isEmpty) {
      _filteredStocks = _stocks;
    } else {
      _filteredStocks = _stocks.where((stock) {
        final stockStatus =
            stock['shariah_status']?['status']?.toString() ?? '';
        return stockStatus.toUpperCase() == status.toUpperCase();
      }).toList();
    }
    notifyListeners();
  }

  void clearFilter() {
    _filteredStocks = _stocks;
    notifyListeners();
  }

  // Market Indexes
  List<Map<String, dynamic>> _marketIndexes = [];
  List<Map<String, dynamic>> get marketIndexes => _marketIndexes;

  Future<void> loadMarketIndexes() async {
    try {
      final data = await ApiService.getMarketIndexes();
      _marketIndexes = data;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading market indexes: $e');
    }
  }

  // Market Sentiment
  Map<String, dynamic>? _fearAndGreedData;
  Map<String, dynamic>? get fearAndGreedData => _fearAndGreedData;

  Future<void> loadMarketSentiment() async {
    try {
      final data = await ApiService.getFearAndGreedIndex();
      if (data != null) {
        _fearAndGreedData = data;
        notifyListeners();
      }
    } catch (e) {
      // Silently fail for optional market data
      debugPrint('Error loading market sentiment: $e');
    }
  }

  // Auto-refresh
  Timer? _marketTimer;

  void startMarketUpdates(bool isPremium) {
    _marketTimer?.cancel();
    if (!isPremium) return; // Disable live updates for free users

    _marketTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      loadMarketIndexes();
      loadMarketSentiment();
    });
  }

  void stopMarketUpdates() {
    _marketTimer?.cancel();
    _marketTimer = null;
  }

  @override
  void dispose() {
    stopMarketUpdates();
    super.dispose();
  }
}
