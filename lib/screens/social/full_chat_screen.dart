import 'package:flutter/material.dart';
import '../../widgets/directional_icon.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../widgets/social/shariah_grade_chip.dart';
import 'mock_social_data.dart';
import 'social_tokens.dart';

/// =============================================================================
/// Full-screen Chat — dedicated WhatsApp/Telegram-style chat room.
///
/// Unlike `CommunityDetailScreen` (which has the community card, ticker strip,
/// trading chart, AND a tab bar before the chat starts), this screen is
/// 100% chat — just an app bar with the community identity and a clean
/// messages-only canvas underneath.
///
///   ┌──────────────────────────────────────┐
///   │ ← [US] US Halal Tech    🟢 588 active │  Slim header
///   │                                      │
///   │      ─── TODAY ───                   │
///   │                                      │
///   │  ⊙ Mariam · 2m                       │
///   │  ┌─────────────────────────────┐    │
///   │  │ Volume is solid. Holding.   │    │
///   │  └─────────────────────────────┘    │
///   │                                      │
///   │              You · now    ⊙          │
///   │  ┌─────────────────────────────┐    │
///   │  │ Same — debt is much cleaner.│    │
///   │  └─────────────────────────────┘    │
///   │                                      │
///   │ [💼 Insert symbol] $AAPL  $MSFT  …    │
///   │ ┌──────────────────────────────┬─┐  │
///   │ │ + Type a message…       😀  │↑│  │
///   │ └──────────────────────────────┴─┘  │
///   └──────────────────────────────────────┘
/// =============================================================================
class FullChatScreen extends StatefulWidget {
  final Community community;

  const FullChatScreen({
    super.key,
    required this.community,
  });

  @override
  State<FullChatScreen> createState() => _FullChatScreenState();
}

