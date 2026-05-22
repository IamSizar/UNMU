import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../config/api_config.dart';
import '../../models/expert_post.dart' show resolveUrl;
import '../../controllers/auth_controller.dart';
import '../../controllers/chat_presence_controller.dart';
import '../../controllers/language_controller.dart';
import '../../controllers/mute_controller.dart';
import '../../controllers/realtime_controller.dart';
import '../../services/community_messages_service.dart' as svc;
import '../../services/realtime_service.dart';
import '../../widgets/social/chat_search_bar.dart';
import '../../widgets/social/poll_bubble.dart';
import '../../widgets/social/poll_creator_sheet.dart';
import '../../widgets/social/read_receipts_strip.dart';
import '../../widgets/social/ticker_card.dart';
import '../../widgets/social/typing_pill.dart';
import 'mock_social_data.dart';
import 'social_tokens.dart';

/// Standalone full-page community chat. Reached via the chat icon in
/// the [CommunityDetailScreen]'s AppBar. Pure UI scaffold — no
/// websocket, no persistence. The thread is pre-seeded from the
/// community's mock member roster so the page feels alive on first
/// paint, and tapping send appends a "you" bubble in-place (cleared
/// when the screen is popped).
///
/// All chat-related types are private to this file.
class CommunityChatScreen extends StatefulWidget {
  final Community community;
  const CommunityChatScreen({super.key, required this.community});

  @override
  State<CommunityChatScreen> createState() => _CommunityChatScreenState();
}

