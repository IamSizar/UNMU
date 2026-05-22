import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dark-mode toggle. Replaces the old `ThemeProvider`.
///
/// Reactive surface: `isDarkMode` is an [RxBool] — wrap consumers in `Obx(...)`
/// to rebuild when it flips.
class ThemeController extends GetxController {
  final RxBool _isDarkMode = false.obs;

  /// Plain bool — call from anywhere. Tracked by Obx because the getter reads .value.
  bool get isDarkMode => _isDarkMode.value;

  /// Direct reactive handle for advanced use (e.g. binding a switch).
  RxBool get isDarkModeRx => _isDarkMode;

  ThemeMode get mode => _isDarkMode.value ? ThemeMode.dark : ThemeMode.light;

  @override
  void onInit() {
    super.onInit();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode.value = prefs.getBool('isDarkMode') ?? false;
  }

  Future<void> toggleTheme() async {
    _isDarkMode.value = !_isDarkMode.value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode.value);
  }

  Future<void> setDarkMode(bool value) async {
    _isDarkMode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }
}
