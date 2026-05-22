/// Feed / Social-Hub feature string maps (GetX i18n).
///
/// Owns the UI-chrome strings for the social hub, the discover feed, the
/// all-experts list, the reels & video players, and the expert paywall.
///
/// Merged into the central table in `app_translations.dart` (do NOT edit
/// that file from here). Both maps below MUST stay key-for-key identical so
/// no English leaks through in Arabic.
///
/// Namespaces (kept distinct to avoid collisions with other workers):
///   socialHub.  feedScreen.  allExperts.  reels.  videoView.  paywall.
///
/// Reuses central `common.*` and `feed.filter.*` keys where they apply —
/// those are defined in app_translations.dart and are NOT redefined here.
library;

// -----------------------------------------------------------------------------
// English
// -----------------------------------------------------------------------------
const Map<String, String> feedHubEn = {
  // ── Social hub ───────────────────────────────────────────────
  'socialHub.title': 'Social',
  'socialHub.discoverTooltip': 'Discover',
  'socialHub.liveTickerTitle': 'Live ticker tape',
  'socialHub.comingSoon': 'Coming soon.',
  'socialHub.liveStoriesTitle': 'Live stories',
  'socialHub.liveStoriesBody': 'Expert stories coming soon.',
  'socialHub.featuredExpertTitle': 'Featured expert',
  'socialHub.featuredExpertBody': 'We\'ll highlight a top expert every week.',
  'socialHub.topMovers': 'Top movers',
  'socialHub.topMoversBody': 'Per-expert performance tracking coming soon.',
  'socialHub.topExpertsThisWeek': 'Top experts this week',
  'socialHub.thisWeek': 'This week',
  'socialHub.noVerifiedExperts': 'No verified experts yet.',
  'socialHub.yourCommunitiesTitle': 'Your communities',
  'socialHub.discoverCommunities': 'Discover Communities',
  'socialHub.noCommunitiesToDiscover': 'No communities to discover yet.',
  'socialHub.noJoinedCommunities': 'You haven\'t joined any communities yet.',
  'socialHub.yourCommunitiesBand': 'YOUR COMMUNITIES',
  'socialHub.owner': 'Owner',
  'socialHub.joined': 'Joined',
  'socialHub.joinedOnly': 'Joined only',
  'socialHub.members': 'members',
  'socialHub.soon': 'SOON',
  'socialHub.viewAll': 'View all',
  'socialHub.joinFlowSoon':
      'Joining flow for newly-discovered communities arrives in the next patch.',

  // ── Discover feed screen ─────────────────────────────────────
  'feedScreen.title': 'Discover',
  'feedScreen.feedLoadError': 'Could not load the feed. Pull to refresh.',
  'feedScreen.emptySubscribe':
      'Subscribe to an expert to see their posts here.',
  'feedScreen.reelsHeader': 'REELS',
  'feedScreen.watchAll': 'Watch all →',
  'feedScreen.noMessages': 'No messages yet',
  'feedScreen.share': 'Share',
  'feedScreen.viewsSuffix': 'views',

  // ── All-experts list ─────────────────────────────────────────
  'allExperts.title': 'Top experts this week',
  'allExperts.noMatching': 'No matching experts.',
  'allExperts.noVerified': 'No verified experts yet.',
  'allExperts.searchHint': 'Search by name or expertise',
  'allExperts.loadError': 'Could not load experts.',
  'allExperts.countExperts': '@count experts',
  'allExperts.countMatching': '@count matching',

  // ── Reels player ─────────────────────────────────────────────
  'reels.share': 'Share',
  'reels.save': 'Save',
  'reels.saved': 'Saved',
  'reels.viewsSuffix': 'views',

  // ── Video player ─────────────────────────────────────────────
  'videoView.masterclass': 'MASTERCLASS',
  'videoView.description': 'DESCRIPTION',
  'videoView.subscribe': 'Subscribe',
  'videoView.subscribed': 'Subscribed',
  'videoView.share': 'Share',
  'videoView.save': 'Save',
  'videoView.saved': 'Saved',
  'videoView.viewsSuffix': 'views',
  'videoView.membersSuffix': 'members',

  // ── Expert paywall ───────────────────────────────────────────
  'paywall.title': 'Subscribers only',
  'paywall.subscribeToExpert': 'Subscribe to @name',
  'paywall.bodyForSubscribers':
      'This @kind is for subscribers of @name. Subscribe to read it — and '
          'every other post on this profile, plus future updates.',
  'paywall.monthly': 'Monthly',
  'paywall.billedMonthly': 'Billed monthly',
  'paywall.yearly': 'Yearly',
  'paywall.worksOutTo': 'Works out to @price/mo',
  'paywall.bestValue': 'BEST VALUE',
  'paywall.subscribeToUnlock': 'Subscribe to unlock',
  'paywall.cancelAnytime':
      'Cancel anytime. Subscribers see every post on this profile + receive '
          'updates when new ones drop.',
  'paywall.kindVideo': 'video',
  'paywall.kindReel': 'reel',
  'paywall.kindPost': 'post',
};

