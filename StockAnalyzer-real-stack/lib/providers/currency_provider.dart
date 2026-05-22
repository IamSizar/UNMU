import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class Currency {
  final String code;
  final String symbol;
  final String name;
  final String flag;

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.flag,
  });
}

class CurrencyProvider with ChangeNotifier {
  static const List<Currency> availableCurrencies = [
    Currency(code: 'USD', symbol: '\$', name: 'US Dollar', flag: '🇺🇸'),
    Currency(code: 'SAR', symbol: 'ر.س', name: 'Saudi Riyal', flag: '🇸🇦'),
    Currency(code: 'AED', symbol: 'د.إ', name: 'UAE Dirham', flag: '🇦🇪'),
    Currency(code: 'KWD', symbol: 'د.ك', name: 'Kuwaiti Dinar', flag: '🇰🇼'),
    Currency(code: 'QAR', symbol: 'ر.ق', name: 'Qatari Riyal', flag: '🇶🇦'),
    Currency(code: 'BHD', symbol: 'د.ب', name: 'Bahraini Dinar', flag: '🇧🇭'),
    Currency(code: 'OMR', symbol: 'ر.ع', name: 'Omani Rial', flag: '🇴🇲'),
    Currency(code: 'EUR', symbol: '€', name: 'Euro', flag: '🇪🇺'),
    Currency(code: 'GBP', symbol: '£', name: 'British Pound', flag: '🇬🇧'),
  ];

  Currency _selectedCurrency = availableCurrencies[0];
  final Map<String, double> _rates = {'USD': 1.0};
  bool _isLoading = false;

  Currency get selectedCurrency => _selectedCurrency;
  Map<String, double> get rates => _rates;
  bool get isLoading => _isLoading;

  CurrencyProvider() {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('preferred_currency') ?? 'USD';
    _selectedCurrency = availableCurrencies.firstWhere(
      (c) => c.code == code,
      orElse: () => availableCurrencies[0],
    );
    notifyListeners();
    fetchRates();
  }

  Future<void> updateCurrency(Currency currency) async {
    _selectedCurrency = currency;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_currency', currency.code);

    await fetchRates();
  }

  Future<void> fetchRates() async {
    if (_selectedCurrency.code == 'USD') {
      _rates['USD'] = 1.0;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final rate = await ApiService.getExchangeRate(
        'USD',
        _selectedCurrency.code,
      );
      if (rate != null) {
        _rates[_selectedCurrency.code] = rate;
      }
    } catch (e) {
      debugPrint('Error fetching rates: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  double convert(double amount) {
    if (_selectedCurrency.code == 'USD') return amount;
    final rate = _rates[_selectedCurrency.code] ?? 1.0;
    return amount * rate;
  }

  String formatPrice(double amount) {
    final converted = convert(amount);
    return '${_selectedCurrency.symbol} ${converted.toStringAsFixed(2)}';
  }
}
