// =============================================================================
// user_created_at_test.dart — the profile "member since" cell reads
// User.createdAt, so it must survive the JSON round trip and stay null
// when the backend (or an old saved session) doesn't send it.
// =============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:halalstocks/localization/locale_format.dart';
import 'package:halalstocks/models/user.dart';

void main() {
  setUpAll(initializeDateFormatting);

  test('createdAt parses from the backend and survives toJson', () {
    final u = User.fromJson({
      'id': 1,
      'email': 'a@b.test',
      'createdAt': '2026-05-03T07:00:00Z',
    });
    expect(u.createdAt, DateTime.utc(2026, 5, 3, 7));
    final again = User.fromJson(u.toJson());
    expect(again.createdAt, DateTime.utc(2026, 5, 3, 7));
  });

  test('createdAt is null when missing', () {
    final u = User.fromJson({'id': 1, 'email': 'a@b.test'});
    expect(u.createdAt, isNull);
  });

  test('monthYear in English', () {
    expect(LocaleFormat.monthYear(DateTime(2026, 5, 3)), "May '26");
  });
}
