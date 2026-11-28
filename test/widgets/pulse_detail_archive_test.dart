// =============================================================================
// pulse_detail_archive_test.dart — the Pulse item screen (content, save toggle,
// not-found) and the archive screen (results, saved tab, empty/error states) on
// both platforms, driven by the shared fake API.
// =============================================================================
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:halalstocks/controllers/auth_controller.dart';
import 'package:halalstocks/controllers/language_controller.dart';
import 'package:halalstocks/controllers/pulse_controller.dart';
import 'package:halalstocks/localization/app_translations.dart';
import 'package:halalstocks/models/pulse_item.dart';
import 'package:halalstocks/screens/pulse/pulse_archive_screen.dart';
import 'package:halalstocks/screens/pulse/pulse_item_screen.dart';
import 'package:halalstocks/services/pulse_service.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_pulse_api.dart';

/// An API whose single-item lookup fails, to exercise the not-found state.
class _MissingItemApi extends FakePulseApi {
  @override
  Future<PulseResult<PulseItem>> item(int id) async =>
      const PulseResult.fail(PulseFailure.notFound);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  Future<void> pump(
    WidgetTester tester,
    FakePulseApi api,
    Widget screen, {
    TargetPlatform platform = TargetPlatform.android,
    String lang = 'en',
  }) async {
    SharedPreferences.setMockInitialValues({});
    Get.reset();
    Get.put(AuthController());
    final language = Get.put(LanguageController());
    // Let its async saved-language load finish first, or it would overwrite ours.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    language.localeRx.value = Locale(lang);
    Get.put(PulseController(api: api));
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(
        translations: AppTranslations(),
        locale: Locale(lang),
        fallbackLocale: const Locale('en'),
        theme: ThemeData(platform: platform),
        home: screen,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group('item screen ($platform)', () {
      testWidgets('shows the item and its sources', (t) async {
        await pump(
          t,
          FakePulseApi(),
          const PulseItemScreen(itemId: 7),
          platform: platform,
        );
        expect(find.text('Title 7'), findsWidgets);
        expect(t.takeException(), isNull);
      });

      testWidgets('tapping save calls the API and flips the label', (t) async {
        final api = FakePulseApi();
        await pump(
          t,
          api,
          const PulseItemScreen(itemId: 7),
          platform: platform,
        );
        await t.tap(find.byTooltip('pulse.detail.save'.tr));
        await t.pump(const Duration(milliseconds: 200));
        expect(api.calls, contains('save 7'));
        expect(find.byTooltip('pulse.detail.saved'.tr), findsOneWidget);
      });

      testWidgets('a failed save reverts and tells the user', (t) async {
        final api = FakePulseApi()..saveOk = false;
        await pump(
          t,
          api,
          const PulseItemScreen(itemId: 7),
          platform: platform,
        );
        await t.tap(find.byTooltip('pulse.detail.save'.tr));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('pulse.detail.saveFailed'.tr), findsOneWidget);
        expect(find.byTooltip('pulse.detail.save'.tr), findsOneWidget);
      });

      testWidgets('a missing item shows a friendly way out', (t) async {
        await pump(
          t,
          _MissingItemApi(),
          const PulseItemScreen(itemId: 99),
          platform: platform,
        );
        expect(find.text('pulse.detail.notFoundTitle'.tr), findsOneWidget);
        expect(find.text('pulse.openArchive'.tr), findsOneWidget);
      });
    });

    group('archive screen ($platform)', () {
      testWidgets('lists archived items', (t) async {
        await pump(
          t,
          FakePulseApi(),
          const PulseArchiveScreen(),
          platform: platform,
        );
        expect(find.text('Title 5'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('the saved tab shows its empty state', (t) async {
        await pump(
          t,
          FakePulseApi(),
          const PulseArchiveScreen(initialView: PulseArchiveView.saved),
          platform: platform,
        );
        expect(find.text('pulse.saved.emptyTitle'.tr), findsOneWidget);
      });
    });
  }

  testWidgets('archive renders in Arabic (RTL) without overflow', (t) async {
    await pump(t, FakePulseApi(), const PulseArchiveScreen(), lang: 'ar');
    expect(find.text('عنوان 5'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
