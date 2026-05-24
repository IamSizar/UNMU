import 'dart:convert';

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
  final RxBool communityEnabled = true.obs;
  final RxBool communityChatEnabled = true.obs;
  final RxBool communityPostsEnabled = true.obs;

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
        final m = json.decode(res.body) as Map<String, dynamic>;
        communityEnabled.value = m['communityEnabled'] as bool? ?? true;
        communityChatEnabled.value = m['communityChatEnabled'] as bool? ?? true;
        communityPostsEnabled.value =
            m['communityPostsEnabled'] as bool? ?? true;
        loaded.value = true;
      }
    } catch (_) {
      // Network blip — keep the (enabled) defaults; we re-fetch on the
      // next app resume / hub open.
    }
  }
}
