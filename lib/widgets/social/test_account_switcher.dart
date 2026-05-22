import 'package:flutter/material.dart';
import '../directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../models/user.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/dev_service.dart';

/// Bottom-sheet picker for switching accounts.
///
/// Pre-migration this was a static list of 14 hardcoded preset accounts.
/// Now it fetches `GET /api/dev/users` on open so EVERY account in the
/// DB (including ones registered today via the new email flow) shows up.
/// Tapping a row calls `POST /api/dev/impersonate` which issues a JWT
/// without asking for a password — instant session swap.
///
/// Both backend routes are gated by `APP_ENV != "production"`, so the
/// switcher silently degrades to "no remote list" in real deploys; the
/// hardcoded preset list is shown as a fallback.
///
/// UI:
///   • Drag handle + header
///   • Search bar (filters by email / name)
///   • Scrollable list of [_DevAccountTile]s, newest first
///   • Loading spinner while fetching; error banner with Retry on failure
class TestAccountSwitcherSheet extends StatefulWidget {
  const TestAccountSwitcherSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const TestAccountSwitcherSheet(),
    );
  }

  @override
  State<TestAccountSwitcherSheet> createState() =>
      _TestAccountSwitcherSheetState();
}

class _TestAccountSwitcherSheetState extends State<TestAccountSwitcherSheet> {
  final _searchCtl = TextEditingController();
  String _query = '';

