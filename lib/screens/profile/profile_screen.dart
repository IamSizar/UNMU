import 'dart:io';

import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:get/get.dart';

import '../../models/user.dart';
import '../../controllers/app_config_controller.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/currency_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/theme_controller.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/expert/become_expert_banner.dart';
import '../../screens/legal/legal_screen.dart';
import '../../screens/subscriptions/my_subscriptions_screen.dart';
import '../../screens/expert/expert_dashboard_screen.dart';
import '../../screens/saved/saved_posts_screen.dart';
import '../../screens/settings/support_chat_screen.dart';
import '../../screens/social/community_invitations_screen.dart';
import '../../screens/social/social_tokens.dart';
// Watchlist + Tools moved here from the bottom nav. The tiles in the
// Quick Actions grid push the same screens that used to be bottom-nav
// tabs — so the destinations themselves didn't change, only the entry
// point.
import '../../screens/tools/tools_screen.dart';
import '../../screens/watchlist/watchlist_screen.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/platform_adaptive/platform_dialog.dart';
import '../../widgets/social/test_account_switcher.dart';
import '../subscription/subscription_screen.dart';
import '../tools/dca_calculator_screen.dart';
import '../tools/zakat_calculator_screen.dart';
import 'change_email_screen.dart';
import '../../services/cache_service.dart';
import 'change_password_screen.dart';
import 'delete_account_screen.dart';
import 'edit_profile_screen.dart';
import 'notification_prefs_screen.dart';

