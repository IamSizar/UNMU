import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/pulse_controller.dart';
import '../../localization/locale_format.dart';
import '../../models/pulse_item.dart';
import '../../services/pulse_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/dismiss_keyboard_on_tap.dart';
import '../../widgets/platform_adaptive/platform_segmented.dart';
import '../../widgets/pulse/pulse_cards.dart';
import '../../widgets/pulse/pulse_states.dart';
import '../../widgets/pulse/pulse_tokens.dart';
import '../../widgets/skeleton_loaders.dart';
import '../social/social_tokens.dart';
import 'pulse_item_screen.dart';

/// =============================================================================
/// PulseArchiveScreen — earlier Pulse, and the user's saved Pulse.
///
/// "All" lists published items newest day first, narrowed by a day strip (last
/// seven days) and a search box (titles and summaries, both languages). "Saved"
/// lists what the user bookmarked. Both page in as you scroll.
///
/// Every list has its four states: loading skeleton, content, designed empty
/// state, and a failure view with Retry. Typing in search debounces so the
/// server is not hit on every keystroke, and the keyboard dismisses on tap
/// outside and on drag.
/// =============================================================================
enum PulseArchiveView { all, saved }

class PulseArchiveScreen extends StatefulWidget {
  /// Which tab to open first.
  final PulseArchiveView initialView;

  const PulseArchiveScreen({
    super.key,
    this.initialView = PulseArchiveView.all,
  });

  @override
  State<PulseArchiveScreen> createState() => _PulseArchiveScreenState();
}

class _PulseArchiveScreenState extends State<PulseArchiveScreen> {
  static const _searchDelay = Duration(milliseconds: 400);

  late final PulseController _c = Get.find<PulseController>();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  late PulseArchiveView _view = widget.initialView;
  String? _day; // YYYY-MM-DD, or null for all days

  // "All" list state.
  final List<PulseItem> _items = [];
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;
  PulseFailure? _failure;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadView();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  // ── Loading ─────────────────────────────────────────────────────────

