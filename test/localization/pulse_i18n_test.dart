// =============================================================================
// pulse_i18n_test.dart — guards the Pulse translation invariant: the English
// and Arabic maps must hold exactly the same keys, and no value may be blank.
// A key missing from one language would show a raw key to that user.
// =============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/localization/i18n_pulse.dart';

void main() {
  test('pulseEn and pulseAr have identical keys', () {
    expect(pulseAr.keys.toSet().difference(pulseEn.keys.toSet()), isEmpty);
    expect(pulseEn.keys.toSet().difference(pulseAr.keys.toSet()), isEmpty);
  });

  test('no Pulse translation is blank', () {
    for (final m in [pulseEn, pulseAr]) {
      m.forEach((k, v) => expect(v.trim(), isNotEmpty, reason: k));
    }
  });

  test('placeholders match between languages', () {
    final re = RegExp(r'@\w+');
    pulseEn.forEach((k, v) {
      final en = re.allMatches(v).map((m) => m.group(0)).toSet();
      final ar = re.allMatches(pulseAr[k] ?? '').map((m) => m.group(0)).toSet();
      expect(ar, en, reason: k);
    });
  });
}
