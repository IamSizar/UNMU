// =============================================================================
// aurora_tokens.dart
//
// The Aurora bento glass finish, expressed in UNMU's own brand colours.
//
// Aurora bento (aurora-bento/src/styles/aurora.css) describes a surface, not a
// palette: a frosted card floating over coloured light, with a bright inset
// edge and a colour-tinted drop shadow. This file keeps that *recipe* and
// feeds it UNMU's colours instead of the library's stock blobs, so the app
// gains the finish without gaining a second brand.
//
// Everything is derived, not written down twice:
//   * the aurora sweep is built from [SocialTokens] (violet / cyan / gold),
//   * fill, border, sheen and shadow are computed from the live
//     [SocialPalette] and the brand accent for the current theme.
//
// Change a brand colour in social_tokens.dart and the tab bar follows. There
// are no literal hex values below.
//
// See widgets/aurora/aurora_glass_surface.dart for the widget that paints it.
// =============================================================================

import 'package:flutter/material.dart';

import '../screens/social/social_tokens.dart';

/// Blur and motion constants for the aurora glass finish.
///
/// These are the only fixed numbers in the file; they describe the optics of
/// the material, not its colour, so they do not belong to the palette.
abstract final class AuroraTokens {
  /// Gaussian sigma for the backdrop blur.
  ///
  /// The CSS original is `blur(40px)`. A CSS blur radius is approximately
  /// twice the Gaussian sigma, so 40px maps to sigma 20. Pushed past that
  /// here: with the fill this translucent, a softer backdrop is what keeps
  /// text behind the bar from reading as legible-but-smeared content rather
  /// than as frosted glass.
  static const double blurSigma = 34;

  /// Saturation multiplier applied to the blurred backdrop.
  ///
  /// The CSS original is `saturate(2)`. Dialled right back: at 2.0 the colour
  /// cast over a photo-heavy feed reads as a rendering bug rather than a
  /// finish, and on a near-white light theme it turned everything showing
  /// through the bar into a muddy pastel wash. 1.15 is enough to stop the
  /// blurred backdrop looking grey without tinting it.
  static const double saturation = 1.15;

  /// Duration of the active-pill slide. Matches the existing nav cross-fade
  /// in modern_bottom_nav.dart so the two never look out of step.
  static const Duration pillSlide = Duration(milliseconds: 300);
}

/// The resolved aurora glass recipe for the current theme.
///
/// Resolve once per build with [AuroraGlass.of] rather than re-deriving at
/// each paint site, so every part of a surface agrees about the brightness.
@immutable
class AuroraGlass {
  /// Live palette the recipe was derived from. Kept so callers can reach
  /// text and surface colours without a second lookup.
  final SocialPalette palette;

  const AuroraGlass._(this.palette);

  /// Derives the recipe from the ambient theme.
  ///
  /// Uses [SocialTheme.of], which reads `Theme.of(context).brightness` — so an
  /// in-app theme override is honoured rather than the platform setting.
  factory AuroraGlass.of(BuildContext context) =>
      AuroraGlass._(SocialTheme.of(context));

  bool get isDark => palette.isDark;

  /// The aurora sweep: the colours the surface appears to be lit by.
  ///
  /// The aurora sweep: the colours the surface appears to be lit by.
  ///
  /// Dark mode gets the full accent trio — violet → cyan → gold, hue rotating
  /// in one direction so it reads as a single band of light rather than three
  /// stripes. Against a near-black page it looks like an aurora.
  ///
  /// Light mode drops gold and violet. On a near-white page a warm accent
  /// turns the glass beige and the three-colour sweep reads as a smudge
  /// rather than as light. What is left is a single cool hue at two
  /// strengths, which tints the glass without colouring the content behind
  /// it.
  List<Color> get sweep => isDark
      ? const <Color>[
          SocialTokens.violet,
          SocialTokens.cyan,
          SocialTokens.gold,
        ]
      : const <Color>[
          SocialTokens.cyanSoft,
          SocialTokens.cyan,
        ];

  /// Translucent body painted over the blurred backdrop.
  ///
  /// Derived from the palette's own surface colour so the bar belongs to the
  /// theme it floats on.
  ///
  /// Light mode stays more opaque than dark. The CSS original is 30%, which
  /// assumes a saturated aurora page behind the card; this app's light theme
  /// is near-white, where 30% drops icon contrast below the 4.5:1 floor
  /// against scrolled content. 0.58 is the most transparent setting that
  /// still clears it with the labels at their current weight — do not lower
  /// this without re-checking contrast against a white-background screen.
  Color get fill => palette.surface.withValues(alpha: isDark ? 0.16 : 0.46);

  /// Hairline around the surface. Brand-tinted rather than plain white, which
  /// is what keeps the edge in the aurora family instead of looking like a
  /// generic frosted panel.
  Color get border => Color.lerp(
        palette.border,
        SocialTokens.cyan,
        isDark ? 0.22 : 0.14,
      )!
          .withValues(alpha: isDark ? 0.55 : 0.70);

  /// Inset highlight along the top edge — the single line that makes glass
  /// read as glass. Light mode gets a near-opaque white; dark mode only a
  /// suggestion, or the bar looks like it has a chrome rim.
  Color get sheen => (isDark ? palette.textPrimary : Colors.white)
      .withValues(alpha: isDark ? 0.20 : 0.95);

  /// Drop shadow. Tinted with the brand violet rather than neutral black —
  /// the coloured shadow is what separates an aurora surface from a plain
  /// Material elevation.
  Color get shadow => Color.lerp(
        Colors.black,
        SocialTokens.violetDeep,
        isDark ? 0.45 : 0.65,
      )!
          .withValues(alpha: isDark ? 0.55 : 0.22);

  /// Opacity of the aurora glow bleeding out from behind the surface.
  ///
  /// Dark mode carries it: there is no bright page behind the glass for the
  /// colour to pick up, so the glow is the only thing making it aurora.
  ///
  /// Light mode is nearly off. At 0.26 the coloured pools read as a stain on
  /// the white UI instead of as light — the glass should look clean and cool,
  /// and get its character from the blur and the bright edge, not from pigment.
  double get glowOpacity => isDark ? 0.45 : 0.07;

  /// Fill for the sliding pill behind the active tab.
  ///
  /// Dark mode uses the full sweep at reduced alpha. Light mode uses the cool
  /// pair only — a multi-hue pill on white looked like a colour-fringing
  /// artefact around the selected icon. Alpha stays low either way: this sits
  /// UNDER the icon and label, and anything stronger costs the 4.5:1 text
  /// contrast the design rules require.
  List<Color> get pillFill => <Color>[
        for (final c in sweep) c.withValues(alpha: isDark ? 0.34 : 0.20),
      ];

  /// Colour of the glow cast by the active pill.
  Color get pillGlow =>
      SocialTokens.cyan.withValues(alpha: isDark ? 0.34 : 0.16);
}
