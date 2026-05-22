/// Arabic / English localization map for the *support chat* surface:
///   * the built-in user ↔ admin support chat (app-bar title/subtitle,
///     empty state, message composer hint, edit-message sheet, pinned
///     strip, deleted/edited markers, rate-limit + edit-failed snackbars)
///     — support_chat_screen.dart
///
/// This file is OWNED by the support localization worker. The central
/// table at `app_translations.dart` merges these two maps in — do NOT add
/// these keys there directly.
///
/// Namespace used here (avoids collisions with other workers): support.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally
/// (common.ok, common.cancel, common.save, …).
///
/// NEVER translated (DATA, not UI): the actual chat / message text typed by
/// the user or returned by support, user/agent NAMES, stock TICKERS, the
/// brand "UNMU", server-returned error/status strings, and all NUMBERS /
/// timestamps. Only the static UI chrome lives here. Digits stay Western
/// even in AR.
///
/// INVARIANT: `supportEn` and `supportAr` MUST contain the exact same set of
/// keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> supportEn = {
  'support.title': 'Admin support',
  'support.subtitle.replyWindow': 'We reply within a few hours',
  'support.subtitle.closed': 'Conversation closed',
  'support.empty.title': 'How can we help, @name?',
  'support.empty.body':
      'Send a message and an admin will reply soon. '
      'You can come back to this screen any time to read replies.',
  'support.empty.nameFallback': 'there',
  'support.message.deleted': 'Message deleted',
  'support.message.edited': '· edited',
  'support.edit.title': 'Edit message',
  'support.editFailed': 'Edit failed',
  'support.pinned.label': 'PINNED',
  'support.pinned.fallback': 'Pinned message',
  'support.pinned.deleted': '[deleted message]',
  'support.composer.hint': 'Type a message…',
  'support.composer.hintReopen': 'Send a message to re-open this chat…',
  'support.rateLimited.title': 'Slow down',
  'support.rateLimited.body': 'Please wait a moment.',
};

const Map<String, String> supportAr = {
  'support.title': 'دعم الإدارة',
  'support.subtitle.replyWindow': 'نرد خلال ساعات قليلة',
  'support.subtitle.closed': 'تم إغلاق المحادثة',
  'support.empty.title': 'كيف نساعدك، @name؟',
  'support.empty.body':
      'أرسل رسالة وسيرد عليك المشرف قريباً. يمكنك العودة إلى هذه الشاشة في أي وقت لقراءة الردود.',
  'support.empty.nameFallback': 'صديقي',
  'support.message.deleted': 'تم حذف الرسالة',
  'support.message.edited': '· معدّلة',
  'support.edit.title': 'تعديل الرسالة',
  'support.editFailed': 'فشل التعديل',
  'support.pinned.label': 'مثبّتة',
  'support.pinned.fallback': 'رسالة مثبتة',
  'support.pinned.deleted': '[رسالة محذوفة]',
  'support.composer.hint': 'اكتب رسالة…',
  'support.composer.hintReopen': 'أرسل رسالة لإعادة فتح المحادثة…',
  'support.rateLimited.title': 'تمهّل',
  'support.rateLimited.body': 'يرجى الانتظار قليلاً.',
};