class _CommunityChatScreenState extends State<CommunityChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  // Real message thread, hydrated by an initial GET on mount and kept
  // in sync via the WebSocket `community_message` event for this
  // community. Stored chronologically (oldest → newest), which is
  // how the ListView paints them top-to-bottom.
  List<svc.CommunityMessage> _messages = const [];

  bool _loading = true;
  bool _sending = false;
  String? _loadError; // null = OK; any other = render empty + error banner
  String? _sendError; // shown briefly under the composer if a send fails

  // Realtime subscription — listens on every event, filters in the
  // handler. Disposed on widget tear-down.
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  // Reply-to state. Non-null while the user has a "Replying to X"
  // strip visible above the composer. Set by [_startReplyTo] from
  // the long-press action sheet, cleared on send or cancel.
  svc.CommunityMessage? _replyingTo;

  // Highlight pulse — when the user taps a quote preview the matching
  // parent bubble flashes its border with this controller's value.
  // Single controller is enough because only one bubble can be
  // "currently highlighted" at a time.
  late final AnimationController _highlightCtrl;
  int? _highlightedMessageId;

  // ── Voice recording state ────────────────────────────────────────
  // The `record` package's recorder. Lazily allocated on first
  // record-start, reused for the lifetime of this screen, disposed
  // in [dispose].
  AudioRecorder? _recorder;
  // Disk path of the in-progress recording. While non-null we render
  // the recording strip instead of the normal composer.
  String? _recordingPath;
  // Wall-clock time the current recording started — drives the live
  // mm:ss timer on the recording strip.
  DateTime? _recordingStartedAt;
  // Tick timer that rebuilds the timer text every 200ms during a
  // recording. Cancelled on stop / cancel.
  Timer? _recordingTicker;
  // True while a stop+upload is in flight — disables the send button
  // so a quick double-tap can't fire two POSTs.
  bool _uploadingAudio = false;
  // Reactive notifier for the timer text. Putting this on a tiny
  // ValueNotifier instead of setState lets us rebuild only the
  // timer label every tick instead of the whole composer.
  final ValueNotifier<int> _recordingMs = ValueNotifier<int>(0);

  // ── Step-21 (mig 0021, item 5.19) — typing indicators ──
  // Active typers; entries auto-prune after 6s of silence.
  final List<_TypingUser> _typing = [];
  Timer? _typingJanitor;
  // Composer-side: tracks whether we last sent `started` so we don't
  // spam the endpoint on every keystroke.
  bool _typingSent = false;
  Timer? _typingDebounce;

  // ── Step-21 (mig 0021, item 5.17) — chat search overlay state ──
  bool _searching = false;

  // Single global "currently playing" tracker so tapping a different
  // bubble's play button stops the previous one. Lives on the
  // screen state because all audio bubbles in the same chat share
  // the same parent.
  int? _activePlaybackMessageId;
  void _claimPlayback(int messageId) {
    if (_activePlaybackMessageId == messageId) return;
    final prev = _activePlaybackMessageId;
    _activePlaybackMessageId = messageId;
    if (prev != null) _stopPlaybackRequests.add(prev);
  }

  // One-shot signal sink — _AudioBubble subscribes by id and
  // pause-on-message. Using a broadcast stream so multiple
  // bubbles can listen without stepping on each other.
  final StreamController<int> _stopPlaybackRequests =
      StreamController<int>.broadcast();

  // Whether to show the floating "scroll to bottom" FAB. Driven by
  // the scroll listener — toggled to true when the user scrolls
  // > 300px above the latest message.
  bool _showScrollFab = false;
  // Set to true when a new message lands while we're scrolled up,
  // so the FAB shows a small unread dot.
  bool _scrollFabHasUnread = false;

  @override
  void initState() {
    super.initState();
    _highlightCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          if (mounted) setState(() => _highlightedMessageId = null);
        }
      });
    _load();
    _wireRealtime();
    // Tell the global banner: "user is reading THIS community now,
    // skip toasts for it." Cleared in dispose.
    try {
      Get.find<ChatPresenceController>().setActive(widget.community.id);
    } catch (_) {/* presence not registered yet */}
    _scroll.addListener(_onScroll);
    _composer.addListener(_onComposerChanged);
    // Step-21 (mig 0021, item 5.19) — periodic janitor that drops
    // typing entries older than 6s. Without it a stale `started`
    // event with no follow-up `stopped` would pin the pill forever.
    _typingJanitor = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final stale = _typing
          .where((t) => now.difference(t.startedAt).inSeconds > 6)
          .toList();
      if (stale.isEmpty) return;
      setState(() {
        for (final s in stale) {
          _typing.remove(s);
        }
      });
    });
  }

  // Step-21 (mig 0021, item 5.19) — composer-side typing emitter.
  // Sends `typing_started` on first keystroke after blank, then
  // `typing_stopped` after 5s of silence (debounced).
  void _onComposerChanged() {
    final hasText = _composer.text.trim().isNotEmpty;
    if (hasText) {
      if (!_typingSent) {
        _typingSent = true;
        svc.CommunityMessagesService.sendTyping(widget.community.id);
      }
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        _typingSent = false;
        svc.CommunityMessagesService.sendTyping(
          widget.community.id,
          stopped: true,
        );
      });
    } else if (_typingSent) {
      _typingSent = false;
      _typingDebounce?.cancel();
      svc.CommunityMessagesService.sendTyping(
        widget.community.id,
        stopped: true,
      );
    }
  }

  /// Drives the scroll-to-bottom FAB visibility — flips when the
  /// user scrolls more than ~300px above the latest message.
  /// Hot-path callback, so we early-return when the state would
  /// not actually change (avoids excess setState).
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final shouldShow = p.maxScrollExtent - p.pixels > 300;
    if (shouldShow != _showScrollFab) {
      setState(() {
        _showScrollFab = shouldShow;
        // When the FAB hides (user reached the bottom), clear the
        // unread dot — they've now seen everything.
        if (!shouldShow) _scrollFabHasUnread = false;
      });
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    HapticFeedback.selectionClick();
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  // Step-21 (mig 0021, item 5.21) — opens the poll-creator sheet,
  // then fires createPoll on submit. The host message arrives via
  // the realtime fan-out a moment later (de-dupe by id) so we don't
  // need to optimistically prepend.
  Future<void> _openPollComposer(bool isArabic) async {
    final result = await PollCreatorSheet.show(context);
    if (result == null || !mounted) return;
    final res = await svc.CommunityMessagesService.createPoll(
      communityId: widget.community.id,
      question: result.question,
      options: result.options,
      isAnonymous: result.isAnonymous,
      expiresInHours: result.expiresInHours,
    );
    if (!mounted) return;
    if (res.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(res.error!),
        behavior: SnackBarBehavior.floating,
        backgroundColor: SocialTokens.down,
      ));
    }
  }

  @override
  void dispose() {
    try {
      Get.find<ChatPresenceController>().clearActive(widget.community.id);
    } catch (_) {}
    _realtimeSub?.cancel();
    _typingJanitor?.cancel();
    _typingDebounce?.cancel();
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _highlightCtrl.dispose();
    // Voice recording teardown — cancel any in-flight recording so
    // the recorder releases the mic + the temp file gets cleaned up.
    _recordingTicker?.cancel();
    _recorder?.dispose();
    _stopPlaybackRequests.close();
    _recordingMs.dispose();
    super.dispose();
  }

  /// Initial fetch — newest 50 messages. Backend returns newest-first;
  /// we reverse here so the rendered list reads chronologically
  /// (oldest at top, newest at bottom — matching every modern chat UI).
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await svc.CommunityMessagesService.list(widget.community.id);
    if (!mounted) return;
    if (res.error != null && res.messages == null) {
      setState(() {
        _loading = false;
        _loadError = res.error;
        _messages = const [];
      });
      return;
    }
    setState(() {
      _loading = false;
      _messages = (res.messages ?? []).reversed.toList(growable: true);
    });
    // Land at the bottom on first paint — newest messages are the
    // ones the user wants to see.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  /// Subscribe to the global realtime event stream. The WS hub
  /// auto-subscribed us to `community:<id>` on connect, so we just
  /// need to filter by event type + community id and append.
  void _wireRealtime() {
    final RealtimeController rt;
    try {
      rt = Get.find<RealtimeController>();
    } catch (_) {
      return; // realtime controller not registered (offline dev mode)
    }
    _realtimeSub = rt.events.listen((ev) {
      // ── New chat message ───────────────────────────
      if (ev.type == 'community_message') {
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        // Construct from the fan-out payload — same JSON shape as the
        // REST list response.
        final m = svc.CommunityMessage.fromJson(ev.data);
        // De-dupe — the sender also receives this event on top of the
        // POST response. Compare by id.
        if (_messages.any((existing) => existing.id == m.id)) return;
        if (!mounted) return;
        // If the user has scrolled up away from the bottom, light
        // the FAB's unread dot instead of yanking the list to the
        // newest message — that's a Telegram-style affordance.
        final wasAwayFromBottom = _scroll.hasClients &&
            (_scroll.position.maxScrollExtent - _scroll.position.pixels) > 80;
        if (wasAwayFromBottom) {
          // Subtle haptic so the user FEELS the new message even
          // when their eyes are on history. Same energy as iMessage's
          // incoming-message tap.
          HapticFeedback.selectionClick();
        }
        setState(() {
          _messages = [..._messages, m];
          if (wasAwayFromBottom) _scrollFabHasUnread = true;
        });
        if (!wasAwayFromBottom) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) {
              _scroll.animateTo(
                _scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });
        }
        return;
      }
      // ── Message pinned / unpinned ──────────────────
      if (ev.type == 'community_message_pinned') {
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        final mid = (ev.data['messageId'] as num?)?.toInt() ?? 0;
        if (mid <= 0) return;
        final pinned = ev.data['pinned'] as bool? ?? false;
        final pinnedAtRaw = ev.data['pinnedAt']?.toString();
        final pinnedAt = pinnedAtRaw == null || pinnedAtRaw.isEmpty
            ? null
            : DateTime.tryParse(pinnedAtRaw);
        if (!mounted) return;
        setState(() {
          _messages = _messages
              .map((x) => x.id == mid
                  ? x.copyWithPin(
                      pinnedAt: pinned ? pinnedAt : null,
                      clearPin: !pinned,
                    )
                  : x)
              .toList();
        });
        return;
      }
      // ── Message deleted ────────────────────────────
      if (ev.type == 'community_message_deleted') {
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        final mid = (ev.data['messageId'] as num?)?.toInt() ?? 0;
        if (mid <= 0) return;
        if (!mounted) return;
        // De-dupe — if we already removed it locally (the deleter
        // already updated their own UI optimistically), this is a
        // no-op for them.
        if (!_messages.any((m) => m.id == mid)) return;
        setState(() {
          _messages = _messages.where((m) => m.id != mid).toList();
        });
        return;
      }
      // ── Reaction patch ─────────────────────────────
      if (ev.type == 'community_message_reaction') {
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        final mid = (ev.data['messageId'] as num?)?.toInt() ?? 0;
        if (mid <= 0) return;
        final myId = Get.find<AuthController>().user?.id ?? -1;
        final actorId = (ev.data['userId'] as num?)?.toInt() ?? 0;
        final emoji = ev.data['emoji']?.toString() ?? '';
        final added = ev.data['added'] as bool? ?? false;
        final rawCounts = ev.data['counts'];
        final counts = <String, int>{};
        if (rawCounts is Map) {
          rawCounts.forEach((k, v) {
            if (k is String && v is num) counts[k] = v.toInt();
          });
        }
        if (!mounted) return;
        setState(() {
          _messages = _messages.map((existing) {
            if (existing.id != mid) return existing;
            // Only patch the viewer's myReactions when it's the
            // viewer's own action — otherwise we'd flip another
            // user's reaction onto the local viewer state.
            //
            // One-reaction-per-user rule: on `added` the viewer's
            // set becomes exactly {emoji} (replacing whatever was
            // there); on `removed` it becomes empty.
            Set<String>? newMine;
            if (actorId == myId && emoji.isNotEmpty) {
              newMine = added ? <String>{emoji} : <String>{};
            }
            return existing.copyWithReactions(
              reactionCounts: counts,
              myReactions: newMine,
            );
          }).toList();
        });
        return;
      }
      // ── Step-21 (mig 0021, item 5.22) — message edited ───
      if (ev.type == 'community_message_edited') {
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        final updated = svc.CommunityMessage.fromJson(ev.data);
        if (!mounted) return;
        setState(() {
          _messages = _messages
              .map((m) => m.id == updated.id ? updated : m)
              .toList();
        });
        return;
      }
      // ── Step-21 (mig 0021, item 5.18) — read receipt patches ──
      if (ev.type == 'message_read' || ev.type == 'message_read_batch') {
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        // Best-effort: bump readCount by 1 on the affected message(s).
        // Authoritative count arrives on the next List() call; this
        // gives instant UX feedback without a fetch.
        final myId = Get.find<AuthController>().user?.id ?? -1;
        final actorId = (ev.data['userId'] as num?)?.toInt() ?? 0;
        if (actorId == myId) return; // never bump on own reads
        final ids = <int>{};
        final rawSingle = (ev.data['messageId'] as num?)?.toInt();
        if (rawSingle != null && rawSingle > 0) ids.add(rawSingle);
        final rawList = ev.data['messageIds'];
        if (rawList is List) {
          for (final e in rawList) {
            if (e is num) ids.add(e.toInt());
          }
        }
        if (ids.isEmpty) return;
        if (!mounted) return;
        setState(() {
          _messages = _messages.map((m) {
            if (!ids.contains(m.id)) return m;
            return m.copyWith(readCount: m.readCount + 1);
          }).toList();
        });
        return;
      }
      // ── Step-21 (mig 0021, item 5.21) — poll vote / close ────
      if (ev.type == 'poll_voted' || ev.type == 'poll_closed') {
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        // poll_closed sometimes wraps the message under a "message"
        // key; poll_voted broadcasts the message struct directly.
        final raw = ev.data['message'] is Map<String, dynamic>
            ? ev.data['message'] as Map<String, dynamic>
            : ev.data;
        final updated = svc.CommunityMessage.fromJson(raw);
        if (!mounted) return;
        setState(() {
          _messages = _messages
              .map((m) => m.id == updated.id ? updated : m)
              .toList();
        });
        return;
      }
      // ── Step-21 (mig 0021, item 5.19) — typing indicators ────
      if (ev.type == 'typing_started' || ev.type == 'typing_stopped') {
        final cid = ev.data['communityId']?.toString() ?? '';
        if (cid != widget.community.id) return;
        final actorId = (ev.data['userId'] as num?)?.toInt() ?? 0;
        final name = ev.data['name']?.toString() ?? '';
        final myId = Get.find<AuthController>().user?.id ?? -1;
        if (actorId == myId || actorId == 0 || name.isEmpty) return;
        if (!mounted) return;
        if (ev.type == 'typing_started') {
          setState(() {
            _typing.removeWhere((t) => t.userId == actorId);
            _typing.insert(0, _TypingUser(actorId, name, DateTime.now()));
          });
        } else {
          setState(() {
            _typing.removeWhere((t) => t.userId == actorId);
          });
        }
        return;
      }
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.lightImpact();
    final replyParent = _replyingTo;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    final res = await svc.CommunityMessagesService.send(
      widget.community.id,
      text,
      parentId: replyParent?.id,
    );
    if (!mounted) return;
    if (res.error != null) {
      // Heavy haptic on send failure — matches the iOS "task
      // failed" feel and the visible inline error banner above the
      // composer.
      HapticFeedback.heavyImpact();
      setState(() {
        _sending = false;
        _sendError = res.error;
      });
      return;
    }
    final saved = res.message!;
    setState(() {
      _sending = false;
      _composer.clear();
      _replyingTo = null; // drop the reply strip after a successful send
      // Append immediately if the realtime event hasn't already
      // landed. Either path keeps the bubble visible without a
      // visible delay.
      if (!_messages.any((m) => m.id == saved.id)) {
        _messages = [..._messages, saved];
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Long-press handler — pops a floating action overlay anchored to
  /// the long-pressed bubble. The overlay carries:
  ///
  ///   * a row of the curated emojis (👏 👍 👎 🔥) — tap to toggle the
  ///     reaction on this message,
  ///   * Reply / Copy chips below the emojis.
  ///
  /// Auto-positioning: if the bubble is closer to the bottom of the
  /// screen, the overlay floats above it; otherwise below. Tapping
  /// the dimmed scrim dismisses without doing anything.
  void _showMessageActions(
    svc.CommunityMessage m,
    bool isArabic,
    Rect anchor,
    bool isMe,
  ) {
    HapticFeedback.selectionClick();
    final palette = SocialTheme.of(context);
    final accent = SocialTokens.regionColor(widget.community.regionCode);
    final overlay = Overlay.of(context, rootOverlay: true);
    OverlayEntry? entry;
    void close() {
      entry?.remove();
      entry = null;
    }

    entry = OverlayEntry(
      builder: (overlayCtx) => _MessageActionOverlay(
        anchor: anchor,
        message: m,
        accent: accent,
        palette: palette,
        isMe: isMe,
        onDismiss: close,
        onPickEmoji: (emoji) {
          close();
          _toggleReaction(m, emoji);
        },
        onReply: () {
          close();
          _startReplyTo(m);
        },
        onCopy: () {
          close();
          Clipboard.setData(ClipboardData(text: m.body));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 1),
                content: Text('chat.copied'.tr),
              ),
            );
          }
        },
        // Surface Delete when the viewer authored the message OR
        // when they're the community owner (moderation). The
        // backend already authorizes both paths via Delete()'s
        // canModerate flag — see the repo's Delete method.
        onDelete: (isMe || _isOwner)
            ? () {
                close();
                _deleteMessage(m, isArabic);
              }
            : null,
        // Pin / unpin only for the community owner. Admins also
        // have the API-level capability but they don't get the UI
        // affordance here — same convention as Delete above.
        onTogglePin: _isOwner
            ? () {
                close();
                _togglePin(m, isArabic);
              }
            : null,
        currentlyPinned: m.isPinned,
      ),
    );
    overlay.insert(entry!);
  }

  /// True when the current viewer is the community owner. Computed
  /// once on each render rather than cached — auth state can change
  /// (test-account switch) and we want the gear/pin permissions to
  /// reflect that immediately.
  bool get _isOwner {
    final auth = Get.find<AuthController>();
    final myId = auth.user?.id;
    return widget.community.ownerId != null &&
        myId != null &&
        myId == widget.community.ownerId;
  }

  /// Toggle pin/unpin on a message. Optimistic patch + reconcile
  /// with server. The realtime broadcast will land on every
  /// connected member (including the actor) and overwrite the local
  /// state with the authoritative pinnedAt value.
  Future<void> _togglePin(svc.CommunityMessage m, bool isArabic) async {
    HapticFeedback.selectionClick();
    final wasPinned = m.isPinned;
    setState(() {
      _messages = _messages
          .map((x) => x.id == m.id
              ? x.copyWithPin(
                  pinnedAt: wasPinned ? null : DateTime.now(),
                  clearPin: wasPinned,
                )
              : x)
          .toList();
    });
    final res = await svc.CommunityMessagesService.togglePin(
      widget.community.id,
      m.id,
    );
    if (!mounted) return;
    if (res.error != null) {
      // Rollback.
      HapticFeedback.heavyImpact();
      setState(() {
        _messages = _messages
            .map((x) => x.id == m.id
                ? x.copyWithPin(
                    pinnedAt: m.pinnedAt,
                    clearPin: !wasPinned,
                  )
                : x)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(res.error!),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(
          (res.pinned ?? false)
              ? 'chat.pinned'.tr
              : 'chat.unpinned'.tr,
        ),
      ),
    );
  }

  /// Toggle [emoji] on [m]. One-reaction-per-user rule:
  ///
  ///   * tap same emoji you already have → remove it,
  ///   * tap different emoji → replace previous one,
  ///   * tap when you have nothing → add it.
  ///
  /// Optimistically patches local state so the chip flips without
  /// waiting for the network, then reconciles with the server's
  /// authoritative count map on the response.
  Future<void> _toggleReaction(svc.CommunityMessage m, String emoji) async {
    HapticFeedback.lightImpact();
    final myId = Get.find<AuthController>().user?.id ?? -1;
    if (myId <= 0) return;
    final newMine = <String>{};
    final newCounts = Map<String, int>.from(m.reactionCounts);
    final hadSame = m.myReactions.contains(emoji);
    // Decrement any existing reaction the viewer had — covers both
    // the toggle-off (same emoji) and the replace (different emoji)
    // cases. Set semantics: at most one element.
    for (final prev in m.myReactions) {
      final c = (newCounts[prev] ?? 1) - 1;
      if (c <= 0) {
        newCounts.remove(prev);
      } else {
        newCounts[prev] = c;
      }
    }
    if (!hadSame) {
      newMine.add(emoji);
      newCounts[emoji] = (newCounts[emoji] ?? 0) + 1;
    }
    setState(() {
      _messages = _messages
          .map((existing) => existing.id == m.id
              ? existing.copyWithReactions(
                  reactionCounts: newCounts,
                  myReactions: newMine,
                )
              : existing)
          .toList();
    });
    // Network round-trip — reconcile with server's authoritative
    // count map on the response.
    final res = await svc.CommunityMessagesService.toggleReaction(
      widget.community.id,
      m.id,
      emoji,
    );
    if (!mounted) return;
    if (res.error != null) {
      // Heavy haptic announces the rollback so the user knows the
      // optimistic flip just got reverted.
      HapticFeedback.heavyImpact();
      // Rollback on failure.
      setState(() {
        _messages = _messages
            .map((existing) => existing.id == m.id
                ? existing.copyWithReactions(
                    reactionCounts: m.reactionCounts,
                    myReactions: m.myReactions,
                  )
                : existing)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(res.error!),
        ),
      );
      return;
    }
    // Reconcile counts (myReactions is already correct from the
    // optimistic patch above).
    if (res.counts != null) {
      setState(() {
        _messages = _messages
            .map((existing) => existing.id == m.id
                ? existing.copyWithReactions(reactionCounts: res.counts!)
                : existing)
            .toList();
      });
    }
  }

  /// Open the "who reacted with what" detail sheet for [m]. Fetches
  /// the per-user list once, then renders grouped-by-emoji tabs.
  Future<void> _showReactorsSheet(svc.CommunityMessage m) async {
    HapticFeedback.selectionClick();
    final palette = SocialTheme.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _ReactorsSheet(
        communityId: widget.community.id,
        messageId: m.id,
        palette: palette,
      ),
    );
  }

  /// Start composing a reply to [m]. Surfaces the "Replying to …"
  /// strip above the composer + auto-focuses the text field so the
  /// user can immediately type without an extra tap.
  void _startReplyTo(svc.CommunityMessage m) {
    setState(() => _replyingTo = m);
    _composerFocus.requestFocus();
  }

  void _cancelReply() {
    HapticFeedback.selectionClick();
    setState(() => _replyingTo = null);
  }

  /// Tap-handler on a quote preview — scrolls the parent into view
  /// and runs the highlight pulse on its bubble.
  void _jumpToParent(int parentId) {
    final idx = _messages.indexWhere((m) => m.id == parentId);
    if (idx < 0) {
      // Parent isn't in the loaded window (older than the latest
      // 50). Could trigger a paginated fetch here in v2; for now
      // just no-op.
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _highlightedMessageId = parentId);
    _highlightCtrl.forward(from: 0);
    // The ListView is built off [items] (with day separators) so we
    // can't scroll-to-index reliably. Instead, scroll based on the
    // proportional position — good enough to bring the parent
    // visually close on screens with 50 messages.
    if (_scroll.hasClients) {
      final proportion = idx / (_messages.length.clamp(1, 9999));
      final target = _scroll.position.maxScrollExtent * proportion;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  /// Delete a message authored by the current user. Confirmation
  /// dialog → optimistic local remove → server DELETE → realtime
  /// broadcast lands on every other client.
  ///
  /// On failure we restore the message to its original index so the
  /// user doesn't lose context.
  Future<void> _deleteMessage(
    svc.CommunityMessage m,
    bool isArabic,
  ) async {
    HapticFeedback.selectionClick();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SocialTheme.of(context).surface,
        title: Text(
          'chat.delete.title'.tr,
          style: TextStyle(
            color: SocialTheme.of(context).textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'chat.delete.body'.tr,
          style: TextStyle(color: SocialTheme.of(context).textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'common.delete'.tr,
              style: const TextStyle(
                color: Color(0xFFFF6B7A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Optimistic remove. Capture the original index so we can
    // restore the order on failure.
    final originalIndex = _messages.indexWhere((x) => x.id == m.id);
    if (originalIndex < 0) return;
    setState(() {
      _messages = _messages.where((x) => x.id != m.id).toList();
    });
    final res = await svc.CommunityMessagesService.deleteMessage(
      widget.community.id,
      m.id,
    );
    if (!mounted) return;
    if (!res.ok) {
      // Heavy haptic on delete failure — message is reappearing,
      // user should feel that the destructive action got reverted.
      HapticFeedback.heavyImpact();
      // Roll back — re-insert at original index.
      setState(() {
        final restored = List<svc.CommunityMessage>.from(_messages);
        final idx =
            originalIndex.clamp(0, restored.length).toInt();
        restored.insert(idx, m);
        _messages = restored;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(res.error ?? 'chat.deleteFailed'.tr),
        ),
      );
    }
  }

  Future<void> _toggleMute(bool isArabic) async {
    HapticFeedback.selectionClick();
    final mute = Get.find<MuteController>();
    final nowMuted = await mute.toggle(widget.community.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(
          nowMuted ? 'chat.muted'.tr : 'chat.unmuted'.tr,
        ),
      ),
    );
  }

  // ─── Voice recording lifecycle ────────────────────────────────

  /// Start a voice recording. Permissions are requested on first
  /// invocation (`record` package handles the native prompt). On
  /// failure (denied / busy mic) shows an inline error snackbar
  /// and stays in not-recording state.
  Future<void> _startRecording(bool isArabic) async {
    if (_recordingPath != null || _uploadingAudio) return;
    HapticFeedback.lightImpact();
    _recorder ??= AudioRecorder();
    final rec = _recorder!;
    try {
      final allowed = await rec.hasPermission();
      if (!allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 2),
              content: Text('chat.voice.permissionNeeded'.tr),
            ),
          );
        }
        return;
      }
      // Use a per-recording temp file under the OS temp dir so
      // multiple cancelled-then-restarted attempts don't clobber.
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/voice_$ts.m4a';
      await rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recordingPath = path;
        _recordingStartedAt = DateTime.now();
      });
      _recordingTicker?.cancel();
      _recordingTicker = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) {
          final start = _recordingStartedAt;
          if (start == null) return;
          _recordingMs.value = DateTime.now().difference(start).inMilliseconds;
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('chat.voice.startFailed'.tr),
          ),
        );
      }
    }
  }

  /// Cancel the current recording — stops the recorder, deletes the
  /// partial file, returns to the normal composer state. Safe to
  /// call when not recording (no-op).
  Future<void> _cancelRecording() async {
    // Selection-click haptic mirrors the "start recording" light
    // tap so the bookend feels symmetric.
    HapticFeedback.selectionClick();
    final path = _recordingPath;
    final rec = _recorder;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    if (rec != null && await rec.isRecording()) {
      try {
        await rec.stop();
      } catch (_) {}
    }
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recordingPath = null;
      _recordingStartedAt = null;
    });
    _recordingMs.value = 0;
  }

  /// Stop the recording, upload it, send it as a message. On any
  /// failure the partial file is preserved and an error snackbar
  /// surfaces — the user can re-tap send to retry, or × to drop.
  Future<void> _stopAndSendRecording(bool isArabic) async {
    if (_recordingPath == null || _uploadingAudio) return;
    HapticFeedback.mediumImpact();
    final rec = _recorder;
    final start = _recordingStartedAt;
    String? path;
    try {
      path = await rec?.stop();
    } catch (_) {/* fall through — handled below */}
    path ??= _recordingPath;
    _recordingTicker?.cancel();
    _recordingTicker = null;
    final durationMs = start == null
        ? 0
        : DateTime.now().difference(start).inMilliseconds;
    if (!mounted) return;
    setState(() => _uploadingAudio = true);
    // Refuse to send a recording shorter than 400ms — usually a
    // mis-tap rather than an actual message.
    if (durationMs < 400) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          content: Text('chat.voice.tooShort'.tr),
        ),
      );
      await _cancelRecording();
      if (mounted) setState(() => _uploadingAudio = false);
      return;
    }
    final replyParent = _replyingTo;
    final res = await svc.CommunityMessagesService.sendAudio(
      widget.community.id,
      path!,
      durationMs: durationMs,
      parentId: replyParent?.id,
    );
    if (!mounted) return;
    if (res.error != null) {
      // Heavy haptic — voice upload failure is annoying enough that
      // the user should feel it without looking at the screen.
      HapticFeedback.heavyImpact();
      setState(() => _uploadingAudio = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(res.error!),
        ),
      );
      return;
    }
    final saved = res.message!;
    setState(() {
      _uploadingAudio = false;
      _recordingPath = null;
      _recordingStartedAt = null;
      _replyingTo = null;
      if (!_messages.any((m) => m.id == saved.id)) {
        _messages = [..._messages, saved];
      }
    });
    _recordingMs.value = 0;
    // Cleanup the temp file — server has its own copy now.
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final isArabic = Get.find<LanguageController>().isArabic;
    final c = widget.community;
    final accent = SocialTokens.regionColor(c.regionCode);
    final items = _withDayDividers(_messages);

    // Step-21 (mig 0021, item 5.17) — when search is active, replace
    // the regular chat with the search overlay. Tapping a result
    // closes the overlay AND scrolls to the bubble (parent supplies
    // the scroll callback).
    if (_searching) {
      return ChatSearchOverlay(
        communityId: c.id,
        onClose: () => setState(() => _searching = false),
        onJumpTo: (mid) {
          setState(() => _searching = false);
          // Scroll to the matched message id. Best-effort — if the
          // result isn't already in the cached list (older page), the
          // user lands at the bottom of what we have. A future patch
          // can paginate to the result.
          final idx = _messages.indexWhere((m) => m.id == mid);
          if (idx >= 0 && _scroll.hasClients) {
            // Approximate: each bubble ~80px. We could measure with
            // a key but this gets close enough for v1.
            final approxOffset = (_messages.length - idx) * 80.0;
            _scroll.animateTo(
              _scroll.position.maxScrollExtent - approxOffset,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            );
            setState(() => _highlightedMessageId = mid);
            _highlightCtrl.forward(from: 0);
          }
        },
      );
    }

    return Scaffold(
      backgroundColor: palette.background,
      extendBodyBehindAppBar: true,
      // resizeToAvoidBottomInset = true (default) so the composer
      // floats above the keyboard automatically.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(64),
        child: ClipRect(
          // Frosted-glass header — the chat list scrolls UNDER it,
          // bubbles peek through with a soft blur. Modern messaging
          // app aesthetic (iOS 18 Messages, Telegram).
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppBar(
              backgroundColor: palette.background.withValues(alpha: 0.65),
              elevation: 0,
              scrolledUnderElevation: 0,
              iconTheme: IconThemeData(color: palette.textPrimary),
              titleSpacing: 0,
              title: InkWell(
                // Tap anywhere on the header → back to community
                // detail. Matches Telegram/WhatsApp behavior.
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).maybePop();
                },
                child: Row(
                  children: [
                    _CommunityHeaderAvatar(
                      community: c,
                      accent: accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 15.5,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'chat.header.subtitle'.trParams(
                                {'count': _compactMembers(c.memberCount)}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: accent.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                // Step-21 (mig 0021, item 5.17) — chat search.
                IconButton(
                  tooltip: 'chat.tooltip.search'.tr,
                  icon: Icon(Icons.search_rounded,
                      color: palette.textPrimary),
                  onPressed: () => setState(() => _searching = true),
                ),
                // Mute bell — tap to toggle. Wrapped in Obx so the icon
                // updates immediately on toggle without a parent rebuild.
                Obx(() {
                  final mute = Get.find<MuteController>();
                  final muted = mute.isMuted(c.id);
                  return IconButton(
                    tooltip: muted
                        ? 'chat.tooltip.unmute'.tr
                        : 'chat.tooltip.mute'.tr,
                    icon: Icon(
                      muted
                          ? Icons.notifications_off_rounded
                          : Icons.notifications_outlined,
                      color: muted
                          ? const Color(0xFFFF6B7A)
                          : palette.textPrimary,
                    ),
                    onPressed: () => _toggleMute(isArabic),
                  );
                }),
                const SizedBox(width: 4),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(0.5),
                child: Container(
                  height: 0.5,
                  color: palette.border.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Container(
        // Subtle background gradient — region accent at the top
        // bleeding through the glass header, fading to surface
        // toward the composer. Anchors the screen visually without
        // competing with bubble content.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: 0.08),
              palette.background,
              palette.background,
            ],
            stops: const [0.0, 0.18, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                _buildBody(palette, accent, items, isArabic),
                // Pinned-message strip — sticky at the top of the
                // chat view. Renders the most-recently pinned
                // message; tap to scroll to it.
                Builder(builder: (_) {
                  final pinned = _messages
                      .where((m) => m.isPinned)
                      .toList()
                    ..sort((a, b) =>
                        b.pinnedAt!.compareTo(a.pinnedAt!));
                  if (pinned.isEmpty) return const SizedBox.shrink();
                  return Positioned(
                    top: MediaQuery.of(context).padding.top + 64 + 4,
                    left: 8,
                    right: 8,
                    child: _PinnedMessageStrip(
                      pinned: pinned.first,
                      totalPinned: pinned.length,
                      accent: accent,
                      palette: palette,
                      onTap: () => _jumpToParent(pinned.first.id),
                    ),
                  );
                }),
                if (_showScrollFab)
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: _ScrollToBottomFab(
                      onTap: () {
                        _scrollToBottom();
                        setState(() => _scrollFabHasUnread = false);
                      },
                      hasUnread: _scrollFabHasUnread,
                      accent: accent,
                      palette: palette,
                    ),
                  ),
              ],
            ),
          ),
          if (_sendError != null)
            // Inline send-error banner above the composer. Auto-clears
            // on the next successful send (resets _sendError to null).
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFFFF6B7A).withValues(alpha: 0.12),
              child: Text(
                _sendError!,
                style: const TextStyle(
                  color: Color(0xFFFF6B7A),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (_replyingTo != null)
            // "Replying to X" strip — sits between the message list
            // and the composer. Tap × to drop the reply target.
            _ReplyingToStrip(
              replyingTo: _replyingTo!,
              accent: accent,
              palette: palette,
              onCancel: _cancelReply,
            ),
          // Step-21 (mig 0021, item 5.19) — typing indicator. Sits
          // above the composer. Auto-hides when [_typing] is empty.
          TypingPill(names: _typing.map((t) => t.name).toList()),
          if (_recordingPath != null)
            _RecordingStrip(
              elapsedMs: _recordingMs,
              accent: accent,
              palette: palette,
              uploading: _uploadingAudio,
              onCancel: _cancelRecording,
              onSend: () => _stopAndSendRecording(isArabic),
            )
          else
            _ChatComposer(
              controller: _composer,
              focus: _composerFocus,
              accent: accent,
              onSend: _send,
              sending: _sending,
              onMicPressed: () => _startRecording(isArabic),
              onPollPressed: () => _openPollComposer(isArabic),
            ),
        ],
        ),
      ),
    );
  }

  Widget _buildBody(
    SocialPalette palette,
    Color accent,
    List<Object> items,
    bool isArabic,
  ) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: accent),
      );
    }
    if (_loadError != null && _messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                color: palette.textMuted,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: _load,
                child: Text('common.retry'.tr),
              ),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return _EmptyChat(palette: palette);
    }
    return ListView.builder(
      controller: _scroll,
      // Top padding clears the glass header (extendBodyBehindAppBar
      // means the list is BEHIND the AppBar; without padding the
      // first message would render under the blur).
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.of(context).padding.top + 64 + 8,
        12,
        12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item is _DaySeparator) {
          return _DaySeparatorWidget(label: item.label, palette: palette);
        }
        if (item is svc.CommunityMessage) {
          final myId = Get.find<AuthController>().user?.id ?? -1;
          // Decide whether to show the time stamp on this bubble.
          // Rule: show if (a) this is the LAST message in the
          // visible list, OR (b) the next item is a day separator,
          // OR (c) the next message is from a different author, OR
          // (d) the next message is more than 5 minutes later.
          // Otherwise the bubble is "mid-cluster" — hide the time
          // for a cleaner look (Telegram / iMessage convention).
          final next = i + 1 < items.length ? items[i + 1] : null;
          final showTime = next == null ||
              next is _DaySeparator ||
              (next is svc.CommunityMessage &&
                  (next.authorId != item.authorId ||
                      next.createdAt.difference(item.createdAt).inMinutes >=
                          5));
          // Hide the author header on bubbles that continue a
          // cluster (same author as the previous message within
          // 5 min) — same convention.
          final prev = i > 0 ? items[i - 1] : null;
          final showAuthorHeader = prev == null ||
              prev is _DaySeparator ||
              (prev is svc.CommunityMessage &&
                  (prev.authorId != item.authorId ||
                      item.createdAt.difference(prev.createdAt).inMinutes >=
                          5));
          return _ChatBubble(
            msg: item,
            accent: accent,
            ownerId: widget.community.ownerId,
            currentUserId: myId,
            showTimestamp: showTime,
            showAuthorHeader: showAuthorHeader,
            onLongPressWithAnchor: (rect, isMe) =>
                _showMessageActions(item, isArabic, rect, isMe),
            onTapParent: item.isReply
                ? () => _jumpToParent(item.parentId)
                : null,
            onTapReactionChips: () => _showReactorsSheet(item),
            highlightAnimation: _highlightedMessageId == item.id
                ? _highlightCtrl
                : null,
            onClaimPlayback: _claimPlayback,
            stopRequests: _stopPlaybackRequests.stream,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  // Insert lightweight "Today / Yesterday / <date>" dividers between
  // messages that span day boundaries.
  List<Object> _withDayDividers(List<svc.CommunityMessage> msgs) {
    final out = <Object>[];
    String? lastBucket;
    final today = _ymd(DateTime.now());
    final yesterday = _ymd(DateTime.now().subtract(const Duration(days: 1)));
    for (final m in msgs) {
      final bucket = _ymd(m.createdAt);
      if (bucket != lastBucket) {
        String label;
        if (bucket == today) {
          label = 'chat.day.today'.tr;
        } else if (bucket == yesterday) {
          label = 'chat.day.yesterday'.tr;
        } else {
          label = '${m.createdAt.day}/${m.createdAt.month}/${m.createdAt.year}';
        }
        out.add(_DaySeparator(label));
        lastBucket = bucket;
      }
      out.add(m);
    }
    return out;
  }

  String _ymd(DateTime t) => '${t.year}-${t.month}-${t.day}';

  String _compactMembers(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    }
    return '$n';
  }
}

