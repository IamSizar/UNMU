import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../config/api_config.dart';
import '../../screens/social/social_tokens.dart';
import 'shariah_grade_chip.dart';

/// Cashtag parser + tiny inline card for chat bubbles (mig 0021,
/// item 5.16).
///
/// Usage:
///
///   final tickers = TickerCard.parseCashtags("Watching $NVDA into earns");
///   if (tickers.isNotEmpty)
///     TickerCardStrip(tickers: tickers);
///
/// We render the strip BELOW the message bubble, max 3 cards. Tap a
/// card → opens the stock detail screen (caller injects the
/// navigation callback).
class TickerCard extends StatefulWidget {
  final String symbol;
  final VoidCallback? onTap;

  const TickerCard({super.key, required this.symbol, this.onTap});

  /// Strict cashtag parser — picks `$AAPL`, `$NVDA`, `$BRK` (1..5
  /// uppercase letters preceded by `$` and a word boundary). Returns
  /// the unique set in order of appearance, capped at 3 entries to
  /// keep bubbles compact.
  static List<String> parseCashtags(String text) {
    final re = RegExp(r'(?<![A-Za-z])\$([A-Z]{1,5})(?![A-Za-z])');
    final out = <String>[];
    final seen = <String>{};
    for (final m in re.allMatches(text)) {
      final s = m.group(1)!;
      if (seen.add(s)) {
        out.add(s);
        if (out.length >= 3) break;
      }
    }
    return out;
  }

  @override
  State<TickerCard> createState() => _TickerCardState();
}

/// Tiny in-memory cache keyed by symbol so scrolling a chat doesn't
/// hammer the backend with the same lookup repeatedly. TTL is 5 min;
/// after that we refetch (so a fresh halal-grade flip eventually
/// propagates without a hard reload).
class _TickerCache {
  static final Map<String, _CacheEntry> _entries = {};
  static const Duration _ttl = Duration(minutes: 5);

  static _StockMatch? get(String symbol) {
    final e = _entries[symbol];
    if (e == null) return null;
    if (DateTime.now().difference(e.fetchedAt) > _ttl) {
      _entries.remove(symbol);
      return null;
    }
    return e.match;
  }

  static void put(String symbol, _StockMatch? match) {
    _entries[symbol] = _CacheEntry(match, DateTime.now());
  }
}

class _CacheEntry {
  final _StockMatch? match;
  final DateTime fetchedAt;
  _CacheEntry(this.match, this.fetchedAt);
}

class _StockMatch {
  final String ticker;
  final String name;
  final String? grade;
  final String? status;
  const _StockMatch({
    required this.ticker,
    required this.name,
    this.grade,
    this.status,
  });
}

class _TickerCardState extends State<TickerCard> {
  _StockMatch? _match;
  bool _loading = false;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    final cached = _TickerCache.get(widget.symbol);
    if (cached != null) {
      _match = cached;
    } else {
      _loading = true;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/search?q=${Uri.encodeQueryComponent(widget.symbol)}',
        ),
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        setState(() {
          _loading = false;
          _missing = true;
        });
        _TickerCache.put(widget.symbol, null);
        return;
      }
      final body = json.decode(res.body) as Map<String, dynamic>;
      final list = (body['results'] as List<dynamic>? ??
              body['stocks'] as List<dynamic>? ??
              const []);
      _StockMatch? hit;
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final t = (raw['ticker'] as String? ?? '').toUpperCase();
        if (t == widget.symbol) {
          final shariah = raw['shariah_status'] as Map<String, dynamic>?;
          hit = _StockMatch(
            ticker: t,
            name: raw['name'] as String? ?? t,
            grade: shariah?['grade'] as String?,
            status: shariah?['status'] as String?,
          );
          break;
        }
      }
      _TickerCache.put(widget.symbol, hit);
      setState(() {
        _loading = false;
        _match = hit;
        _missing = hit == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _missing = true;
      });
      _TickerCache.put(widget.symbol, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Unknown ticker → render nothing (caller filters at the strip level).
    if (_missing) return const SizedBox.shrink();
    final palette = SocialTheme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: SocialTokens.cyan.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '\$${widget.symbol}',
              style: const TextStyle(
                color: SocialTokens.cyan,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 6),
            if (_loading)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            else if (_match != null) ...[
              SizedBox(
                width: 80,
                child: Text(
                  _match!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_match!.grade != null && _match!.grade!.isNotEmpty) ...[
                const SizedBox(width: 6),
                ShariahGradeChip(
                  grade: _match!.grade!,
                  size: 16,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Horizontal strip of ticker cards rendered below a message bubble.
/// Skips render entirely when [tickers] is empty so callers can splat
/// without a null-check.
class TickerCardStrip extends StatelessWidget {
  final List<String> tickers;
  final void Function(String symbol)? onTickerTap;

  const TickerCardStrip({
    super.key,
    required this.tickers,
    this.onTickerTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tickers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final t in tickers)
            TickerCard(
              symbol: t,
              onTap: onTickerTap == null ? null : () => onTickerTap!(t),
            ),
        ],
      ),
    );
  }
}
