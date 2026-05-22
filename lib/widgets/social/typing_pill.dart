import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../screens/social/social_tokens.dart';

/// "Sarah is typing…" pill rendered above the chat composer (mig 0021,
/// item 5.19).
///
/// Cap: show up to 2 names, then "X, Y and N others are typing…".
/// Hides itself when [names] is empty.
class TypingPill extends StatelessWidget {
  /// Active typers' display names. Order is treated as significant —
  /// caller controls the most-recent-first ordering.
  final List<String> names;

  const TypingPill({super.key, required this.names});

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final palette = SocialTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Row(
        children: [
          _TypingDots(color: palette.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _formatLabel(names),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLabel(List<String> ns) {
    if (ns.length == 1) {
      return 'typing.one'.trParams({'name': ns[0]});
    }
    if (ns.length == 2) {
      return 'typing.two'.trParams({'first': ns[0], 'second': ns[1]});
    }
    return 'typing.many'.trParams({
      'first': ns[0],
      'second': ns[1],
      'count': '${ns.length - 2}',
    });
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctl.value * 3 - i).clamp(0.0, 1.0);
            final scale = 0.6 + 0.4 * (1 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 5 * scale,
                height: 5 * scale,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
