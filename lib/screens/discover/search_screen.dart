import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../screens/social/social_tokens.dart';
import '../../screens/stock_detail/stock_detail_screen.dart';
import '../../services/api_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/ads/banner_ad_widget.dart';
import '../../widgets/stock_card.dart';

/// =============================================================================
/// Search Screen — modern fintech search.
///
///   ▸ Custom rounded search field with cyan focus glow
///   ▸ Recent searches (in-memory) as quick chips
///   ▸ Suggested categories when input is empty
///   ▸ Skeleton loaders while results stream in
///   ▸ Polished empty / error states
///   ▸ Theme-reactive via SocialTheme
/// =============================================================================
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  final List<String> _recent = [];

  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  String? _error;
  Timer? _debounceTimer;
  bool _hasText = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus != _isFocused) {
        setState(() => _isFocused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---- search behaviour --------------------------------------------------

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await ApiService.searchStocks(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
      _rememberQuery(query);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSearching = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    setState(() => _hasText = value.isNotEmpty);

    if (value.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
        _error = null;
      });
      return;
    }
    if (value.length < 2) {
      setState(() => _results = []);
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      _search(value);
    });
  }

  /// Tracks recently-typed queries so we can show them as quick chips.
  /// Most recent first; bounded to 6.
  void _rememberQuery(String q) {
    final t = q.trim();
    if (t.isEmpty) return;
    _recent.removeWhere((s) => s.toLowerCase() == t.toLowerCase());
    _recent.insert(0, t);
    if (_recent.length > 6) _recent.removeLast();
    setState(() {});
  }

  void _useQuery(String q) {
    _searchController.text = q;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: q.length),
    );
    setState(() => _hasText = true);
    _search(q);
    HapticUtils.lightTap();
  }

  void _clear() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _hasText = false;
      _results = [];
      _isSearching = false;
      _error = null;
    });
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'search.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: Column(
        children: [
          // ── Search field (custom, focus-glow) ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _SearchField(
              palette: palette,
              controller: _searchController,
              focusNode: _focusNode,
              isFocused: _isFocused,
              hasText: _hasText,
              onChanged: _onSearchChanged,
              onClear: _clear,
              onSubmitted: (v) {
                _debounceTimer?.cancel();
                _search(v);
              },
            ),
          ),
          // ── Body ──
          Expanded(
            child: _buildBody(palette),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(SocialPalette palette) {
    // 1) Searching → skeleton list
    if (_isSearching) {
      return _SkeletonList(palette: palette);
    }

    // 2) Error
    if (_error != null) {
      return _ErrorState(
        palette: palette,
        message: _error!,
        retryLabel: 'common.retry'.tr,
        onRetry: () => _search(_searchController.text),
      );
    }

    // 3) Has results
    if (_results.isNotEmpty) {
      final auth = Get.find<AuthController>();
      final visibleResults = !auth.isPremium && _results.length > 5
          ? _results.sublist(0, 5)
          : _results;

      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: _ResultsHeader(
              palette: palette,
              count: visibleResults.length,
              isPremiumLimited:
                  !auth.isPremium && _results.length > 5,
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              physics: const BouncingScrollPhysics(),
              itemCount: visibleResults.length,
              itemBuilder: (_, i) {
                final stock = visibleResults[i];
                return InkWell(
                  onTap: () {
                    HapticUtils.lightTap();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StockDetailScreen(
                          ticker: stock['ticker']?.toString() ?? '',
                          exchange: stock['exchange']?.toString() ?? '',
                        ),
                      ),
                    );
                  },
                  child: StockCard(stock: stock),
                );
              },
            ),
          ),
          if (!auth.isPremium) const BannerAdWidget(),
        ],
      );
    }

    // 4) No results for current query
    if (_hasText && _searchController.text.length >= 2) {
      return _EmptyState(
        palette: palette,
        icon: Icons.travel_explore_rounded,
        title: 'search.noResults'.tr,
        subtitle: 'search.noResultsSubtitle'.tr,
      );
    }

    // 5) Idle / typing < 2 chars → suggestions + recent
    return _IdleSuggestions(
      palette: palette,
      recent: _recent,
      onPickRecent: _useQuery,
      onPickSuggestion: _useQuery,
      onClearRecent: () {
        setState(() => _recent.clear());
        HapticUtils.lightTap();
      },
    );
  }
}

