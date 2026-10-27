import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/language_controller.dart';
import '../../models/pulse_item.dart';
import '../../screens/social/social_tokens.dart';
import '../skeleton_loaders.dart';
import 'pulse_tokens.dart';

/// =============================================================================
/// pulse_cards.dart — the Pulse item cards and their small parts.
///
///   [PulseItemCard]      one item as a bento card (hero / half / wide)
///   [PulseEmptySlotCard] a slot with nothing published yet (never a hole)
///   [PulseCardsSkeleton] shimmering placeholders shaped like the real bento
///   [PulseTypeBadge]     "Confirmed" vs "Analysis" (spec §4: always distinct)
///   [PulseMarkerBadge]   New / Updated / Corrected
///   [PulseStockChip]     the linked stock + how it relates to the user
///
/// Everything is localised through `'pulse.*'.tr` and uses logical (start/end)
/// edges so it mirrors correctly in Arabic.
/// =============================================================================

/// True when the app language is Arabic (false in tests with no controller).
bool pulseIsArabic() {
  try {
    return Get.find<LanguageController>().isArabic;
  } catch (_) {
    return false;
  }
}

/// Card size variants of the home bento.
enum PulseCardSize { hero, half, wide }

/// The card surface each slot uses on the home screen (matches the mockup).
PulseSurface pulseSurfaceFor(PulseSlot slot) {
  switch (slot) {
    case PulseSlot.global:
      return PulseSurface.teal;
    case PulseSlot.sharia:
      return PulseSurface.ink;
    case PulseSlot.gulf:
    case PulseSlot.opportunity:
      return PulseSurface.glass;
  }
}

/// Foreground colours for a surface (tones are always white-on-dark).
class _Fg {
  final Color primary;
  final Color secondary;
  final Color accent;
  final bool onTone;

  const _Fg(this.primary, this.secondary, this.accent, this.onTone);

