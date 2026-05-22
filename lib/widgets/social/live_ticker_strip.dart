import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/social/mock_social_data.dart';
import '../../screens/social/social_tokens.dart';
import 'price_indicator.dart';
import 'shariah_grade_chip.dart';

/// A horizontally-scrolling strip of live tickers, with an animated "LIVE"
/// pulse pill on the leading edge. Adapts surfaces / borders to the current
/// theme via [SocialTheme.of(context)].
class LiveTickerStrip extends StatelessWidget {
  final List<TickerQuote> quotes;
  final bool showLiveBadge;
  final bool isArabic;

  const LiveTickerStrip({
    super.key,
    required this.quotes,
    this.showLiveBadge = true,
    this.isArabic = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (showLiveBadge) const _LivePill(),
          if (showLiveBadge) const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: quotes.length,
              physics: const BouncingScrollPhysics(),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) =>
                  _TickerChip(quote: quotes[i], palette: palette),
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatefulWidget {
  const _LivePill();

  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = 'ticker.live'.tr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: SocialTokens.down.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SocialTokens.down.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SocialTokens.down.withValues(
                  alpha: 0.5 + _ctrl.value * 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: SocialTokens.down.withValues(
                      alpha: _ctrl.value * 0.6,
                    ),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: SocialTokens.down,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _TickerChip extends StatelessWidget {
  final TickerQuote quote;
  final SocialPalette palette;
  const _TickerChip({required this.quote, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShariahGradeChip(grade: quote.shariahGrade, size: 16),
          const SizedBox(width: 6),
          Text(
            quote.symbol,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          PriceIndicator(changePct: quote.changePct, fontSize: 11, dense: true),
        ],
      ),
    );
  }
}
