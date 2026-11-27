// =============================================================================
// iap_service_test.dart — restored purchases must reach the right expert.
//
// Restore (required by App Review) re-delivers purchases with no pending buy,
// so the expert id must come from the SKU itself:
// `com.unmu.expert.{expertId}.{monthly|yearly}`.
// =============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/services/iap_service.dart';

void main() {
  test('reads the expert id from an expert SKU', () {
    expect(IAPService.expertIdFromProductId('com.unmu.expert.e_42.monthly'),
        'e_42');
    expect(IAPService.expertIdFromProductId('com.unmu.expert.17.yearly'), '17');
  });

  test('keeps dots inside the expert id', () {
    expect(IAPService.expertIdFromProductId('com.unmu.expert.a.b.yearly'),
        'a.b');
  });

  test('returns null for non-expert or malformed SKUs', () {
    expect(IAPService.expertIdFromProductId('com.unmu.premium.monthly'), isNull);
    expect(IAPService.expertIdFromProductId('com.unmu.expert..monthly'), isNull);
    expect(IAPService.expertIdFromProductId('com.unmu.expert.e_1.weekly'),
        isNull);
    expect(IAPService.expertIdFromProductId('com.other.expert.e_1.monthly'),
        isNull);
  });
}
