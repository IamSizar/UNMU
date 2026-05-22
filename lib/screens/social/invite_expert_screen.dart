import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/community_owners_service.dart';
import '../../services/community_service.dart';
import '../../utils/haptic_utils.dart';
import 'social_tokens.dart';

/// InviteExpertScreen — primary owner of a community picks an EXPERT
/// to invite as a co-owner of that community.
///
/// Flow:
///   1. Fetch /api/experts → flat list of verified experts.
///   2. Filter out: yourself (auth.user.id), anyone already a co-owner
///      (fetched in parallel via /communities/:id/owners).
///   3. Search box for name/expertise.
///   4. Tap a row → optional message input → POST invitation.
///   5. Snackbar success + pop back to community detail.
///
/// Server enforces the same constraints; this screen pre-filters to
/// avoid showing users that would just return 4xx ("user already a
/// co-owner", "pending invitation exists", etc.).
class InviteExpertScreen extends StatefulWidget {
  final String communityId;
  final String communityName;
  const InviteExpertScreen({
    super.key,
    required this.communityId,
    required this.communityName,
  });

  @override
  State<InviteExpertScreen> createState() => _InviteExpertScreenState();
}

class _InviteExpertScreenState extends State<InviteExpertScreen> {
  final _searchCtl = TextEditingController();
  String _q = '';

  bool _loading = true;
  String? _error;
  List<RealExpertRow> _experts = const [];
  // Expert IDs (e.g. "ex_26") of users who are already owner/co-owner —
  // skipped in the picker so we don't show invitable rows that would
  // 409 on submit.
  Set<String> _existingOwnerExpertIds = {};
  // While an invite is in flight for a given expert id. Drives a
  // spinner on that row.
  String? _sending;

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() {
      setState(() => _q = _searchCtl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final futExperts = CommunityService.listAllExperts();
    final futOwners =
        CommunityOwnersService.listOwners(widget.communityId);
    final expertsRes = await futExperts;
    final owners = await futOwners;
    if (!mounted) return;
    // We dedupe by `expertId` (e.g. "ex_26"), not user_id, because
    // /api/experts gives us expertIds but `/communities/:id/owners`
    // returns user-side fields including expertId. Both align.
    final existing = <String>{};
    if (owners.primary != null && owners.primary!.expertId.isNotEmpty) {
      existing.add(owners.primary!.expertId);
    }
    for (final c in owners.coOwners) {
      if (c.expertId.isNotEmpty) existing.add(c.expertId);
    }
    setState(() {
      _loading = false;
      if (expertsRes.experts == null) {
        _error = expertsRes.error ?? 'inviteExpert.couldNotLoad'.tr;
      } else {
        _experts = expertsRes.experts!;
        _existingOwnerExpertIds = existing;
      }
    });
  }

  // Filter: hide experts already in the community owner set, plus
  // anyone matching the search query (case-insensitive across name
  // and expertise). Backend also enforces these (returns 409) — this
  // is purely UX clean-up so the picker never offers a row that will
  // 409 on submit.
  List<RealExpertRow> get _filtered {
    return _experts.where((e) {
      if (_existingOwnerExpertIds.contains(e.id)) return false;
      if (_q.isEmpty) return true;
      final hay = '${e.name.toLowerCase()} ${e.expertise.toLowerCase()}';
      return hay.contains(_q);
    }).toList(growable: false);
  }

  Future<void> _sendInvite(RealExpertRow e) async {
    if (_sending != null) return;
    HapticUtils.lightTap();
    setState(() => _sending = e.id);

    final res = await CommunityOwnersService.sendInvite(
      communityId: widget.communityId,
      invitedExpertId: e.id,
    );
    if (!mounted) return;
    setState(() => _sending = null);

    if (res.success) {
      await HapticUtils.success();
      if (!mounted) return;
      Get.snackbar(
        'inviteExpert.sent'.tr,
        'inviteExpert.sentBody'.trParams({'name': e.name}),
        snackPosition: SnackPosition.TOP,
      );
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    await HapticUtils.error();
    if (!mounted) return;
    Get.snackbar(
      'inviteExpert.couldNotSend'.tr,
      _errorString(res),
      snackPosition: SnackPosition.TOP,
    );
  }

  String _errorString(InviteResult r) {
    // Map common backend error codes to friendly localized copy.
    switch (r.errorCode) {
      case 'INVITATION_PENDING':
        return 'inviteExpert.errPending'.tr;
      case 'ALREADY_OWNER':
        return 'inviteExpert.errAlreadyOwner'.tr;
      case 'NOT_EXPERT':
        return 'inviteExpert.errNotExpert'.tr;
      default:
        return r.errorMessage ?? 'inviteExpert.somethingWrong'.tr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'inviteExpert.title'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              widget.communityName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtl,
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: palette.textMuted,
                  size: 20,
                ),
                hintText: 'inviteExpert.searchHint'.tr,
                hintStyle: TextStyle(
                  color: palette.textMuted,
                  fontSize: 13.5,
                ),
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
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: SocialTokens.cyan),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: TextStyle(color: SocialTokens.down),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 80),
                              Center(
                                child: Text(
                                  _q.isEmpty
                                      ? 'inviteExpert.noneAvailable'.tr
                                      : 'inviteExpert.noMatches'.tr,
                                  style: TextStyle(color: palette.textMuted),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) => _ExpertRow(
                              expert: filtered[i],
                              palette: palette,
                              busy: _sending == filtered[i].id,
                              onInvite: () => _sendInvite(filtered[i]),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _ExpertRow extends StatelessWidget {
  final RealExpertRow expert;
  final SocialPalette palette;
  final bool busy;
  final VoidCallback onInvite;

  const _ExpertRow({
    required this.expert,
    required this.palette,
    required this.busy,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SocialTokens.gold.withValues(alpha: 0.15),
              border: Border.all(
                color: SocialTokens.gold.withValues(alpha: 0.40),
              ),
            ),
            child: Text(
              (expert.name.isNotEmpty ? expert.name[0] : '?').toUpperCase(),
              style: const TextStyle(
                color: SocialTokens.gold,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expert.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                    letterSpacing: -0.2,
                  ),
                ),
                if (expert.expertise.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 2),
                    child: Text(
                      expert.expertise,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: busy ? null : onInvite,
            style: ElevatedButton.styleFrom(
              backgroundColor: SocialTokens.cyan,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.black),
                    ),
                  )
                : Text(
                    'inviteExpert.invite'.tr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
