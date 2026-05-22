/// Arabic / English localization map for the *saved & interactions* surface:
///   * the "Saved" bookmarks screen (app-bar title, refresh tooltip,
///     empty/error states, author fallback, post-type badges) —
///     saved_posts_screen.dart
///   * the post-interactions / activity screen (Likes & Comments tabs,
///     delete-comment dialog, empty states, expert badge, relative "liked"
///     line, member fallback) — post_interactions_screen.dart
///   * the chat read-receipts strip ("Sent", "Seen by N", readers sheet
///     title + empty state) — read_receipts_strip.dart
///   * the "typing…" pill (one / two / many typers) — typing_pill.dart
///
/// The like_button.dart and comment_button.dart micro-widgets carry only
/// icons + numeric counts (no translatable text) and so contribute NO keys.
///
/// This file is OWNED by the saved/interactions localization worker. The
/// central table at `app_translations.dart` merges these two maps in — do
/// NOT add these keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   saved.  interactions.  readReceipts.  typing.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally
/// (common.cancel, common.delete, common.retry, common.refresh, …).
///
/// NEVER translated (DATA, not UI): post titles/bodies, user/expert/member
/// NAMES, comment text, stock TICKERS, the brand "UNMU", and all
/// NUMBERS / timestamps. Only static UI chrome lives here. Digits stay
/// Western even in AR; relative time is produced by `LocaleFormat.relative`.
///
/// INVARIANT: `savedInteractionsEn` and `savedInteractionsAr` MUST contain the
/// exact same set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> savedInteractionsEn = {
  // ----- Saved screen -----
  'saved.title': 'Saved',
  'saved.emptyTitle': 'Nothing saved yet',
  'saved.errorTitle': 'Couldn\'t load saves',
  'saved.emptySubtitle':
      'Tap the bookmark on any post to save it for later. They\'ll all show up here.',
  'saved.errorSubtitle': 'Pull down to retry once you\'re back online.',
  'saved.expertFallback': 'Expert',
  'saved.typeArticle': 'ARTICLE',
  'saved.typeVideo': 'VIDEO',
  'saved.typeReel': 'REEL',

  // ----- Post interactions screen -----
  'interactions.title': 'Interactions',
  'interactions.tabLikes': 'Likes',
  'interactions.tabComments': 'Comments',
  'interactions.likesLoadError':
      'Could not load likes — make sure you own this post and try again.',
  'interactions.noLikesTitle': 'No likes yet',
  'interactions.noLikesBody':
      'When someone hearts this post, they\'ll show up here with a name and a timestamp.',
  'interactions.expertBadge': 'EXPERT',
  'interactions.likedAt': 'Liked @time',
  'interactions.noCommentsTitle': 'No comments yet',
  'interactions.noCommentsBody':
      'When subscribers leave a comment, you\'ll see it here. You can delete any comment as the post\'s author.',
  'interactions.memberFallback': 'Member',
  'interactions.deleteCommentTitle': 'Delete comment?',
  'interactions.deleteCommentBody': 'This cannot be undone.',

  // ----- Read receipts strip + readers sheet -----
  'readReceipts.sent': 'Sent',
  'readReceipts.seenByOne': 'Seen by 1',
  'readReceipts.seenByMany': 'Seen by @count',
  'readReceipts.seenByTitle': 'Seen by',
  'readReceipts.noReads': 'No reads yet.',

  // ----- Typing pill -----
  'typing.one': '@name is typing…',
  'typing.two': '@first and @second are typing…',
  'typing.many': '@first, @second and @count others are typing…',
};

const Map<String, String> savedInteractionsAr = {
  // ----- Saved screen -----
  'saved.title': 'المحفوظات',
  'saved.emptyTitle': 'لا يوجد شيء محفوظ بعد',
  'saved.errorTitle': 'تعذّر تحميل المحفوظات',
  'saved.emptySubtitle':
      'اضغط على علامة الحفظ في أي منشور لحفظه لوقت لاحق. ستظهر جميعها هنا.',
  'saved.errorSubtitle': 'اسحب للأسفل لإعادة المحاولة عند عودة الاتصال.',
  'saved.expertFallback': 'خبير',
  'saved.typeArticle': 'مقال',
  'saved.typeVideo': 'فيديو',
  'saved.typeReel': 'ريل',

  // ----- Post interactions screen -----
  'interactions.title': 'التفاعلات',
  'interactions.tabLikes': 'الإعجابات',
  'interactions.tabComments': 'التعليقات',
  'interactions.likesLoadError':
      'تعذّر تحميل الإعجابات — تأكّد من أنك صاحب هذا المنشور ثم حاول مرة أخرى.',
  'interactions.noLikesTitle': 'لا توجد إعجابات بعد',
  'interactions.noLikesBody':
      'عندما يُعجب أحدهم بهذا المنشور، سيظهر هنا مع الاسم ووقت الإعجاب.',
  'interactions.expertBadge': 'خبير',
  'interactions.likedAt': 'أُعجب @time',
  'interactions.noCommentsTitle': 'لا توجد تعليقات بعد',
  'interactions.noCommentsBody':
      'عندما يترك المشتركون تعليقًا، ستراه هنا. يمكنك حذف أي تعليق بصفتك صاحب المنشور.',
  'interactions.memberFallback': 'عضو',
  'interactions.deleteCommentTitle': 'حذف التعليق؟',
  'interactions.deleteCommentBody': 'لا يمكن التراجع عن هذا الإجراء.',

  // ----- Read receipts strip + readers sheet -----
  'readReceipts.sent': 'تم الإرسال',
  'readReceipts.seenByOne': 'شاهده 1',
  'readReceipts.seenByMany': 'شاهده @count',
  'readReceipts.seenByTitle': 'شاهده',
  'readReceipts.noReads': 'لا توجد مشاهدات بعد.',

  // ----- Typing pill -----
  'typing.one': '@name يكتب الآن…',
  'typing.two': '@first و@second يكتبان الآن…',
  'typing.many': '@first و@second و@count آخرون يكتبون الآن…',
};
