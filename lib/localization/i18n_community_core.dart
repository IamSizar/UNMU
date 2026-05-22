// =============================================================================
// Community & chat localization map (GetX i18n) — worker-owned slice.
//
// These two maps are MERGED into the central AppTranslations table by the
// orchestrator. They cover the user-facing chrome in:
//   • lib/screens/social/community_detail_screen.dart
//   • lib/screens/social/community_chat_screen.dart
//
// Namespaces used here: `community.` and `chat.` (plus reuse of central
// `common.*` keys, which are NOT redefined here).
//
// RULES followed:
//   • Both maps below MUST hold the IDENTICAL set of keys (every English key
//     has a matching Arabic key) — otherwise English leaks in Arabic mode.
//   • No user-generated content (post bodies/titles, member/expert names,
//     chat message text, tickers, promo codes, brand "UNMU"). Numbers/prices
//     stay Western digits.
//   • Variables use `@token` placeholders consumed by `.trParams({...})`.
// =============================================================================

// -----------------------------------------------------------------------------
// English
// -----------------------------------------------------------------------------
const Map<String, String> communityCoreEn = {
  // ── Tabs / sections ──────────────────────────────────────────
  'community.tab.posts': 'Posts',
  'community.tab.members': 'Members',
  'community.members.experts': 'Experts',
  'community.members.section': 'Members',
  'community.experts.title': 'Experts in this community',

  // ── Header / membership ──────────────────────────────────────
  'community.join': 'Join',
  'community.joined': 'Joined',
  'community.joinCta': 'Join community',
  'community.leave': 'Leave',
  'community.members.label': 'members',
  'community.activeNow': 'active now',
  'community.marketSentiment': 'Market sentiment',
  'community.sentiment.bullish': 'Bullish',
  'community.sentiment.bearish': 'Bearish',
  'community.owner': 'Owner',
  'community.expertFallback': 'Expert',
  'community.subscribed': 'Subscribed ✓',
  'community.view': 'View',
  'community.views': 'views',

  // ── AppBar tooltips ──────────────────────────────────────────
  'community.tooltip.chat': 'Chat',
  'community.tooltip.inviteExpert': 'Invite expert',
  'community.tooltip.manage': 'Manage',
  'community.actions': 'Actions',

  // ── Compose ──────────────────────────────────────────────────
  'community.newPost': 'New post',

  // ── Posts feed ───────────────────────────────────────────────
  'community.posts.empty': 'No posts yet',
  'community.post.hiddenBadge': 'Hidden',
  'community.removeMember': 'Remove member',

  // ── Post moderation menu ─────────────────────────────────────
  'community.post.unhide': 'Unhide',
  'community.post.hide': 'Hide',

  // ── Edit post dialog ─────────────────────────────────────────
  'community.editPost.title': 'Edit post',
  'community.editPost.fieldTitle': 'Title',
  'community.editPost.fieldBody': 'Body',
  'community.editPost.required': 'Title and body are required',
  'community.editPost.updated': 'Post updated',

  // ── Hide / delete post ───────────────────────────────────────
  'community.post.nowVisible': 'Post is now visible',
  'community.post.hidden': 'Post hidden',
  'community.deletePost.title': 'Delete post?',
  'community.deletePost.body': 'This action cannot be undone.',
  'community.deletePost.deleted': 'Post deleted',

  // ── Leave / join community ───────────────────────────────────
  'community.leave.title': 'Leave @name?',
  'community.leave.body':
      'You\'ll lose access to private posts and chat. You can rejoin anytime.',
  'community.left': 'Left community',
  'community.joinedCommunity': 'Joined community',
  'community.actionFailed': 'Failed',

  // ── Members tab ──────────────────────────────────────────────
  'community.members.empty': 'No members yet.',
  'community.members.loadError': 'Failed to load members.',
  'community.members.joined': 'Joined @time',

  // ── Kick member (inline confirm) ─────────────────────────────
  'community.kick.title': 'Remove member?',
  'community.kick.body':
      '@name will be removed from this community. They can re-join on their own unless you also block them at the platform level.',
  'community.kick.removeFailed': 'Could not remove member.',
  'community.kick.removed': '@name removed from the community.',

  // ── Manage sheet ─────────────────────────────────────────────
  'community.manage.title': 'Manage community',
  'community.manage.members': 'Members',
  'community.manage.editDescription': 'Edit description & rules',
  'community.manage.updated': 'Community updated',
  'community.manage.pinPost': 'Pin a post',
  'community.manage.removeMember': 'Remove a member',
  'community.manage.transferOwnership': 'Transfer ownership',
  'community.manage.soon': 'Soon',

  // ── Member picker (remove / transfer) ────────────────────────
  'community.picker.removeTitle': 'Choose a member to remove',
  'community.picker.transferTitle': 'Choose new owner',
  'community.picker.removeEmpty': 'No members to remove.',
  'community.picker.transferEmpty':
      'No experts in this community yet. Ownership can only be transferred to an expert member.',
  'community.picker.confirmRemoveTitle': 'Remove member?',
  'community.picker.confirmTransferTitle': 'Transfer ownership?',
  'community.picker.confirmRemoveBody': '@name will be removed from the community.',
  'community.picker.confirmTransferBody':
      '@name will become the new owner. This cannot be undone here.',
  'community.picker.remove': 'Remove',
  'community.picker.transfer': 'Transfer',
  'community.picker.removed': 'Member removed',
  'community.picker.transferred': 'Ownership transferred',

  // ── Misc relative-time (member row) ──────────────────────────
  'community.time.justNow': 'just now',
  'community.time.monthsAgo': '@nmo ago',
  'community.time.daysAgo': '@nd ago',
  'community.time.hoursAgo': '@nh ago',

  // ── Legacy chat tab widgets (still in file) ──────────────────
  'community.chatTab.today': 'TODAY',
  'community.chat.insertSymbol': 'Insert symbol',
  'community.chat.typeMessage': 'Type a message...',

  // =====================================================================
  // CHAT SCREEN
  // =====================================================================
  'chat.header.subtitle': '@count members · active now',
  'chat.tooltip.search': 'Search chat',
  'chat.tooltip.mute': 'Mute',
  'chat.tooltip.unmute': 'Unmute',
  'chat.muted': 'Muted',
  'chat.unmuted': 'Unmuted',

  // Composer
  'chat.composer.hint': 'Message',
  'chat.addMenu.createPoll': 'Create a poll',
  'chat.addMenu.pollSubtitle': 'Question + 2..4 options',

  // Day separators
  'chat.day.today': 'Today',
  'chat.day.yesterday': 'Yesterday',

  // Empty / error / retry
  'chat.empty.title': 'No messages yet.',
  'chat.empty.subtitle': 'Be the first to start the conversation.',

  // Message states
  'chat.edited': 'edited',
  'chat.copied': 'Copied',

  // Reply strip
  'chat.replyingTo': 'Replying to @name',
  'chat.tooltip.cancelReply': 'Cancel reply',
  'chat.voiceMessage': '🎙️ Voice message',
  'chat.parentFallback': 'Member',
  'chat.messageFallback': 'Message',

  // Message action overlay
  'chat.action.reply': 'Reply',
  'chat.action.copy': 'Copy',
  'chat.action.delete': 'Delete',
  'chat.action.pin': 'Pin',
  'chat.action.unpin': 'Unpin',

  // Pin / delete results
  'chat.pinned': 'Message pinned',
  'chat.unpinned': 'Message unpinned',
  'chat.pinnedBadge': 'Pinned',
  'chat.deleteFailed': 'Delete failed',

  // Delete message dialog
  'chat.delete.title': 'Delete message?',
  'chat.delete.body': 'This can\'t be undone.',

  // Reactions sheet
  'chat.reactions.title': 'Reactions',
  'chat.reactions.empty': 'No reactions yet.',
  'chat.reactions.all': 'All · @count',

  // Voice recording
  'chat.voice.permissionNeeded': 'Microphone permission needed',
  'chat.voice.startFailed': 'Could not start recording',
  'chat.voice.tooShort': 'Recording too short',
  'chat.voice.recording': 'Recording · @time',
  'chat.voice.playbackFailed': 'Audio playback failed: @error',
};