  bool _loading = true;
  String? _error;
  List<DevUser>? _users;
  // Account currently being swapped (email) — used to render a spinner on
  // that row and disable other taps until the impersonate call finishes.
  String? _switching;

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final list = await DevService.listUsers();
    if (!mounted) return;
    if (list == null) {
      setState(() {
        _loading = false;
        _error = 'testAccounts.fallbackError'.tr;
        _users = _presetFallback();
      });
      return;
    }
    setState(() {
      _loading = false;
      _users = list;
    });
  }

  /// If the backend is unreachable, fall back to the hardcoded preset list
  /// so dev still works offline.
  List<DevUser> _presetFallback() {
    return testAccountPresets
        .map((p) => DevUser(
              id: AuthController.testAccounts[p.email]?.id ?? 0,
              email: p.email,
              name: p.name,
              role: _roleToWire(p.role),
              expertId: p.expertId,
              subscriptionTier: p.tier,
              emailVerified: true,
              createdAt: '',
            ))
        .toList(growable: false);
  }

  String _roleToWire(dynamic role) {
    // UserRole enum → backend string. Defensive: only USER / EXPERT / ADMIN.
    final s = role.toString().split('.').last.toLowerCase();
    if (s == 'expert') return 'EXPERT';
    if (s == 'admin') return 'ADMIN';
    return 'USER';
  }

  List<DevUser> get _filtered {
    final all = _users ?? const <DevUser>[];
    if (_query.isEmpty) return all;
    return all
        .where((u) =>
            u.email.toLowerCase().contains(_query) ||
            (u.name?.toLowerCase().contains(_query) ?? false))
        .toList(growable: false);
  }

  Future<void> _switchTo(DevUser u) async {
    if (_switching != null) return;
    HapticFeedback.selectionClick();
    setState(() => _switching = u.email);
    final ok = await Get.find<AuthController>().switchToAnyAccount(u.email);
    if (!mounted) return;
    setState(() => _switching = null);
    if (ok) {
      if (context.mounted) Navigator.of(context).pop();
    } else {
      Get.snackbar(
        'testAccounts.switchFailedTitle'.tr,
        'testAccounts.switchFailedBody'.tr,
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final auth = Get.find<AuthController>();
    final activeEmail = auth.user?.email.toLowerCase();
    final maxH = MediaQuery.of(context).size.height * 0.85;
    final filtered = _filtered;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: palette.border, width: 1),
          left: BorderSide(color: palette.border, width: 1),
          right: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              // Header row
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SocialTokens.cyan.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: SocialTokens.cyan.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: SocialTokens.cyan,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'testAccounts.switchAccount'.tr,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _users == null
                              ? 'common.loading'.tr
                              : '${_users!.length} '
                                  '${_users!.length == 1 ? 'testAccounts.accountOne'.tr : 'testAccounts.accountMany'.tr} '
                                  '${'testAccounts.countSuffix'.tr}',
                          maxLines: 2,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Refresh
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: Icon(
                      Icons.refresh_rounded,
                      color: palette.textMuted,
                      size: 20,
                    ),
                    tooltip: 'common.refresh'.tr,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Search
              Container(
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border, width: 1),
                ),
                child: TextField(
                  controller: _searchCtl,
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: palette.textMuted,
                      size: 18,
                    ),
                    hintText: 'testAccounts.searchHint'.tr,
                    hintStyle: TextStyle(
                      color: palette.textMuted,
                      fontSize: 13,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SocialTokens.gold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: SocialTokens.gold.withValues(alpha: 0.40),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: SocialTokens.gold,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: palette.textSecondary,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // List
              Flexible(
                child: _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: SocialTokens.cyan,
                            strokeWidth: 2.2,
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Center(
                              child: Text(
                                _query.isEmpty
                                    ? 'testAccounts.noAccounts'.tr
                                    : 'testAccounts.noMatches'
                                        .trParams({'query': _query}),
                                style: TextStyle(color: palette.textMuted),
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(top: 4, bottom: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final u = filtered[i];
                              final isActive = activeEmail == u.email.toLowerCase();
                              final isSwitching = _switching == u.email;
                              return _DevAccountTile(
                                palette: palette,
                                user: u,
                                isActive: isActive,
                                isSwitching: isSwitching,
                                onTap: () => _switchTo(u),
                              );
                            },
                          ),
              ),
              // Danger zone — admin only. The backend endpoint is dev-mode
              // gated AND requires a confirmation header, so even if a
              // non-admin somehow reached this code path the wipe would
              // still go through. Restricting it in the UI keeps the
              // panic-button out of casual sight.
              if (auth.user?.role == UserRole.admin) ...[
                const SizedBox(height: 14),
                _DangerZone(
                  palette: palette,
                  totalAccounts: _users?.length ?? 0,
                  onReset: _confirmAndReset,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the two-step confirm dialog and, if the user types RESET and
  /// taps the destructive button, calls `/api/dev/reset`. On success we
  /// reload the list (will show just admin) and surface a snackbar with
  /// the summary.
  Future<void> _confirmAndReset() async {
    final palette = SocialTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ResetConfirmDialog(
        palette: palette,
        totalAccounts: _users?.length ?? 0,
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    // Show a brief "wiping…" snackbar before the call so the user knows
    // the tap registered. Resets can take a beat if there are lots of
    // post_events / audit_logs rows.
    Get.snackbar(
      'testAccounts.resettingTitle'.tr,
      'testAccounts.resettingBody'.tr,
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 2),
    );

    final summary = await DevService.resetAll();
    if (!mounted) return;

    if (summary == null) {
      Get.snackbar(
        'testAccounts.resetFailedTitle'.tr,
        'testAccounts.resetFailedBody'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: SocialTokens.down.withValues(alpha: 0.10),
      );
      return;
    }

    final otherRows = summary.totalRows -
        summary.users -
        summary.communities -
        summary.posts -
        summary.experts;
    Get.snackbar(
      'testAccounts.resetDoneTitle'.tr,
      'testAccounts.resetDoneBody'.trParams({
        'users': '${summary.users}',
        'communities': '${summary.communities}',
        'posts': '${summary.posts}',
        'experts': '${summary.experts}',
        'other': '$otherRows',
      }),
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 5),
    );

    // Refresh the list — should now only show admin.
    await _load();
  }
}

class _DevAccountTile extends StatelessWidget {
  final SocialPalette palette;
  final DevUser user;
  final bool isActive;
  final bool isSwitching;
  final VoidCallback onTap;

  const _DevAccountTile({
    required this.palette,
    required this.user,
    required this.isActive,
    required this.isSwitching,
    required this.onTap,
  });

  Color get _roleColor {
    switch (user.role) {
      case 'EXPERT':
        return SocialTokens.cyan;
      case 'ADMIN':
        return SocialTokens.gold;
      default:
        return SocialTokens.up;
    }
  }

  String _initials() {
    final source = (user.name?.trim().isNotEmpty == true)
        ? user.name!.trim()
        : user.email;
    final parts = source.split(RegExp(r'\s+|@|\.'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1 || parts[1].isEmpty) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final accent = _roleColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isSwitching ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: isActive
                ? accent.withValues(alpha: 0.10)
                : palette.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? accent.withValues(alpha: 0.55)
                  : palette.border,
              width: isActive ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [accent, accent.withValues(alpha: 0.55)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Text(
                  _initials(),
                  style: const TextStyle(
                    color: Color(0xFF0A1628),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Identity
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Chip(label: user.role, color: accent),
                        if (!user.emailVerified) ...[
                          const SizedBox(width: 4),
                          _Chip(
                            label: 'testAccounts.unverified'.tr,
                            color: SocialTokens.down,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Trailing — spinner / check / chevron
              if (isSwitching)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SocialTokens.cyan,
                  ),
                )
              else if (isActive)
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SocialTokens.up.withValues(alpha: 0.18),
                    border: Border.all(
                      color: SocialTokens.up.withValues(alpha: 0.55),
                    ),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: SocialTokens.up,
                    size: 14,
                  ),
                )
              else
                DirectionalIcon(
                  Icons.chevron_right_rounded,
                  color: palette.textMuted,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 9,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

// ============================================================================
// Danger zone — admin-only red panel with the Reset DB button. The actual
// destructive action is fenced behind the [_ResetConfirmDialog] below.
// ============================================================================
class _DangerZone extends StatelessWidget {
  final SocialPalette palette;
  final int totalAccounts;
  final VoidCallback onReset;
  const _DangerZone({
    required this.palette,
    required this.totalAccounts,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final red = SocialTokens.down;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: red.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: red, size: 18),
              const SizedBox(width: 6),
              Text(
                'testAccounts.dangerZone'.tr,
                style: TextStyle(
                  color: red,
                  fontWeight: FontWeight.w900,
                  fontSize: 10.5,
                  letterSpacing: 0.9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'testAccounts.dangerDesc'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: red.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onReset,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: red.withValues(alpha: 0.55)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_forever_rounded, color: red, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'testAccounts.resetButton'.tr,
                      style: TextStyle(
                        color: red,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
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
// Two-step confirmation dialog — requires typing "RESET" before the
// destructive button enables.
// ============================================================================
class _ResetConfirmDialog extends StatefulWidget {
  final SocialPalette palette;
  final int totalAccounts;
  const _ResetConfirmDialog({
    required this.palette,
    required this.totalAccounts,
  });

  @override
  State<_ResetConfirmDialog> createState() => _ResetConfirmDialogState();
}

class _ResetConfirmDialogState extends State<_ResetConfirmDialog> {
  final _ctl = TextEditingController();
  bool get _canReset => _ctl.text.trim().toUpperCase() == 'RESET';

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final red = SocialTokens.down;
    return AlertDialog(
      backgroundColor: palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: red, size: 22),
          const SizedBox(width: 8),
          Text(
            'testAccounts.resetTitle'.tr,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'testAccounts.resetBody1'.tr,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'testAccounts.resetBody2'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'testAccounts.resetTypePrompt'.tr,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _ctl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: palette.surfaceElevated,
              hintText: 'RESET',
              hintStyle: TextStyle(color: palette.textMuted, letterSpacing: 1.2),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: red, width: 1.4),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'common.cancel'.tr,
            style: TextStyle(color: palette.textMuted),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _canReset ? () => Navigator.of(context).pop(true) : null,
          icon: const Icon(Icons.delete_forever_rounded, size: 18),
          label: Text('testAccounts.resetConfirm'.tr),
          style: ElevatedButton.styleFrom(
            backgroundColor: red,
            disabledBackgroundColor: red.withValues(alpha: 0.25),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }
}
