import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/community_service.dart';
import '../../widgets/social/leaderboard_row.dart';
import 'expert_profile_screen.dart';
import 'mock_social_data.dart';
import 'social_tokens.dart';

/// Full ranked list of every visible expert on the platform.
///
/// Reached from the Social hub's "Top experts this week" section
/// header → "View all →" pill. The hub itself only renders the top
/// few; this screen surfaces the long tail with a search bar so once
/// the platform has 50+ experts the user can still find a specific
/// one without scrolling forever.
///
/// Data source: `GET /api/experts` — the same call the hub makes.
/// Backend already filters out empty stub experts (no subscribers,
/// no posts, no linked user), so an "All experts" page never shows
/// auto-created placeholders.
///
/// State: stateful so we can hold the fetched list + the search
/// query. Pull-to-refresh re-fetches; the search filter is purely
/// client-side (cheap, instant, no extra round-trips).
class AllExpertsScreen extends StatefulWidget {
  final bool isArabic;
  const AllExpertsScreen({super.key, required this.isArabic});

  @override
  State<AllExpertsScreen> createState() => _AllExpertsScreenState();
}

class _AllExpertsScreenState extends State<AllExpertsScreen> {
  final _searchCtl = TextEditingController();
  String _query = '';
  bool _loading = true;
  String? _error;
  List<Expert> _experts = const [];

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() {
      setState(() => _query = _searchCtl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  /// Fetches every expert and adapts each row into the existing
  /// `Expert` mock-shape so the [LeaderboardRow] widget stays untouched.
  /// Same adapter logic the hub uses — see `social_hub_screen.dart:
  /// _adaptExpert`. Duplicated here on purpose (tiny + decouples the
  /// two screens; if the hub's adapter changes for some hub-specific
  /// decoration, this page shouldn't inherit the change).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await CommunityService.listAllExperts();
    if (!mounted) return;
    if (res.experts == null) {
      setState(() {
        _loading = false;
        _error = res.error ?? 'allExperts.loadError'.tr;
      });
      return;
    }
    setState(() {
      _loading = false;
      _experts = res.experts!
          .map(
            (r) => Expert(
              id: r.id,
              name: r.name,
              handle: '@${r.id}',
              expertise: r.expertise,
              tier: ExpertTier.verified,
              subscriberCount: r.subscriberCount,
              sparkline: const <double>[],
              pctChange: 0,
              currentTicker: '',
              currentPrice: 0,
              currentChangePct: 0,
              shariahGrade: '',
              bio: r.bio,
              posts: const [],
              reels: const [],
              videos: const [],
            ),
          )
          .toList();
    });
  }

  /// Client-side search filter. Matches on name OR expertise so a
  /// user can find "Halal Tech" experts as easily as searching by
  /// "Sarah". Case-insensitive (`_query` is lowercased on input).
  List<Expert> get _filtered {
    if (_query.isEmpty) return _experts;
    return _experts.where((e) {
      final hay =
          '${e.name.toLowerCase()} ${e.expertise.toLowerCase()}';
      return hay.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final isArabic = widget.isArabic;
    final filtered = _filtered;

    final title = 'allExperts.title'.tr;
    final emptyText = 'allExperts.noMatching'.tr;
    final initialEmptyText = 'allExperts.noVerified'.tr;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          title,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search row — tiny enough to live above the list without
          // its own toggle. Persistent (always visible) because once
          // a screen routes here the user is implicitly in "find a
          // specific expert" mode.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _SearchBox(controller: _searchCtl, palette: palette),
          ),

          // Result count strip — gives the user a sense of scale
          // ("280 experts" vs "1 expert matching") at a glance.
          if (!_loading && _error == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text(
                    _query.isEmpty
                        ? 'allExperts.countExperts'
                            .trParams({'count': '${_experts.length}'})
                        : 'allExperts.countMatching'
                            .trParams({'count': '${filtered.length}'}),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: SocialTokens.violet,
              child: _loading && _experts.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorView(message: _error!, onRetry: _load, palette: palette)
                      : filtered.isEmpty
                          ? ListView(
                              // ListView (not Center) so pull-to-refresh
                              // still works on the empty state.
                              children: [
                                const SizedBox(height: 80),
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Text(
                                      _experts.isEmpty
                                          ? initialEmptyText
                                          : emptyText,
                                      style: TextStyle(
                                        color: palette.textMuted,
                                        fontSize: 14,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                24,
                              ),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final e = filtered[i];
                                // Rank reflects position in the FULL
                                // list, not the filtered slice — so
                                // searching for "Sarah" doesn't say
                                // she's rank 1 when she's really 5th
                                // overall. We look up her real index
                                // in `_experts`.
                                final rank = _experts.indexOf(e) + 1;
                                return LeaderboardRow(
                                  rank: rank,
                                  expert: e,
                                  isArabic: isArabic,
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ExpertProfileScreen(expert: e),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact search field with a leading magnifier + trailing clear
/// button. Themed to match the rest of the app — palette-aware
/// surface color, cyan focus ring.
class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final SocialPalette palette;
  const _SearchBox({required this.controller, required this.palette});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: TextStyle(color: palette.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        prefixIcon: Icon(
          Icons.search_rounded,
          color: palette.textMuted,
          size: 20,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: palette.textMuted,
                  size: 18,
                ),
                onPressed: controller.clear,
              ),
        hintText: 'allExperts.searchHint'.tr,
        hintStyle: TextStyle(color: palette.textMuted, fontSize: 13.5),
        filled: true,
        fillColor: palette.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: SocialTokens.cyan,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final SocialPalette palette;
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: SocialTokens.down,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text('common.retry'.tr),
              style: TextButton.styleFrom(
                foregroundColor: SocialTokens.cyan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