// -----------------------------------------------------------------------------
// Arabic
// -----------------------------------------------------------------------------
const Map<String, String> feedHubAr = {
  // ── Social hub ───────────────────────────────────────────────
  'socialHub.title': 'المجتمع',
  'socialHub.discoverTooltip': 'استكشاف',
  'socialHub.liveTickerTitle': 'شريط الأسعار الحي',
  'socialHub.comingSoon': 'سيظهر هنا قريباً.',
  'socialHub.liveStoriesTitle': 'القصص المباشرة',
  'socialHub.liveStoriesBody': 'قصص الخبراء قادمة قريباً.',
  'socialHub.featuredExpertTitle': 'الخبير المميز',
  'socialHub.featuredExpertBody': 'سنختار الأبرز كل أسبوع.',
  'socialHub.topMovers': 'الأكثر تحركاً',
  'socialHub.topMoversBody': 'تتبع الأداء لكل خبير قادم قريباً.',
  'socialHub.topExpertsThisWeek': 'كبار الخبراء هذا الأسبوع',
  'socialHub.thisWeek': 'هذا الأسبوع',
  'socialHub.noVerifiedExperts': 'لا يوجد خبراء معتمدون بعد.',
  'socialHub.yourCommunitiesTitle': 'مجتمعاتك',
  'socialHub.discoverCommunities': 'اكتشف المجتمعات',
  'socialHub.noCommunitiesToDiscover': 'لا توجد مجتمعات للاكتشاف.',
  'socialHub.noJoinedCommunities': 'لم تنضم إلى أي مجتمع بعد.',
  'socialHub.yourCommunitiesBand': 'مجتمعاتك',
  'socialHub.owner': 'مالك',
  'socialHub.joined': 'منضم',
  'socialHub.joinedOnly': 'المنضم إليها فقط',
  'socialHub.members': 'عضو',
  'socialHub.soon': 'قريباً',
  'socialHub.viewAll': 'عرض الكل',
  'socialHub.joinFlowSoon':
      'سيتوفر الانضمام إلى المجتمعات المكتشفة حديثاً في التحديث القادم.',

  // ── Discover feed screen ─────────────────────────────────────
  'feedScreen.title': 'استكشاف',
  'feedScreen.feedLoadError': 'تعذّر تحميل التغذية. اسحب للتحديث.',
  'feedScreen.emptySubscribe':
      'اشترك مع خبير لرؤية منشوراته هنا.',
  'feedScreen.reelsHeader': 'مقاطع',
  'feedScreen.watchAll': 'مشاهدة الكل →',
  'feedScreen.noMessages': 'لا توجد رسائل بعد',
  'feedScreen.share': 'مشاركة',
  'feedScreen.viewsSuffix': 'مشاهدة',

  // ── All-experts list ─────────────────────────────────────────
  'allExperts.title': 'كبار الخبراء هذا الأسبوع',
  'allExperts.noMatching': 'لا يوجد خبراء مطابقون.',
  'allExperts.noVerified': 'لا يوجد خبراء معتمدون بعد.',
  'allExperts.searchHint': 'ابحث بالاسم أو التخصص',
  'allExperts.loadError': 'تعذّر تحميل الخبراء.',
  'allExperts.countExperts': '@count خبير',
  'allExperts.countMatching': '@count نتيجة',

  // ── Reels player ─────────────────────────────────────────────
  'reels.share': 'مشاركة',
  'reels.save': 'حفظ',
  'reels.saved': 'محفوظ',
  'reels.viewsSuffix': 'مشاهدة',

  // ── Video player ─────────────────────────────────────────────
  'videoView.masterclass': 'دورة احترافية',
  'videoView.description': 'الوصف',
  'videoView.subscribe': 'اشترك',
  'videoView.subscribed': 'مشترك',
  'videoView.share': 'مشاركة',
  'videoView.save': 'حفظ',
  'videoView.saved': 'محفوظ',
  'videoView.viewsSuffix': 'مشاهدة',
  'videoView.membersSuffix': 'عضو',

  // ── Expert paywall ───────────────────────────────────────────
  'paywall.title': 'للمشتركين فقط',
  'paywall.subscribeToExpert': 'اشترك مع @name',
  'paywall.bodyForSubscribers':
      'هذا الـ@kind متاح لمشتركي @name. اشترك لقراءته — وكل المنشورات الأخرى '
          'على هذا الملف، بالإضافة إلى التحديثات المستقبلية.',
  'paywall.monthly': 'شهري',
  'paywall.billedMonthly': 'يُدفع شهرياً',
  'paywall.yearly': 'سنوي',
  'paywall.worksOutTo': 'بما يعادل @price/شهرياً',
  'paywall.bestValue': 'أفضل قيمة',
  'paywall.subscribeToUnlock': 'اشترك لفتح المحتوى',
  'paywall.cancelAnytime':
      'يمكنك الإلغاء في أي وقت. يرى المشتركون كل منشور على هذا الملف ويتلقون '
          'تحديثات عند نشر الجديد.',
  'paywall.kindVideo': 'الفيديو',
  'paywall.kindReel': 'المقطع',
  'paywall.kindPost': 'المنشور',
};
