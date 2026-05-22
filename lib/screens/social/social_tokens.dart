import 'package:flutter/material.dart';

/// =============================================================================
/// SocialTokens — colors that DO NOT change between light and dark mode.
///
/// These are the "brand"-level accents (cyan, gold, market up/down, premium
/// gradient seeds). Everything else (surfaces, borders, text colors,
/// backgrounds) lives on [SocialPalette] and adapts to the current theme.
/// =============================================================================
class SocialTokens {
  // Brand accents (constant in both modes) ---------------------------------
  static const Color cyan = Color(0xFF00D9FF);
  static const Color cyanSoft = Color(0xFF1AB6D9);
  static const Color cyanDeep = Color(0xFF0096B7);
  static const Color gold = Color(0xFFFFD700);
  static const Color goldSoft = Color(0xFFE6BD0F);
  static const Color goldDeep = Color(0xFFB8860B);

  // Section accents — added with the May 2026 social-hub refresh so
  // the three big lists (Yours / Discover / Top experts) each read as
  // a distinct shelf at a glance instead of all-cyan-everything.
  static const Color violet = Color(0xFF8B5CF6);
  static const Color violetSoft = Color(0xFFA78BFA);
  static const Color violetDeep = Color(0xFF6D28D9);

  // Market direction indicators (also constant) ----------------------------
  static const Color up = Color(0xFF10B981);
  static const Color down = Color(0xFFEF4444);

  // Region accent palette — used to subtly tint community cards by region.
  static const Map<String, Color> regionAccent = {
    'GCC': Color(0xFFE6BD0F),
    'MENA': Color(0xFF8B5CF6),
    'US': Color(0xFF00D9FF),
    'EU': Color(0xFF38BDF8),
    'ASIA': Color(0xFFF472B6),
    'CN': Color(0xFFEF4444),
    'GLOBAL': Color(0xFF10B981),
  };

  static Color regionColor(String code) =>
      regionAccent[code] ?? const Color(0xFF00D9FF);
}

/// =============================================================================
/// SocialPalette — theme-aware surface, border, and text colors.
///
/// Use [SocialTheme.of(context)] from any widget to get the right palette
/// for the current Brightness. All social widgets read colors from this so
/// they flip automatically when the user toggles dark mode.
/// =============================================================================
class SocialPalette {
  final Brightness brightness;

  // Backgrounds & surfaces
  final Color background;
  final Color surface; // primary card
  final Color surfaceElevated; // hovered / pressed / nested cards
  final Color glassFill; // translucent overlay used on hero gradients

  // Lines
  final Color border;
  final Color subtleDivider;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // The deep gradient color used behind hero / premium areas. In dark mode
  // it's midnight blue; in light mode it's a soft tinted off-white so the
  // section reads as "premium" without going pure-dark on a light app.
  final Color heroGradientStart;
  final Color heroGradientEnd;