// -----------------------------------------------------------------------------
// Arabic
// -----------------------------------------------------------------------------
const Map<String, String> communityCoreAr = {
  // ── Tabs / sections ──────────────────────────────────────────
  'community.tab.posts': 'المنشورات',
  'community.tab.members': 'الأعضاء',
  'community.members.experts': 'الخبراء',
  'community.members.section': 'الأعضاء',
  'community.experts.title': 'خبراء المجتمع',

  // ── Header / membership ──────────────────────────────────────
  'community.join': 'انضم',
  'community.joined': 'منضم',
  'community.joinCta': 'انضمام',
  'community.leave': 'مغادرة',
  'community.members.label': 'عضو',
  'community.activeNow': 'نشط الآن',
  'community.marketSentiment': 'مزاج السوق',
  'community.sentiment.bullish': 'صعودي',
  'community.sentiment.bearish': 'هبوطي',
  'community.owner': 'مالك',
  'community.expertFallback': 'خبير',
  'community.subscribed': 'مشترك ✓',
  'community.view': 'متابعة',
  'community.views': 'مشاهدة',

  // ── AppBar tooltips ──────────────────────────────────────────
  'community.tooltip.chat': 'الدردشة',
  'community.tooltip.inviteExpert': 'ادعُ خبيراً',
  'community.tooltip.manage': 'إدارة',
  'community.actions': 'إجراءات',

  // ── Compose ──────────────────────────────────────────────────
  'community.newPost': 'منشور جديد',

  // ── Posts feed ───────────────────────────────────────────────
  'community.posts.empty': 'لا توجد منشورات بعد',
  'community.post.hiddenBadge': 'مخفي',
  'community.removeMember': 'إزالة العضو',

  // ── Post moderation menu ─────────────────────────────────────
  'community.post.unhide': 'إظهار',
  'community.post.hide': 'إخفاء',

  // ── Edit post dialog ─────────────────────────────────────────
  'community.editPost.title': 'تعديل المنشور',
  'community.editPost.fieldTitle': 'العنوان',
  'community.editPost.fieldBody': 'النص',
  'community.editPost.required': 'العنوان والنص مطلوبان',
  'community.editPost.updated': 'تم تحديث المنشور',

  // ── Hide / delete post ───────────────────────────────────────
  'community.post.nowVisible': 'تم إظهار المنشور',
  'community.post.hidden': 'تم إخفاء المنشور',
  'community.deletePost.title': 'حذف المنشور؟',
  'community.deletePost.body': 'لا يمكن التراجع عن هذا الإجراء.',
  'community.deletePost.deleted': 'تم حذف المنشور',

  // ── Leave / join community ───────────────────────────────────
  'community.leave.title': 'مغادرة المجتمع؟',
  'community.leave.body':
      'لن تتمكن من رؤية المنشورات أو الرسائل الخاصة بهذا المجتمع. يمكنك الانضمام مرة أخرى لاحقًا.',
  'community.left': 'تم المغادرة',
  'community.joinedCommunity': 'انضممت إلى المجتمع',
  'community.actionFailed': 'فشل الإجراء',

  // ── Members tab ──────────────────────────────────────────────
  'community.members.empty': 'لا يوجد أعضاء بعد.',
  'community.members.loadError': 'تعذر تحميل الأعضاء.',
  'community.members.joined': 'انضم @time',

  // ── Kick member (inline confirm) ─────────────────────────────
  'community.kick.title': 'إزالة العضو؟',
  'community.kick.body':
      'ستتم إزالة @name من هذا المجتمع. يمكنه الانضمام مرة أخرى بنفسه ما لم تقم بحظره على مستوى المنصة أيضًا.',
  'community.kick.removeFailed': 'تعذرت إزالة العضو.',
  'community.kick.removed': 'تمت إزالة @name من المجتمع.',

  // ── Manage sheet ─────────────────────────────────────────────
  'community.manage.title': 'إدارة المجتمع',
  'community.manage.members': 'الأعضاء',
  'community.manage.editDescription': 'تعديل الوصف والقواعد',
  'community.manage.updated': 'تم حفظ تغييرات المجتمع',
  'community.manage.pinPost': 'تثبيت منشور',
  'community.manage.removeMember': 'إزالة عضو',
  'community.manage.transferOwnership': 'نقل الملكية',
  'community.manage.soon': 'قريباً',

  // ── Member picker (remove / transfer) ────────────────────────
  'community.picker.removeTitle': 'اختر عضو للإزالة',
  'community.picker.transferTitle': 'اختر المالك الجديد',
  'community.picker.removeEmpty': 'لا يوجد أعضاء قابلين للإزالة.',
  'community.picker.transferEmpty':
      'لا يوجد خبراء في هذا المجتمع. لا يمكن نقل الملكية إلا إلى خبير.',
  'community.picker.confirmRemoveTitle': 'إزالة العضو؟',
  'community.picker.confirmTransferTitle': 'نقل الملكية؟',
  'community.picker.confirmRemoveBody': 'سيتم إزالة @name من المجتمع.',
  'community.picker.confirmTransferBody':
      'سيصبح @name المالك الجديد. لن تتمكن من التراجع.',
  'community.picker.remove': 'إزالة',
  'community.picker.transfer': 'نقل',
  'community.picker.removed': 'تمت إزالة العضو',
  'community.picker.transferred': 'تم نقل الملكية',

  // ── Misc relative-time (member row) ──────────────────────────
  'community.time.justNow': 'الآن',
  'community.time.monthsAgo': 'منذ @nش',
  'community.time.daysAgo': 'منذ @nي',
  'community.time.hoursAgo': 'منذ @nس',

  // ── Legacy chat tab widgets (still in file) ──────────────────
  'community.chatTab.today': 'اليوم',
  'community.chat.insertSymbol': 'إدراج رمز',
  'community.chat.typeMessage': 'اكتب رسالة...',

  // =====================================================================
  // CHAT SCREEN
  // =====================================================================
  'chat.header.subtitle': '@count عضو · نشط الآن',
  'chat.tooltip.search': 'بحث',
  'chat.tooltip.mute': 'كتم',
  'chat.tooltip.unmute': 'رفع الكتم',
  'chat.muted': 'تم كتم المجتمع',
  'chat.unmuted': 'تم رفع الكتم',

  // Composer
  'chat.composer.hint': 'اكتب رسالة…',
  'chat.addMenu.createPoll': 'إنشاء استطلاع',
  'chat.addMenu.pollSubtitle': 'سؤال + 2 إلى 4 خيارات',

  // Day separators
  'chat.day.today': 'اليوم',
  'chat.day.yesterday': 'أمس',

  // Empty / error / retry
  'chat.empty.title': 'لا توجد رسائل بعد.',
  'chat.empty.subtitle': 'كن أول من يبدأ المحادثة.',

  // Message states
  'chat.edited': 'مُعدّل',
  'chat.copied': 'تم النسخ',

  // Reply strip
  'chat.replyingTo': 'الرد على @name',
  'chat.tooltip.cancelReply': 'إلغاء',
  'chat.voiceMessage': '🎙️ رسالة صوتية',
  'chat.parentFallback': 'عضو',
  'chat.messageFallback': 'رسالة',

  // Message action overlay
  'chat.action.reply': 'رد',
  'chat.action.copy': 'نسخ',
  'chat.action.delete': 'حذف',
  'chat.action.pin': 'تثبيت',
  'chat.action.unpin': 'إلغاء التثبيت',

  // Pin / delete results
  'chat.pinned': 'تم تثبيت الرسالة',
  'chat.unpinned': 'تم إلغاء التثبيت',
  'chat.pinnedBadge': 'مثبت',
  'chat.deleteFailed': 'فشل الحذف',

  // Delete message dialog
  'chat.delete.title': 'حذف الرسالة؟',
  'chat.delete.body': 'لن تتمكن من التراجع عن هذا الإجراء.',

  // Reactions sheet
  'chat.reactions.title': 'التفاعلات',
  'chat.reactions.empty': 'لا توجد تفاعلات.',
  'chat.reactions.all': 'الكل · @count',

  // Voice recording
  'chat.voice.permissionNeeded': 'يحتاج إلى إذن الميكروفون',
  'chat.voice.startFailed': 'تعذر بدء التسجيل',
  'chat.voice.tooShort': 'التسجيل قصير جدًا',
  'chat.voice.recording': 'يتم التسجيل · @time',
  'chat.voice.playbackFailed': 'فشل تشغيل الصوت: @error',
};
