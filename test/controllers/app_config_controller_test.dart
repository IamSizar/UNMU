// =============================================================================
// app_config_controller_test.dart — the test-account switcher must never reach
// a store build.
//
// Release blocker found in the 2026-11-27 audit: the switcher was shown by the
// server flag alone, which defaulted to TRUE (also when the fetch failed), so
// App Review and real users saw a "Test account" button in release builds.
// =============================================================================
import 'package:flutter_test/flutter_test.dart';
import 'package:halalstocks/controllers/app_config_controller.dart';

void main() {
  test('flag defaults to off before any config arrives', () {
    final c = AppConfigController(allowTestTools: true);
    expect(c.testAccountEnabled.value, isFalse);
    expect(c.showTestTools, isFalse);
  });

  test('a config without the flag keeps it off', () {
    final c = AppConfigController(allowTestTools: true)..applyConfig({});
    expect(c.showTestTools, isFalse);
  });

  test('debug build + flag on shows the switcher', () {
    final c = AppConfigController(allowTestTools: true)
      ..applyConfig({'testAccountEnabled': true});
    expect(c.showTestTools, isTrue);
  });

  test('release build never shows it, even with the flag on', () {
    final c = AppConfigController(allowTestTools: false)
      ..applyConfig({'testAccountEnabled': true});
    expect(c.showTestTools, isFalse);
  });

  test('other flags still default to on when missing', () {
    final c = AppConfigController(allowTestTools: false)..applyConfig({});
    expect(c.communityEnabled.value, isTrue);
    expect(c.communityChatEnabled.value, isTrue);
    expect(c.communityPostsEnabled.value, isTrue);
  });
}
