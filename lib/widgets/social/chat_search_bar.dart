import 'dart:async';

import 'package:flutter/material.dart';
import '../directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../localization/locale_format.dart';
import '../../screens/social/social_tokens.dart';
import '../../services/community_messages_service.dart';

/// Inline chat-search panel (mig 0021, item 5.17).
///
/// When [active] flips true, renders a search bar + result list inside
/// the chat view (replaces the bubble stream while active). Tap a
/// result → caller's [onJumpTo] receives the message id; the parent
/// scrolls the underlying chat to that bubble + flashes it.
///
/// Debounce: 300ms after the last keystroke. Queries shorter than 2
/// chars don't fire — avoids hammering the backend on a single
/// character.
class ChatSearchOverlay extends StatefulWidget {
  final String communityId;
  final ValueChanged<int> onJumpTo;
  final VoidCallback onClose;

  const ChatSearchOverlay({
    super.key,
    required this.communityId,
    required this.onJumpTo,
    required this.onClose,
  });

  @override
  State<ChatSearchOverlay> createState() => _ChatSearchOverlayState();
}

class _ChatSearchOverlayState extends State<ChatSearchOverlay> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  bool _searching = false;
  String? _error;
  List<CommunityMessage> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
  }

  Future<void> _run(String q) async {
    final res = await CommunityMessagesService.search(
      widget.communityId,
      q,
    );
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = res.results ?? const [];
      _error = res.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return Material(
      color: palette.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _searchHeader(palette),
            const Divider(height: 1),
            Expanded(child: _body(palette)),
          ],
        ),
      ),
    );
  }

  Widget _searchHeader(SocialPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: widget.onClose,
            icon: DirectionalIcon(Icons.arrow_back_rounded, color: palette.textPrimary),
          ),
          Expanded(
            child: TextField(
              controller: _ctl,
              focusNode: _focus,
              onChanged: _onChanged,
              autofocus: true,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'chatSearch.hint'.tr,
                hintStyle: TextStyle(
                  color: palette.textMuted.withValues(alpha: 0.7),
                ),
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          if (_ctl.text.isNotEmpty)
            IconButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                _ctl.clear();
                _onChanged('');
              },
              icon: Icon(Icons.close_rounded, color: palette.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _body(SocialPalette palette) {
    if (_searching) {
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
    if (_ctl.text.trim().length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_rounded,
                  size: 48, color: palette.textMuted),
              const SizedBox(height: 10),
              Text(
                'chatSearch.typeMin'.tr,
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'chatSearch.noMatches'.tr,
            style: TextStyle(
              color: palette.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final query = _ctl.text.trim();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (_, i) {
        final m = _results[i];
        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onJumpTo(m.id);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor:
                          SocialTokens.cyan.withValues(alpha: 0.15),
                      child: Text(
                        m.authorName.isNotEmpty
                            ? m.authorName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: SocialTokens.cyan,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      _relTime(m.createdAt),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _HighlightedBody(
                  body: m.body,
                  query: query,
                  palette: palette,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _relTime(DateTime t) => LocaleFormat.relative(t);
}

/// Renders [body] with every case-insensitive occurrence of [query]
/// wrapped in a cyan-highlighted span.
class _HighlightedBody extends StatelessWidget {
  final String body;
  final String query;
  final SocialPalette palette;
  const _HighlightedBody({
    required this.body,
    required this.query,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        body,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
      );
    }
    final spans = <TextSpan>[];
    final lower = body.toLowerCase();
    final qLower = query.toLowerCase();
    int i = 0;
    while (i < body.length) {
      final next = lower.indexOf(qLower, i);
      if (next < 0) {
        spans.add(TextSpan(text: body.substring(i)));
        break;
      }
      if (next > i) {
        spans.add(TextSpan(text: body.substring(i, next)));
      }
      spans.add(TextSpan(
        text: body.substring(next, next + query.length),
        style: const TextStyle(
          color: SocialTokens.cyan,
          fontWeight: FontWeight.w900,
        ),
      ));
      i = next + query.length;
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(color: palette.textPrimary, fontSize: 13.5),
        children: spans,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
