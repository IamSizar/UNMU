// =============================================================================
// iap_service_test.dart — restored purchases must reach the right expert.
//
// Restore (required by App Review) re-delivers purchases with no pending buy,
// so the expert id must come from the SKU itself:
// `com.unmu.expert.{expertId}.{monthly|yearly}`.
// =============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/models/expert_subscription.dart';
import 'package:halalstocks/services/iap_access.dart';
import 'package:halalstocks/services/iap_service.dart';

void main() {
  test('reads the expert id from an expert SKU', () {
    expect(
      IAPService.expertIdFromProductId('com.unmu.expert.e_42.monthly'),
      'e_42',
    );
    expect(IAPService.expertIdFromProductId('com.unmu.expert.17.yearly'), '17');
  });

  test('keeps dots inside the expert id', () {
    expect(
      IAPService.expertIdFromProductId('com.unmu.expert.a.b.yearly'),
      'a.b',
    );
  });

  test('returns null for non-expert or malformed SKUs', () {
    expect(
      IAPService.expertIdFromProductId('com.unmu.premium.monthly'),
      isNull,
    );
    expect(
      IAPService.expertIdFromProductId('com.unmu.expert..monthly'),
      isNull,
    );
    expect(
      IAPService.expertIdFromProductId('com.unmu.expert.e_1.weekly'),
      isNull,
    );
    expect(
      IAPService.expertIdFromProductId('com.other.expert.e_1.monthly'),
      isNull,
    );
  });

  // Android purchases used to be refused on the device ("not yet
  // supported"); they now go to the Google Play endpoint with the token.
  group('verify request', () {
    test('iOS sends the receipt to the Apple endpoint', () {
      final r = IAPService.verifyRequestFor(
        isIOS: true,
        isAndroid: false,
        baseUrl: 'https://api.test/api',
        storeData: 'RECEIPT',
        productId: 'com.unmu.premium.monthly',
      )!;
      expect(r.uri.toString(), 'https://api.test/api/me/iap/apple/verify');
      expect(r.body, {
        'receiptData': 'RECEIPT',
        'productId': 'com.unmu.premium.monthly',
      });
    });

    test('Android sends the purchase token to the Google endpoint', () {
      final r = IAPService.verifyRequestFor(
        isIOS: false,
        isAndroid: true,
        baseUrl: 'https://api.test/api',
        storeData: 'TOKEN',
        productId: 'com.unmu.expert.e1.monthly',
        expertId: 'e1',
      )!;
      expect(r.uri.toString(), 'https://api.test/api/me/iap/google/verify');
      expect(r.body, {
        'purchaseToken': 'TOKEN',
        'productId': 'com.unmu.expert.e1.monthly',
        'expertId': 'e1',
      });
    });

    test('other platforms cannot verify', () {
      expect(
        IAPService.verifyRequestFor(
          isIOS: false,
          isAndroid: false,
          baseUrl: 'x',
          storeData: 't',
          productId: 'p',
        ),
        isNull,
      );
    });
  });

  group('tier access purchases', () {
    test(
      'iOS sends receipt, transaction and target to the access endpoint',
      () {
        final r = IAPService.verifyRequestFor(
          isIOS: true,
          isAndroid: false,
          baseUrl: 'https://api.test/api',
          storeData: 'RECEIPT',
          productId: 'com.unmu.access.t2.month',
          target: const AccessTarget.expert('e1'),
          transactionId: 'T1',
        )!;
        expect(r.uri.toString(), 'https://api.test/api/me/iap/access/apple');
        expect(r.body, {
          'receiptData': 'RECEIPT',
          'productId': 'com.unmu.access.t2.month',
          'transactionId': 'T1',
          'targetType': 'expert',
          'targetId': 'e1',
        });
      },
    );

    test('Android sends the purchase token for a community', () {
      final r = IAPService.verifyRequestFor(
        isIOS: false,
        isAndroid: true,
        baseUrl: 'https://api.test/api',
        storeData: 'TOKEN',
        productId: 'com.unmu.access.t1.year',
        target: const AccessTarget.community('c1'),
      )!;
      expect(r.uri.toString(), 'https://api.test/api/me/iap/access/google');
      expect(r.body, {
        'purchaseToken': 'TOKEN',
        'productId': 'com.unmu.access.t1.year',
        'targetType': 'community',
        'targetId': 'c1',
      });
    });
  });

  group('AccessTiers', () {
    test('product ids and prices per tier', () {
      expect(
        AccessTiers.productId('t1', SubPlan.monthly),
        'com.unmu.access.t1.month',
      );
      expect(
        AccessTiers.productId('t4', SubPlan.yearly),
        'com.unmu.access.t4.year',
      );
      expect(AccessTiers.productId('t9', SubPlan.monthly), isNull);
      expect(AccessTiers.productId(null, SubPlan.monthly), isNull);
      expect(AccessTiers.priceCents('t2', SubPlan.monthly), 999);
      expect(AccessTiers.usdLabel('t3', SubPlan.yearly), r'$199.99');
      expect(AccessTiers.isAccessProduct('com.unmu.access.t1.month'), isTrue);
      expect(AccessTiers.isAccessProduct('com.unmu.premium.monthly'), isFalse);
    });

    test('target encoding round-trips and rejects junk', () {
      final t = AccessTarget.decode(
        const AccessTarget.community('c:1').encode(),
      );
      expect(t?.type, 'community');
      expect(t?.id, 'c:1');
      expect(AccessTarget.decode('user:1'), isNull);
      expect(AccessTarget.decode('expert:'), isNull);
      expect(AccessTarget.decode(null), isNull);
    });
  });
}