/// =============================================================================
/// Profile Screen — editorial bento redesign.
///
/// Layout:
///   ▸ Hero profile card (avatar with gradient ring, premium badge, name+email)
///   ▸ Stats strip (Watchlist · Network · Member since) — 3-cell bento
///   ▸ Quick actions (2×2 bento: DCA, Zakat, Subscription, Notifications)
///   ▸ Preferences card (Dark mode · Language · Currency) with colored icon
///     tiles
///   ▸ About card (About · Help)
///   ▸ Logout (destructive button) or Sign in CTA when unauthenticated
///
/// Theme-reactive via [SocialTheme.of(context)].
/// =============================================================================
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  /// Marks the Preferences section header so the AppBar's gear icon can
  /// scroll the ListView directly to it via `Scrollable.ensureVisible`.
  final GlobalKey _prefsAnchor = GlobalKey();

  Future<void> _scrollToSettings() async {
    HapticUtils.lightTap();
    final ctx = _prefsAnchor.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.05, // sit near the top, not flush
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    // Wrapping the body in Obx means any Rx read inside (auth.user,
    // lang.locale, etc.) makes this whole screen rebuild when those values
    // change. Without this, switching test accounts via the switcher
    // doesn't re-render the hero + Become-Expert / Open-Studio banners.
    return Obx(() {
    final auth = Get.find<AuthController>();
    // Touch the user observable so this Obx tracks user changes even when
    // boolean short-circuits skip later auth.* reads (e.g. when not authed).
    auth.userObservable.value;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Text('profile.title'.tr,
            style: TextStyle(color: palette.textPrimary)),
        iconTheme: IconThemeData(color: palette.textPrimary),
        actions: [
          IconButton(
            tooltip: 'profile.settingsTooltip'.tr,
            icon: const Icon(Icons.settings_outlined),
            onPressed: _scrollToSettings,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          physics: const BouncingScrollPhysics(),
          children: [
            // ─────── HERO ───────
            if (auth.isAuthenticated)
              _ProfileHero(palette: palette, auth: auth)
            else
              _SignInHero(palette: palette),

            const SizedBox(height: 14),

            // ─────── STATS STRIP ───────
            if (auth.isAuthenticated)
              _StatsBento(palette: palette),
            if (auth.isAuthenticated) const SizedBox(height: 22),

            // ─────── BECOME AN EXPERT (Step 1) ───────
            // Only renders for regular USERs (banner returns SizedBox.shrink
            // for experts/admins). Drives the apply / pending / rejected flow.
            if (auth.isAuthenticated) ...[
              const BecomeExpertBanner(),
              const SizedBox(height: 22),
            ],

            // ─────── EXPERT STUDIO ENTRY (Step 2) ───────
            // Only experts/scholars see this — opens the studio dashboard
            // where they manage their articles, videos, and reels.
            if (auth.isAuthenticated && (auth.user?.isExpert ?? false)) ...[
              _OpenStudioBanner(palette: palette),
              const SizedBox(height: 22),
            ],

            // ─────── QUICK ACTIONS ───────
            _MiniSectionHeader(
              palette: palette,
              eyebrow: 'profile.sectionQuickEyebrow'.tr,
              title: 'profile.sectionQuickTitle'.tr,
            ),
            const SizedBox(height: 10),
            _QuickActionsGrid(palette: palette),

            const SizedBox(height: 22),

            // ─────── PREFERENCES ───────
            // GlobalKey anchor for the AppBar's gear icon (Phase 2.9) —
            // tapping the icon scrolls the ListView to this header.
            _MiniSectionHeader(
              key: _prefsAnchor,
              palette: palette,
              eyebrow: 'profile.sectionPrefsEyebrow'.tr,
              title: 'profile.sectionPrefsTitle'.tr,
            ),
            const SizedBox(height: 10),
            _PreferencesCard(palette: palette),

            // ─────── ACCOUNT (security) ───────
            // Only renders when authed — these endpoints require a JWT.
            if (auth.isAuthenticated) ...[
              const SizedBox(height: 22),
              _MiniSectionHeader(
                palette: palette,
                eyebrow: 'profile.sectionAccountEyebrow'.tr,
                title: 'profile.sectionAccountTitle'.tr,
              ),
              const SizedBox(height: 10),
              _AccountCard(palette: palette),
            ],

            // ─────── TEST MODE ───────
            // Lets you hop between USER / EXPERT / SCHOLAR presets to verify
            // the subscription paywall and post-creation rights. Gated on the
            // SAME admin flag as the login-screen "Test account" button
            // (app-config `testAccountEnabled`) — when the admin hides the
            // test account, this whole section disappears too. Obx so it
            // shows/hides live when the admin flips the toggle.
            if (auth.isAuthenticated)
              Obx(() {
                final show =
                    Get.find<AppConfigController>().testAccountEnabled.value;
                if (!show) return const SizedBox.shrink();
                return Column(
                  children: [
                    const SizedBox(height: 22),
                    _MiniSectionHeader(
                      palette: palette,
                      eyebrow: 'profile.sectionTestEyebrow'.tr,
                      title: 'profile.sectionTestTitle'.tr,
                    ),
                    const SizedBox(height: 10),
                    _TestModeCard(palette: palette, auth: auth),
                  ],
                );
              }),

            const SizedBox(height: 22),

            // ─────── ABOUT ───────
            _MiniSectionHeader(
              palette: palette,
              eyebrow: 'profile.sectionAboutEyebrow'.tr,
              title: 'profile.sectionAboutTitle'.tr,
            ),
            const SizedBox(height: 10),
            _AboutCard(palette: palette),

            const SizedBox(height: 24),

            // ─────── LOGOUT ───────
            if (auth.isAuthenticated)
              _LogoutButton(palette: palette),
          ],
        ),
      ),
    );
    }); // end Obx
  }
}

// ============================================================================
// HERO — authenticated profile card
// ============================================================================
class _ProfileHero extends StatelessWidget {
  final SocialPalette palette;
  final AuthController auth;
  const _ProfileHero({
    required this.palette,
    required this.auth,
  });