// ============================================================================
// Custom search field with focus glow
// ============================================================================
class _SearchField extends StatelessWidget {
  final SocialPalette palette;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const _SearchField({
    required this.palette,
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.hasText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFocused ? SocialTokens.cyan : palette.border,
          width: isFocused ? 1.4 : 1,
        ),
        boxShadow: isFocused
            ? [
                BoxShadow(
                  color: SocialTokens.cyan.withValues(alpha: 0.20),
                  blurRadius: 20,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SocialTokens.cyan.withValues(alpha: isFocused ? 0.22 : 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.search_rounded,
                color: SocialTokens.cyan,
                size: 18,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'search.hint'.tr,
                hintStyle: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w500,
                ),
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (hasText)
            IconButton(
              tooltip: 'search.clear'.tr,
              icon: Icon(
                Icons.close_rounded,
                color: palette.textMuted,
                size: 18,
              ),
              onPressed: onClear,
            )
          else
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  'search.cta'.tr,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Results header — count + premium-limit hint
// ============================================================================
class _ResultsHeader extends StatelessWidget {
  final SocialPalette palette;
  final int count;
  final bool isPremiumLimited;

  const _ResultsHeader({
    required this.palette,
    required this.count,
    required this.isPremiumLimited,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'search.results'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: palette.border),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const Spacer(),
        if (isPremiumLimited)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: SocialTokens.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: SocialTokens.gold.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.workspace_premium_rounded,
                  size: 11,
                  color: SocialTokens.gold,
                ),
                const SizedBox(width: 4),
                Text(
                  'search.premiumForMore'.tr,
                  style: const TextStyle(
                    color: SocialTokens.gold,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// Idle state — recent searches + suggestion categories
// ============================================================================
class _IdleSuggestions extends StatelessWidget {
  final SocialPalette palette;
  final List<String> recent;
  final ValueChanged<String> onPickRecent;
  final ValueChanged<String> onPickSuggestion;
  final VoidCallback onClearRecent;

  const _IdleSuggestions({
    required this.palette,
    required this.recent,
    required this.onPickRecent,
    required this.onPickSuggestion,
    required this.onClearRecent,
  });

  @override
  Widget build(BuildContext context) {
    final suggestions = <_Suggestion>[
      _Suggestion(
        'search.sector.tech'.tr,
        Icons.memory_rounded,
        SocialTokens.cyan,
        'AAPL',
      ),
      _Suggestion(
        'search.sector.energy'.tr,
        Icons.bolt_rounded,
        SocialTokens.gold,
        'ARAMCO',
      ),
      _Suggestion(
        'search.sector.banks'.tr,
        Icons.account_balance_rounded,
        SocialTokens.up,
        'JPM',
      ),
      _Suggestion(
        'search.sector.health'.tr,
        Icons.health_and_safety_rounded,
        const Color(0xFFF472B6),
        'JNJ',
      ),
      _Suggestion(
        'search.sector.consumer'.tr,
        Icons.shopping_bag_rounded,
        const Color(0xFF8B5CF6),
        'NKE',
      ),
      _Suggestion(
        'search.sector.industrials'.tr,
        Icons.precision_manufacturing_rounded,
        SocialTokens.cyanSoft,
        'SABIC',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const BouncingScrollPhysics(),
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              Text(
                'search.recent'.tr.toUpperCase(),
                style: const TextStyle(
                  color: SocialTokens.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onClearRecent,
                child: Text(
                  'search.clear'.tr,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: recent
                .map(
                  (q) => _RecentChip(
                    palette: palette,
                    label: q,
                    onTap: () => onPickRecent(q),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 24),
        ],

        // Suggested categories
        Text(
          'search.browse'.tr.toUpperCase(),
          style: const TextStyle(
            color: SocialTokens.cyan,
            fontWeight: FontWeight.w900,
            fontSize: 10.5,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'search.bySector'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.4,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: suggestions.length,
          itemBuilder: (_, i) {
            final s = suggestions[i];
            return _SuggestionTile(
              palette: palette,
              suggestion: s,
              onTap: () => onPickSuggestion(s.seedQuery),
            );
          },
        ),
      ],
    );
  }
}

class _Suggestion {
  final String label;
  final IconData icon;
  final Color accent;
  final String seedQuery;
  const _Suggestion(this.label, this.icon, this.accent, this.seedQuery);
}

class _RecentChip extends StatelessWidget {
  final SocialPalette palette;
  final String label;
  final VoidCallback onTap;
  const _RecentChip({
    required this.palette,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 13,
              color: palette.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: palette.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final SocialPalette palette;
  final _Suggestion suggestion;
  final VoidCallback onTap;
  const _SuggestionTile({
    required this.palette,
    required this.suggestion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: suggestion.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  suggestion.icon,
                  color: suggestion.accent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  suggestion.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              DirectionalIcon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Skeleton list shown while results load
// ============================================================================
class _SkeletonList extends StatefulWidget {
  final SocialPalette palette;
  const _SkeletonList({required this.palette});

  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList>
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
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = 0.4 + _ctrl.value * 0.4;
          final base = widget.palette.subtleDivider.withValues(alpha: t);
          return Container(
            height: 76,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: widget.palette.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        height: 12,
                        width: 130,
                        decoration: BoxDecoration(
                          color: base,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 10,
                        width: 80,
                        decoration: BoxDecoration(
                          color: base,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 50,
                  height: 24,
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// Empty state (no results)
// ============================================================================
class _EmptyState extends StatelessWidget {
  final SocialPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SocialTokens.cyan.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: SocialTokens.cyan, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 17,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Error state
// ============================================================================
class _ErrorState extends StatelessWidget {
  final SocialPalette palette;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
  const _ErrorState({
    required this.palette,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: SocialTokens.down.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                color: SocialTokens.down,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                retryLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: SocialTokens.cyan,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                side: const BorderSide(color: SocialTokens.cyan, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
