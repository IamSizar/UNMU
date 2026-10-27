import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../screens/pulse/pulse_item_screen.dart';

/// Where a tapped Pulse push notification should land.
enum PulsePushTarget {
  /// A single published / updated / corrected item: open its detail screen.
  item,

  /// Several items published at once: just land on the app's first screen,
  /// where Pulse (tab 0) shows today's briefing.
  today,
}

/// The decision made from a push payload. Pure data so it can be unit tested
/// without Firebase or a navigator.
@immutable
class PulsePushRoute {
  const PulsePushRoute.item(this.itemId) : target = PulsePushTarget.item;
  const PulsePushRoute.today()
      : target = PulsePushTarget.today,
        itemId = null;

  final PulsePushTarget target;
  final int? itemId;

  @override
  bool operator ==(Object other) =>
      other is PulsePushRoute &&
      other.target == target &&
      other.itemId == itemId;

  @override
  int get hashCode => Object.hash(target, itemId);
}

/// Turns the FCM `data` map into a [PulsePushRoute], or null when the push is
/// not a Pulse push.
///
/// The backend (`services/pulse_notifier.go`) always sends `type` plus the
/// template params: `pulse_new`, `pulse_updated` and `pulse_corrected` carry an
/// `itemId`; `pulse_new_many` carries only `count` and `date`.
PulsePushRoute? resolvePulsePush(Map<String, dynamic> data) {
  final type = data['type']?.toString();
  switch (type) {
    case 'pulse_new':
    case 'pulse_updated':
    case 'pulse_corrected':
      // A missing or non-numeric id means we cannot open an item; fall back
      // to Pulse home rather than doing nothing, since the user did tap.
      final id = int.tryParse(data['itemId']?.toString() ?? '');
      return id == null
          ? const PulsePushRoute.today()
          : PulsePushRoute.item(id);
    case 'pulse_new_many':
      return const PulsePushRoute.today();
    default:
      return null;
  }
}

/// Performs the navigation for a tapped push. Returns true when the payload
/// was a Pulse push and was handled.
bool openPulsePush(Map<String, dynamic> data) {
  final route = resolvePulsePush(data);
  if (route == null) return false;
  // Drop anything stacked on top (an open item, archive...) so back from the
  // item returns to the app's first screen, not a stale one.
  Get.until((r) => r.isFirst);
  if (route.target == PulsePushTarget.item) {
    Get.to(() => PulseItemScreen(itemId: route.itemId!));
  }
  return true;
}
