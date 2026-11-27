import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Global feature flags, read from the public `GET /api/app-config`.
///
/// Currently drives the **community kill-switch**: when the admin turns
/// communities off in the dashboard, the whole app hides every
/// community surface (the hub section, the "create community" CTA in the
/// expert studio, community destinations in the post composer, etc.) so
/// users never see — or tap into — anything community-related.
///
/// Defaults to ENABLED for every flag, so a failed/slow fetch never hides
/// a feature that's actually live.
class AppConfigController extends GetxController with WidgetsBindingObserver {
  /// [allowTestTools] defaults to "not a release build", so store builds can
  /// never show test tooling whatever the server says. Tests pass it directly.
  AppConfigController({bool allowTestTools = !kReleaseMode})
      : _allowTestTools = allowTestTools;

  final bool _allowTestTools;

  final RxBool communityEnabled = true.obs;
  final RxBool communityChatEnabled = true.obs;
  final RxBool communityPostsEnabled = true.obs;

  /// Server flag for the "Test account" quick-switch (dashboard Settings).
  /// Defaults to OFF: a failed fetch must never reveal test tooling.
  final RxBool testAccountEnabled = false.obs;

  /// Whether the test-account switcher may be shown: never in a release
  /// (store) build, and only when the admin flag is on. Read inside Obx.
  ///
  /// The flag is read FIRST on purpose: an Obx that reads no observable
  /// throws, so short-circuiting on [_allowTestTools] would crash release.
  bool get showTestTools {
    final enabled = testAccountEnabled.value;
    return _allowTestTools && enabled;
  }

  /// True only after the first successful fetch — lets UI avoid a flash
  /// of community content before we know the real flag value.
  final RxBool loaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    // Re-check flags every time the app returns to the foreground, so an
    // admin toggling the kill-switch shows/hides community across the app
    // without the user needing to relaunch.
    WidgetsBinding.instance.addObserver(this);
    refreshConfig();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refreshConfig();
    }
  }

  Future<void> refreshConfig() async {
    try {
      final res = await http
          .get(Uri.parse('${ApiConfig.baseUrl}/app-config'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        applyConfig(json.decode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {
      // Network blip — keep the (enabled) defaults; we re-fetch on the
      // next app resume / hub open.
    }
  }

  /// Applies a decoded `/app-config` body. Feature flags default to on when
  /// missing; the test-account flag defaults to off.
  void applyConfig(Map<String, dynamic> m) {
    communityEnabled.value = m['communityEnabled'] as bool? ?? true;
    communityChatEnabled.value = m['communityChatEnabled'] as bool? ?? true;
    communityPostsEnabled.value = m['communityPostsEnabled'] as bool? ?? true;
    testAccountEnabled.value = m['testAccountEnabled'] as bool? ?? false;
    loaded.value = true;
  }
}
