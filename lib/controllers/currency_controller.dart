import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
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

/// Multi-currency price conversion. Replaces the old `CurrencyProvider`.
///
/// Reactive surface:
///   * [selectedCurrency] — current display currency
///   * [rates]            — USD-base rates map
///   * [isLoading]        — true while fetching a new rate
class CurrencyController extends GetxController {
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

  final Rx<Currency> _selectedCurrency = availableCurrencies.first.obs;
  final RxMap<String, double> _rates = <String, double>{'USD': 1.0}.obs;
  final RxBool _isLoading = false.obs;

  /// Plain getters — Obx-tracked because they read .value internally.
  Currency get selectedCurrency => _selectedCurrency.value;
  Map<String, double> get rates => _rates;
  bool get isLoading => _isLoading.value;

  @override
  void onInit() {
    super.onInit();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('preferred_currency') ?? 'USD';
    _selectedCurrency.value = availableCurrencies.firstWhere(
      (c) => c.code == code,
      orElse: () => availableCurrencies.first,
    );
    await fetchRates();
  }

  Future<void> updateCurrency(Currency currency) async {
    _selectedCurrency.value = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_currency', currency.code);
    await fetchRates();
  }

  Future<void> fetchRates() async {
    if (_selectedCurrency.value.code == 'USD') {
      _rates['USD'] = 1.0;
      return;
    }

    _isLoading.value = true;
    try {
      final rate = await ApiService.getExchangeRate(
        'USD',
        _selectedCurrency.value.code,
      );
      if (rate != null) {
        _rates[_selectedCurrency.value.code] = rate;
      }
    } catch (e) {
      debugPrint('Error fetching rates: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  double convert(double amount) {
    if (_selectedCurrency.value.code == 'USD') return amount;
    final rate = _rates[_selectedCurrency.value.code] ?? 1.0;
    return amount * rate;
  }

  String formatPrice(double amount) {
    final converted = convert(amount);
    return '${_selectedCurrency.value.symbol} ${converted.toStringAsFixed(2)}';
  }
}