  void _loadView() {
    if (_view == PulseArchiveView.saved) {
      _c.loadSaved();
    } else {
      _loadFirstPage();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _loading = true;
      _failure = null;
      _loadMoreFailed = false;
    });
    final res = await _c.loadArchive(from: _day, to: _day, query: _search.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.ok) {
        _items
          ..clear()
          ..addAll(res.data!.items);
        _hasMore = res.data!.hasMore;
      } else {
        _failure = res.failure;
        _items.clear();
      }
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    final res = await _c.loadArchive(
      from: _day,
      to: _day,
      query: _search.text,
      offset: _items.length,
    );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.ok) {
        _items.addAll(res.data!.items);
        _hasMore = res.data!.hasMore;
      } else {
        _loadMoreFailed = true;
      }
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd =
        _scroll.position.pixels > _scroll.position.maxScrollExtent - 320;
    if (!nearEnd) return;
    if (_view == PulseArchiveView.saved) {
      _c.loadMoreSaved();
    } else {
      _loadMore();
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(_searchDelay, _loadFirstPage);
    setState(() {}); // shows / hides the clear button
  }

  void _setView(PulseArchiveView v) {
    if (v == _view) return;
    HapticUtils.lightTap();
    setState(() => _view = v);
    _loadView();
  }

  void _setDay(String? day) {
    HapticUtils.lightTap();
    setState(() => _day = day);
    _loadFirstPage();
  }

  void _open(PulseItem item) {
    HapticUtils.lightTap();
    Get.to(() => PulseItemScreen(itemId: item.id, preview: item));
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return PulseAuroraBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          iconTheme: IconThemeData(color: p.textPrimary),
          title: Text(
            'pulse.archive.title'.tr,
            style: TextStyle(
              color: p.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: PulseSpace.md),
              child: Center(
                child: PlatformSegmented<PulseArchiveView>(
                  options: {
                    PulseArchiveView.all: 'pulse.archive.all'.tr,
                    PulseArchiveView.saved: 'pulse.archive.saved'.tr,
                  },
                  value: _view,
                  onChanged: _setView,
                ),
              ),
            ),
          ],
        ),
        body: DismissKeyboardOnTap(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _view == PulseArchiveView.saved
                  ? _savedBody()
                  : _allBody(),
            ),
          ),
        ),
      ),
    );
  }

  // ── "All" ───────────────────────────────────────────────────────────

  Widget _allBody() {
    return Column(
      children: [
        _SearchField(
          controller: _search,
          onChanged: _onSearchChanged,
          onClear: () {
            _search.clear();
            _onSearchChanged('');
          },
        ),
        _DayStrip(selected: _day, onSelect: _setDay),
        const SizedBox(height: PulseSpace.sm),
        Expanded(child: _allList()),
      ],
    );
  }

  Widget _allList() {
    if (_loading) return const _ListSkeleton();
    if (_failure != null) {
      return _Scrollable(
        scroll: _scroll,
        child: PulseStatusView.failure(
          context,
          failure: _failure!,
          onRetry: _loadFirstPage,
        ),
      );
    }
    if (_items.isEmpty) {
      return _Scrollable(
        scroll: _scroll,
        child: PulseStatusView(
          icon: PulseIcons.search(context),
          title: 'pulse.archive.emptyTitle'.tr,
          body: 'pulse.archive.emptyBody'.tr,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: _ItemList(
        scroll: _scroll,
        items: _items,
        onOpen: _open,
        footer: _footer(),
      ),
    );
  }

  Widget? _footer() {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(PulseSpace.lg),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (_loadMoreFailed) {
      return Padding(
        padding: const EdgeInsets.all(PulseSpace.md),
        child: TextButton(
          onPressed: _loadMore,
          child: Text('pulse.archive.loadMoreFailed'.tr),
        ),
      );
    }
    return null;
  }

  // ── "Saved" ─────────────────────────────────────────────────────────

  Widget _savedBody() {
    return Obx(() {
      final items = _c.savedItems.toList();
      if (_c.savedLoading.value && items.isEmpty) return const _ListSkeleton();
      final failure = _c.savedFailure.value;
      if (failure != null && items.isEmpty) {
        return _Scrollable(
          scroll: _scroll,
          child: PulseStatusView.failure(
            context,
            failure: failure,
            onRetry: _c.loadSaved,
          ),
        );
      }
      if (items.isEmpty) {
        return _Scrollable(
          scroll: _scroll,
          child: PulseStatusView(
            icon: PulseIcons.bookmark(context, filled: false),
            title: 'pulse.saved.emptyTitle'.tr,
            body: 'pulse.saved.emptyBody'.tr,
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: _c.loadSaved,
        child: _ItemList(
          scroll: _scroll,
          items: items,
          onOpen: _open,
          grouped: false,
          footer: _c.savedLoading.value
              ? const Padding(
                  padding: EdgeInsets.all(PulseSpace.lg),
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              : null,
        ),
      );
    });
  }
}

// ── Pieces ─────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PulseSpace.lg,
        PulseSpace.sm,
        PulseSpace.lg,
        PulseSpace.sm,
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        keyboardType: TextInputType.text,
        maxLength: 100, // matches the server's search limit
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                null,
        style: TextStyle(color: p.textPrimary),
        decoration: InputDecoration(
          hintText: 'pulse.archive.search'.tr,
          hintStyle: TextStyle(color: p.textMuted),
          prefixIcon: Icon(PulseIcons.search(context), color: p.textMuted),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, color: p.textMuted),
                  onPressed: onClear,
                ),
          filled: true,
          fillColor: p.isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.6),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// "All days" plus the last seven days as tappable chips.
class _DayStrip extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onSelect;

  const _DayStrip({required this.selected, required this.onSelect});

  /// Today in the Pulse time zone (UTC+3, no daylight saving).
  static DateTime _pulseToday() {
    final t = DateTime.now().toUtc().add(const Duration(hours: 3));
    return DateTime.utc(t.year, t.month, t.day);
  }

  static String _key(DateTime d) => DateFormat('yyyy-MM-dd', 'en').format(d);

  String _weekday(DateTime d) {
    try {
      return DateFormat.E(pulseIsArabic() ? 'ar' : 'en').format(d);
    } catch (_) {
      return DateFormat.E('en').format(d); // locale data not loaded (tests)
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final today = _pulseToday();
    final days = [
      for (var i = 0; i < 7; i++) today.subtract(Duration(days: i)),
    ];

    Widget chip({
      required String top,
      required String bottom,
      required bool on,
      required VoidCallback tap,
    }) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Semantics(
          button: true,
          selected: on,
          label: '$top $bottom',
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: tap,
            child: Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: on
                    ? PulseColors.tealDeep
                    : (p.isDark
                          ? Colors.white.withValues(alpha: 0.07)
                          : Colors.white.withValues(alpha: 0.55)),
                border: Border.all(color: on ? Colors.transparent : p.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    top,
                    style: TextStyle(
                      color: on
                          ? Colors.white.withValues(alpha: 0.9)
                          : p.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bottom,
                    style: TextStyle(
                      color: on ? Colors.white : p.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      // Tall enough for Arabic's taller line height and for large system text
      // sizes; a fixed 64 overflowed in both.
      height: 24 + MediaQuery.textScalerOf(context).scale(60),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PulseSpace.lg),
        children: [
          chip(
            top: '',
            bottom: 'pulse.archive.all'.tr,
            on: selected == null,
            tap: () => onSelect(null),
          ),
          for (final d in days)
            chip(
              top: _weekday(d),
              bottom: '${d.day}',
              on: selected == _key(d),
              tap: () => onSelect(_key(d)),
            ),
        ],
      ),
    );
  }
}

/// A scrollable wrapper so pull-to-refresh and short content both work.
class _Scrollable extends StatelessWidget {
  final ScrollController scroll;
  final Widget child;

  const _Scrollable({required this.scroll, required this.child});

  @override
  Widget build(BuildContext context) => ListView(
    controller: scroll,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.all(PulseSpace.lg),
    children: [child],
  );
}

/// The list of item rows, optionally grouped under day headings.
class _ItemList extends StatelessWidget {
  final ScrollController scroll;
  final List<PulseItem> items;
  final ValueChanged<PulseItem> onOpen;
  final bool grouped;
  final Widget? footer;

  const _ItemList({
    required this.scroll,
    required this.items,
    required this.onOpen,
    this.grouped = true,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final rows = <Widget>[];
    String? lastDate;
    for (final it in items) {
      if (grouped && it.date != lastDate) {
        lastDate = it.date;
        final parsed = DateTime.tryParse(it.date);
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              4,
              PulseSpace.md,
              4,
              PulseSpace.sm,
            ),
            child: Text(
              parsed == null ? it.date : LocaleFormat.date(parsed),
              style: TextStyle(
                color: p.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: pulseIsArabic() ? 0 : 0.8,
              ),
            ),
          ),
        );
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: PulseSpace.sm),
          child: _ArchiveRow(item: it, onTap: () => onOpen(it)),
        ),
      );
    }
    if (footer != null) rows.add(footer!);

    return ListView(
      controller: scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        PulseSpace.lg,
        0,
        PulseSpace.lg,
        PulseSpace.xxl,
      ),
      children: rows,
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  final PulseItem item;
  final VoidCallback onTap;

  const _ArchiveRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = SocialTheme.of(context);
    final arabic = pulseIsArabic();
    final type =
        (item.isAnalysis ? 'pulse.badge.analysis' : 'pulse.badge.confirmed').tr;
    final slot = 'pulse.slot.${item.slot.name}'.tr;
    final time = item.publishedAt ?? item.verifiedAt;
    final meta = [slot, type, if (time != null) pulseTime(time)].join(' · ');

    return Semantics(
      button: true,
      label: '${item.title(arabic)}. $meta',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(kPulseRadius),
          onTap: onTap,
          child: PulseSurfaceBox(
            surface: PulseSurface.glass,
            padding: const EdgeInsets.all(PulseSpace.md + 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: PulseColors.teal.withValues(
                      alpha: p.isDark ? 0.2 : 0.13,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    PulseIcons.slot(context, item.slot),
                    size: 19,
                    color: p.isDark
                        ? PulseColors.tealBright
                        : PulseColors.tealInk,
                  ),
                ),
                const SizedBox(width: PulseSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title(arabic),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontSize: 14.5,
                          height: arabic ? 1.5 : 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        style: TextStyle(color: p.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (item.isCorrected || item.isUpdated)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: PulseMarkerBadge(item: item),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Shimmer(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(PulseSpace.lg),
          children: [
            for (var i = 0; i < 5; i++)
              const Padding(
                padding: EdgeInsets.only(bottom: PulseSpace.sm),
                child: PulseSurfaceBox(
                  surface: PulseSurface.glass,
                  child: Row(
                    children: [
                      SkeletonBox(width: 38, height: 38, radius: 14),
                      SizedBox(width: PulseSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(height: 14),
                            SizedBox(height: 8),
                            SkeletonBox(width: 150, height: 11),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
