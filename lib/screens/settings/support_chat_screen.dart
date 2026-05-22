import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/realtime_controller.dart';
import '../../localization/locale_format.dart';
import '../../services/support_service.dart';
import '../../utils/haptic_utils.dart';
import '../social/social_tokens.dart';

/// Contact Admin — built-in user ↔ admin support chat.
///
/// Mounted from Profile → Help & Support. Shows the user's single
/// thread (auto-created server-side on first open), renders every
/// message + a composer, and listens to realtime
/// `support_message_*` events so admin replies appear live without
/// pull-to-refresh.
///
/// Notifications:
///   * Opening this screen calls `markRead()` → zeroes unread_user
///     on the backend so the bell stops blinking on the user's other
///     devices.
///   * Incoming admin reply (live realtime event) triggers a haptic
///     tick + plays the system selection click.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  bool _loading = true;
  bool _sending = false;
  String? _error;

  SupportThread? _thread;
  List<SupportMessage> _messages = const [];

  StreamSubscription<dynamic>? _rtSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final res = await SupportService.myMessages();
    if (!mounted) return;
    setState(() {
      _thread = res.thread;
      _messages = res.messages;
      _loading = false;
      _error = res.error;
    });
    // Mark anything currently unread as read — fire-and-forget; the
    // backend handler is idempotent.
    SupportService.markRead();
    // Live updates: listen for support_message_sent events on the
    // realtime hub. We filter to events that belong to the current
    // user's thread; admin replies should append, user echoes (multi-
    // device) should also append and dedupe on id.
    final rt = Get.isRegistered<RealtimeController>()
        ? Get.find<RealtimeController>()
        : null;
    _rtSub = rt?.events.listen(_onRealtime);
    _scrollToBottomLater();
  }

  void _onRealtime(dynamic ev) {
    final type = (ev as dynamic).type as String? ?? '';
    if (type == 'support_thread_closed') {
      if (!mounted) return;
      setState(() {
        _thread = _thread?.copyWith(status: 'closed');
      });
      return;
    }
    // Pin / unpin (mig 0030).
    if (type == 'support_thread_pinned' || type == 'support_thread_unpinned') {
      final data = ((ev as dynamic).data as Map?) ?? const {};
      if (_thread == null) return;
      final threadId = (data['threadId'] as num?)?.toInt() ?? 0;
      if (threadId != _thread!.id) return;
      final pinned = (data['pinnedMessageId'] as num?)?.toInt();
      if (!mounted) return;
      setState(() {
        _thread = pinned == null
            ? _thread!.copyWith(clearPin: true)
            : _thread!.copyWith(pinnedMessageId: pinned);
      });
      return;
    }
    if (!type.startsWith('support_message_')) return;
    final data = ((ev as dynamic).data as Map?) ?? const {};
    final threadId = (data['threadId'] as num?)?.toInt() ?? 0;
    if (_thread == null || threadId != _thread!.id) return;

    final messageId = (data['messageId'] as num?)?.toInt() ?? 0;
    if (messageId == 0) return;

    // Mig 0030 — edit / soft-delete events update an existing row in
    // place rather than appending a new bubble.
    if (type == 'support_message_edited') {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map(
              (m) => m.id == messageId
                  ? m.copyWith(
                      body: data['body']?.toString() ?? m.body,
                      editedAt: DateTime.tryParse(
                            data['editedAt']?.toString() ?? '',
                          ) ??
                          DateTime.now(),
                    )
                  : m,
            )
            .toList();
      });
      return;
    }
    if (type == 'support_message_deleted') {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map(
              (m) => m.id == messageId
                  ? m.copyWith(
                      deletedAt: DateTime.tryParse(
                            data['deletedAt']?.toString() ?? '',
                          ) ??
                          DateTime.now(),
                    )
                  : m,
            )
            .toList();
      });
      return;
    }

    // 'sent' — new bubble. Dedupe on id (handles the optimistic-append
    // race we fixed earlier).
    if (_messages.any((m) => m.id == messageId)) return;
    final senderRole = data['senderRole']?.toString() ?? '';
    final msg = SupportMessage(
      id: messageId,
      threadId: threadId,
      senderUserId: (data['senderUserId'] as num?)?.toInt() ?? 0,
      senderRole: senderRole,
      senderName: '',
      body: data['body']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
              DateTime.now(),
    );

    if (!mounted) return;
    setState(() => _messages = [..._messages, msg]);
    _scrollToBottomLater();

    // Notify the user about admin replies — gentle haptic + the same
    // mark-read call so the bell doesn't blink redundantly if the
    // screen is already open.
    if (senderRole == 'admin') {
      HapticFeedback.selectionClick();
      SupportService.markRead();
    }
  }

  Future<void> _editMessage(SupportMessage msg) async {
    final ctl = TextEditingController(text: msg.body);
    final focus = FocusNode();
    final palette = SocialTheme.of(context);
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        // Request focus AFTER layout. `autofocus: true` requests focus
        // during the sheet's first build, which races the keyboard-inset
        // relayout and trips a framework assertion (_dependents.isEmpty).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (focus.context != null && !focus.hasFocus) focus.requestFocus();
        });
        final inset = MediaQuery.of(sheetCtx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: inset),
          child: Container(
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(color: palette.border),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: palette.textMuted.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Text(
                    'support.edit.title'.tr,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctl,
                    focusNode: focus,
                    minLines: 2,
                    maxLines: 6,
                    maxLength: 2000,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: palette.surfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.border),
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(),
                          child: Text('common.cancel'.tr),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(sheetCtx).pop(
                            ctl.text.trim(),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SocialTokens.cyan,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'common.save'.tr,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    ctl.dispose();
    focus.dispose();
    if (saved == null || saved.isEmpty || saved == msg.body) return;
    if (!mounted) return;
    final res = await SupportService.editMine(msg.id, saved);
    if (!mounted) return;
    if (res.message != null) {
      // Optimistic apply — realtime echo dedupes via id+editedAt
      // comparison in _onRealtime (same body, same id → no-op).
      setState(() {
        _messages = _messages
            .map((m) => m.id == res.message!.id ? res.message! : m)
            .toList();
      });
      HapticUtils.lightTap();
    } else if (res.error != null) {
      Get.snackbar(
        'support.editFailed'.tr,
        res.error!,
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  void _onLongPressMessage(SupportMessage msg) {
    // Only the user's OWN, non-deleted messages can be edited from the
    // mobile side. Admin actions (delete / pin) happen on the dashboard.
    if (!msg.isUser || msg.isDeleted) return;
    HapticFeedback.selectionClick();
    _editMessage(msg);
  }

  void _scrollToBottomLater() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final res = await SupportService.send(text);
    if (!mounted) return;
    if (res.message != null) {
      _composer.clear();
      // Optimistic append — but the WS echo on `support_message_sent`
      // can race ahead of our HTTP response (pg_notify fires in
      // microseconds, the HTTP round-trip takes milliseconds). If the
      // echo already added this exact message id, skip — otherwise we
      // get a duplicate bubble that only clears on full refresh.
      final alreadyShown =
          _messages.any((m) => m.id == res.message!.id);
      setState(() {
        if (!alreadyShown) {
          _messages = [..._messages, res.message!];
        }
        _sending = false;
      });
      HapticUtils.lightTap();
      _scrollToBottomLater();
      return;
    }
    setState(() {
      _sending = false;
      _error = res.error;
    });
    if (res.rateLimited) {
      Get.snackbar(
        'support.rateLimited.title'.tr,
        res.error ?? 'support.rateLimited.body'.tr,
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final isClosed = _thread?.isClosed ?? false;
    final auth = Get.find<AuthController>();
    // A friendly fallback when the user has no name or email; the
    // translation provides an informal placeholder per locale.
    final userName = auth.user?.name ??
        auth.user?.email.split('@').first ??
        'support.empty.nameFallback'.tr;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.background,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SocialTokens.cyan.withValues(alpha: 0.16),
                border: Border.all(
                  color: SocialTokens.cyan.withValues(alpha: 0.45),
                ),
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: SocialTokens.cyan,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'support.title'.tr,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    isClosed
                        ? 'support.subtitle.closed'.tr
                        : 'support.subtitle.replyWindow'.tr,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Mig 0030 — sticky pinned-message strip. Renders only when
          // the admin has pinned a message in this thread; tap to
          // scroll to it.
          if (_thread?.pinnedMessageId != null)
            _PinnedStrip(
              palette: palette,
              message: _messages.firstWhere(
                (m) => m.id == _thread!.pinnedMessageId,
                orElse: () => SupportMessage(
                  id: _thread!.pinnedMessageId!,
                  threadId: _thread!.id,
                  senderUserId: 0,
                  senderRole: 'admin',
                  senderName: '',
                  body: 'support.pinned.fallback'.tr,
                  createdAt: DateTime.now(),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: SocialTokens.cyan,
                    ),
                  )
                : _messages.isEmpty
                    ? _EmptyHint(
                        palette: palette,
                        name: userName,
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _MessageBubble(
                          key: ValueKey(_messages[i].id),
                          palette: palette,
                          msg: _messages[i],
                          onLongPress: () =>
                              _onLongPressMessage(_messages[i]),
                        ),
                      ),
          ),
          if (_error != null && !_loading)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              color: SocialTokens.down.withValues(alpha: 0.10),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: SocialTokens.down,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          _Composer(
            palette: palette,
            controller: _composer,
            disabled: _sending,
            isClosed: isClosed,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ── empty state ─────────────────────────────────────────────────────
class _EmptyHint extends StatelessWidget {
  final SocialPalette palette;
  final String name;
  const _EmptyHint({
    required this.palette,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SocialTokens.cyan.withValues(alpha: 0.12),
                border: Border.all(
                  color: SocialTokens.cyan.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(
                Icons.waving_hand_rounded,
                color: SocialTokens.cyan,
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'support.empty.title'.trParams({'name': name}),
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'support.empty.body'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── message bubble ──────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final SocialPalette palette;
  final SupportMessage msg;
  /// Long-press only fires for the user's own non-deleted bubbles —
  /// see _onLongPressMessage. Pass a no-op for messages that aren't
  /// edit-eligible so we don't show a phantom haptic.
  final VoidCallback? onLongPress;
  const _MessageBubble({
    super.key,
    required this.palette,
    required this.msg,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = msg.isUser;
    final isDeleted = msg.isDeleted;

    // Deleted bubbles take a calmer palette regardless of sender so
    // the eye understands they're inert.
    final color = isDeleted
        ? palette.surfaceElevated.withValues(alpha: 0.5)
        : (isUser ? SocialTokens.cyan : palette.surfaceElevated);
    final textColor = isDeleted
        ? palette.textMuted
        : (isUser ? const Color(0xFF0A1628) : palette.textPrimary);

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(isUser ? 14 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 14),
        ),
        border: (!isUser || isDeleted)
            ? Border.all(color: palette.border, width: 1)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDeleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.do_not_disturb_alt_rounded,
                    size: 14, color: palette.textMuted),
                const SizedBox(width: 6),
                Text(
                  'support.message.deleted'.tr,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            Text(
              msg.body,
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LocaleFormat.time(msg.createdAt.toLocal()),
                style: TextStyle(
                  color: isUser && !isDeleted
                      ? const Color(0xFF0A1628).withValues(alpha: 0.6)
                      : palette.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (msg.isEdited && !isDeleted) ...[
                const SizedBox(width: 4),
                Text(
                  'support.message.edited'.tr,
                  style: TextStyle(
                    color: isUser
                        ? const Color(0xFF0A1628).withValues(alpha: 0.6)
                        : palette.textMuted,
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: bubble,
            ),
          ),
        ],
      ),
    );
  }
}

// ── pinned strip ────────────────────────────────────────────────────
class _PinnedStrip extends StatelessWidget {
  final SocialPalette palette;
  final SupportMessage message;
  const _PinnedStrip({
    required this.palette,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: SocialTokens.gold.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(
            color: SocialTokens.gold.withValues(alpha: 0.30),
            width: 1,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(
            Icons.push_pin_rounded,
            color: SocialTokens.gold,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'support.pinned.label'.tr,
                  style: const TextStyle(
                    color: SocialTokens.gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.isDeleted
                      ? 'support.pinned.deleted'.tr
                      : message.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontStyle:
                        message.isDeleted ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── composer ────────────────────────────────────────────────────────
class _Composer extends StatelessWidget {
  final SocialPalette palette;
  final TextEditingController controller;
  final bool disabled;
  final bool isClosed;
  final VoidCallback onSend;
  const _Composer({
    required this.palette,
    required this.controller,
    required this.disabled,
    required this.isClosed,
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
          border: Border(
            top: BorderSide(color: palette.border, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: palette.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: palette.border),
                ),
                child: TextField(
                  controller: controller,
                  enabled: !disabled,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: isClosed
                        ? 'support.composer.hintReopen'.tr
                        : 'support.composer.hint'.tr,
                    hintStyle: TextStyle(
                      color: palette.textMuted,
                      fontSize: 13.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    counterText: '',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: SocialTokens.cyan,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: disabled ? null : onSend,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.send_rounded,
                    color: disabled
                        ? Colors.black.withValues(alpha: 0.4)
                        : Colors.black,
                    size: 20,
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
