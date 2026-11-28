import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pulse_item.dart';
import '../../screens/social/social_tokens.dart';

/// =============================================================================
/// pulse_tokens.dart — the visual building blocks shared by every Pulse screen:
/// the UNMU logo colours, platform-native icons, the calm aurora page, and the
/// three card surfaces (teal tone, ink tone, frosted glass).
///
/// Colours come from the UNMU logo (assets/branding/unmu_icon.png):
///   teal #00B7B7 — the mark; ink #0B1B1E — the Latin wordmark.
/// Text on teal uses [PulseColors.tealDeep] (#007F86, 5.0:1 against white) so
/// the 4.5:1 contrast floor holds; the bright teal is for light and fills only.
///
/// Icons follow the platform (SF-style on iOS, Material on Android) and are
/// chosen from `Theme.of(context).platform` so tests can flip it.
/// =============================================================================
abstract final class PulseColors {
  static const Color teal = Color(0xFF00B7B7);
  static const Color tealDeep = Color(0xFF007F86);
  static const Color tealInk = Color(0xFF005A60);
  static const Color tealBright = Color(0xFF2DD4D4); // readable on dark glass
  static const Color ink = Color(0xFF0B1B1E);
}

/// Platform-adaptive icons for Pulse.
abstract final class PulseIcons {
  static bool _ios(BuildContext c) =>
      Theme.of(c).platform == TargetPlatform.iOS;

  static IconData slot(BuildContext c, PulseSlot s) {
    final ios = _ios(c);
    switch (s) {
      case PulseSlot.global:
        return ios ? CupertinoIcons.globe : Icons.public;
      case PulseSlot.gulf:
        return ios ? CupertinoIcons.building_2_fill : Icons.account_balance;
      case PulseSlot.sharia:
        return ios ? CupertinoIcons.checkmark_shield : Icons.balance;
      case PulseSlot.opportunity:
        return ios ? CupertinoIcons.sparkles : Icons.auto_awesome;
    }
  }

  static IconData bookmark(BuildContext c, {required bool filled}) {
    if (_ios(c)) {
      return filled ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark;
    }
    return filled ? Icons.bookmark : Icons.bookmark_border;
  }

  static IconData clock(BuildContext c) =>
      _ios(c) ? CupertinoIcons.clock : Icons.schedule;

  static IconData verified(BuildContext c) =>
      _ios(c) ? CupertinoIcons.checkmark_shield : Icons.verified_outlined;

  static IconData settings(BuildContext c) =>
      _ios(c) ? CupertinoIcons.slider_horizontal_3 : Icons.tune;

  static IconData chart(BuildContext c) =>
      _ios(c) ? CupertinoIcons.chart_bar : Icons.bar_chart;

  static IconData search(BuildContext c) =>
      _ios(c) ? CupertinoIcons.search : Icons.search;

  static IconData wifiOff(BuildContext c) =>
      _ios(c) ? CupertinoIcons.wifi_slash : Icons.wifi_off;

  static IconData alert(BuildContext c) =>
      _ios(c) ? CupertinoIcons.exclamationmark_circle : Icons.error_outline;

  static IconData inbox(BuildContext c) =>
      _ios(c) ? CupertinoIcons.tray : Icons.inbox_outlined;

  static IconData link(BuildContext c) =>
      _ios(c) ? CupertinoIcons.link : Icons.link;
}

/// "09:05" in Western digits, in the viewer's local time.
String pulseTime(DateTime t) => DateFormat('HH:mm', 'en').format(t.toLocal());

/// Spacing scale (4/8/12/16/24/32) used by the Pulse screens.
abstract final class PulseSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radius of every Pulse card.
const double kPulseRadius = 26;

/// The calm aurora page: a pale (or deep, in dark mode) base with soft pools of
/// teal, blue and violet light, which the glass cards blur over.
class PulseAuroraBackground extends StatelessWidget {
  final Widget child;

  const PulseAuroraBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final dark = palette.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF061214) : const Color(0xFFEAF3F3),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _pool(
            const Alignment(-1.1, -1.05),
            PulseColors.teal,
            dark ? 0.30 : 0.20,
          ),
          _pool(
            const Alignment(1.15, -0.7),
            const Color(0xFF3B6CF5),
            dark ? 0.24 : 0.16,
          ),
          _pool(
            const Alignment(0.7, 1.15),
            const Color(0xFF8A5BC7),
            dark ? 0.24 : 0.12,
          ),
          child,
        ],
      ),
    );
  }

  static Widget _pool(Alignment at, Color color, double alpha) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: at,
          radius: 0.95,
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );
}

/// Which surface a Pulse card is painted on.
enum PulseSurface { teal, ink, glass }

/// Paints a card surface: teal tone, ink tone, or frosted glass.
///
/// Tones are lit from inside by two soft light sources (the Aurora bento
/// recipe); glass blurs whatever is behind it and has a bright top edge.
class PulseSurfaceBox extends StatelessWidget {
  final PulseSurface surface;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const PulseSurfaceBox({
    super.key,
    required this.surface,
    required this.child,
    this.padding = const EdgeInsets.all(PulseSpace.lg),
  });

  @override
  Widget build(BuildContext context) {
    final dark = SocialTheme.of(context).isDark;
    final radius = BorderRadius.circular(kPulseRadius);

    switch (surface) {
      case PulseSurface.glass:
        return ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: dark
                    ? Colors.white.withValues(alpha: 0.07)
                    : Colors.white.withValues(alpha: 0.46),
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.80),
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        );
      case PulseSurface.teal:
        return _toneBox(
          radius: radius,
          base: dark ? const Color(0xFF06383D) : PulseColors.tealDeep,
          glow: PulseColors.teal.withValues(alpha: dark ? 0.5 : 0.9),
          glowRadius: 1.1,
          border: dark
              ? Border.all(color: PulseColors.teal.withValues(alpha: 0.28))
              : null,
          shadow: dark
              ? null
              : [
                  BoxShadow(
                    color: PulseColors.tealInk.withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                    spreadRadius: -10,
                  ),
                ],
        );
      case PulseSurface.ink:
        return _toneBox(
          radius: radius,
          base: dark ? const Color(0xFF0E2226) : PulseColors.ink,
          glow: PulseColors.teal.withValues(alpha: dark ? 0.30 : 0.42),
          glowRadius: 1.0,
          border: dark
              ? Border.all(color: Colors.white.withValues(alpha: 0.10))
              : null,
        );
    }
  }

  /// A tone card: a SOLID base colour with a soft light source on top.
  ///
  /// Two nested boxes on purpose. A single BoxDecoration paints its gradient
  /// OR its colour, never both, so putting both on one box drops the base and
  /// the fading glow lets the pale page show through, which made the white
  /// text on these cards unreadable.
  Widget _toneBox({
    required BorderRadius radius,
    required Color base,
    required Color glow,
    required double glowRadius,
    BoxBorder? border,
    List<BoxShadow>? shadow,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: base,
        border: border,
        boxShadow: shadow,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: RadialGradient(
            center: const Alignment(0.95, -0.9),
            radius: glowRadius,
            colors: [glow, glow.withValues(alpha: 0)],
          ),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
