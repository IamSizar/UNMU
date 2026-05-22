import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/notification_prefs_service.dart';
import '../../utils/haptic_utils.dart';
import '../social/social_tokens.dart';

/// Settings sub-screen — per-user notification toggles.
///
/// Master switch: `Push notifications` is the global kill-switch the
/// backend's admin broadcast respects today (mig 0041 + push_tokens
/// JOIN). The per-category toggles below it (Likes, Comments, etc.)
/// persist server-side; the targeted senders that honor them are added
/// incrementally in later phases.
class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  /// Local state that the toggles flip optimistically. Initial state
  /// shows the documented defaults until the GET completes so the
  /// screen never renders a blank/spinner-only frame.
  NotificationPrefs _prefs = NotificationPrefs.initial();
  bool _loading = true;
  /// We track which switch is currently mid-save so the user sees a
  /// tiny spinner next to it; the rest of the toggles stay clickable.
  String? _saving;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await NotificationPrefsService.get();
    if (!mounted) return;
    setState(() {
      _prefs = res.prefs;
      _loading = false;
      _error = res.error;
    });
  }

  /// Toggle helper — flips one boolean optimistically, fires the
  /// PATCH, and reconciles with the server's authoritative response.
  /// On failure we revert and show a snackbar.
  Future<void> _toggle({
    required String key,
    required bool current,
    required NotificationPrefs Function(NotificationPrefs) apply,
    required ({bool? pushEnabled, bool? emailEnabled, bool? likesEnabled,
              bool? commentsEnabled, bool? subscriptionsEnabled,
              bool? communitiesEnabled, bool? marketingEnabled})
        Function(bool value) buildPatch,
  }) async {
    HapticUtils.selection();
    final newValue = !current;
    final previous = _prefs;
    setState(() {
      _prefs = apply(_prefs);
      _saving = key;
    });

    final patch = buildPatch(newValue);
    final res = await NotificationPrefsService.update(
      pushEnabled: patch.pushEnabled,
      emailEnabled: patch.emailEnabled,
      likesEnabled: patch.likesEnabled,
      commentsEnabled: patch.commentsEnabled,
      subscriptionsEnabled: patch.subscriptionsEnabled,
      communitiesEnabled: patch.communitiesEnabled,
      marketingEnabled: patch.marketingEnabled,
    );
    if (!mounted) return;
    if (res.error != null) {
      // Revert to the pre-toggle state.
      setState(() {
        _prefs = previous;
        _saving = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error!)),
      );
      return;
    }
    setState(() {
      if (res.prefs != null) _prefs = res.prefs!;
      _saving = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final pushMaster = _prefs.pushEnabled;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text(
          'notifPrefs.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: IconThemeData(color: palette.textPrimary),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    'notifPrefs.channels'.tr,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Card(
                    palette: palette,
                    children: [
                      _PrefRow(
                        palette: palette,
                        icon: Icons.notifications_active_rounded,
                        accent: SocialTokens.cyan,
                        title: 'notifPrefs.pushTitle'.tr,
                        subtitle: 'notifPrefs.pushSubtitle'.tr,
                        value: _prefs.pushEnabled,
                        loading: _saving == 'push',
                        onChanged: () => _toggle(
                          key: 'push',
                          current: _prefs.pushEnabled,
                          apply: (p) => p.copyWith(pushEnabled: !p.pushEnabled),
                          buildPatch: (v) => (
                            pushEnabled: v,
                            emailEnabled: null,
                            likesEnabled: null,
                            commentsEnabled: null,
                            subscriptionsEnabled: null,
                            communitiesEnabled: null,
                            marketingEnabled: null,
                          ),
                        ),
                      ),
                      _Divider(palette: palette),
                      _PrefRow(
                        palette: palette,
                        icon: Icons.mail_outline_rounded,
                        accent: SocialTokens.gold,
                        title: 'notifPrefs.emailTitle'.tr,
                        subtitle: 'notifPrefs.emailSubtitle'.tr,
                        value: _prefs.emailEnabled,
                        loading: _saving == 'email',
                        onChanged: () => _toggle(
                          key: 'email',
                          current: _prefs.emailEnabled,
                          apply: (p) =>
                              p.copyWith(emailEnabled: !p.emailEnabled),
                          buildPatch: (v) => (
                            pushEnabled: null,
                            emailEnabled: v,
                            likesEnabled: null,
                            commentsEnabled: null,
                            subscriptionsEnabled: null,
                            communitiesEnabled: null,
                            marketingEnabled: null,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'notifPrefs.categories'.tr,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'notifPrefs.categoriesNote'.tr,
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: pushMaster ? 1.0 : 0.45,
                    child: IgnorePointer(
                      ignoring: !pushMaster,
                      child: _Card(
                        palette: palette,
                        children: [
                          _PrefRow(
                            palette: palette,
                            icon: Icons.favorite_outline_rounded,
                            accent: const Color(0xFFEC4899),
                            title: 'notifPrefs.likesTitle'.tr,
                            subtitle: 'notifPrefs.likesSubtitle'.tr,
                            value: _prefs.likesEnabled,
                            loading: _saving == 'likes',
                            onChanged: () => _toggle(
                              key: 'likes',
                              current: _prefs.likesEnabled,
                              apply: (p) =>
                                  p.copyWith(likesEnabled: !p.likesEnabled),
                              buildPatch: (v) => (
                                pushEnabled: null,
                                emailEnabled: null,
                                likesEnabled: v,
                                commentsEnabled: null,
                                subscriptionsEnabled: null,
                                communitiesEnabled: null,
                                marketingEnabled: null,
                              ),
                            ),
                          ),
                          _Divider(palette: palette),
                          _PrefRow(
                            palette: palette,
                            icon: Icons.chat_bubble_outline_rounded,
                            accent: SocialTokens.cyan,
                            title: 'notifPrefs.commentsTitle'.tr,
                            subtitle: 'notifPrefs.commentsSubtitle'.tr,
                            value: _prefs.commentsEnabled,
                            loading: _saving == 'comments',
                            onChanged: () => _toggle(
                              key: 'comments',
                              current: _prefs.commentsEnabled,
                              apply: (p) => p.copyWith(
                                  commentsEnabled: !p.commentsEnabled),
                              buildPatch: (v) => (
                                pushEnabled: null,
                                emailEnabled: null,
                                likesEnabled: null,
                                commentsEnabled: v,
                                subscriptionsEnabled: null,
                                communitiesEnabled: null,
                                marketingEnabled: null,
                              ),
                            ),
                          ),
                          _Divider(palette: palette),
                          _PrefRow(
                            palette: palette,
                            icon: Icons.workspace_premium_rounded,
                            accent: SocialTokens.gold,
                            title: 'notifPrefs.subscriptionsTitle'.tr,
                            subtitle: 'notifPrefs.subscriptionsSubtitle'.tr,
                            value: _prefs.subscriptionsEnabled,
                            loading: _saving == 'subs',
                            onChanged: () => _toggle(
                              key: 'subs',
                              current: _prefs.subscriptionsEnabled,
                              apply: (p) => p.copyWith(
                                  subscriptionsEnabled:
                                      !p.subscriptionsEnabled),
                              buildPatch: (v) => (
                                pushEnabled: null,
                                emailEnabled: null,
                                likesEnabled: null,
                                commentsEnabled: null,
                                subscriptionsEnabled: v,
                                communitiesEnabled: null,
                                marketingEnabled: null,
                              ),
                            ),
                          ),
                          _Divider(palette: palette),
                          _PrefRow(
                            palette: palette,
                            icon: Icons.groups_2_rounded,
                            accent: const Color(0xFF8B5CF6),
                            title: 'notifPrefs.communitiesTitle'.tr,
                            subtitle: 'notifPrefs.communitiesSubtitle'.tr,
                            value: _prefs.communitiesEnabled,
                            loading: _saving == 'communities',
                            onChanged: () => _toggle(
                              key: 'communities',
                              current: _prefs.communitiesEnabled,
                              apply: (p) => p.copyWith(
                                  communitiesEnabled:
                                      !p.communitiesEnabled),
                              buildPatch: (v) => (
                                pushEnabled: null,
                                emailEnabled: null,
                                likesEnabled: null,
                                commentsEnabled: null,
                                subscriptionsEnabled: null,
                                communitiesEnabled: v,
                                marketingEnabled: null,
                              ),
                            ),
                          ),
                          _Divider(palette: palette),
                          _PrefRow(
                            palette: palette,
                            icon: Icons.local_offer_outlined,
                            accent: SocialTokens.up,
                            title: 'notifPrefs.promotionsTitle'.tr,
                            subtitle: 'notifPrefs.promotionsSubtitle'.tr,
                            value: _prefs.marketingEnabled,
                            loading: _saving == 'marketing',
                            onChanged: () => _toggle(
                              key: 'marketing',
                              current: _prefs.marketingEnabled,
                              apply: (p) => p.copyWith(
                                  marketingEnabled:
                                      !p.marketingEnabled),
                              buildPatch: (v) => (
                                pushEnabled: null,
                                emailEnabled: null,
                                likesEnabled: null,
                                commentsEnabled: null,
                                subscriptionsEnabled: null,
                                communitiesEnabled: null,
                                marketingEnabled: v,
                              ),
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

// ───────────────────────────────────────────────────────────────────────
// Small layout primitives — kept private to this screen so they can
// evolve without touching the rest of the profile area's styling.
// ───────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final SocialPalette palette;
  final List<Widget> children;
  const _Card({required this.palette, required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  final SocialPalette palette;
  const _Divider({required this.palette});
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: palette.subtleDivider);
}

class _PrefRow extends StatelessWidget {
  final SocialPalette palette;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final bool value;
  final bool loading;
  final VoidCallback onChanged;

  const _PrefRow({
    required this.palette,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.loading,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: loading ? null : onChanged,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch.adaptive(
                value: value,
                activeThumbColor: SocialTokens.cyan,
                onChanged: (_) => onChanged(),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SocialTokens.down.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SocialTokens.down.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: SocialTokens.down, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: SocialTokens.down, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
