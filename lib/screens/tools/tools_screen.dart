import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:get/get.dart';

import '../../screens/social/social_tokens.dart';
import '../../utils/haptic_utils.dart';
import 'dca_calculator_screen.dart';
import 'zakat_calculator_screen.dart';

/// =============================================================================
/// Tools Screen — editorial bento landing.
///
///   ▸ Themed app bar
///   ▸ Hero header: "Calculation tools" eyebrow + bold title + subtitle
///   ▸ 2-column bento grid of tool tiles (Zakat, DCA, future tools)
/// =============================================================================
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);

    final tools = <_ToolEntry>[
      _ToolEntry(
        icon: Icons.volunteer_activism_rounded,
        accent: SocialTokens.gold,
        title: 'tools.zakatTitle'.tr,
        subtitle: 'tools.zakatSubtitle'.tr,
        eyebrow: 'tools.zakatEyebrow'.tr,
        onTap: () =>
            _open(context, const ZakatCalculatorScreen()),
      ),
      _ToolEntry(
        icon: Icons.trending_up_rounded,
        accent: SocialTokens.up,
        title: 'tools.dcaTitle'.tr,
        subtitle: 'tools.dcaSubtitle'.tr,
        eyebrow: 'tools.dcaEyebrow'.tr,
        onTap: () => _open(context, const DcaCalculatorScreen()),
      ),
    ];

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'tools.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: SafeArea(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _Hero(palette: palette),
            const SizedBox(height: 22),
            _MiniSectionHeader(
              palette: palette,
              eyebrow: 'tools.sectionEyebrow'.tr,
              title: 'tools.sectionTitle'.tr,
            ),
            const SizedBox(height: 12),
            // 2-col bento grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.95,
              children: tools.map((t) => _ToolTile(entry: t)).toList(),
            ),
            const SizedBox(height: 22),
            // Coming soon teaser
            _ComingSoonTile(palette: palette),
          ],
        ),
      ),
    );
  }

  static void _open(BuildContext context, Widget screen) {
    HapticUtils.lightTap();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}

class _ToolEntry {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String eyebrow;
  final VoidCallback onTap;
  const _ToolEntry({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.eyebrow,
    required this.onTap,
  });
}

// ============================================================================
// Hero header — sets the tone of the page
// ============================================================================
class _Hero extends StatelessWidget {
  final SocialPalette palette;
  const _Hero({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: SocialTokens.cyan.withValues(alpha: 0.4),
          width: 1.4,
        ),
        boxShadow: palette.cardShadow(accent: SocialTokens.cyan),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.calculate_rounded,
              color: Color(0xFF0A1628),
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'tools.eyebrow'.tr.toUpperCase(),
                  style: const TextStyle(
                    color: SocialTokens.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'tools.title'.tr,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'tools.heroSubtitle'.tr,
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Section header
// ============================================================================
class _MiniSectionHeader extends StatelessWidget {
  final SocialPalette palette;
  final String eyebrow;
  final String title;
  const _MiniSectionHeader({
    required this.palette,
    required this.eyebrow,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: SocialTokens.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 19,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Tool tile — bento card with icon, eyebrow, title, subtitle, arrow
// ============================================================================
class _ToolTile extends StatelessWidget {
  final _ToolEntry entry;
  const _ToolTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: palette.cardShadow(accent: entry.accent),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: entry.onTap,
          borderRadius: BorderRadius.circular(20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                gradient: palette.cardGradient(),
                borderRadius: BorderRadius.circular(20),
                border: palette.highlightedBorder(accent: entry.accent),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: entry.accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(entry.icon, color: entry.accent, size: 22),
                  ),
                  const Spacer(),
                  Text(
                    entry.eyebrow.toUpperCase(),
                    style: TextStyle(
                      color: entry.accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 9.5,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'tools.open'.tr,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      DirectionalIcon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: palette.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Coming soon teaser — placeholder for future tools
// ============================================================================
class _ComingSoonTile extends StatelessWidget {
  final SocialPalette palette;
  const _ComingSoonTile({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF8B5CF6),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'tools.comingSoon'.tr,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'tools.comingSoonSubtitle'.tr,
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'tools.soon'.tr,
              style: const TextStyle(
                color: Color(0xFF8B5CF6),
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
