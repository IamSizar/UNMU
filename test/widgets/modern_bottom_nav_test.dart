// =============================================================================
// modern_bottom_nav_test.dart
//
// Covers the Aurora bento pill navigation bar.
//
// The point of these tests is not that the bar "looks right" — a widget test
// cannot judge that. It is that the two things most likely to regress
// silently stay true:
//
//   1. The aurora colours are DERIVED from the UNMU brand tokens, not written
//      down a second time inside the widget. If someone pastes a literal
//      colour into the bar, the recipe test stops matching SocialTokens and
//      fails.
//   2. The bar builds and lays out in both brightnesses, on both platform
//      targets, and in RTL — the combinations a manual pass on one simulator
//      in one language will not catch.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:halalstocks/screens/social/social_tokens.dart';
import 'package:halalstocks/theme/aurora_tokens.dart';
import 'package:halalstocks/widgets/aurora/aurora_glass_surface.dart';
import 'package:halalstocks/widgets/modern_bottom_nav.dart';

void main() {
  /// Five items mirrors what MainTabScaffold actually passes (Pulse is first).
  const items = <NavItem>[
    NavItem(icon: Icons.monitor_heart_outlined, label: 'Pulse'),
    NavItem(icon: Icons.explore_outlined, label: 'Discover'),
    NavItem(icon: Icons.bar_chart_outlined, label: 'Indexes'),
    NavItem(icon: Icons.groups_outlined, label: 'Social'),
    NavItem(icon: Icons.dynamic_feed_outlined, label: 'Feed'),
  ];

  /// Resolves the aurora recipe for one brightness by pumping a throwaway
  /// app and capturing it from a descendant's context.
  Future<AuroraGlass> resolveGlass(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    late AuroraGlass captured;
    // A bare Theme, not a MaterialApp. MaterialApp builds a Navigator and
    // caches the widget for its initial route, so pumping a second theme
    // into the same tester would not rebuild `home` — both brightnesses
    // would then report whichever one was pumped first.
    await tester.pumpWidget(
      Theme(
        data: ThemeData(brightness: brightness),
        child: Builder(
          builder: (context) {
            captured = AuroraGlass.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    return captured;
  }

  /// Pumps the bar inside a minimal app shell.
  ///
  /// [brightness] drives the aurora recipe; [platform] is set so the same
  /// test can assert the chrome is identical on iOS and Android, which is a
  /// deliberate product decision (one branded bar) rather than an oversight.
  Future<void> pumpNav(
    WidgetTester tester, {
    required Brightness brightness,
    TargetPlatform platform = TargetPlatform.iOS,
    TextDirection direction = TextDirection.ltr,
    double currentPage = 0,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        theme: ThemeData(brightness: brightness, platform: platform),
        home: Directionality(
          textDirection: direction,
          child: Scaffold(
            bottomNavigationBar: ModernBottomNav(
              currentIndex: currentPage.round(),
              currentPage: currentPage,
              items: items,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('aurora recipe', () {
    testWidgets('derives its sweep from the UNMU brand tokens', (tester) async {
      final dark = await resolveGlass(tester, Brightness.dark);
      final light = await resolveGlass(tester, Brightness.light);

      // The exact colours must come from SocialTokens. Asserting identity
      // against the tokens (rather than against literal hex) is what makes
      // this a regression test for "someone hardcoded a colour".
      expect(
        dark.sweep,
        <Color>[SocialTokens.violet, SocialTokens.cyan, SocialTokens.gold],
      );
      // Light mode is deliberately cool-only. Gold and violet on a
      // near-white page turned the glass beige and read as a smudge rather
      // than as light, so the light sweep is one hue at two strengths.
      expect(
        light.sweep,
        <Color>[SocialTokens.cyanSoft, SocialTokens.cyan],
      );
      expect(light.sweep, isNot(contains(SocialTokens.gold)));
      expect(light.sweep, isNot(contains(SocialTokens.goldSoft)));
    });

    testWidgets('resolves a distinct, more opaque fill in light mode',
        (tester) async {
      final dark = await resolveGlass(tester, Brightness.dark);
      final light = await resolveGlass(tester, Brightness.light);

      expect(dark.isDark, isTrue);
      expect(light.isDark, isFalse);
      expect(dark.fill, isNot(equals(light.fill)));

      // Light mode must stay the more opaque of the two. The Aurora CSS
      // original is 30% white, which put icon contrast under 4.5:1 against
      // scrolled content on this app's near-white light theme.
      expect(light.fill.a, greaterThan(dark.fill.a));

      // The aurora glow is the opposite way round. Dark mode needs it —
      // there is no bright page behind the glass to pick colour up from.
      // Light mode must stay nearly off, or the coloured pools read as a
      // stain on the white UI.
      expect(light.glowOpacity, lessThan(dark.glowOpacity));
      expect(light.glowOpacity, lessThan(0.15));
    });
  });

  group('pill bar', () {
    testWidgets('clips to a stadium, not a rounded rectangle', (tester) async {
      await pumpNav(tester, brightness: Brightness.dark);

      expect(find.byType(AuroraGlassSurface), findsOneWidget);

      // The pill shape is the whole point of the design. The clip is a
      // ClipRRect (not a ClipPath) so BackdropFilter stays bounded; a 999
      // radius clamps to half the height, which is a true stadium.
      final clip = tester.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(AuroraGlassSurface),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(clip.borderRadius, BorderRadius.circular(999));

      // The painted fill/border follows the same stadium. The glow behind
      // the pane is a BoxDecoration, so pick the ShapeDecoration one.
      final pane = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AuroraGlassSurface),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where((box) => box.decoration is ShapeDecoration)
          .first;
      expect((pane.decoration as ShapeDecoration).shape, isA<StadiumBorder>());
    });

    for (final platform in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.android,
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'builds on $platform in $brightness with every label visible',
          (tester) async {
            await pumpNav(
              tester,
              brightness: brightness,
              platform: platform,
            );

            expect(tester.takeException(), isNull);
            for (final item in items) {
              expect(find.text(item.label), findsOneWidget);
            }
          },
        );
      }
    }

    testWidgets('lays out without overflow in RTL', (tester) async {
      await pumpNav(
        tester,
        brightness: Brightness.dark,
        direction: TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    for (final direction in <TextDirection>[TextDirection.ltr, TextDirection.rtl]) {
      testWidgets('five tabs fit on a 320pt phone without overflow ($direction)',
          (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await pumpNav(tester, brightness: Brightness.light, direction: direction);

        // A RenderFlex overflow would surface as a thrown exception.
        expect(tester.takeException(), isNull);
        for (final item in items) {
          expect(find.text(item.label), findsOneWidget);
        }
      });
    }

    testWidgets('tracks a fractional page offset without throwing',
        (tester) async {
      // 1.5 is mid-swipe between two tabs — the state the sliding pill is
      // positioned from on every frame while a finger is down.
      await pumpNav(
        tester,
        brightness: Brightness.dark,
        currentPage: 1.5,
      );
      expect(tester.takeException(), isNull);
    });

    // Feed mode (the Articles/Videos/Reels filter row) is deliberately NOT
    // covered here. Its content is unchanged by the aurora work — only the
    // surface around it changed, which every test above already exercises —
    // and building it requires a live FeedController, which in turn needs a
    // real AuthController and its storage. That is an integration concern,
    // not something to fake for a chrome test.
  });
}
