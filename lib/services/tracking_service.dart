import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';

/// App Tracking Transparency boot helper.
///
/// Apple requires that any iOS binary linking the AppTrackingTransparency
/// framework calls `requestTrackingAuthorization()` before any SDK can
/// access the IDFA. UNMU does not yet ship an IDFA-using SDK (Firebase
/// Messaging on its own does not read the IDFA), but pre-wiring the
/// prompt means our App Privacy declaration matches the framework that
/// ships in the binary today.
///
/// On Android the plugin returns immediately, so the call is a safe
/// no-op there.
///
/// We only call `requestTrackingAuthorization()` when the status is
/// `notDetermined`. Once the user has answered, iOS caches the
/// decision and any subsequent call returns the cached value without
/// showing the prompt — so this method is idempotent across launches.
class TrackingService {
  TrackingService._();
  static final TrackingService instance = TrackingService._();

  Future<void> requestIfNeeded() async {
    try {
      final current = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (current == TrackingStatus.notDetermined) {
        // The system modal appears here. Result is cached by iOS; the
        // user can change it later in Settings → Privacy → Tracking.
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e, st) {
      // The plugin throws on platforms it doesn't support (older iOS,
      // some desktop targets). Swallow so app boot never stalls on an
      // optional permission step.
      debugPrint('[att] requestIfNeeded: $e\n$st');
    }
  }
}
