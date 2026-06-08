import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/api_service.dart';
import '../../screens/indexes/indexes_screen.dart';
import '../../screens/social/social_tokens.dart';
import 'sparkline_chart.dart';

/// "Market Pulse" — a real-data block for the social hub that fills the space
/// the old "coming soon" cards left behind. Two pieces, both live:
///
///   1. A Fear & Greed **sentiment gauge** (GET /api/market/fear-greed):
///      gradient bar with a marker at the current value, a localized label,
///      and the move vs the previous close.
///   2. **Index spotlight** cards (GET /api/market/indexes): name, price,
///      % change and a mini sparkline each, in a horizontal scroller.
///
/// Self-contained: fetches its own data in parallel, shows a slim skeleton
/// while loading, and renders nothing if both feeds are empty so it never
/// leaves a blank gap.
class MarketPulse extends StatefulWidget {
  final bool isArabic;
  const MarketPulse({super.key, required this.isArabic});

  @override
  State<MarketPulse> createState() => _MarketPulseState();
}

class _MarketPulseState extends State<MarketPulse> {
  Map<String, dynamic>? _fg;
  List<Map<String, dynamic>> _indexes = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      ApiService.getFearAndGreedIndex(),
      ApiService.getMarketIndexes(),
    ]);
    if (!mounted) return;
    setState(() {
      _fg = results[0] as Map<String, dynamic>?;
      _indexes = (results[1] as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    if (_loading) return _skeleton(palette);
    if (_fg == null && _indexes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_fg != null) _sentimentCard(palette, _fg!),
        if (_fg != null && _indexes.isNotEmpty) const SizedBox(height: 14),
        if (_indexes.isNotEmpty) _indexSpotlight(palette),
      ],
    );
  }

  // ── Fear & Greed sentiment gauge ──────────────────────────────────────
  Widget _sentimentCard(SocialPalette palette, Map<String, dynamic> fg) {
    final value = (fg['value'] as num?)?.toInt() ?? 50;
    final prev = (fg['previous_close'] as num?)?.toInt();
    final delta = prev == null ? null : value - prev;
    final tone = _sentimentColor(value);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 16, color: tone),
              const SizedBox(width: 7),
              Text(
                'socialHub.sentimentTitle'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              Text(
                '$value',
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Gauge: red → amber → green gradient with a marker at value/100.
          LayoutBuilder(
            builder: (context, c) {
              final x = (value.clamp(0, 100) / 100.0) * c.maxWidth;
              return SizedBox(
                height: 14,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 8,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFEF4444),
                            Color(0xFFFDD835),
                            Color(0xFF10B981),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: (x - 7).clamp(0.0, c.maxWidth - 14),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: palette.surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: tone, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: tone.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                _sentimentLabel(value),
                style: TextStyle(
                  color: tone,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              if (delta != null)
                Text(
                  '${delta >= 0 ? '+' : ''}$delta ${'socialHub.vsPrevClose'.tr}',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _sentimentColor(int v) {
    if (v < 25) return const Color(0xFFEF4444); // extreme fear
    if (v < 45) return const Color(0xFFF59E0B); // fear
    if (v <= 55) return const Color(0xFFFDD835); // neutral
    if (v <= 75) return SocialTokens.up; // greed
    return const Color(0xFF059669); // extreme greed
  }

  String _sentimentLabel(int v) {
    if (v < 25) return 'socialHub.sentExtremeFear'.tr;
    if (v < 45) return 'socialHub.sentFear'.tr;
    if (v <= 55) return 'socialHub.sentNeutral'.tr;
    if (v <= 75) return 'socialHub.sentGreed'.tr;
    return 'socialHub.sentExtremeGreed'.tr;
  }

  // ── Index spotlight ───────────────────────────────────────────────────
  Widget _indexSpotlight(SocialPalette palette) {
    final items = _indexes.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 2, bottom: 8),
          child: Text(
            'socialHub.indicesTitle'.tr,
            style: TextStyle(
              color: palette.textSecondary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _indexCard(palette, items[i]),
          ),
        ),
      ],
    );
  }

  Widget _indexCard(SocialPalette palette, Map<String, dynamic> it) {
    final name = (it['name'] ?? it['symbol'] ?? '').toString();
    final price = (it['price'] as num?)?.toDouble() ?? 0;
    final chg = (it['change_percent'] as num?)?.toDouble() ?? 0;
    final up = chg >= 0;
    final color = up ? SocialTokens.up : SocialTokens.down;
    final spark = ((it['sparkline'] as List?) ?? const [])
        .map((e) => (e as num).toDouble())
        .toList();

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const IndexesScreen()),
      ),
      child: Container(
        width: 158,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(
                  price >= 1000 ? price.toStringAsFixed(0) : price.toStringAsFixed(2),
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Icon(
                  up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                  color: color,
                  size: 16,
                ),
                Text(
                  '${up ? '+' : ''}${chg.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SparklineChart(
                data: spark,
                overrideColor: color,
                height: 40,
                strokeWidth: 1.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton(SocialPalette palette) {
    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: const AlwaysStoppedAnimation(SocialTokens.cyan),
        ),
      ),
    );
  }
}
