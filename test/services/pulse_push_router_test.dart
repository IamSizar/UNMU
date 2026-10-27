// Unit tests for resolvePulsePush: maps an FCM data payload to a Pulse route.
// Payload shapes mirror backend/internal/services/pulse_notifier.go.
import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/services/pulse_push_router.dart';

void main() {
  group('resolvePulsePush', () {
    test('opens the item for a new, updated or corrected push', () {
      for (final type in ['pulse_new', 'pulse_updated', 'pulse_corrected']) {
        expect(
          resolvePulsePush({'type': type, 'itemId': '42', 'slot': 'global'}),
          const PulsePushRoute.item(42),
          reason: type,
        );
      }
    });

    test('lands on today for a many-items push', () {
      expect(
        resolvePulsePush({'type': 'pulse_new_many', 'count': '4'}),
        const PulsePushRoute.today(),
      );
    });

    test('falls back to today when the item id is missing or invalid', () {
      expect(resolvePulsePush({'type': 'pulse_new'}),
          const PulsePushRoute.today());
      expect(resolvePulsePush({'type': 'pulse_new', 'itemId': 'abc'}),
          const PulsePushRoute.today());
    });

    test('ignores pushes that are not Pulse pushes', () {
      expect(resolvePulsePush({'type': 'new_message'}), isNull);
      expect(resolvePulsePush({}), isNull);
    });
  });
}
