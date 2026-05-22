import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  String? get token => _token;
  bool get isAuthenticated => _token != null;
  bool get isPremium => true; // _user?.subscriptionTier == 'PREMIUM';
  bool get isLoading => _isLoading;
  bool get authChecked => !_isLoading;
  String? get error => _error;

  AuthProvider() {
    _loadSession();
  }

  Future<void> _loadSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await AuthService.getToken();
      final user = await AuthService.getUser();
      if (token != null && user != null) {
        _token = token;
        _user = user;
      }
    } catch (_) {
      // Clear invalid session
      _token = null;
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    _error = null;

    final result = await AuthService.login(email, password);

    if (result['success']) {
      _user = result['user'];
      _token = result['token'];
      _setLoading(false); // Notify listeners
      return true;
    } else {
      _error = result['error'];
      _setLoading(false);
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    _setLoading(true);
    _error = null;

    final result = await AuthService.register(name, email, password);

    if (result['success']) {
      _user = result['user'];
      _token = result['token'];
      _setLoading(false);
      return true;
    } else {
      _error = result['error'];
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    await AuthService.logout();
    _user = null;
    _token = null;
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