// ─── Chat — supporting types (private to this file) ──────────────────

// _FakeMsg removed — every message now flows through the real
// `svc.CommunityMessage` from CommunityMessagesService. The "is this
// my message" branch in [_ChatBubble] is now driven by comparing
// `msg.authorId` against the current user's id.

class _DaySeparator {
  final String label;
  _DaySeparator(this.label);
}

class _DaySeparatorWidget extends StatelessWidget {
  final String label;
  final SocialPalette palette;
  const _DaySeparatorWidget({required this.label, required this.palette});

  @override
  Widget build(BuildContext context) {
    // Centered pill chip — Telegram/iMessage style. No horizontal
    // lines cutting the screen; the chip floats clean over the
    // background gradient.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: palette.border.withValues(alpha: 0.4),
              width: 0.6,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatefulWidget {
  final svc.CommunityMessage msg;
  final Color accent;
  final int? ownerId;
  /// Current logged-in user's id — used to right-align "my" messages.
  /// Pass -1 (or any non-author value) when the auth state isn't
  /// available; bubble defaults to "other" rendering.
  final int currentUserId;
  /// Long-press handler. Receives the bubble's screen-space [Rect] so
  /// the floating action overlay can anchor itself above/below it,
  /// and an [isMe] flag so the overlay can mirror its alignment.
  final void Function(Rect anchor, bool isMe) onLongPressWithAnchor;
  /// Tap-handler on the quote preview (only meaningful when this
  /// message is a reply). Null disables the tap interaction.
  final VoidCallback? onTapParent;
  /// Tap-handler on the reaction-chip strip. Pops the "who reacted"
  /// detail sheet.
  final VoidCallback? onTapReactionChips;
  /// Non-null while a "highlight pulse" animation is targeting this
  /// bubble — e.g. user tapped a quote that points back to here.
  /// The bubble fades a colored ring in and out off the controller's
  /// value.
  final Animation<double>? highlightAnimation;
  /// Plumbed through for the audio player widget when this is a
  /// voice message — the parent screen tracks "currently playing"
  /// across all bubbles via these.
  final void Function(int messageId)? onClaimPlayback;
  final Stream<int>? stopRequests;
  /// True when the timestamp should render on this bubble. The
  /// parent decides via the "5-min cluster" rule so mid-cluster
  /// bubbles hide their time for a cleaner look.
  final bool showTimestamp;
  /// True when the author name + role icon should render above
  /// this bubble (only on the first bubble of a cluster).
  final bool showAuthorHeader;
  const _ChatBubble({
    required this.msg,
    required this.accent,
    required this.currentUserId,
    required this.onLongPressWithAnchor,
    this.ownerId,
    this.onTapParent,
    this.onTapReactionChips,
    this.highlightAnimation,
    this.onClaimPlayback,
    this.stopRequests,
    this.showTimestamp = true,
    this.showAuthorHeader = true,
  });

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  void _handleLongPress(bool isMe, LongPressStartDetails details) {
    // Read THIS bubble's own render box to anchor the actions overlay.
    // We deliberately do NOT use a GlobalKey here: a GlobalKey on a
    // rebuilding list item reparents the element and trips a framework
    // assertion (_dependents.isEmpty). Fall back to the touch point.
    final box = context.findRenderObject() as RenderBox?;
    final Rect rect = (box != null && box.hasSize)
        ? (box.localToGlobal(Offset.zero) & box.size)
        : (details.globalPosition & Size.zero);
    widget.onLongPressWithAnchor(rect, isMe);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    final msg = widget.msg;
    final accent = widget.accent;
    final highlightAnimation = widget.highlightAnimation;
    final isMe = msg.authorId == widget.currentUserId;
    final isOwnerMsg =
        widget.ownerId != null && msg.authorId == widget.ownerId;
    // Minimal-but-coherent bubble — surface tint strong enough to
    // contain the body + reply quote / audio player at a glance,
    // without going full opaque. No borders, no shadows. Only fill
    // differs between me / owner / other.
    final bubbleFill = isMe
        ? accent.withValues(alpha: 0.24)
        : isOwnerMsg
            ? SocialTokens.gold.withValues(alpha: 0.16)
            : palette.surfaceElevated.withValues(alpha: 0.85);
    final highlightFill = isMe
        ? accent.withValues(alpha: 0.42)
        : isOwnerMsg
            ? SocialTokens.gold.withValues(alpha: 0.32)
            : palette.surfaceElevated;
    return Padding(
      // Tighter vertical spacing on mid-cluster bubbles so a quick
      // burst of 3 messages reads as one block instead of three
      // disconnected bubbles. The first-of-cluster gets normal
      // breathing room.
      padding: EdgeInsets.only(
        top: widget.showAuthorHeader ? 8 : 1,
        bottom: widget.showTimestamp ? 4 : 1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            // Avatar shown only on the FIRST bubble of a cluster —
            // mid-cluster bubbles get a same-size empty space so
            // they still align horizontally with the cluster header.
            widget.showAuthorHeader
                ? _ChatAvatar(
                    name: msg.authorName,
                    role: msg.authorRole,
                    size: 32,
                  )
                : const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe && widget.showAuthorHeader)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          msg.authorName,
                          style: TextStyle(
                            // Owner is special-cased gold; everyone
                            // else gets a softer textPrimary so the
                            // name doesn't shout louder than the
                            // body. Keeps the eye on the message.
                            color: isOwnerMsg
                                ? SocialTokens.gold
                                : palette.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            letterSpacing: -0.1,
                          ),
                        ),
                        if (isOwnerMsg) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.workspace_premium_rounded,
                            size: 12,
                            color: SocialTokens.gold,
                          ),
                        ],
                        const SizedBox(width: 6),
                        // Time inline next to the author name —
                        // saves a row, mirrors Telegram. Only on
                        // first bubble of cluster (showAuthorHeader
                        // already gates this).
                        Text(
                          _hm(msg.createdAt),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                // GestureDetector wraps the bubble so long-press
                // anywhere inside it pops the actions overlay. Using
                // a GlobalKey on the inner Container so we can read
                // its on-screen rect to anchor the overlay.
                GestureDetector(
                  onLongPressStart: (details) =>
                      _handleLongPress(isMe, details),
                  child: AnimatedBuilder(
                    animation: highlightAnimation ??
                        const AlwaysStoppedAnimation(0.0),
                    builder: (context, _) {
                      // Highlight pulse: 0..1..0 across the
                      // controller's range. Drives the temporary
                      // [highlightFill] fade-in/out below.
                      final pulse = highlightAnimation == null
                          ? 0.0
                          : (highlightAnimation.value <= 0.5
                              ? highlightAnimation.value * 2
                              : (1 - highlightAnimation.value) * 2);
                      // Subtle bubble — same shape always, fill
                      // brightens during the jump-to-parent
                      // highlight pulse via Color.lerp.
                      final bg = pulse > 0
                          ? Color.lerp(
                              bubbleFill,
                              highlightFill,
                              pulse.clamp(0.0, 1.0),
                            )!
                          : bubbleFill;
                      return Container(
                        constraints: const BoxConstraints(maxWidth: 290),
                        padding: msg.isAudio
                            ? const EdgeInsets.fromLTRB(10, 8, 12, 8)
                            : const EdgeInsets.fromLTRB(13, 9, 13, 9),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(18),
                            topRight: const Radius.circular(18),
                            bottomLeft: isMe
                                ? const Radius.circular(18)
                                : const Radius.circular(6),
                            bottomRight: isMe
                                ? const Radius.circular(6)
                                : const Radius.circular(18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Quote preview — only renders when this
                            // message is a reply. Tappable: jumps the
                            // list to the parent + flashes its ring.
                            if (msg.isReply)
                              _ParentQuote(
                                authorName: msg.parentAuthorName,
                                body: msg.parentBody,
                                accent: accent,
                                palette: palette,
                                onTap: widget.onTapParent,
                              ),
                            if (msg.isReply) const SizedBox(height: 6),
                            // Image attachment (e.g. a shared index chart).
                            // Renders above any caption text, which still
                            // shows via the `msg.body.isNotEmpty` branch below.
                            if (msg.isImage) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  _resolveChatAttachmentUrl(msg.attachmentUrl),
                                  width: 250,
                                  fit: BoxFit.cover,
                                  loadingBuilder: (ctx, child, progress) =>
                                      progress == null
                                          ? child
                                          : Container(
                                              width: 250,
                                              height: 160,
                                              alignment: Alignment.center,
                                              color: palette.surfaceElevated,
                                              child: const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child: CircularProgressIndicator(
                                                    strokeWidth: 2.2),
                                              ),
                                            ),
                                  errorBuilder: (ctx, _, __) => Container(
                                    width: 250,
                                    height: 120,
                                    alignment: Alignment.center,
                                    color: palette.surfaceElevated,
                                    child: Icon(Icons.broken_image_outlined,
                                        color: palette.textMuted),
                                  ),
                                ),
                              ),
                              if (msg.body.isNotEmpty) const SizedBox(height: 6),
                            ],
                            if (msg.isAudio &&
                                widget.onClaimPlayback != null &&
                                widget.stopRequests != null)
                              _AudioBubblePlayer(
                                msg: msg,
                                accent: accent,
                                palette: palette,
                                onClaimPlayback: widget.onClaimPlayback!,
                                stopRequests: widget.stopRequests!,
                              )
                            else if (msg.isPoll)
                              // Step-21 (mig 0021, item 5.21) — poll
                              // bubble replaces the plain-text body.
                              PollBubble(
                                poll: msg.poll!,
                                authorName: msg.authorName,
                                canClose: isMe ||
                                    (widget.ownerId != null &&
                                        widget.currentUserId == widget.ownerId),
                                onVote: (optionId) async {
                                  await svc.CommunityMessagesService.votePoll(
                                    communityId: msg.communityId,
                                    pollId: msg.poll!.id,
                                    optionId: optionId,
                                  );
                                  // Realtime `poll_voted` will patch the
                                  // bubble — no local state mutation.
                                },
                                onClose: () async {
                                  await svc.CommunityMessagesService.closePoll(
                                    communityId: msg.communityId,
                                    pollId: msg.poll!.id,
                                  );
                                },
                              )
                            else if (msg.body.isNotEmpty) ...[
                              Text(
                                msg.body,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 14,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              // Step-21 (mig 0021, item 5.16) — inline
                              // ticker cards. Parses $AAPL etc. from
                              // the body and renders mini cards below.
                              if (TickerCard
                                  .parseCashtags(msg.body)
                                  .isNotEmpty)
                                TickerCardStrip(
                                  tickers: TickerCard.parseCashtags(msg.body),
                                ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Reaction chip strip — sits flush below the bubble
                // (no overlap; the overlap looked disconnected when
                // mixed with replies + audio). Same alignment as
                // the bubble.
                if (msg.hasReactions)
                  Padding(
                    padding: EdgeInsets.only(
                      top: 4,
                      left: isMe ? 0 : 4,
                      right: isMe ? 4 : 0,
                    ),
                    child: _ReactionChipStrip(
                      counts: msg.reactionCounts,
                      mine: msg.myReactions,
                      accent: accent,
                      palette: palette,
                      onTap: widget.onTapReactionChips,
                    ),
                  ),
                // Step-21 (mig 0021, item 5.22) — "edited" pill below
                // the bubble for messages the author has edited within
                // the 15-min window.
                if (msg.isEdited)
                  Padding(
                    padding: EdgeInsets.only(
                      top: 3,
                      left: isMe ? 0 : 4,
                      right: isMe ? 4 : 0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_note_rounded,
                            size: 11, color: palette.textMuted),
                        const SizedBox(width: 2),
                        Text(
                          'chat.edited'.tr,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Step-21 (mig 0021, item 5.18) — read receipts pill
                // on the author's own bubbles. Tap → "Seen by N"
                // sheet with the avatar list.
                if (isMe)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 3, end: 4),
                    child: ReadReceiptsStrip(
                      messageId: msg.id,
                      communityId: msg.communityId,
                      readCount: msg.readCount,
                    ),
                  ),
                // Trailing time stamp — only for "me" bubbles on
                // the LAST bubble of a cluster. Other bubbles get
                // their time inline next to the author name above
                // (see showAuthorHeader block), so the trailing
                // version would be a duplicate.
                if (widget.showTimestamp && isMe)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 3, end: 4),
                    child: Text(
                      _hm(msg.createdAt),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 10,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _hm(DateTime t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }
}

class _ChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final Color accent;
  final VoidCallback onSend;
  /// Tap handler for the mic button, shown when the text field is
  /// empty. Tapping it starts a voice recording (parent state takes
  /// over the strip rendering).
  final VoidCallback onMicPressed;
  /// Step-21 (mig 0021, item 5.21) — opens the poll-creator sheet.
  final VoidCallback? onPollPressed;
  final bool sending;
  const _ChatComposer({
    required this.controller,
    required this.focus,
    required this.accent,
    required this.onSend,
    required this.onMicPressed,
    this.onPollPressed,
    this.sending = false,
  });

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  // Mirror of widget.controller.text.isNotEmpty — drives the
  // mic↔send button swap on the right edge of the composer.
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final v = widget.controller.text.trim().isNotEmpty;
    if (v != _hasText && mounted) setState(() => _hasText = v);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SocialTheme.of(context);
    return SafeArea(
      top: false,
      // Floating capsule composer — margin from the screen edges so
      // it visually detaches from the bottom edge. The whole row is
      // wrapped in a single rounded surface with a soft shadow.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Container(
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Row(
            children: [
              // + menu — opens a small action sheet with poll
              // creation (mig 0021, item 5.21) and future attachment
              // options.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onPollPressed == null
                      ? null
                      : () => _showAddMenu(context),
                  child: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.add_rounded,
                      color: palette.textMuted,
                      size: 24,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: widget.focus,
                  minLines: 1,
                  maxLines: 4,
                  onSubmitted: (_) => widget.onSend(),
                  style:
                      TextStyle(color: palette.textPrimary, fontSize: 14.5),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'chat.composer.hint'.tr,
                    hintStyle: TextStyle(
                      color: palette.textMuted,
                      fontSize: 14.5,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Mic when empty, send arrow when there's text.
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.sending
                      ? null
                      : (_hasText ? widget.onSend : widget.onMicPressed),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: widget.sending
                            ? [
                                widget.accent.withValues(alpha: 0.4),
                                widget.accent.withValues(alpha: 0.25),
                              ]
                            : [
                                widget.accent,
                                widget.accent.withValues(alpha: 0.7),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: widget.sending
                          ? null
                          : [
                              BoxShadow(
                                color: widget.accent.withValues(alpha: 0.45),
                                blurRadius: 8,
                                spreadRadius: -2,
                              ),
                            ],
                    ),
                    alignment: Alignment.center,
                    child: widget.sending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0A1628),
                            ),
                          )
                        : Icon(
                            _hasText
                                ? Icons.arrow_upward_rounded
                                : Icons.mic_rounded,
                            color: const Color(0xFF0A1628),
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step-21 (mig 0021, item 5.21) — small action sheet that lets the
  // user kick off a poll. Future attachment types (image, file) slot
  // in here as additional rows.
  void _showAddMenu(BuildContext context) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final palette = SocialTheme.of(sheetCtx);
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: palette.border),
            ),
            child: ListTile(
              leading: const Icon(
                Icons.bar_chart_rounded,
                color: SocialTokens.cyan,
              ),
              title: Text(
                'chat.addMenu.createPoll'.tr,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              subtitle: Text(
                'chat.addMenu.pollSubtitle'.tr,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12,
                ),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                widget.onPollPressed?.call();
              },
            ),
          ),
        );
      },
    );
  }
}

