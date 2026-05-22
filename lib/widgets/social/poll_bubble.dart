import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../screens/social/social_tokens.dart';
import '../../services/community_messages_service.dart';

/// Rich poll bubble shown inline in a community chat (mig 0021,
/// item 5.21).
///
/// Behaviour:
///   * Tap an option → fires [onVote] with that option id.
///   * Already-voted state → that option is highlighted.
///   * Closed state → all options locked, "Closed" badge.
///   * Anonymous polls hide the "12 voted" → tap-to-see-who affordance.
class PollBubble extends StatelessWidget {
  final CommunityPoll poll;
  /// Display name of the poll author (for the question's attribution).
  final String authorName;
  /// Whether the current viewer is the poll author OR the community
  /// owner. Drives the "Close poll" action menu.
  final bool canClose;
  /// Fired when the user taps an option. Caller should optimistically
  /// update its CommunityPoll copy + then refetch on the realtime
  /// `poll_voted` event for authoritative state.
  final ValueChanged<int> onVote;
  /// Fired when the user taps the close action. Only relevant when
  /// [canClose] is true.
  final VoidCallback? onClose;

  const PollBubble({
    super.key,
    required this.poll,
    required this.authorName,
    required this.canClose,
    required this.onVote,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final closed = poll.isClosed;
    final total = poll.totalVotes;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: closed
              ? palette.border
              : SocialTokens.cyan.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  size: 18, color: SocialTokens.cyan),
              const SizedBox(width: 6),
              Text(
                closed ? 'Poll · Closed' : 'Poll',
                style: TextStyle(
                  color:
                      closed ? palette.textMuted : SocialTokens.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
              if (poll.isAnonymous) ...[
                const SizedBox(width: 6),
                Icon(Icons.visibility_off_rounded,
                    size: 13, color: palette.textMuted),
              ],
              const Spacer(),
              if (canClose && !closed && onClose != null)
                IconButton(
                  iconSize: 16,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'poll.closePoll'.tr,
                  onPressed: onClose,
                  icon: Icon(Icons.lock_outline_rounded,
                      color: palette.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            poll.question,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 15,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          for (final opt in poll.options)
            _OptionRow(
              option: opt,
              total: total,
              isMine: poll.myOptionId == opt.id,
              locked: closed,
              onTap: closed ? null : () => onVote(opt.id),
              palette: palette,
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.people_alt_rounded,
                  size: 12, color: palette.textMuted),
              const SizedBox(width: 4),
              Text(
                total == 1
                    ? 'poll.voteOne'.tr
                    : 'poll.votesOther'.trParams({'n': '$total'}),
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (poll.expiresAt != null && !closed) ...[
                const SizedBox(width: 10),
                Icon(Icons.schedule_rounded,
                    size: 12, color: palette.textMuted),
                const SizedBox(width: 4),
                Text(
                  'poll.closesPrefix'.trParams({'time': _relTime(poll.expiresAt!)}),
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _relTime(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.isNegative) return 'poll.closesNow'.tr;
    if (d.inMinutes < 60) {
      return 'poll.closesInMin'.trParams({'n': '${d.inMinutes}'});
    }
    if (d.inHours < 24) {
      return 'poll.closesInHour'.trParams({'n': '${d.inHours}'});
    }
    return 'poll.closesInDay'.trParams({'n': '${d.inDays}'});
  }
}

class _OptionRow extends StatelessWidget {
  final CommunityPollOption option;
  final int total;
  final bool isMine;
  final bool locked;
  final VoidCallback? onTap;
  final SocialPalette palette;
  const _OptionRow({
    required this.option,
    required this.total,
    required this.isMine,
    required this.locked,
    required this.onTap,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : option.voteCount / total;
    final pctLabel = '${(pct * 100).round()}%';
    final accent =
        isMine ? SocialTokens.cyan : palette.textMuted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Stack(
          children: [
            // Background bar — fills based on vote share.
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isMine
                      ? SocialTokens.cyan.withValues(alpha: 0.6)
                      : palette.border,
                  width: isMine ? 1.4 : 1,
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LayoutBuilder(
                builder: (_, c) => Container(
                  height: 38,
                  width: c.maxWidth * pct,
                  decoration: BoxDecoration(
                    color: isMine
                        ? SocialTokens.cyan.withValues(alpha: 0.18)
                        : accent.withValues(alpha: 0.10),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 38,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    if (isMine) ...[
                      const Icon(Icons.check_circle_rounded,
                          size: 14, color: SocialTokens.cyan),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13.5,
                          fontWeight:
                              isMine ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      pctLabel,
                      style: TextStyle(
                        color: isMine
                            ? SocialTokens.cyan
                            : palette.textMuted,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
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
