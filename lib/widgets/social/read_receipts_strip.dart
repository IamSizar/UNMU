import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../localization/locale_format.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/community_messages_service.dart';

/// "Seen by N" tappable pill rendered under the *author's own* sent
/// bubble (mig 0021, item 5.18).
///
/// Tap → opens the [_ReadersSheet] with the avatar list. We only show
/// this for the user's own messages — receipt visibility on other
/// users' messages would expose who's reading what to non-authors,
/// which isn't the goal.
class ReadReceiptsStrip extends StatelessWidget {
  final int messageId;
  final String communityId;
  final int readCount;

  const ReadReceiptsStrip({
    super.key,
    required this.messageId,
    required this.communityId,
    required this.readCount,
  });

  @override
  Widget build(BuildContext context) {
    if (readCount <= 0) {
      // Render an "Sent · not yet seen" hint so the author knows the
      // bubble is delivered. Tiny, low-noise.
      return _Pill(
        icon: Icons.done_rounded,
        label: 'readReceipts.sent'.tr,
        accent: false,
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        HapticFeedback.selectionClick();
        _ReadersSheet.show(
          context,
          messageId: messageId,
          communityId: communityId,
        );
      },
      child: _Pill(
        icon: Icons.done_all_rounded,
        label: readCount == 1
            ? 'readReceipts.seenByOne'.tr
            : 'readReceipts.seenByMany'.trParams({'count': '$readCount'}),
        accent: true,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;
  const _Pill({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final color = accent ? SocialTokens.cyan : palette.textMuted;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadersSheet extends StatefulWidget {
  final int messageId;
  final String communityId;
  const _ReadersSheet({
    required this.messageId,
    required this.communityId,
  });

  static Future<void> show(
    BuildContext context, {
    required int messageId,
    required String communityId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReadersSheet(
        messageId: messageId,
        communityId: communityId,
      ),
    );
  }

  @override
  State<_ReadersSheet> createState() => _ReadersSheetState();
}

class _ReadersSheetState extends State<_ReadersSheet> {
  bool _loading = true;
  String? _error;
  List<MessageReader> _readers = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final res = await CommunityMessagesService.listReaders(
      widget.communityId,
      widget.messageId,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _readers = res.readers ?? const [];
      _error = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final h = MediaQuery.of(context).size.height;
    return Container(
      constraints: BoxConstraints(maxHeight: h * 0.6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: palette.border, width: 1),
          left: BorderSide(color: palette.border, width: 1),
          right: BorderSide(color: palette.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: Row(
                children: [
                  const Icon(Icons.done_all_rounded,
                      color: SocialTokens.cyan),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'readReceipts.seenByTitle'.tr,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.close_rounded,
                        color: palette.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _body(palette)),
          ],
        ),
      ),
    );
  }

  Widget _body(SocialPalette palette) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SocialTokens.down),
          ),
        ),
      );
    }
    if (_readers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'readReceipts.noReads'.tr,
            style: TextStyle(color: palette.textMuted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _readers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final r = _readers[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor:
                SocialTokens.cyan.withValues(alpha: 0.15),
            child: Text(
              r.name.isNotEmpty ? r.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: SocialTokens.cyan,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          title: Text(
            r.name,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            LocaleFormat.relative(r.readAt),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11.5,
            ),
          ),
        );
      },
    );
  }
}
