import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../screens/feed/post_viewer_screen.dart';

/// Receives incoming deep-link URIs (cold start + while running) and
/// routes them to the right in-app screen.
///
/// Currently understands one route shape:
///
///     unmu://p/:id
///     unmu.app/p/:id          (any scheme: https / http / unmu)
///
/// → opens [PostViewerScreen.forId] which fetches the post and renders
/// it. New routes get added here as additive `case` blocks in [_route].
///
/// Lifecycle:
///   * [init] is called once at app startup, after `runApp` (so the
///     navigator exists). It pulls the cold-start URI and starts
///     listening for subsequent links while the app is alive.
///   * [dispose] cancels the running-app listener — only relevant in
///     tests, since the app process owning this service stays alive.
///
/// Why a singleton: the share / route flow needs exactly one listener;
/// hot reload would otherwise stack duplicates that all fire on each
/// link.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;

  /// Wire up cold-start + while-running URI delivery. Idempotent — calling
  /// it twice (e.g. across hot reload) is a no-op.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Cold start — was the app launched FROM a link?
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        // Defer to the next frame so the navigator + first route are
        // mounted before we push on top of them.
        Future<void>.delayed(
          const Duration(milliseconds: 200),
          () => _route(initial),
        );
      }
    } catch (e) {
      _log('initial link error: $e');
    }

    // 2. While running — every subsequent link the OS hands us.
    _sub = _appLinks.uriLinkStream.listen(
      _route,
      onError: (Object e) => _log('uri stream error: $e'),
    );
  }

  /// Tear-down. Production app keeps the listener alive for the whole
  /// process lifetime; this is here for tests and hot-restart safety.
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _initialized = false;
  }

  // ─── Routing ─────────────────────────────────────────────────────────

  /// Match a URI's path against known route shapes and navigate.
  ///
  /// Scheme-agnostic: `unmu://p/123`, `https://unmu.app/p/123`, and
  /// `http://unmu.app/p/123` all resolve to the same screen. Path-only
  /// matching means Universal Links (row 3) and a custom scheme (used
  /// for QR / chat-bot links) share this resolver.
  void _route(Uri uri) {
    _log('route: $uri');
    final segments = uri.pathSegments;
    if (segments.isEmpty) return;

    switch (segments.first) {
      case 'p':
        // /p/:id  →  PostViewerScreen
        if (segments.length < 2) return;
        final id = int.tryParse(segments[1]);
        if (id == null) return;
        Get.to(() => PostViewerScreen.forId(id));
        return;
      // Add more cases here as new routes ship — `/e/:expertId`,
      // `/c/:communityId`, etc.
    }
  }

  void _log(String msg) {
    if (kDebugMode) {
      // Keep prefix grep-friendly when triaging share-link bugs.
      // ignore: avoid_print
      print('[DeepLinkService] $msg');
    }
  }
}
