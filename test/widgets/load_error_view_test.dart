// Indexes and Watchlist used to show an endless skeleton / a false "empty"
// state when the first load failed. LoadErrorView is their error state.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:halalstocks/localization/app_translations.dart';
import 'package:halalstocks/widgets/common/load_error_view.dart';

Widget _host(Widget child) => GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en'),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows the message and Retry calls back', (t) async {
    var retries = 0;
    await t.pumpWidget(_host(LoadErrorView(onRetry: () => retries++)));
    expect(find.text("Couldn't load this"), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('busy swaps Retry for a spinner', (t) async {
    await t.pumpWidget(_host(LoadErrorView(onRetry: () {}, busy: true)));
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
