import 'package:flutter/material.dart';

import '../../screens/social/social_strings.dart';
import '../../screens/social/social_tokens.dart';

/// Greeting hero opens the Social Hub.
///
/// May 2026 refresh — time-aware, gradient-backed welcome block with
/// distinct day/dusk/night moods so the screen feels alive rather
/// than static. The old "MARKETS OPEN" pill + flat surface card was
/// readable but visually identical to every other card on the screen,
/// which made the hub feel monotone. Now:
///
///   ▸ Background  — a soft cyan→violet→midnight diagonal gradient
///                   tuned per time-of-day (warm cyan mornings,
///                   richer violet evenings).
///   ▸ Mood badge  — small "Good morning ☀" pill in the corner with a
///                   time-appropriate icon (☀️ → 🌤 → 🌙).
///   ▸ Name        — `firstName` rendered as a hero display headline.
///   ▸ Tagline     — one-line "Welcome back to the hub" copy.
///
/// The "MARKETS OPEN · LIVE" status was retired here because it
/// repeated information already conveyed by the live ticker strip on
/// community pages. If we want a status pill back, a single
/// `realtimeOnline` indicator (from RealtimeController) would be the
/// honest signal to surface.
class GreetingHero extends StatelessWidget {
  final String userName;
  final bool isArabic;

  const GreetingHero({
    super.key,
    required this.userName,
    required this.isArabic,
  });

  // ── time-of-day helpers ──────────────────────────────────────────
  // Three time buckets:
  //   morning  →  5 .. 11   (cool cyan glow, ☀️)
  //   afternoon → 12 .. 16  (warm cyan→violet, 🌤)
  //   evening  → 17 .. 4    (richer violet midnight, 🌙)
  _Mood _moodFor(int hour) {
    if (hour >= 5 && hour < 12) return _Mood.morning;
    if (hour >= 12 && hour < 17) return _Mood.afternoon;
    return _Mood.evening;
  }

  String _greetingFor(_Mood mood) {
    switch (mood) {
      case _Mood.morning:
        return isArabic
            ? SocialStrings.goodMorningAr
            : SocialStrings.goodMorning;
      case _Mood.afternoon:
        return isArabic
            ? SocialStrings.goodAfternoonAr
            : SocialStrings.goodAfternoon;
      case _Mood.evening:
        return isArabic
            ? SocialStrings.goodEveningAr
            : SocialStrings.goodEvening;
    }
  }

  String _moodIcon(_Mood mood) {
    switch (mood) {
      case _Mood.morning:
        return '☀️';
      case _Mood.afternoon:
        return '🌤';
      case _Mood.evening:
        return '🌙';
    }
  }

  List<Color> _gradientFor(_Mood mood, bool isDark) {
    // Each mood mixes two brand accents at a low alpha over a deep
    // base so the gradient is "felt" rather than overpowering. Dark
    // mode uses the deeper variants; light mode keeps the same hues
    // but at lower alpha for a sun-bleached feel.
    final cyanAlpha = isDark ? 0.30 : 0.18;
    final violetAlpha = isDark ? 0.28 : 0.16;
    final baseAlpha = isDark ? 1.0 : 0.04;
    final base = isDark
        ? const Color(0xFF0E1B2E)
        : const Color(0xFFF4FAFC);
    switch (mood) {
      case _Mood.morning:
        return [
          SocialTokens.cyan.withValues(alpha: cyanAlpha),
          SocialTokens.cyanDeep.withValues(alpha: cyanAlpha * 0.6),
          base.withValues(alpha: baseAlpha),
        ];
      case _Mood.afternoon:
        return [
          SocialTokens.cyan.withValues(alpha: cyanAlpha * 0.8),
          SocialTokens.violet.withValues(alpha: violetAlpha * 0.7),
          base.withValues(alpha: baseAlpha),
        ];
      case _Mood.evening:
        return [
          SocialTokens.violet.withValues(alpha: violetAlpha),
          SocialTokens.violetDeep.withValues(alpha: violetAlpha * 0.8),
          base.withValues(alpha: baseAlpha),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final hour = DateTime.now().hour;
    final mood = _moodFor(hour);
    final greeting = _greetingFor(mood);
    final firstName = userName.split(' ').first;
    final tagline = isArabic
        ? 'تابع مجتمعاتك وخبراءك'
        : 'Catch up with your communities & experts';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: palette.border.withValues(alpha: 0.6),
          width: 1,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientFor(mood, palette.isDark),
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: (mood == _Mood.evening
                    ? SocialTokens.violet
                    : SocialTokens.cyan)
                .withValues(alpha: palette.isDark ? 0.18 : 0.08),
            blurRadius: 24,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mood badge — "Good morning ☀" pill. Replaces the old
          // MARKETS OPEN pill (which was static text — not honest
          // status data — and added nothing the user couldn't already
          // see elsewhere).
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: palette.surface.withValues(
                    alpha: palette.isDark ? 0.50 : 0.70,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _moodIcon(mood),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      greeting.toUpperCase(),
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontWeight: FontWeight.w900,
                        fontSize: 9.5,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Name — hero headline. Uses 32pt and a slight negative
          // tracking so it reads like an editorial banner, not a
          // form field.
          Text(
            firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 32,
              letterSpacing: -0.8,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 4),
          // Tagline — what the user can do here. Short.
          Text(
            tagline,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

enum _Mood { morning, afternoon, evening }