class _FullChatScreenState extends State<FullChatScreen> {
  late List<ChatMessage> _messages;
  late final TextEditingController _input;
  late final ScrollController _scroll;
  late final FocusNode _focus;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _messages = List<ChatMessage>.from(widget.community.chatMessages);
    _input = TextEditingController();
    _scroll = ScrollController();
    _focus = FocusNode();
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          author: 'You',
          timeAgo: 'now',
          body: text,
          tickers: const [],
          isCurrentUser: true,
        ),
      );
      _input.clear();
      _hasText = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _insertTicker(String symbol) {
    final base = _input.text;
    final sep = base.isEmpty || base.endsWith(' ') ? '' : ' ';
    _input.text = '$base$sep\$$symbol ';
    _input.selection = TextSelection.fromPosition(
      TextPosition(offset: _input.text.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final c = widget.community;
    final accent = SocialTokens.regionColor(c.regionCode);
    final todayLabel = 'fullChat.today'.tr;

    return Scaffold(
      backgroundColor: palette.background,
      // resizeToAvoidBottomInset: true (default) so the input lifts above keyboard
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        titleSpacing: 0,
        iconTheme: IconThemeData(color: palette.textPrimary),
        leading: IconButton(
          icon: const DirectionalIcon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _ChatHeader(
          community: c,
          accent: accent,
          palette: palette,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: palette.textPrimary),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: palette.textPrimary),
            onPressed: () {},
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: palette.subtleDivider),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              physics: const BouncingScrollPhysics(),
              // +1 for the "TODAY" header that floats at the top of the list.
              itemCount: _messages.length + 1,
              itemBuilder: (_, i) {
                if (i == _messages.length) {
                  return _DateSeparator(palette: palette, label: todayLabel);
                }
                final realIndex = _messages.length - 1 - i;
                final msg = _messages[realIndex];
                final prev = realIndex > 0 ? _messages[realIndex - 1] : null;
                final showAuthor = prev == null || prev.author != msg.author;
                return _MessageBubble(
                  palette: palette,
                  message: msg,
                  showAuthor: showAuthor,
                );
              },
            ),
          ),
          _SymbolQuickInsertBar(
            palette: palette,
            tickers: widget.community.liveTickers,
            onTap: _insertTicker,
          ),
          _ChatInputBar(
            palette: palette,
            controller: _input,
            focusNode: _focus,
            hasText: _hasText,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Slim chat header (community avatar + name + active count)
// ============================================================================
class _ChatHeader extends StatelessWidget {
  final Community community;
  final Color accent;
  final SocialPalette palette;
  const _ChatHeader({
    required this.community,
    required this.accent,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: LinearGradient(
              colors: [accent, accent.withValues(alpha: 0.55)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.30),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            community.regionCode,
            style: const TextStyle(
              color: Color(0xFF0A1628),
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                community.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: SocialTokens.up,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${community.activeNow} ${'fullChat.activeNow'.tr}',
                    style: const TextStyle(
                      color: SocialTokens.up,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// Date separator chip
// ============================================================================
class _DateSeparator extends StatelessWidget {
  final SocialPalette palette;
  final String label;
  const _DateSeparator({required this.palette, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: palette.subtleDivider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: palette.subtleDivider)),
        ],
      ),
    );
  }
}

// ============================================================================
// Message bubble (avatar + bubble + tickers)
// ============================================================================
class _MessageBubble extends StatelessWidget {
  final SocialPalette palette;
  final ChatMessage message;
  final bool showAuthor;

  const _MessageBubble({
    required this.palette,
    required this.message,
    required this.showAuthor,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isCurrentUser;
    final accent = isMe ? SocialTokens.cyan : _avatarColorFor(message.author);

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: isMe
            ? SocialTokens.cyan.withValues(alpha: 0.18)
            : palette.surface,
        border: Border.all(
          color: isMe
              ? SocialTokens.cyan.withValues(alpha: 0.4)
              : palette.border,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isMe ? 14 : (showAuthor ? 4 : 14)),
          topRight: Radius.circular(isMe ? (showAuthor ? 4 : 14) : 14),
          bottomLeft: const Radius.circular(14),
          bottomRight: const Radius.circular(14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.body,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          if (message.tickers.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: message.tickers
                  .map(
                    (t) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: SocialTokens.cyan.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '\$$t',
                        style: const TextStyle(
                          color: SocialTokens.cyan,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );

    final headerLine = showAuthor
        ? Padding(
            padding: EdgeInsets.fromLTRB(
              isMe ? 0 : 38,
              0,
              isMe ? 38 : 0,
              4,
            ),
            child: Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Text(
                  message.author,
                  style: TextStyle(
                    color: isMe ? SocialTokens.cyan : palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  message.timeAgo,
                  style: TextStyle(color: palette.textMuted, fontSize: 10),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final avatar = SizedBox(
      width: 30,
      height: 30,
      child: showAuthor
          ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [accent, accent.withValues(alpha: 0.55)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                _initials(message.author),
                style: const TextStyle(
                  color: Color(0xFF0A1628),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: -0.5,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );

    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.74;

    return Padding(
      padding: EdgeInsets.only(top: showAuthor ? 8 : 2),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          headerLine,
          Row(
            mainAxisAlignment:
                isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                avatar,
                const SizedBox(width: 8),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: bubble,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 8),
                avatar,
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Color _avatarColorFor(String name) {
    final hash = name.codeUnits.fold<int>(0, (a, b) => a + b);
    final hue = (hash * 47) % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.62).toColor();
  }
}

// ============================================================================
// Quick-insert symbol bar — tap to inject $TICKER into the input
// ============================================================================
class _SymbolQuickInsertBar extends StatelessWidget {
  final SocialPalette palette;
  final List<TickerQuote> tickers;
  final ValueChanged<String> onTap;

  const _SymbolQuickInsertBar({
    required this.palette,
    required this.tickers,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border(top: BorderSide(color: palette.subtleDivider)),
      ),
      child: Row(
        children: [
          Icon(Icons.add_chart_rounded, size: 14, color: palette.textMuted),
          const SizedBox(width: 5),
          Text(
            'fullChat.insertSymbol'.tr.toUpperCase(),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: tickers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final t = tickers[i];
                return GestureDetector(
                  onTap: () => onTap(t.symbol),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ShariahGradeChip(grade: t.shariahGrade, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          '\$${t.symbol}',
                          style: const TextStyle(
                            color: SocialTokens.cyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Chat input bar (multi-line text + animated send)
// ============================================================================
class _ChatInputBar extends StatelessWidget {
  final SocialPalette palette;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final VoidCallback onSend;

  const _ChatInputBar({
    required this.palette,
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.subtleDivider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.add_circle_outline_rounded,
                        color: palette.textMuted,
                        size: 22,
                      ),
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                    ),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'fullChat.typeMessage'.tr,
                          hintStyle: TextStyle(color: palette.textMuted),
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.sentiment_satisfied_rounded,
                        color: palette.textMuted,
                        size: 22,
                      ),
                      onPressed: () {},
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: hasText
                    ? const LinearGradient(
                        colors: [SocialTokens.cyan, SocialTokens.cyanSoft],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: hasText ? null : palette.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(
                  color: hasText ? SocialTokens.cyan : palette.border,
                ),
                boxShadow: hasText
                    ? [
                        BoxShadow(
                          color: SocialTokens.cyan.withValues(alpha: 0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: hasText ? onSend : null,
                  customBorder: const CircleBorder(),
                  child: Center(
                    child: Icon(
                      Icons.send_rounded,
                      size: 19,
                      color: hasText
                          ? const Color(0xFF0A1628)
                          : palette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