  @override
  Widget build(BuildContext context) {
    final user = auth.user;
    final isPremium = auth.isPremium;
    // The user's customized accent (from Edit Profile) wins over the
    // tier-default — falls back to gold (premium) or cyan (free).
    final accent = auth.avatarAccent ??
        (isPremium ? SocialTokens.gold : SocialTokens.cyan);
    final imagePath = auth.avatarPath;
    final name = user?.name ?? user?.email.split('@').first ?? 'Investor';
    final email = user?.email ?? '';
    final tierLabel = isPremium
        ? 'profile.premiumMember'.tr.toUpperCase()
        : 'profile.freeMember'.tr.toUpperCase();
    final upgradeLabel = 'profile.upgrade'.tr;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accent.withValues(alpha: palette.isDark ? 0.45 : 0.30),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: palette.isDark ? 0.18 : 0.10),
            blurRadius: 26,
            spreadRadius: -4,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Soft accent corner glow
          Positioned(
            right: -50,
            top: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: palette.isDark ? 0.30 : 0.18),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _ProfileAvatar(
                    name: name,
                    accent: accent,
                    isPremium: isPremium,
                    role: user?.role,
                    size: 70,
                    imagePath: imagePath,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            // Compact "Edit" pill button
                            _EditProfilePill(palette: palette, accent: accent),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Tier + Expert pills
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            // Tier pill (FREE / PREMIUM)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isPremium
                                        ? Icons.workspace_premium_rounded
                                        : Icons.account_circle_outlined,
                                    size: 12,
                                    color: accent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tierLabel,
                                    style: TextStyle(
                                      color: accent,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 9.5,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Verified Expert / Scholar pill — only when role is set.
                            // Role-aware badge — renders different label,
                            // icon and color for every role:
                            //   USER     → "MEMBER" (slate)
                            //   EXPERT   → "VERIFIED EXPERT" (cyan ✓)
                            //   SCHOLAR  → "VERIFIED SCHOLAR" (gold ✓)
                            //   ADMIN    → "ADMIN" (violet shield)
                            if (user != null) _RoleBadge(role: user.role),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!isPremium) ...[
                const SizedBox(height: 16),
                // Upgrade CTA when free
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      await HapticUtils.lightTap();
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [SocialTokens.gold, SocialTokens.goldSoft],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.rocket_launch_rounded,
                            color: Color(0xFF0A1628),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  upgradeLabel,
                                  style: const TextStyle(
                                    color: Color(0xFF0A1628),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                Text(
                                  'profile.upgradeToUnlock'.tr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF0A1628),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const DirectionalIcon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF0A1628),
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HERO — sign-in card for unauthenticated users
// ============================================================================
class _SignInHero extends StatelessWidget {
  final SocialPalette palette;
  const _SignInHero({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: palette.heroGradient(),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: SocialTokens.cyan.withValues(alpha: 0.45),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: SocialTokens.cyan.withValues(
              alpha: palette.isDark ? 0.16 : 0.10,
            ),
            blurRadius: 24,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SocialTokens.cyan.withValues(alpha: 0.18),
              border: Border.all(
                color: SocialTokens.cyan.withValues(alpha: 0.5),
                width: 1.4,
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.person_outline_rounded,
              color: SocialTokens.cyan,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'profile.signInWelcome'.tr,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'profile.signInSubtitle'.tr,
            style: TextStyle(
              color: palette.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticUtils.lightTap();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(
                'profile.signIn'.tr,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: SocialTokens.cyan,
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
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
// Avatar with gradient ring + premium star badge
// ============================================================================
class _ProfileAvatar extends StatelessWidget {
  final String name;
  final Color accent;
  final bool isPremium;
  /// User's role drives the corner mini-badge:
  ///   expert  → cyan ✓
  ///   scholar → gold ✓
  ///   admin   → violet shield
  ///   user    → premium star (if premium) or nothing
  final UserRole? role;
  final double size;
  final String? imagePath;

  const _ProfileAvatar({
    required this.name,
    required this.accent,
    required this.isPremium,
    this.role,
    this.size = 70,
    this.imagePath,
  });

  bool get _isExpert => role == UserRole.expert;
  // SCHOLAR retired (mig 0013) — kept as a getter that's always false
  // so the rest of this widget's role-aware branches still compile
  // without churn.
  bool get _isScholar => false;
  bool get _isAdmin => role == UserRole.admin;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0.4), accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(3),
            child: ClipOval(
              child: imagePath != null
                  ? Image.file(File(imagePath!), fit: BoxFit.cover)
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: 0.85),
                            accent.withValues(alpha: 0.55),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _initials(name),
                        style: TextStyle(
                          color: const Color(0xFF0A1628),
                          fontWeight: FontWeight.w900,
                          fontSize: size * 0.35,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
            ),
          ),
          // Role-based corner badge — beats the premium star because role is
          // a stronger signal. Falls through to premium star for plain USERs.
          if (_isExpert || _isScholar)
            _CornerBadge(
              size: size,
              color: _isScholar ? SocialTokens.gold : SocialTokens.cyan,
              icon: Icons.verified_rounded,
            )
          else if (_isAdmin)
            _CornerBadge(
              size: size,
              color: const Color(0xFF8B5CF6), // violet
              icon: Icons.shield_rounded,
            )
          else if (isPremium)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: size * 0.32,
                height: size * 0.32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  shape: BoxShape.circle,
                  border: Border.all(color: SocialTokens.gold, width: 1.8),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: SocialTokens.gold,
                  size: size * 0.20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

// ============================================================================
// Edit Profile pill — small tappable button on the hero
// ============================================================================
class _EditProfilePill extends StatelessWidget {
  final SocialPalette palette;
  final Color accent;
  const _EditProfilePill({required this.palette, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticUtils.lightTap();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const EditProfileScreen()),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_outlined, size: 13, color: accent),
              const SizedBox(width: 4),
              Text(
                'profile.editPill'.tr,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Stats bento — 3 cells (Watchlist · Network · Member since)
// ============================================================================
class _StatsBento extends StatelessWidget {
  final SocialPalette palette;
  const _StatsBento({required this.palette});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statCell(
              icon: Icons.bookmark_rounded,
              accent: SocialTokens.cyan,
              value: '12',
              label: 'profile.statWatchlist'.tr,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCell(
              icon: Icons.trending_up_rounded,
              accent: SocialTokens.up,
              value: '+8.2%',
              label: 'profile.statNetwork'.tr,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statCell(
              icon: Icons.calendar_today_rounded,
              accent: SocialTokens.gold,
              value: 'May \'26',
              label: 'profile.statMember'.tr,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCell({
    required IconData icon,
    required Color accent,
    required String value,
    required String label,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: accent),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: accent, size: 18),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Section header (small eyebrow + title)
// ============================================================================
class _MiniSectionHeader extends StatelessWidget {
  final SocialPalette palette;
  final String eyebrow;
  final String title;
  const _MiniSectionHeader({
    super.key,
    required this.palette,
    required this.eyebrow,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: const TextStyle(
              color: SocialTokens.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 19,
              letterSpacing: -0.4,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Quick actions — 2x2 bento grid
// ============================================================================
class _QuickActionsGrid extends StatelessWidget {
  final SocialPalette palette;
  const _QuickActionsGrid({required this.palette});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        // Watchlist + Tools moved here from the bottom nav (May 2026).
        // Pinned to the FIRST two slots so the user finds them at the
        // exact spot the eye lands when Profile opens.
        _QuickActionTile(
          palette: palette,
          icon: Icons.show_chart_rounded,
          accent: SocialTokens.cyan,
          title: 'profile.quickWatchlistTitle'.tr,
          subtitle: 'profile.quickWatchlistSubtitle'.tr,
          onTap: () => _open(context, const WatchlistScreen()),
        ),
        _QuickActionTile(
          palette: palette,
          icon: Icons.build_rounded,
          accent: SocialTokens.gold,
          title: 'profile.quickToolsTitle'.tr,
          subtitle: 'profile.quickToolsSubtitle'.tr,
          onTap: () => _open(context, const ToolsScreen()),
        ),
        _QuickActionTile(
          palette: palette,
          icon: Icons.calculate_rounded,
          accent: SocialTokens.up,
          title: 'profile.quickDcaTitle'.tr,
          subtitle: 'profile.quickDcaSubtitle'.tr,
          onTap: () => _open(context, const DcaCalculatorScreen()),
        ),
        _QuickActionTile(
          palette: palette,
          icon: Icons.volunteer_activism_rounded,
          accent: SocialTokens.gold,
          title: 'profile.quickZakatTitle'.tr,
          subtitle: 'profile.quickZakatSubtitle'.tr,
          onTap: () => _open(context, const ZakatCalculatorScreen()),
        ),
        _QuickActionTile(
          palette: palette,
          icon: Icons.workspace_premium_rounded,
          accent: SocialTokens.gold,
          title: 'profile.quickSubscriptionsTitle'.tr,
          subtitle: 'profile.quickSubscriptionsSubtitle'.tr,
          onTap: () => _open(context, const MySubscriptionsScreen()),
        ),
        _QuickActionTile(
          palette: palette,
          icon: Icons.bookmark_rounded,
          accent: SocialTokens.cyan,
          title: 'profile.quickSavedTitle'.tr,
          subtitle: 'profile.quickSavedSubtitle'.tr,
          onTap: () => _open(context, const SavedPostsScreen()),
        ),
      ],
    );
  }

  void _open(BuildContext context, Widget screen) {
    HapticUtils.lightTap();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final SocialPalette palette;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickActionTile({
    required this.palette,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Preferences card (Dark mode · Language · Currency)
// ============================================================================
class _PreferencesCard extends StatelessWidget {
  final SocialPalette palette;
  const _PreferencesCard({required this.palette});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Get.find<ThemeController>();
    final languageProvider = Get.find<LanguageController>();
    final currencyProvider = Get.find<CurrencyController>();

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          _SettingRow(
            palette: palette,
            icon: themeProvider.isDarkMode
                ? Icons.dark_mode_rounded
                : Icons.light_mode_rounded,
            accent: const Color(0xFF8B5CF6),
            title: 'profile.darkMode'.tr,
            trailing: Switch.adaptive(
              value: themeProvider.isDarkMode,
              activeColor: SocialTokens.cyan,
              onChanged: (_) async {
                await HapticUtils.selection();
                themeProvider.toggleTheme();
              },
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.translate_rounded,
            accent: SocialTokens.cyan,
            title: 'profile.language'.tr,
            trailing: _StyledDropdown<String>(
              palette: palette,
              value: languageProvider.locale.languageCode,
              items: const [
                // Native language names — always shown in their own
                // script regardless of the active UI locale, so they are
                // NOT routed through .tr.
                DropdownMenuItem(
                  value: 'en',
                  child: Text('English'),
                ),
                DropdownMenuItem(
                  value: 'ar',
                  child: Text('العربية'),
                ),
              ],
              onChanged: (v) async {
                if (v != null) {
                  await HapticUtils.selection();
                  languageProvider.setLanguage(v);
                }
              },
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.attach_money_rounded,
            accent: SocialTokens.gold,
            title: 'profile.currency'.tr,
            // Obx so the dropdown reflects the new currency immediately —
            // without it, the value only refreshed after a tab switch
            // because this card is a StatelessWidget that doesn't rebuild
            // on a currency change (unlike theme/language, which rebuild
            // the whole app).
            trailing: Obx(
              () => _StyledDropdown<String>(
                palette: palette,
                value: currencyProvider.selectedCurrency.code,
                items: CurrencyController.availableCurrencies
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.flag} ${c.code}'),
                      ),
                    )
                    .toList(),
                onChanged: (v) async {
                  if (v != null) {
                    await HapticUtils.selection();
                    final c = CurrencyController.availableCurrencies
                        .firstWhere((cur) => cur.code == v);
                    currencyProvider.updateCurrency(c);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Test-mode card — shows the current role and a "Switch test account" row
// that opens the bottom-sheet picker.
// ============================================================================
class _TestModeCard extends StatelessWidget {
  final SocialPalette palette;
  final AuthController auth;
  const _TestModeCard({
    required this.palette,
    required this.auth,
  });

  String _roleLabel(BuildContext context) {
    final role = auth.user?.role.wireValue ?? 'USER';
    switch (role) {
      case 'SCHOLAR':
        return 'profile.roleScholar'.tr;
      case 'EXPERT':
        return 'profile.roleExpert'.tr;
      default:
        return 'profile.roleUser'.tr;
    }
  }

  Color _roleColor() {
    // SCHOLAR retired (mig 0013) — every former scholar now reads as
    // expert and renders the cyan accent.
    switch (auth.user?.role) {
      case UserRole.expert:
        return SocialTokens.cyan;
      default:
        return SocialTokens.up;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _roleColor();
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          // Current role row (read-only).
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    // SCHOLAR retired (mig 0013) — premium icon path is
                    // dropped, expert role gets the verified checkmark,
                    // everyone else gets a generic person.
                    auth.user?.role == UserRole.expert
                        ? Icons.verified_rounded
                        : Icons.person_rounded,
                    color: accent,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'profile.currentRole'.tr,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _roleLabel(context),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: accent.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    (auth.user?.role.wireValue ?? 'USER').toUpperCase(),
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.swap_horiz_rounded,
            accent: SocialTokens.cyan,
            title: 'profile.switchTestAccount'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              await TestAccountSwitcherSheet.show(context);
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Account card — change password / change email / delete account.
// Backed by Phase 1.9 → 1.11 endpoints (POST /me/change-password,
// POST /me/change-email/{request,confirm}, DELETE /me/account).
// ============================================================================
class _AccountCard extends StatelessWidget {
  final SocialPalette palette;
  const _AccountCard({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          _SettingRow(
            palette: palette,
            icon: Icons.notifications_outlined,
            accent: SocialTokens.cyan,
            title: 'account.notificationPrefs'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationPrefsScreen(),
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.lock_outline_rounded,
            accent: SocialTokens.gold,
            title: 'account.changePassword'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ChangePasswordScreen(),
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.alternate_email_rounded,
            accent: SocialTokens.cyan,
            title: 'account.changeEmail'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ChangeEmailScreen(),
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.cleaning_services_outlined,
            accent: SocialTokens.cyan,
            title: 'account.clearCache'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              final size = await CacheService.sizeBytes();
              if (!context.mounted) return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('account.clearCache'.tr),
                  content: Text('account.clearCacheBody'.trParams(
                      {'size': CacheService.formatBytes(size)})),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text('common.cancel'.tr),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('account.clearCacheConfirm'.tr),
                    ),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              final freed = await CacheService.clear();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('account.clearCacheDone'.trParams(
                      {'size': CacheService.formatBytes(freed)})),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.delete_outline_rounded,
            accent: SocialTokens.down,
            title: 'account.deleteAccount'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DeleteAccountScreen(),
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// About card
// ============================================================================
class _AboutCard extends StatelessWidget {
  final SocialPalette palette;
  const _AboutCard({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          _SettingRow(
            palette: palette,
            icon: Icons.info_outline_rounded,
            accent: SocialTokens.cyan,
            title: 'profile.about'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              PlatformDialog.show(
                context: context,
                title: 'profile.about'.tr,
                content: 'profile.aboutBody'.tr,
                confirmText: 'common.close'.tr,
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
          _Divider(palette: palette),
          // Mig 0032 — community co-owner invitations. EXPERT users
          // see pending invitations here. USER role accounts will see
          // it too but the empty state explains there's nothing for
          // them yet.
          _SettingRow(
            palette: palette,
            icon: Icons.mail_outline_rounded,
            accent: SocialTokens.gold,
            title: 'profile.communityInvitations'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CommunityInvitationsScreen(),
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.support_agent_rounded,
            accent: SocialTokens.cyan,
            // Mig 0029 — built-in chat with admin. Replaces the
            // earlier "contact us via email" placeholder dialog.
            title: 'profile.contactAdmin'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SupportChatScreen(),
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.privacy_tip_outlined,
            accent: SocialTokens.cyan,
            title: 'profile.privacyPolicy'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LegalScreen(doc: LegalDoc.privacy),
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
          _Divider(palette: palette),
          _SettingRow(
            palette: palette,
            icon: Icons.description_outlined,
            accent: SocialTokens.gold,
            title: 'profile.termsOfService'.tr,
            onTap: () async {
              await HapticUtils.lightTap();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const LegalScreen(doc: LegalDoc.terms),
                ),
              );
            },
            trailing: DirectionalIcon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Generic setting row used in Preferences + About cards
// ============================================================================
class _SettingRow extends StatelessWidget {
  final SocialPalette palette;
  final IconData icon;
  final Color accent;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.palette,
    required this.icon,
    required this.accent,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

class _Divider extends StatelessWidget {
  final SocialPalette palette;
  const _Divider({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      height: 1,
      color: palette.subtleDivider,
    );
  }
}

// ============================================================================
// Styled dropdown — themed to match preferences card
// ============================================================================
class _StyledDropdown<T> extends StatelessWidget {
  final SocialPalette palette;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _StyledDropdown({
    required this.palette,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: DropdownButton<T>(
        value: value,
        items: items,
        onChanged: onChanged,
        underline: const SizedBox(),
        isDense: true,
        icon: Icon(Icons.expand_more_rounded, color: palette.textSecondary),
        dropdownColor: palette.surface,
        style: TextStyle(
          color: palette.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============================================================================
// Logout button (destructive)
// ============================================================================
class _LogoutButton extends StatelessWidget {
  final SocialPalette palette;
  const _LogoutButton({required this.palette});

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          await HapticUtils.lightTap();
          if (!context.mounted) return;
          final shouldLogout = await PlatformDialog.show(
            context: context,
            title: 'profile.logoutConfirmTitle'.tr,
            content: 'profile.logoutConfirmBody'.tr,
            confirmText: 'profile.logout'.tr,
            cancelText: 'common.cancel'.tr,
            isDestructive: true,
          );
          if (shouldLogout == true && context.mounted) {
            await HapticUtils.success();
            await auth.logout();
            // Don't navigate here. _AppEntry (in main.dart) listens to
            // AuthController and swaps in LoginScreen automatically once
            // auth.logout() fires notifyListeners(). Calling
            // Navigator.pushReplacement here used to REPLACE _AppEntry
            // itself with a standalone LoginScreen, which broke any
            // subsequent login attempts (no _AppEntry left to route back
            // to MainTabScaffold).
          }
        },
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(
          'profile.logout'.tr,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: SocialTokens.down,
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(
            color: SocialTokens.down.withValues(alpha: 0.5),
            width: 1.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// OPEN STUDIO — entry banner for experts/scholars (Step 2)
// ============================================================================
class _OpenStudioBanner extends StatelessWidget {
  final SocialPalette palette;
  const _OpenStudioBanner({required this.palette});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticUtils.lightTap();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ExpertDashboardScreen()),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              SocialTokens.gold.withValues(alpha: 0.20),
              SocialTokens.cyan.withValues(alpha: 0.12),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: SocialTokens.gold.withValues(alpha: 0.40),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SocialTokens.gold.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.movie_creation_outlined,
                  color: SocialTokens.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'profile.openStudio'.tr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'profile.openStudioSubtitle'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            DirectionalIcon(Icons.chevron_right, color: palette.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// ROLE BADGE — small pill rendered next to the tier pill on the hero.
// Shows label + color tuned to the user's role.
// ============================================================================
class _RoleBadge extends StatelessWidget {
  final UserRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: spec.color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: 12, color: spec.color),
          const SizedBox(width: 4),
          Text(
            spec.labelKey.tr,
            style: TextStyle(
              color: spec.color,
              fontWeight: FontWeight.w900,
              fontSize: 9.5,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  static _BadgeSpec _specFor(UserRole role) {
    // SCHOLAR retired (mig 0013) — only USER / EXPERT / ADMIN remain.
    switch (role) {
      case UserRole.expert:
        return const _BadgeSpec(
          labelKey: 'profile.badgeVerifiedExpert',
          color: SocialTokens.cyan,
          icon: Icons.verified_rounded,
        );
      case UserRole.admin:
        return const _BadgeSpec(
          labelKey: 'profile.badgeAdmin',
          color: Color(0xFF8B5CF6), // violet
          icon: Icons.shield_rounded,
        );
      case UserRole.user:
        return const _BadgeSpec(
          labelKey: 'profile.badgeMember',
          color: Color(0xFF94A3B8), // slate-400
          icon: Icons.person_rounded,
        );
    }
  }
}

class _BadgeSpec {
  final String labelKey;
  final Color color;
  final IconData icon;
  const _BadgeSpec(
      {required this.labelKey, required this.color, required this.icon});
}

// Small reusable corner badge for the avatar (matches role / premium variants).
class _CornerBadge extends StatelessWidget {
  final double size;
  final Color color;
  final IconData icon;
  const _CornerBadge({required this.size, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -2,
      bottom: -2,
      child: Container(
        width: size * 0.36,
        height: size * 0.36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF0A1628), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.45),
              blurRadius: 10,
              spreadRadius: -1,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: const Color(0xFF0A1628),
          size: size * 0.24,
        ),
      ),
    );
  }
}
