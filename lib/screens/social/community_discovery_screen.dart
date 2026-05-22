import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../config/api_config.dart';
import '../../services/community_service.dart';
import '../../utils/price_format.dart';
import 'community_preview_screen.dart';
import 'social_tokens.dart';

/// Search-and-browse for communities (item 2.15).
///
/// Two filter axes — text query + category chips — combined with a
/// server-side AND. Tag filter is reachable too via [initialTag], used
/// when the user taps a `#tag` chip on a community card to drill in.
///
/// The screen renders [CommunityMeta] rows (cover image, name,
/// member count, lock icon when private) and links to the existing
/// community detail screen via the `id` field. The detail screen
/// receives only the id; it fetches its own metadata.
class CommunityDiscoveryScreen extends StatefulWidget {
  /// Optional pre-filter — if non-null, the screen mounts with this
  /// tag selected. Used by the "tag chip" tap target on community
  /// cards elsewhere in the app.
  final String? initialTag;

  const CommunityDiscoveryScreen({super.key, this.initialTag});

  @override
  State<CommunityDiscoveryScreen> createState() =>
      _CommunityDiscoveryScreenState();
}

class _CommunityDiscoveryScreenState extends State<CommunityDiscoveryScreen> {
  final _queryCtl = TextEditingController();
  String _category = '';
  String? _tag;
  Timer? _debounce;

