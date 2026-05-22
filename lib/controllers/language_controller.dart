import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Trans;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/locale_sync_service.dart';

/// English / Arabic language toggle. Replaces the old `LanguageProvider`.
///
/// Reactive surface: `locale` is an [Rx] — wrap consumers in `Obx(...)`.
class LanguageController extends GetxController {
  final Rx<Locale> _locale = const Locale('en').obs;

  /// Plain Locale — Obx-tracked because the getter reads .value.
  Locale get locale => _locale.value;

  /// Direct reactive handle for advanced use.
  Rx<Locale> get localeRx => _locale;

  bool get isArabic => _locale.value.languageCode == 'ar';

  @override
  void onInit() {
    super.onInit();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('language') ?? 'en';
    _locale.value = Locale(code);
  }

  Future<void> setLanguage(String languageCode) async {
    _locale.value = Locale(languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', languageCode);
    Get.updateLocale(_locale.value);
    // Tell the backend so notification pushes use this language. Fire-
    // and-forget; no-op when signed out.
    LocaleSyncService.sync(languageCode);
  }

  Future<void> toggleLanguage() async {
    final next = _locale.value.languageCode == 'en' ? 'ar' : 'en';
    await setLanguage(next);
  }
}