  factory _Fg.of(BuildContext context, PulseSurface surface) {
    if (surface != PulseSurface.glass) {
      return _Fg(
        Colors.white,
        Colors.white.withValues(alpha: 0.86),
        surface == PulseSurface.ink ? PulseColors.tealBright : Colors.white,
        true,
      );
    }
    final p = SocialTheme.of(context);
    return _Fg(
      p.textPrimary,
      p.textSecondary,
      p.isDark ? PulseColors.tealBright : PulseColors.tealInk,
      false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Badges
// ─────────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 9,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: pulseIsArabic() ? 0 : 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Confirmed" (verified fact with a source) vs "Analysis" (interpretation).
class PulseTypeBadge extends StatelessWidget {
  final bool isAnalysis;
  final bool onTone;

  const PulseTypeBadge({
    super.key,
    required this.isAnalysis,
    this.onTone = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = SocialTheme.of(context).isDark;
    if (onTone) {
      return _Pill(
        label:
            (isAnalysis ? 'pulse.badge.analysis' : 'pulse.badge.confirmed').tr,
        background: Colors.white.withValues(alpha: 0.2),
        foreground: Colors.white,
        icon: isAnalysis ? null : PulseIcons.verified(context),
      );
    }
    return isAnalysis
        ? _Pill(
            label: 'pulse.badge.analysis'.tr,
            background: const Color(
              0xFF8A5BC7,
            ).withValues(alpha: dark ? 0.26 : 0.16),
            foreground: dark
                ? const Color(0xFFD8CBFF)
                : const Color(0xFF5B3A8E),
          )
        : _Pill(
            label: 'pulse.badge.confirmed'.tr,
            background: PulseColors.teal.withValues(alpha: dark ? 0.22 : 0.14),
            foreground: dark ? PulseColors.tealBright : PulseColors.tealInk,
            icon: PulseIcons.verified(context),
          );
  }
}

/// New / Updated / Corrected. Renders nothing when the item has no marker.
class PulseMarkerBadge extends StatelessWidget {
  final PulseItem item;
  final bool onTone;

  const PulseMarkerBadge({super.key, required this.item, this.onTone = false});

  @override
  Widget build(BuildContext context) {
    final String? key = item.isCorrected
        ? 'pulse.badge.corrected'
        : item.isUpdated
        ? 'pulse.badge.updated'
        : item.isNew
        ? 'pulse.badge.new'
        : null;
    if (key == null) return const SizedBox.shrink();

    if (item.isNew) {
      return _Pill(
        label: key.tr,
        background: onTone ? Colors.white : PulseColors.tealDeep,
        foreground: onTone ? PulseColors.tealInk : Colors.white,
      );
    }
    // Updated / corrected share the amber "this changed" look.
    return _Pill(
      label: key.tr,
      background: onTone
          ? Colors.white.withValues(alpha: 0.2)
          : const Color(0xFFF5A623).withValues(alpha: 0.2),
      foreground: onTone ? Colors.white : const Color(0xFF7A4F00),
    );
  }
}

/// The linked stock ("2222 · TADAWUL") and how it relates to the user.
class PulseStockChip extends StatelessWidget {
  final PulseItem item;
  final bool onTone;

  const PulseStockChip({super.key, required this.item, this.onTone = false});

  @override
  Widget build(BuildContext context) {
    final stock = item.stock;
    if (stock == null) return const SizedBox.shrink();
    final p = SocialTheme.of(context);
    final fg = onTone ? Colors.white : p.textPrimary;
    final inList = item.relation != null;

    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: onTone
            ? Colors.white.withValues(alpha: 0.18)
            : (p.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: onTone ? Colors.white.withValues(alpha: 0.3) : p.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inList)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsetsDirectional.only(end: 6),
              decoration: BoxDecoration(
                color: item.relation == 'portfolio'
                    ? SocialTokens.up
                    : PulseColors.tealBright,
                shape: BoxShape.circle,
              ),
            ),
          Flexible(
            child: Text(
              inList
                  ? (item.relation == 'portfolio'
                        ? 'pulse.relation.portfolio'.tr
                        : 'pulse.relation.watchlist'.tr)
                  : stock.ticker,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Cards
// ─────────────────────────────────────────────────────────────────────────

/// One published item as a bento card.
class PulseItemCard extends StatelessWidget {
  final PulseItem item;
  final PulseCardSize size;
  final VoidCallback onTap;

  const PulseItemCard({
    super.key,
    required this.item,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = pulseSurfaceFor(item.slot);
    final fg = _Fg.of(context, surface);
    final arabic = pulseIsArabic();
    final hero = size == PulseCardSize.hero;
    final titleSize = hero ? 22.0 : (size == PulseCardSize.wide ? 17.0 : 15.5);
    final shownTime = item.publishedAt ?? item.verifiedAt;
    final slotLabel = 'pulse.slot.${item.slot.name}'.tr;
    final title = item.title(arabic);
    final typeLabel =
        (item.isAnalysis ? 'pulse.badge.analysis' : 'pulse.badge.confirmed').tr;

    return Semantics(
      button: true,
      label: '$slotLabel. $title. $typeLabel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kPulseRadius),
          onTap: onTap,
          child: PulseSurfaceBox(
            surface: surface,
            padding: EdgeInsets.all(hero ? 18 : PulseSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Slot label + Confirmed/Analysis
                Row(
                  children: [
                    Icon(
                      PulseIcons.slot(context, item.slot),
                      size: 17,
                      color: fg.accent,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        slotLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: arabic ? 0 : 0.8,
                        ),
                      ),
                    ),
                    if (size != PulseCardSize.half) ...[
                      const SizedBox(width: 6),
                      PulseTypeBadge(
                        isAnalysis: item.isAnalysis,
                        onTone: fg.onTone,
                      ),
                    ],
                  ],
                ),
                SizedBox(height: hero ? 12 : 10),
                Text(
                  title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg.primary,
                    fontSize: titleSize,
                    height: arabic ? 1.5 : 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (shownTime != null)
                  Row(
                    children: [
                      Icon(
                        PulseIcons.clock(context),
                        size: 14,
                        color: fg.secondary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          item.sourceName.isEmpty
                              ? pulseTime(shownTime)
                              : '${pulseTime(shownTime)} · ${item.sourceName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: fg.secondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                SizedBox(height: hero ? 14 : 10),
                // Footer: type (half cards), marker, stock
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (size == PulseCardSize.half)
                      PulseTypeBadge(
                        isAnalysis: item.isAnalysis,
                        onTone: fg.onTone,
                      ),
                    PulseMarkerBadge(item: item, onTone: fg.onTone),
                    if (item.stock != null)
                      PulseStockChip(item: item, onTone: fg.onTone),
                    if (hero)
                      Text(
                        '${'pulse.readDetails'.tr} ›',
                        style: TextStyle(color: fg.secondary, fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A slot with nothing published yet. Keeps the bento shape instead of leaving
/// a hole, and tells the user why.
class PulseEmptySlotCard extends StatelessWidget {
  final PulseSlot slot;

  const PulseEmptySlotCard({super.key, required this.slot});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return Semantics(
      label: '${'pulse.slot.${slot.name}'.tr}. ${'pulse.slot.empty'.tr}',
      child: PulseSurfaceBox(
        surface: PulseSurface.glass,
        child: Row(
          children: [
            Icon(PulseIcons.slot(context, slot), size: 18, color: p.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'pulse.slot.${slot.name}'.tr,
                    style: TextStyle(
                      color: p.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'pulse.slot.empty'.tr,
                    style: TextStyle(color: p.textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shimmering placeholders shaped like the real bento (hero, two halves, wide),
/// so content fills in instead of popping in.
class PulseCardsSkeleton extends StatelessWidget {
  const PulseCardsSkeleton({super.key});

  Widget _card(double height, List<Widget> lines) => PulseSurfaceBox(
    surface: PulseSurface.glass,
    child: SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const half = [
      SkeletonBox(width: 70, height: 11),
      SizedBox(height: 12),
      SkeletonBox(height: 14),
      SizedBox(height: 6),
      SkeletonBox(width: 90, height: 14),
    ];
    return Semantics(
      label: 'pulse.title'.tr,
      child: ExcludeSemantics(
        child: Shimmer(
          child: Column(
            children: [
              _card(138, const [
                SkeletonBox(width: 110, height: 11),
                SizedBox(height: 14),
                SkeletonBox(height: 20),
                SizedBox(height: 8),
                SkeletonBox(width: 220, height: 20),
                Spacer(),
                SkeletonBox(width: 130, height: 11),
              ]),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _card(118, half)),
                  const SizedBox(width: 10),
                  Expanded(child: _card(118, half)),
                ],
              ),
              const SizedBox(height: 10),
              _card(92, const [
                SkeletonBox(width: 120, height: 11),
                SizedBox(height: 12),
                SkeletonBox(height: 16),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
