import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/api_service.dart';
import '../../screens/indexes/indexes_screen.dart';
import '../../screens/social/social_tokens.dart';

/// A modern, continuously-scrolling market ticker — the social hub's "news
/// bar". Pulls REAL index data from `GET /api/market/indexes` (S&P 500,
/// Nasdaq, Dow, regional benchmarks, …) and runs it as a seamless marquee:
/// each item shows the index name, last price, and the day's move with a
/// green/red arrow. Tapping anywhere opens the full Indexes screen.
///
/// Replaces the old "coming soon" placeholder cards. Self-contained: it
/// fetches its own data, shows a slim loader first, and quietly renders
/// nothing if the feed is empty so it never leaves a broken box.
class MarketTickerBar extends StatefulWidget {
  const MarketTickerBar({super.key});

  @override
  State<MarketTickerBar> createState() => _MarketTickerBarState();
}

class _MarketTickerBarState extends State<MarketTickerBar>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;

  // The marquee is two identical strips back-to-back; we translate left by up
  // to one strip-width then wrap to 0, which reads as an endless loop. We
  // measure the first strip once (via the key) to know the wrap distance and
  // to set a constant scroll speed regardless of item count.
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 30));
  final GlobalKey _stripKey = GlobalKey();
  double _stripWidth = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ApiService.getMarketIndexes();
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndRun());
  }

  void _measureAndRun() {
    if (!mounted) return;
    final w = _stripKey.currentContext?.size?.width ?? 0;
    if (w <= 0) return;
    _stripWidth = w;
    // ~45 px/sec — calm, readable. Clamp so tiny/huge lists still feel right.
    final ms = (w / 45 * 1000).round().clamp(14000, 90000);
    _ctrl
      ..duration = Duration(milliseconds: ms)
      ..reset()
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    if (_loading) return _shell(palette, child: _loader(palette));
    if (_items.isEmpty) return const SizedBox.shrink();

    final strip = _buildStrip(palette, key: _stripKey);
    final stripDup = _buildStrip(palette);

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const IndexesScreen()),
      ),
      child: _shell(
        palette,
        child: Row(
          children: [
            _leadingBadge(palette),
            Expanded(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => Transform.translate(
                    offset: Offset(-_ctrl.value * _stripWidth, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [strip, stripDup],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Outer rounded container shared by the loaded + loading states.
  Widget _shell(SocialPalette palette, {required Widget child}) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _leadingBadge(SocialPalette palette) {
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 12, end: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            SocialTokens.cyan.withValues(alpha: palette.isDark ? 0.16 : 0.10),
            SocialTokens.cyan.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _LivePulse(),
          const SizedBox(width: 6),
          Text(
            'socialHub.markets'.tr,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrip(SocialPalette palette, {Key? key}) {
    return Row(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [for (final it in _items) _tickerItem(it, palette)],
    );
  }

  Widget _tickerItem(Map<String, dynamic> it, SocialPalette palette) {
    final name = (it['name'] ?? it['symbol'] ?? '').toString();
    final price = (it['price'] as num?)?.toDouble() ?? 0;
    final chg = (it['change_percent'] as num?)?.toDouble() ?? 0;
    final up = chg >= 0;
    final color = up ? SocialTokens.up : SocialTokens.down;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _fmtPrice(price),
            style: TextStyle(
              color: palette.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            up ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
            color: color,
            size: 18,
          ),
          Text(
            '${up ? '+' : ''}${chg.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 11),
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: palette.textMuted.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtPrice(double p) =>
      p >= 1000 ? p.toStringAsFixed(0) : p.toStringAsFixed(2);

  Widget _loader(SocialPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: const AlwaysStoppedAnimation(SocialTokens.cyan),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'socialHub.markets'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small green dot that gently pulses — the "live" cue on the badge.
class _LivePulse extends StatefulWidget {
  const _LivePulse();

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value; // 0..1
        return Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: SocialTokens.up,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: SocialTokens.up.withValues(alpha: 0.5 * (1 - t)),
                blurRadius: 2 + 5 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}
