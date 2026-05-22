import 'package:flutter/material.dart';
import '../services/api_service.dart';

class WatchlistProvider with ChangeNotifier {
  List<Map<String, dynamic>> _watchlist = [];
  bool _isLoading = false;
  String? _error;
  
  List<Map<String, dynamic>> get watchlist => _watchlist;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  Future<void> loadWatchlist(String? token) async {
    if (token == null) {
      _watchlist = [];
      return;
    }
    
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _watchlist = await ApiService.getUserPortfolio(token);
      _error = null;
    } catch (e) {
      _error = e.toString();
      _watchlist = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<bool> addToWatchlist(String? token, int stockId) async {
    if (token == null) return false;
    
    try {
      final success = await ApiService.addToPortfolio(token, stockId);
      if (success) {
        await loadWatchlist(token);
      }
      return success;
    } catch (e) {
      return false;
    }
  }
  
  Future<bool> removeFromWatchlist(String? token, int stockId) async {
    if (token == null) return false;
    
    try {
      final success = await ApiService.removeFromPortfolio(token, stockId);
      if (success) {
        await loadWatchlist(token);
      }
      return success;
    } catch (e) {
      return false;
    }
  }
  
  bool isInWatchlist(int stockId) {
    return _watchlist.any((item) => item['stock_id'] == stockId);
  }
}