  const SocialPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.glassFill,
    required this.border,
    required this.subtleDivider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.heroGradientStart,
    required this.heroGradientEnd,
  });

  bool get isDark => brightness == Brightness.dark;

  // Dark variant -----------------------------------------------------------
  // Tuned for richness: deeper background so brighter surfaces pop, pure
  // white primary text, a subtly cyan-tinted border that hints at the brand.
  factory SocialPalette.dark() => const SocialPalette(
    brightness: Brightness.dark,
    background: Color(0xFF080F1F), // deep midnight
    surface: Color(0xFF15233D), // brighter card so it lifts off bg
    surfaceElevated: Color(0xFF1F2F4D), // even more lift for inset / hover
    glassFill: Color(0x33FFFFFF),
    border: Color(0xFF2C3E5C), // visible enough to define cards
    subtleDivider: Color(0xFF22314D),
    textPrimary: Color(0xFFFFFFFF), // pure white = max pop
    textSecondary: Color(0xFFD6DDE8),
    textMuted: Color(0xFF94A0B5),
    heroGradientStart: Color(0xFF0E1A30),
    heroGradientEnd: Color(0xFF1A2A48),
  );

  // Light variant ----------------------------------------------------------
  factory SocialPalette.light() => const SocialPalette(
    brightness: Brightness.light,
    background: Color(0xFFF6F8FB),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF1F5FA),
    glassFill: Color(0x14000000), // 8% black glass
    border: Color(0xFFE4EAF1),
    subtleDivider: Color(0xFFEFF3F8),
    textPrimary: Color(0xFF152033),
    textSecondary: Color(0xFF425063),
    textMuted: Color(0xFF8794A8),
    heroGradientStart: Color(0xFFFFFFFF),
    heroGradientEnd: Color(0xFFEAF1FA),
  );

  /// Soft cyan-tinted gradient used as the "hero" background.
  /// Adapts subtly per theme so it always feels fresh on top of [background].
  /// In dark mode it's richer — a midnight→indigo→cyan-tint sweep that
  /// makes hero blocks visibly different from regular cards.
  LinearGradient heroGradient() => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark
        ? [
            const Color(0xFF12203A), // brighter top-left
            const Color(0xFF1A2C4E), // mid indigo
            Color.alphaBlend(
              SocialTokens.cyan.withValues(alpha: 0.14),
              const Color(0xFF132238),
            ), // cyan-tinted bottom-right
          ]
        : [
            heroGradientStart,
            heroGradientEnd,
            SocialTokens.cyan.withValues(alpha: 0.06),
          ],
  );

  /// Soft tinted gradient used as a card backdrop in premium contexts.
  LinearGradient premiumCardGradient(Color accent) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      surface,
      Color.alphaBlend(accent.withValues(alpha: isDark ? 0.10 : 0.07), surface),
    ],
  );

  /// Glow color used for soft outer rings on hero items.
  Color glowFor(Color accent) =>
      accent.withValues(alpha: isDark ? 0.35 : 0.18);

  /// Subtle depth gradient for any card. Top-left a touch lighter than the
  /// flat surface, bottom-right a touch darker — tricks the eye into reading
  /// the card as having a tiny bit of dimension without being too "skeuo".
  ///
  /// In dark mode the lift is more pronounced so cards visibly separate from
  /// the deep midnight background.
  LinearGradient cardGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [
              Color(0xFF1B2B47), // brighter top-left
              Color(0xFF13213B), // slightly darker bottom-right
            ]
          : const [
              Color(0xFFFFFFFF),
              Color(0xFFF5F8FC),
            ],
    );
  }

  /// Returns a depth shadow stack for cards. In dark mode the shadow is a
  /// rich black; in light mode it's a soft warm shadow. Pass [accent] to
  /// add an extra glow that hints at the brand.
  List<BoxShadow> cardShadow({Color? accent}) {
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.45)
            : const Color(0xFF152033).withValues(alpha: 0.06),
        blurRadius: isDark ? 22 : 18,
        spreadRadius: -2,
        offset: const Offset(0, 8),
      ),
      if (accent != null)
        BoxShadow(
          color: accent.withValues(alpha: isDark ? 0.20 : 0.10),
          blurRadius: 28,
          spreadRadius: -8,
          offset: const Offset(0, 12),
        ),
    ];
  }

  /// Subtly accent-tinted UNIFORM border — gives cards a hint of brand
  /// presence without breaking [borderRadius] (Flutter requires uniform
  /// borders on rounded boxes). Falls back to the plain divider color when
  /// no accent is provided, or in light mode where the tint isn't needed.
  Border highlightedBorder({Color? accent}) {
    if (!isDark || accent == null) return Border.all(color: border);
    final tinted = Color.alphaBlend(
      accent.withValues(alpha: 0.18),
      border,
    );
    return Border.all(color: tinted, width: 1);
  }
}

/// Convenience accessor: `SocialTheme.of(context)`.
class SocialTheme {
  static SocialPalette of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark
        ? SocialPalette.dark()
        : SocialPalette.light();
  }
}
