/// Feed-tab / post-viewer / reel-player string maps (GetX i18n).
///
/// Owns the UI-chrome strings for the bottom-nav **Feed** tab (the aggregated
/// posts/articles/videos/reels list), the single-post viewer screen, and the
/// thin reel/video player wrapper.
///
/// Merged into the central table in `app_translations.dart` (do NOT edit that
/// file from here). Both maps below MUST stay key-for-key identical so no
/// English leaks through in Arabic.
///
/// Namespaces (kept distinct to avoid collisions with other workers):
///   feedTab.  postViewer.  reelPlayer.
///
/// Reuses central `common.*` keys where they apply — those are defined in
/// app_translations.dart and are NOT redefined here.
library;

// -----------------------------------------------------------------------------
// English
// -----------------------------------------------------------------------------
const Map<String, String> feedMediaEn = {
  // ── Feed tab — app bar + filter ──────────────────────────────
  'feedTab.title': 'Feed',
  'feedTab.filterTooltip': 'Filter feed',
  'feedTab.filterAll': 'All',
  'feedTab.filterArticles': 'Articles',
  'feedTab.filterVideos': 'Videos',
  'feedTab.filterReels': 'Reels',

  // ── Feed cards — labels & fallbacks ──────────────────────────
  'feedTab.expertFallback': 'Expert',
  'feedTab.articleFallback': 'Article',
  'feedTab.badgeArticle': 'ARTICLE',
  'feedTab.badgeVideo': 'VIDEO',
  'feedTab.badgeReel': 'REEL',
  'feedTab.subsBadge': 'SUBS',
  'feedTab.moreTooltip': 'More',
  'feedTab.more': 'more',
  'feedTab.likeOne': 'like',
  'feedTab.likeMany': 'likes',
  'feedTab.viewAllCommentsOne': 'View all @count comment',
  'feedTab.viewAllCommentsMany': 'View all @count comments',

  // ── Feed cards — relative timestamp (uppercase, Western digits) ─
  'feedTab.minuteAgoOne': '@count MINUTE AGO',
  'feedTab.minuteAgoMany': '@count MINUTES AGO',
  'feedTab.hourAgoOne': '@count HOUR AGO',
  'feedTab.hourAgoMany': '@count HOURS AGO',
  'feedTab.dayAgoOne': '@count DAY AGO',
  'feedTab.dayAgoMany': '@count DAYS AGO',
  'feedTab.weekAgoOne': '@count WEEK AGO',
  'feedTab.weekAgoMany': '@count WEEKS AGO',

  // ── Feed cards — report sheet ────────────────────────────────
  'feedTab.thisExpert': 'this expert',
  'feedTab.thisPost': 'this post',
  'feedTab.reportPost': 'Report post',
  'feedTab.flagForModeration': 'Flag for moderation by @author',
  'feedTab.reportThanks': 'Thanks — our team will review it.',

  // ── Feed cards — share sheet copy ────────────────────────────
  'feedTab.shareExpertFallback': 'an UNMU expert',
  'feedTab.shareBodyNoTitle': 'Check out this post from @author on UNMU.',
  'feedTab.shareBodyWithTitle': 'Check out "@title" from @author on UNMU.',
  'feedTab.shareSubjectFallback': 'A post on UNMU',

  // ── Feed tab — empty states ──────────────────────────────────
  'feedTab.emptyTitle': 'No posts yet',
  'feedTab.emptySubtitle':
      'Subscribe to an expert to see their posts here. New posts from anyone '
          'you\'re subscribed to land at the top.',
  'feedTab.errorTitle': 'Couldn\'t reach the feed',
  'feedTab.errorSubtitle':
      'Pull down to retry. Your subscriptions and any new posts from them will '
          'appear once we\'re back online.',

  // ── Post viewer ──────────────────────────────────────────────
  'postViewer.title': 'Post',
  'postViewer.lockedTitle': 'Subscribers only',
  'postViewer.lockedBody': 'Subscribe to @author to read the full post.',
  'postViewer.viewProfile': 'View profile',
  'postViewer.notFoundTitle': 'We couldn\'t find this post.',
  'postViewer.notFoundBody':
      'It may have been deleted, hidden, or the link is invalid.',
  'postViewer.tryAgain': 'Try again',
  'postViewer.editedMinuteAgo': 'Edited @count m ago',
  'postViewer.editedHourAgo': 'Edited @count h ago',
  'postViewer.editedDayAgo': 'Edited @count d ago',
};