  List<String> _categories = const [];
  List<CommunityMeta> _rows = const [];
  /// Step-23 follow-up — set of community ids the viewer is already
  /// in. Drives the "Joined" pill on each result card so the user
  /// can tell at a glance which ones they're already in.
  Set<String> _joinedIds = const <String>{};
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tag = widget.initialTag;
    _bootstrap();
  }

  @override
  void dispose() {
    _queryCtl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([
      CommunityService.listCategories(),
      CommunityService.myCommunityIds(),
    ]);
    if (!mounted) return;
    final cats = results[0] as ({List<String>? categories, String? error});
    final mine = results[1] as ({Set<String>? ids, String? error});
    setState(() {
      _categories = cats.categories ?? const [];
      _joinedIds = mine.ids ?? const <String>{};
    });
    await _runSearch();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), _runSearch);
  }

  Future<void> _runSearch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CommunityService.search(
      query: _queryCtl.text,
      category: _category.isEmpty ? null : _category,
      tag: _tag,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = res.rows ?? const [];
      _error = res.error;
    });
  }

  String _absoluteCover(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = ApiConfig.baseUrl.replaceAll('/api', '');
    return '$base$url';
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'communityDiscovery.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchBar(palette),
          if (_tag != null) _activeTagBanner(palette),
          _categoryChips(palette),
          const SizedBox(height: 6),
          Expanded(child: _resultsList(palette)),
        ],
      ),
    );
  }

  Widget _searchBar(SocialPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: TextField(
        controller: _queryCtl,
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _runSearch(),
        style: TextStyle(color: palette.textPrimary, fontSize: 14.5),
        decoration: InputDecoration(
          hintText: 'communityDiscovery.searchHint'.tr,
          hintStyle: TextStyle(
            color: palette.textMuted.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(Icons.search_rounded, color: palette.textMuted),
          filled: true,
          fillColor: palette.surfaceElevated,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: SocialTokens.cyan, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _activeTagBanner(SocialPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: SocialTokens.cyan.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: SocialTokens.cyan.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.tag_rounded,
                color: SocialTokens.cyan, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'communityDiscovery.filteringByTag'
                    .trParams({'tag': _tag ?? ''}),
                style: const TextStyle(
                  color: SocialTokens.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() => _tag = null);
                _runSearch();
              },
              child: const Icon(Icons.close_rounded,
                  color: SocialTokens.cyan, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryChips(SocialPalette palette) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _catChip(palette, '', 'communityDiscovery.all'.tr),
          for (final c in _categories)
            _catChip(palette, c, _titleCase(c)),
        ],
      ),
    );
  }

  Widget _catChip(SocialPalette palette, String value, String label) {
    final selected = _category == value;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _category = value);
          _runSearch();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? SocialTokens.cyan.withValues(alpha: 0.18)
                : palette.surfaceElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? SocialTokens.cyan : palette.border,
              width: selected ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? SocialTokens.cyan : palette.textPrimary,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultsList(SocialPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SocialTokens.down),
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.travel_explore_rounded,
                  size: 56, color: palette.textMuted),
              const SizedBox(height: 12),
              Text(
                'communityDiscovery.empty'.tr,
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _CommunityResultCard(
        row: _rows[i],
        isJoined: _joinedIds.contains(_rows[i].id),
        coverResolver: _absoluteCover,
        onTap: () async {
          // Step-23 — open the pre-join preview screen. The preview
          // handles free/paid join itself; on a successful join we
          // pop back to Discover with the row so the social hub can
          // refresh the pinned list.
          final joined = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) =>
                  CommunityPreviewScreen(communityId: _rows[i].id),
            ),
          );
          if (!mounted) return;
          if (joined == true) {
            Navigator.of(context).pop<CommunityMeta>(_rows[i]);
          } else {
            // Refresh joined ids so the pill flips immediately if the
            // user joined free / cancelled / etc.
            final mine = await CommunityService.myCommunityIds();
            if (mounted && mine.ids != null) {
              setState(() => _joinedIds = mine.ids!);
            }
          }
        },
        onTagTap: (tag) {
          setState(() => _tag = tag);
          _runSearch();
        },
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _CommunityResultCard extends StatelessWidget {
  final CommunityMeta row;
  /// Step-23 — viewer is already a member of this row. Drives the
  /// "Joined" pill rendered on the cover banner.
  final bool isJoined;
  final String Function(String) coverResolver;
  final VoidCallback onTap;
  final ValueChanged<String> onTagTap;
  const _CommunityResultCard({
    required this.row,
    required this.coverResolver,
    required this.onTap,
    required this.onTagTap,
    this.isJoined = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final accent = SocialTokens.regionColor(row.regionCode);
    final coverAbs = coverResolver(row.coverUrl);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: palette.surfaceElevated,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner — cover image when present, else gradient by region.
            Container(
              height: 96,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.22),
                    accent.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                image: coverAbs.isEmpty
                    ? null
                    : DecorationImage(
                        image: NetworkImage(coverAbs),
                        fit: BoxFit.cover,
                      ),
              ),
              alignment: Alignment.bottomLeft,
              child: Stack(
                children: [
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Row(
                      children: [
                        if (!row.isPublic)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.lock_outline_rounded,
                                    color: SocialTokens.gold, size: 12),
                                const SizedBox(width: 4),
                                Text('communityDiscovery.private'.tr,
                                    style: const TextStyle(
                                      color: SocialTokens.gold,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                    )),
                              ],
                            ),
                          ),
                        if (row.isPublic)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.public_rounded,
                                    color: SocialTokens.up, size: 12),
                                const SizedBox(width: 4),
                                Text('communityDiscovery.public'.tr,
                                    style: const TextStyle(
                                      color: SocialTokens.up,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                    )),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Step-23 — top-right corner: "Joined" pill takes
                  // priority over the price chip when the viewer is
                  // already a member; otherwise the price chip shows
                  // for paid communities. Free + non-member shows
                  // nothing here (the cover stays clean).
                  if (isJoined)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: SocialTokens.up.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: SocialTokens.up, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              'communityDiscovery.joined'.tr,
                              style: const TextStyle(
                                color: SocialTokens.up,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (row.isPaid)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: SocialTokens.gold.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.workspace_premium_rounded,
                                color: SocialTokens.gold, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              _shortPrice(row),
                              style: const TextStyle(
                                color: SocialTokens.gold,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (row.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _titleCase(row.category),
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (row.tagline.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      row.tagline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.people_alt_rounded,
                          size: 13, color: palette.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        '${row.memberCount}',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (row.regionCode.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            row.regionCode,
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (row.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: row.tags
                          .take(5)
                          .map((t) => GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onTagTap(t);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: palette.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: palette.border),
                                  ),
                                  child: Text(
                                    '#$t',
                                    style: TextStyle(
                                      color: palette.textMuted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Compact price string for the chip — picks the cheaper of the
  /// two plans (per-month basis) so "$5/mo" reads more reassuring
  /// than "$50/yr" when both are configured.
  ///
  /// Uses [PriceFormat.formatPrice] so thousand separators + zero-
  /// decimal currency handling (IQD, JPY, …) stay consistent with the
  /// pricing card.
  String _shortPrice(CommunityMeta r) {
    if (r.joinPriceMonthlyCents > 0) {
      return '${PriceFormat.formatPrice(r.joinPriceMonthlyCents, r.priceCurrency)}${'communityDiscovery.perMonthSuffix'.tr}';
    }
    if (r.joinPriceYearlyCents > 0) {
      return '${PriceFormat.formatPrice(r.joinPriceYearlyCents, r.priceCurrency)}${'communityDiscovery.perYearSuffix'.tr}';
    }
    return '';
  }
}