/// Avatar disc — same role tint scheme as the Members tab on the
/// community detail screen, just kept private here so this file
/// doesn't depend on internals of community_detail_screen.dart.
class _ChatAvatar extends StatelessWidget {
  final String name;
  final String role;
  final double size;
  const _ChatAvatar({
    required this.name,
    required this.role,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    Color tint;
    switch (role.toUpperCase()) {
      case 'ADMIN':
        tint = SocialTokens.gold;
        break;
      case 'EXPERT':
        tint = SocialTokens.cyan;
        break;
      default:
        tint = const Color(0xFF94A3B8);
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: tint.withValues(alpha: 0.18),
        border: Border.all(color: tint.withValues(alpha: 0.55)),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          color: tint,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.42,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }
}

class _EmptyChat extends StatelessWidget {
  final SocialPalette palette;
  const _EmptyChat({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: palette.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'chat.empty.title'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'chat.empty.subtitle'.tr,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Replying to ..." strip rendered just above the chat composer
/// while the user has a reply target queued. Tap × to drop the
/// target.
class _ReplyingToStrip extends StatelessWidget {
  final svc.CommunityMessage replyingTo;
  final Color accent;
  final SocialPalette palette;
  final VoidCallback onCancel;

  const _ReplyingToStrip({
    required this.replyingTo,
    required this.accent,
    required this.palette,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final String preview;
    if (replyingTo.isAudio) {
      preview = 'chat.voiceMessage'.tr;
    } else {
      preview = replyingTo.body.length > 60
          ? '${replyingTo.body.substring(0, 60)}…'
          : replyingTo.body;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.35), width: 0.7),
        ),
      ),
      child: Row(
        children: [
          // Vertical accent bar — same visual hint as the parent
          // quote inside reply bubbles, ties them together.
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'chat.replyingTo'
                      .trParams({'name': replyingTo.authorName}),
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'chat.tooltip.cancelReply'.tr,
            icon: Icon(
              Icons.close_rounded,
              color: palette.textMuted,
              size: 20,
            ),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

/// Inline quote preview inside a reply bubble. Renders a thin
/// accent-colored bar + the parent's author + a truncated body
/// preview. Tappable when [onTap] is non-null.
class _ParentQuote extends StatelessWidget {
  final String authorName;
  final String body;
  final Color accent;
  final SocialPalette palette;
  final VoidCallback? onTap;

  const _ParentQuote({
    required this.authorName,
    required this.body,
    required this.accent,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Inline quote — no separate bg fill (would look like a nested
    // bubble inside the bubble). Just an accent-color vertical bar
    // with the quoted author + body indented next to it. Sits
    // cleanly inside the parent bubble's tinted surface.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 2.5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    authorName.isEmpty ? 'chat.parentFallback'.tr : authorName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12,
                      height: 1.25,
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

// ─── Reaction emoji allowlist ───────────────────────────────────────
//
// Same set as the backend's allowedReactionEmojis. Kept private to
// this file because the floating overlay is the only place that
// renders them — if more surfaces need them in the future, lift to
// SocialTokens.
const List<String> _kReactionEmojis = ['👏', '👍', '👎', '🔥'];

/// Floating action overlay shown on long-press. Anchored to the
/// long-pressed bubble's screen rect, it carries the curated emoji
/// row + Reply / Copy chips.
///
/// Positioning: prefers above the bubble. Falls back to below when
/// the bubble is too close to the top of the screen.
class _MessageActionOverlay extends StatefulWidget {
  final Rect anchor;
  final svc.CommunityMessage message;
  final Color accent;
  final SocialPalette palette;
  final bool isMe;
  final VoidCallback onDismiss;
  final void Function(String emoji) onPickEmoji;
  final VoidCallback onReply;
  final VoidCallback onCopy;
  /// Optional — when non-null AND the viewer authored the message
  /// (or is admin), a Delete action is added to the action row.
  final VoidCallback? onDelete;
  /// Optional — when non-null (community owner / admin), a Pin /
  /// Unpin action is added to the action row. The label flips based
  /// on [currentlyPinned].
  final VoidCallback? onTogglePin;
  final bool currentlyPinned;

  const _MessageActionOverlay({
    required this.anchor,
    required this.message,
    required this.accent,
    required this.palette,
    required this.isMe,
    required this.onDismiss,
    required this.onPickEmoji,
    required this.onReply,
    required this.onCopy,
    this.onDelete,
    this.onTogglePin,
    this.currentlyPinned = false,
  });

  @override
  State<_MessageActionOverlay> createState() => _MessageActionOverlayState();
}

class _MessageActionOverlayState extends State<_MessageActionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    // Overlay panel approximate size — height computed by content;
    // width capped so it never spans the full width on tablets.
    const panelWidth = 260.0;
    const panelHeight = 116.0; // emoji row (54) + reply/copy row (52) + pad
    // Default placement: above the bubble. Flip below when the
    // bubble's top is too close to the screen top to fit the panel.
    final spaceAbove = widget.anchor.top - media.padding.top - 12;
    final placeAbove = spaceAbove >= panelHeight;
    final top = placeAbove
        ? widget.anchor.top - panelHeight - 8
        : widget.anchor.bottom + 8;
    // Horizontal: align to the bubble's near edge (start side for
    // others, end side for me) but clamp inside the screen with 8px
    // gutter.
    double left;
    if (widget.isMe) {
      left = widget.anchor.right - panelWidth;
    } else {
      left = widget.anchor.left;
    }
    if (left < 8) left = 8;
    if (left + panelWidth > screen.width - 8) {
      left = screen.width - panelWidth - 8;
    }

    return Stack(
      children: [
        // Tappable scrim — closes the overlay without taking action.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Container(
                color: Colors.black.withValues(alpha: 0.32 * _ctrl.value),
              ),
            ),
          ),
        ),
        // The action panel. Fade + slide-in from 8px below.
        Positioned(
          top: top,
          left: left,
          width: panelWidth,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, child) {
              return Opacity(
                opacity: _ctrl.value,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    (1 - _ctrl.value) * (placeAbove ? 8 : -8),
                  ),
                  child: child,
                ),
              );
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.palette.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: widget.palette.border.withValues(alpha: 0.7),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Emoji row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final e in _kReactionEmojis)
                            _OverlayEmojiButton(
                              emoji: e,
                              isMine: widget.message.myReactions.contains(e),
                              accent: widget.accent,
                              onTap: () => widget.onPickEmoji(e),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      height: 0.6,
                      color: widget.palette.border.withValues(alpha: 0.6),
                    ),
                    // Reply + Copy + (optional) Delete row.
                    Row(
                      children: [
                        Expanded(
                          child: _OverlayActionButton(
                            icon: Icons.reply_rounded,
                            label: 'chat.action.reply'.tr,
                            palette: widget.palette,
                            onTap: widget.onReply,
                          ),
                        ),
                        Container(
                          width: 0.6,
                          height: 36,
                          color: widget.palette.border
                              .withValues(alpha: 0.6),
                        ),
                        Expanded(
                          child: _OverlayActionButton(
                            icon: Icons.copy_rounded,
                            label: 'chat.action.copy'.tr,
                            palette: widget.palette,
                            onTap: widget.onCopy,
                          ),
                        ),
                        if (widget.onDelete != null) ...[
                          Container(
                            width: 0.6,
                            height: 36,
                            color: widget.palette.border
                                .withValues(alpha: 0.6),
                          ),
                          Expanded(
                            child: _OverlayActionButton(
                              icon: Icons.delete_outline_rounded,
                              label: 'chat.action.delete'.tr,
                              palette: widget.palette,
                              danger: true,
                              onTap: widget.onDelete!,
                            ),
                          ),
                        ],
                        if (widget.onTogglePin != null) ...[
                          Container(
                            width: 0.6,
                            height: 36,
                            color: widget.palette.border
                                .withValues(alpha: 0.6),
                          ),
                          Expanded(
                            child: _OverlayActionButton(
                              icon: widget.currentlyPinned
                                  ? Icons.push_pin_rounded
                                  : Icons.push_pin_outlined,
                              label: widget.currentlyPinned
                                  ? 'chat.action.unpin'.tr
                                  : 'chat.action.pin'.tr,
                              palette: widget.palette,
                              onTap: widget.onTogglePin!,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Single tappable emoji inside the overlay's reaction row. When the
/// viewer has already placed this emoji, the button gets a tinted
/// ring so it's obvious the next tap will remove it.
class _OverlayEmojiButton extends StatelessWidget {
  final String emoji;
  final bool isMine;
  final Color accent;
  final VoidCallback onTap;

  const _OverlayEmojiButton({
    required this.emoji,
    required this.isMine,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isMine ? accent.withValues(alpha: 0.18) : Colors.transparent,
          border: Border.all(
            color: isMine ? accent : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
      ),
    );
  }
}

class _OverlayActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final SocialPalette palette;
  final VoidCallback onTap;
  /// Render in destructive-rose styling — used for Delete so it's
  /// visually distinct from the safe Reply/Copy actions.
  final bool danger;

  const _OverlayActionButton({
    required this.icon,
    required this.label,
    required this.palette,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = danger ? const Color(0xFFFF6B7A) : palette.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact strip of reaction-count chips rendered below a bubble.
/// Each chip = `<emoji> <count>`. When the viewer has placed the
/// reaction, the chip gets an accent-tinted ring + bg.
class _ReactionChipStrip extends StatelessWidget {
  final Map<String, int> counts;
  final Set<String> mine;
  final Color accent;
  final SocialPalette palette;
  final VoidCallback? onTap;

  const _ReactionChipStrip({
    required this.counts,
    required this.mine,
    required this.accent,
    required this.palette,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Iterate the curated emoji order so chips are stable left→right
    // regardless of insertion order on the server.
    final visible = <MapEntry<String, int>>[];
    for (final e in _kReactionEmojis) {
      final n = counts[e] ?? 0;
      if (n > 0) visible.add(MapEntry(e, n));
    }
    if (visible.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final entry in visible)
            _ReactionChip(
              emoji: entry.key,
              count: entry.value,
              isMine: mine.contains(entry.key),
              accent: accent,
              palette: palette,
            ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  final String emoji;
  final int count;
  final bool isMine;
  final Color accent;
  final SocialPalette palette;

  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.accent,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    // Solid surface fill (no transparency) so the chip reads
    // clearly against any bubble behind it. "Mine" gets an accent
    // ring + accent count text; others get a faint outline + muted
    // count. Both stand out against the chat background without
    // shouting.
    final bg = isMine
        ? accent.withValues(alpha: 0.16)
        : palette.surface;
    final borderColor = isMine
        ? accent
        : palette.border.withValues(alpha: 0.6);
    final countColor = isMine ? accent : palette.textPrimary;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 9, 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
          width: isMine ? 1.0 : 0.7,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              color: countColor,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Who reacted" detail sheet — fetched lazily on open, then grouped
/// by emoji with a tab bar. Top-level "All" tab shows every reactor
/// in newest-first order; per-emoji tabs filter the same list.
class _ReactorsSheet extends StatefulWidget {
  final String communityId;
  final int messageId;
  final SocialPalette palette;

  const _ReactorsSheet({
    required this.communityId,
    required this.messageId,
    required this.palette,
  });

  @override
  State<_ReactorsSheet> createState() => _ReactorsSheetState();
}

class _ReactorsSheetState extends State<_ReactorsSheet>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  List<svc.CommunityReactor> _reactors = const [];

  TabController? _tabs;
  // The set of emojis present in [_reactors], in curated order — used
  // to build the per-emoji tabs.
  List<String> _emojisPresent = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await svc.CommunityMessagesService.listReactors(
      widget.communityId,
      widget.messageId,
    );
    if (!mounted) return;
    if (res.error != null) {
      setState(() {
        _loading = false;
        _error = res.error;
        _reactors = const [];
      });
      return;
    }
    final list = res.reactors ?? const <svc.CommunityReactor>[];
    final present = <String>[];
    for (final e in _kReactionEmojis) {
      if (list.any((r) => r.emoji == e)) present.add(e);
    }
    setState(() {
      _loading = false;
      _reactors = list;
      _emojisPresent = present;
      // tabs = "All" + each present emoji.
      _tabs = TabController(length: 1 + present.length, vsync: this);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.55,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'chat.reactions.title'.tr,
              style: TextStyle(
                color: palette.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody(palette)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SocialPalette palette) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: palette.textMuted),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textPrimary),
          ),
        ),
      );
    }
    if (_reactors.isEmpty || _tabs == null) {
      return Center(
        child: Text(
          'chat.reactions.empty'.tr,
          style: TextStyle(color: palette.textMuted),
        ),
      );
    }
    final tabs = <Widget>[
      Tab(
        text: 'chat.reactions.all'.trParams({'count': '${_reactors.length}'}),
      ),
      for (final e in _emojisPresent)
        Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(e, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Text(
                '${_reactors.where((r) => r.emoji == e).length}',
                style: TextStyle(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
    ];
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: tabs,
          isScrollable: true,
          labelColor: palette.textPrimary,
          unselectedLabelColor: palette.textMuted,
          indicatorColor: palette.textPrimary,
          dividerColor: palette.border,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _ReactorList(reactors: _reactors, palette: palette),
              for (final e in _emojisPresent)
                _ReactorList(
                  reactors:
                      _reactors.where((r) => r.emoji == e).toList(),
                  palette: palette,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReactorList extends StatelessWidget {
  final List<svc.CommunityReactor> reactors;
  final SocialPalette palette;

  const _ReactorList({required this.reactors, required this.palette});

  @override
  Widget build(BuildContext context) {
    if (reactors.isEmpty) {
      return Center(
        child: Text('—', style: TextStyle(color: palette.textMuted)),
      );
    }
    return ListView.builder(
      itemCount: reactors.length,
      itemBuilder: (_, i) {
        final r = reactors[i];
        return ListTile(
          leading: _ChatAvatar(name: r.userName, role: r.role, size: 36),
          title: Text(
            r.userName.isEmpty ? r.email : r.userName,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          subtitle: Text(
            r.role,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
          trailing: Text(r.emoji, style: const TextStyle(fontSize: 22)),
        );
      },
    );
  }
}

// ─── Voice recording strip ──────────────────────────────────────────
//
// Replaces the regular composer while a recording is in progress.
// Shows a pulsing red dot, the live mm:ss timer, an × cancel button,
// and a send button (▲) that stops the recording, uploads, and posts
// it as a message.
class _RecordingStrip extends StatefulWidget {
  final ValueNotifier<int> elapsedMs;
  final Color accent;
  final SocialPalette palette;
  final bool uploading;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  const _RecordingStrip({
    required this.elapsedMs,
    required this.accent,
    required this.palette,
    required this.uploading,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<_RecordingStrip> createState() => _RecordingStripState();
}

class _RecordingStripState extends State<_RecordingStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          decoration: BoxDecoration(
            color: widget.palette.surface.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF3B5B).withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
          children: [
            IconButton(
              tooltip: 'common.cancel'.tr,
              onPressed: widget.uploading ? null : widget.onCancel,
              icon: Icon(
                Icons.close_rounded,
                color: const Color(0xFFFF6B7A),
                size: 22,
              ),
            ),
            const SizedBox(width: 4),
            // Pulsing red dot — visually communicates "recording".
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFF3B5B).withValues(
                    alpha: 0.55 + (_pulse.value * 0.45),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: widget.elapsedMs,
                builder: (_, ms, __) => Text(
                  'chat.voice.recording'.trParams({'time': _fmt(ms)}),
                  style: TextStyle(
                    color: widget.palette.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: widget.uploading ? null : widget.onSend,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: widget.uploading
                          ? [
                              widget.accent.withValues(alpha: 0.4),
                              widget.accent.withValues(alpha: 0.25),
                            ]
                          : [
                              widget.accent,
                              widget.accent.withValues(alpha: 0.7),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: widget.uploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0A1628),
                          ),
                        )
                      : const Icon(
                          Icons.arrow_upward_rounded,
                          color: Color(0xFF0A1628),
                          size: 20,
                        ),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ─── Audio bubble player ────────────────────────────────────────────
// Resolves a message attachment URL for display. S3 attachments arrive
// as absolute https URLs (already re-signed server-side); legacy disk
// attachments arrive as `/uploads/...` relative paths and get the API
// origin prepended so Image.network can load them.
String _resolveChatAttachmentUrl(String u) {
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  final origin = ApiConfig.baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
  return origin + u;
}

//
// Replaces the text body inside a chat bubble when [msg.isAudio].
// Self-contained AudioPlayer instance per bubble (created lazily on
// first play) — the parent screen coordinates "only one playing at
// a time" via [stopRequests], a broadcast stream that emits the
// id of the bubble that should pause itself.
class _AudioBubblePlayer extends StatefulWidget {
  final svc.CommunityMessage msg;
  final Color accent;
  final SocialPalette palette;
  /// Called when the user taps play — parent uses this to stop any
  /// other bubble that's currently playing before this one starts.
  final void Function(int messageId) onClaimPlayback;
  /// Stream the parent emits onto whenever a different bubble takes
  /// ownership. The bubble pauses itself when its id arrives... wait,
  /// other way around: the stream emits the id of bubbles that should
  /// pause. We listen and pause when our own id matches.
  final Stream<int> stopRequests;

  const _AudioBubblePlayer({
    required this.msg,
    required this.accent,
    required this.palette,
    required this.onClaimPlayback,
    required this.stopRequests,
  });

  @override
  State<_AudioBubblePlayer> createState() => _AudioBubblePlayerState();
}

class _AudioBubblePlayerState extends State<_AudioBubblePlayer> {
  AudioPlayer? _player;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<int>? _stopSub;
  StreamSubscription? _posSub, _stateSub, _durSub, _completeSub;

  @override
  void initState() {
    super.initState();
    _duration = Duration(milliseconds: widget.msg.attachmentDurationMs);
    _stopSub = widget.stopRequests.listen((id) {
      if (id == widget.msg.id) _pause();
    });
  }

  @override
  void dispose() {
    _stopSub?.cancel();
    _posSub?.cancel();
    _stateSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _toggle() async {
    // Light haptic on every play/pause — gives the round button
    // a tactile "click" without being intrusive.
    HapticFeedback.lightImpact();
    if (_playing) {
      await _pause();
      return;
    }
    // Tell the parent we're claiming the floor — parent will signal
    // every other bubble (including the previous one, if any) to
    // pause via stopRequests.
    widget.onClaimPlayback(widget.msg.id);
    final p = _player ??= AudioPlayer();
    if (_posSub == null) {
      _posSub = p.onPositionChanged.listen((pos) {
        if (mounted) setState(() => _position = pos);
      });
      _durSub = p.onDurationChanged.listen((dur) {
        if (mounted && dur > Duration.zero) {
          setState(() => _duration = dur);
        }
      });
      _stateSub = p.onPlayerStateChanged.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s == PlayerState.playing);
      });
      _completeSub = p.onPlayerComplete.listen((_) {
        if (!mounted) return;
        // Soft haptic when the voice note finishes — the standard
        // iOS/Telegram cue that "this just ended". Subtle enough
        // not to annoy on long messages.
        HapticFeedback.selectionClick();
        setState(() {
          _playing = false;
          _position = Duration.zero;
        });
      });
    }
    try {
      // Resolve to an absolute URL. attachmentUrl may be an absolute
      // S3/CDN link (passed through unchanged) OR a relative /uploads/...
      // path (prefixed with the API origin). The old code blindly
      // prefixed the origin onto everything, which corrupted S3 URLs
      // (http://host:8080https://s3...). resolveUrl handles both.
      final url = resolveUrl(widget.msg.attachmentUrl) ??
          widget.msg.attachmentUrl;
      await p.play(UrlSource(url));
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('chat.voice.playbackFailed'.trParams({'error': '$e'})),
          ),
        );
      }
    }
  }

  Future<void> _pause() async {
    final p = _player;
    if (p == null) return;
    try {
      await p.pause();
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final accent = widget.accent;
    final total = _duration.inMilliseconds <= 0
        ? Duration(milliseconds: widget.msg.attachmentDurationMs)
        : _duration;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    // Fixed 230px wide — enough room for play button + 16-bar
    // waveform + duration label without clipping inside a 280-max
    // bubble. Width hard-coded so the waveform always has the same
    // visual proportion regardless of bubble content length.
    return SizedBox(
      width: 230,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            customBorder: const CircleBorder(),
            onTap: _toggle,
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.28),
                border: Border.all(color: accent, width: 1.2),
              ),
              child: Icon(
                _playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: accent,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              // Stretch so the waveform fills the available width —
              // CrossAxisAlignment.start lets children size to
              // their intrinsic width, which would re-collapse the
              // SizedBox we just fixed.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _AudioWaveform(
                  progress: progress,
                  accent: accent,
                  // Brighter unplayed bars so the waveform reads
                  // clearly against the bubble's tinted fill.
                  baseColor: palette.textMuted.withValues(alpha: 0.65),
                  seed: widget.msg.id,
                ),
                const SizedBox(height: 4),
                Text(
                  _playing || _position > Duration.zero
                      ? '${_fmt(_position)} / ${_fmt(total)}'
                      : _fmt(total),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

// ─── Audio waveform painter ────────────────────────────────────────
//
// 16 vertical bars with deterministic randomized heights (seeded by
// the message id, so the same message always paints the same shape
// without us needing real amplitude data). Bars to the left of the
// playback head fill with [accent], bars to the right stay [baseColor].
class _AudioWaveform extends StatelessWidget {
  final double progress; // 0..1
  final Color accent;
  final Color baseColor;
  final int seed;

  const _AudioWaveform({
    required this.progress,
    required this.accent,
    required this.baseColor,
    required this.seed,
  });

  @override
  Widget build(BuildContext context) {
    // CRITICAL: explicit `width: double.infinity` so the SizedBox
    // takes the full width handed to it by its parent Column. Without
    // it, SizedBox(height: 22) sizes its width to fit the (childless)
    // CustomPaint, which is 0px wide — the waveform paints onto a
    // zero-width canvas and disappears. This is exactly what was
    // happening in the prior screenshot.
    return SizedBox(
      height: 22,
      width: double.infinity,
      child: CustomPaint(
        painter: _WaveformPainter(
          progress: progress,
          accent: accent,
          baseColor: baseColor,
          seed: seed,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color accent;
  final Color baseColor;
  final int seed;
  static const int _barCount = 16;

  _WaveformPainter({
    required this.progress,
    required this.accent,
    required this.baseColor,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    final barWidth = (w / _barCount) * 0.55;
    final stepX = w / _barCount;
    // Pseudo-random heights anchored to the message id so the
    // waveform is stable across rebuilds. LCG-style hash gives a
    // varied but reproducible spread.
    int s = seed * 9301 + 49297;
    for (int i = 0; i < _barCount; i++) {
      s = (s * 1103515245 + 12345) & 0x7fffffff;
      final norm = ((s >> 8) & 0xff) / 255.0; // 0..1
      // Bias bars toward 0.4..1.0 height — pure 0..1 makes the
      // waveform look too jittery at low values.
      final hh = (0.30 + 0.70 * norm) * h;
      final x = stepX * i + (stepX - barWidth) / 2;
      final yTop = (h - hh) / 2;
      final played = (i + 0.5) / _barCount <= progress;
      paint.color = played ? accent : baseColor;
      paint.strokeWidth = barWidth;
      canvas.drawLine(
        Offset(x + barWidth / 2, yTop),
        Offset(x + barWidth / 2, yTop + hh),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) {
    return old.progress != progress ||
        old.accent != accent ||
        old.baseColor != baseColor ||
        old.seed != seed;
  }
}

// ─── Community avatar in chat header ───────────────────────────────
//
// Small circular "icon" for the chat AppBar. Uses the community's
// region color as a tint and renders the first letter of the name.
// Distinct from the larger _ChatAvatar used in message bubbles.
class _CommunityHeaderAvatar extends StatelessWidget {
  final Community community;
  final Color accent;
  const _CommunityHeaderAvatar({
    required this.community,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final letter = community.name.trim().isEmpty
        ? '·'
        : community.name.trim().substring(0, 1).toUpperCase();
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.55),
            accent.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: accent.withValues(alpha: 0.7),
          width: 1,
        ),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.w900,
          fontSize: 14,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

// ─── Floating "scroll to bottom" button ─────────────────────────────
//
// Appears at the bottom-right when the user has scrolled up more
// than ~300px from the latest message. Tapping animates back to the
// bottom; a tiny dot lights up if new messages arrived while
// scrolled away (not used yet, plumbed for future).
class _ScrollToBottomFab extends StatelessWidget {
  final VoidCallback onTap;
  final bool hasUnread;
  final Color accent;
  final SocialPalette palette;

  const _ScrollToBottomFab({
    required this.onTap,
    required this.hasUnread,
    required this.accent,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.surface.withValues(alpha: 0.96),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.arrow_downward_rounded,
                size: 20,
                color: palette.textPrimary,
              ),
            ),
            if (hasUnread)
              Positioned(
                top: -2,
                right: -2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                    border: Border.all(
                      color: palette.background,
                      width: 1.5,
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

// ─── Pinned message strip ──────────────────────────────────────────
//
// Sticky pill at the top of the chat showing the most-recently
// pinned message. Owners pin via the long-press overlay; the rest
// of the community sees this strip until the message is unpinned.
// Tap to scroll the list to that message (uses the same jump-to
// helper as quote replies).
class _PinnedMessageStrip extends StatelessWidget {
  final svc.CommunityMessage pinned;
  final int totalPinned;
  final Color accent;
  final SocialPalette palette;
  final VoidCallback onTap;

  const _PinnedMessageStrip({
    required this.pinned,
    required this.totalPinned,
    required this.accent,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = pinned.body.isNotEmpty
        ? pinned.body
        : (pinned.isAudio
            ? 'chat.voiceMessage'.tr
            : 'chat.messageFallback'.tr);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: 0.45),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.push_pin_rounded,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'chat.pinnedBadge'.tr,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 10.5,
                            letterSpacing: 0.6,
                          ),
                        ),
                        if (totalPinned > 1) ...[
                          const SizedBox(width: 4),
                          Text(
                            '· $totalPinned',
                            style: TextStyle(
                              color: palette.textMuted,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            pinned.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Step-21 (mig 0021, item 5.19) — one entry in the active-typers list.
// Pruned after 6s of silence (typing_stopped or stale event).
class _TypingUser {
  final int userId;
  final String name;
  final DateTime startedAt;
  _TypingUser(this.userId, this.name, this.startedAt);
}