// -----------------------------------------------------------------------------
// Arabic
// -----------------------------------------------------------------------------
const Map<String, String> feedMediaAr = {
  // ── Feed tab — app bar + filter ──────────────────────────────
  'feedTab.title': 'المتابعات',
  'feedTab.filterTooltip': 'تصفية المتابعات',
  'feedTab.filterAll': 'الكل',
  'feedTab.filterArticles': 'مقالات',
  'feedTab.filterVideos': 'فيديوهات',
  'feedTab.filterReels': 'ريلز',

  // ── Feed cards — labels & fallbacks ──────────────────────────
  'feedTab.expertFallback': 'خبير',
  'feedTab.articleFallback': 'مقال',
  'feedTab.badgeArticle': 'مقال',
  'feedTab.badgeVideo': 'فيديو',
  'feedTab.badgeReel': 'ريلز',
  'feedTab.subsBadge': 'للمشتركين',
  'feedTab.moreTooltip': 'المزيد',
  'feedTab.more': 'المزيد',
  'feedTab.likeOne': 'إعجاب',
  'feedTab.likeMany': 'إعجاب',
  'feedTab.viewAllCommentsOne': 'عرض تعليق واحد',
  'feedTab.viewAllCommentsMany': 'عرض كل التعليقات (@count)',

  // ── Feed cards — relative timestamp (uppercase, Western digits) ─
  'feedTab.minuteAgoOne': 'قبل دقيقة',
  'feedTab.minuteAgoMany': 'قبل @count دقيقة',
  'feedTab.hourAgoOne': 'قبل ساعة',
  'feedTab.hourAgoMany': 'قبل @count ساعة',
  'feedTab.dayAgoOne': 'قبل يوم',
  'feedTab.dayAgoMany': 'قبل @count يوم',
  'feedTab.weekAgoOne': 'قبل أسبوع',
  'feedTab.weekAgoMany': 'قبل @count أسبوع',

  // ── Feed cards — report sheet ────────────────────────────────
  'feedTab.thisExpert': 'هذا الخبير',
  'feedTab.thisPost': 'هذا المنشور',
  'feedTab.reportPost': 'الإبلاغ عن المنشور',
  'feedTab.flagForModeration': 'الإبلاغ للمراجعة عن @author',
  'feedTab.reportThanks': 'شكراً — سيراجعه فريقنا.',

  // ── Feed cards — share sheet copy ────────────────────────────
  'feedTab.shareExpertFallback': 'خبير في UNMU',
  'feedTab.shareBodyNoTitle': 'اطّلع على هذا المنشور من @author على UNMU.',
  'feedTab.shareBodyWithTitle': 'اطّلع على "@title" من @author على UNMU.',
  'feedTab.shareSubjectFallback': 'منشور على UNMU',

  // ── Feed tab — empty states ──────────────────────────────────
  'feedTab.emptyTitle': 'لا توجد منشورات بعد',
  'feedTab.emptySubtitle':
      'اشترك مع خبير لرؤية منشوراته هنا. تظهر المنشورات الجديدة ممّن تشترك معهم '
          'في الأعلى.',
  'feedTab.errorTitle': 'تعذّر الوصول إلى المتابعات',
  'feedTab.errorSubtitle':
      'اسحب للأسفل لإعادة المحاولة. ستظهر اشتراكاتك وأي منشورات جديدة منها بمجرد '
          'عودة الاتصال.',

  // ── Post viewer ──────────────────────────────────────────────
  'postViewer.title': 'منشور',
  'postViewer.lockedTitle': 'للمشتركين فقط',
  'postViewer.lockedBody': 'اشترك مع @author لقراءة المنشور كاملاً.',
  'postViewer.viewProfile': 'عرض الملف الشخصي',
  'postViewer.notFoundTitle': 'تعذّر العثور على هذا المنشور.',
  'postViewer.notFoundBody': 'قد يكون محذوفاً أو مخفياً أو أن الرابط غير صالح.',
  'postViewer.tryAgain': 'إعادة المحاولة',
  'postViewer.editedMinuteAgo': 'عُدّل قبل @count د',
  'postViewer.editedHourAgo': 'عُدّل قبل @count س',
  'postViewer.editedDayAgo': 'عُدّل قبل @count ي',
};
