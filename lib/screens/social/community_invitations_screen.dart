import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../services/community_owners_service.dart';
import '../../utils/haptic_utils.dart';
import 'social_tokens.dart';

/// Community Invitations — the invitee's inbox for "join my community
/// as a co-owner" invitations sent by community primary owners.
///
/// Reached from the Profile menu. Renders a refreshable list of
/// pending invitations. Each row has the inviter name, community
/// name, optional message, and Accept / Reject buttons. After accept,
/// the row animates out and the user becomes a co-owner of that
/// community — they can now publish posts in it from the community
/// detail screen.
///
/// Realtime hook: when a new invitation lands (`community_invitation_received`
/// WS event), this screen auto-refreshes if it's currently mounted.
class CommunityInvitationsScreen extends StatefulWidget {
  const CommunityInvitationsScreen({super.key});

  @override
  State<CommunityInvitationsScreen> createState() =>
      _CommunityInvitationsScreenState();
}

class _CommunityInvitationsScreenState
    extends State<CommunityInvitationsScreen> {
  bool _loading = true;
  List<CommunityInvitation> _items = const [];
  // Per-id action state — keeps spinners on the right row only.
  final Set<int> _resolving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await CommunityOwnersService.listMyIncoming();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _accept(CommunityInvitation inv) async {
    if (_resolving.contains(inv.id)) return;
    HapticUtils.lightTap();
    setState(() => _resolving.add(inv.id));
    final res = await CommunityOwnersService.accept(inv.id);
    if (!mounted) return;
    setState(() {
      _resolving.remove(inv.id);
      if (res.success) {
        _items = _items.where((x) => x.id != inv.id).toList();
      }
    });
    if (res.success) {
      await HapticUtils.success();
      if (!mounted) return;
      Get.snackbar(
        'communityInvite.accepted'.tr,
        'communityInvite.acceptedBody'
            .trParams({'name': inv.communityName}),
        snackPosition: SnackPosition.TOP,
      );
    } else {
      await HapticUtils.error();
      if (!mounted) return;
      Get.snackbar(
        'communityInvite.acceptFailed'.tr,
        res.errorMessage ?? 'communityInvite.somethingWrong'.tr,
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  Future<void> _reject(CommunityInvitation inv) async {
    if (_resolving.contains(inv.id)) return;
    HapticUtils.lightTap();
    setState(() => _resolving.add(inv.id));
    final res = await CommunityOwnersService.reject(inv.id);
    if (!mounted) return;
    setState(() {
      _resolving.remove(inv.id);
      if (res.success) {
        _items = _items.where((x) => x.id != inv.id).toList();
      }
    });
    if (!res.success) {
      Get.snackbar(
        'communityInvite.rejectFailed'.tr,
        res.errorMessage ?? '',
        snackPosition: SnackPosition.TOP,
      );
    }
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
          'communityInvite.title'.tr,
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: SocialTokens.cyan,
        child: _loading && _items.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: SocialTokens.cyan),
              )
            : _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: SocialTokens.cyan.withValues(
                                    alpha: 0.10,
                                  ),
                                  border: Border.all(
                                    color: SocialTokens.cyan.withValues(
                                      alpha: 0.30,
                                    ),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.mail_outline_rounded,
                                  color: SocialTokens.cyan,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'communityInvite.emptyTitle'.tr,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'communityInvite.emptyBody'.tr,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.textMuted,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _InvitationCard(
                      invitation: _items[i],
                      palette: palette,
                      busy: _resolving.contains(_items[i].id),
                      onAccept: () => _accept(_items[i]),
                      onReject: () => _reject(_items[i]),
                    ),
                  ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final CommunityInvitation invitation;
  final SocialPalette palette;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _InvitationCard({
    required this.invitation,
    required this.palette,
    required this.busy,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat.MMMd().add_jm().format(invitation.createdAt.toLocal());

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — inviter + community + timestamp.
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SocialTokens.gold.withValues(alpha: 0.15),
                  border: Border.all(
                    color: SocialTokens.gold.withValues(alpha: 0.40),
                  ),
                ),
                child: const Icon(
                  Icons.groups_2_outlined,
                  color: SocialTokens.gold,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invitation.communityName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'communityInvite.fromName'
                          .trParams({'name': invitation.invitedByName}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                timeStr,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 10.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),

          // Message — only when the inviter wrote one.
          if (invitation.message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border, width: 1),
              ),
              child: Text(
                invitation.message,
                style: TextStyle(
                  color: palette.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Pitch — what accepting means.
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: SocialTokens.cyan.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: SocialTokens.cyan.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: SocialTokens.cyan,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'communityInvite.pitch'.tr,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Actions.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onReject,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text('communityInvite.decline'.tr),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.textMuted,
                    side: BorderSide(color: palette.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: busy ? null : onAccept,
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.black),
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 16),
                  label: Text('communityInvite.accept'.tr),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SocialTokens.cyan,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
