/// Arabic / English localization map for the social *posts & expert-profile*
/// surface: expert profile screen, post detail, the post composer, the
/// comments sheet, the expert/video post cards, and the report sheet.
///
/// This file is OWNED by the posts/profile localization worker. The central
/// table at `app_translations.dart` merges these two maps in — do NOT add
/// these keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   expertProfile.  post.  createPost.  comments.  postCard.  videoCard.  report.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally.
///
/// INVARIANT: `postsProfileEn` and `postsProfileAr` MUST contain the exact
/// same set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> postsProfileEn = {
  // ── Expert profile screen ──
  'expertProfile.subscribe': 'Subscribe',
  'expertProfile.subscribed': 'Subscribed',
  'expertProfile.pending': 'Pending',
  'expertProfile.tryAgain': 'Try again',
  'expertProfile.subscribers': 'subscribers',
  'expertProfile.newPost': 'New post',
  'expertProfile.reportUser': 'Report user',
  'expertProfile.reportThanks': 'Thanks — our team will review it.',
  'expertProfile.profileUnavailable': 'Profile not available yet.',
  'expertProfile.communityUnavailableTitle': 'Community Unavailable',
  'expertProfile.communityUnavailable': 'This community is currently unavailable.',
  'expertProfile.tabAll': 'All',
  'expertProfile.tabArticles': 'Articles',
  'expertProfile.tabVideos': 'Videos',
  'expertProfile.tabReels': 'Reels',
  'expertProfile.emptyArticles': 'No articles yet — check back soon.',
  'expertProfile.emptyVideos': 'No videos yet — check back soon.',
  'expertProfile.emptyReels': 'No reels yet — check back soon.',
  'expertProfile.emptyPosts': 'No posts yet — check back soon.',
  'expertProfile.statPosts': 'Posts',
  'expertProfile.statArticles': 'Articles',
  'expertProfile.statSubscribers': 'Subscribers',
  'expertProfile.showLess': 'Show less',
  'expertProfile.more': 'more',
  'expertProfile.communities': 'Communities',
  'expertProfile.communityFallback': 'Community',
  'expertProfile.subscribersPost': 'Subscribers post',
  'expertProfile.publicPost': 'Public post',
  'expertProfile.subscribersOnly': 'Subscribers only',
  'expertProfile.subscribeToRead': 'Subscribe to @name to read this post.',
  'expertProfile.cancelSubTitle': 'Cancel subscription?',
  'expertProfile.cancelSubBody':
      'You\'ll lose access to subscriber-only posts immediately.',
  'expertProfile.keep': 'Keep',
  'expertProfile.expertFallback': 'Expert',
  'expertProfile.views': 'views',

  // ── Post detail screen ──
  'post.joined': 'Joined',
  'post.topDiscussion': 'TOP DISCUSSION',
  'post.beFirstToComment': 'Be the first to comment.',
  'post.someone': 'Someone',
  'post.upvotes': 'Upvotes',
  'post.replies': 'Replies',
  'post.views': 'Views',
  'post.addReplyHint': 'Add a reply…',
  'post.reply': 'Reply',

  // ── Create-post composer ──
  'createPost.newPost': 'New post',
  'createPost.shareResearch': 'Share research',
  'createPost.post': 'Post',
  'createPost.title': 'Title',
  'createPost.titleHint': 'A clear, scannable headline',
  'createPost.tickerLabel': 'Ticker',
  'createPost.tickersLabel': 'Tickers (comma-separated)',
  'createPost.publish': 'Publish',
  'createPost.bodyLabel': 'BODY',
  'createPost.bodyHintCommunity': 'Share your analysis…',
  'createPost.bodyHintExpert':
      'Drop your thesis, key levels, or thoughts on the market…',
  'createPost.stanceLabel': 'STANCE',
  'createPost.postingTo': 'Posting to @name',
  'createPost.postingOn': 'Posting on @name\'s profile',

  // ── Comments sheet ──
  'comments.title': 'Comments',
  'comments.startConversation': 'Start the conversation',
  'comments.onePersonJoined': '1 person joined the thread',
  'comments.peopleJoined': '@count people joined the thread',
  'comments.addCommentHint': 'Add a comment…',
  'comments.loadError': 'Could not load comments.',
  'comments.reportThanks': 'Thanks — our team will review it.',
  'comments.thisComment': 'this comment',
  'comments.editTitle': 'Edit comment',
  'comments.editHint': 'Update your comment…',
  'comments.deleteTitle': 'Delete comment?',
  'comments.deleteBody': 'This cannot be undone.',
  'comments.edited': 'edited',
  'comments.member': 'Member',
  'comments.beFirstTitle': 'Be the first to comment',
  'comments.beFirstBody':
      'Share a thought or ask a question — the author will see it.',
  'comments.actionEdit': 'Edit',
  'comments.actionDelete': 'Delete',
  'comments.actionReport': 'Report',

  // ── Video card ──
  'videoCard.masterclass': 'MASTERCLASS',

  // ── Report sheet ──
  'report.title': 'Report @target',
  'report.targetDefault': 'this',
  'report.subtitle': 'Pick the closest reason. Our team reviews every report.',
  'report.detailsLabel': 'Details (optional)',
  'report.detailsHint': 'Anything that helps the moderation team…',
  'report.pickReason': 'Pick a reason first.',
  'report.submit': 'Submit report',
};

const Map<String, String> postsProfileAr = {
  // ── Expert profile screen ──
  'expertProfile.subscribe': 'اشترك',
  'expertProfile.subscribed': 'مشترك',
  'expertProfile.pending': 'قيد الانتظار',
  'expertProfile.tryAgain': 'حاول مرة أخرى',
  'expertProfile.subscribers': 'مشترك',
  'expertProfile.newPost': 'منشور جديد',
  'expertProfile.reportUser': 'الإبلاغ عن المستخدم',
  'expertProfile.reportThanks': 'شكراً — سيراجعه فريقنا.',
  'expertProfile.profileUnavailable': 'الملف الشخصي غير متاح بعد.',
  'expertProfile.communityUnavailableTitle': 'المجتمع غير متاح',
  'expertProfile.communityUnavailable': 'هذا المجتمع غير متاح حاليًا.',
  'expertProfile.tabAll': 'الكل',
  'expertProfile.tabArticles': 'المقالات',
  'expertProfile.tabVideos': 'الفيديوهات',
  'expertProfile.tabReels': 'المقاطع',
  'expertProfile.emptyArticles': 'لا توجد مقالات بعد — تحقّق لاحقاً.',
  'expertProfile.emptyVideos': 'لا توجد فيديوهات بعد — تحقّق لاحقاً.',
  'expertProfile.emptyReels': 'لا توجد مقاطع بعد — تحقّق لاحقاً.',
  'expertProfile.emptyPosts': 'لا توجد منشورات بعد — تحقّق لاحقاً.',
  'expertProfile.statPosts': 'المنشورات',
  'expertProfile.statArticles': 'المقالات',
  'expertProfile.statSubscribers': 'المشتركون',
  'expertProfile.showLess': 'عرض أقل',
  'expertProfile.more': 'المزيد',
  'expertProfile.communities': 'المجتمعات',
  'expertProfile.communityFallback': 'مجتمع',
  'expertProfile.subscribersPost': 'منشور للمشتركين',
  'expertProfile.publicPost': 'منشور عام',
  'expertProfile.subscribersOnly': 'للمشتركين فقط',
  'expertProfile.subscribeToRead': 'اشترك في @name لقراءة هذا المنشور.',
  'expertProfile.cancelSubTitle': 'إلغاء الاشتراك؟',
  'expertProfile.cancelSubBody':
      'ستفقد الوصول إلى منشورات المشتركين فوراً.',
  'expertProfile.keep': 'الإبقاء',
  'expertProfile.expertFallback': 'خبير',
  'expertProfile.views': 'مشاهدة',

  // ── Post detail screen ──
  'post.joined': 'منضم',
  'post.topDiscussion': 'أبرز النقاشات',
  'post.beFirstToComment': 'كن أول من يعلّق.',
  'post.someone': 'شخص ما',
  'post.upvotes': 'تصويتات',
  'post.replies': 'الردود',
  'post.views': 'المشاهدات',
  'post.addReplyHint': 'أضف رداً…',
  'post.reply': 'رد',

  // ── Create-post composer ──
  'createPost.newPost': 'منشور جديد',
  'createPost.shareResearch': 'شارك تحليلك',
  'createPost.post': 'نشر',
  'createPost.title': 'العنوان',
  'createPost.titleHint': 'عنوان واضح وسهل القراءة',
  'createPost.tickerLabel': 'الرمز',
  'createPost.tickersLabel': 'الرموز (مفصولة بفواصل)',
  'createPost.publish': 'نشر',
  'createPost.bodyLabel': 'المحتوى',
  'createPost.bodyHintCommunity': 'شارك تحليلك…',
  'createPost.bodyHintExpert':
      'اطرح أطروحتك أو المستويات المهمة أو رأيك في السوق…',
  'createPost.stanceLabel': 'التوصية',
  'createPost.postingTo': 'النشر في @name',
  'createPost.postingOn': 'النشر على ملف @name',

  // ── Comments sheet ──
  'comments.title': 'التعليقات',
  'comments.startConversation': 'ابدأ المحادثة',
  'comments.onePersonJoined': 'انضم شخص واحد إلى النقاش',
  'comments.peopleJoined': 'انضم @count أشخاص إلى النقاش',
  'comments.addCommentHint': 'أضف تعليقاً…',
  'comments.loadError': 'تعذّر تحميل التعليقات.',
  'comments.reportThanks': 'شكراً — سيراجعه فريقنا.',
  'comments.thisComment': 'هذا التعليق',
  'comments.editTitle': 'تعديل التعليق',
  'comments.editHint': 'حدّث تعليقك…',
  'comments.deleteTitle': 'حذف التعليق؟',
  'comments.deleteBody': 'لا يمكن التراجع عن هذا.',
  'comments.edited': 'مُعدّل',
  'comments.member': 'عضو',
  'comments.beFirstTitle': 'كن أول من يعلّق',
  'comments.beFirstBody':
      'شارك فكرة أو اطرح سؤالاً — سيراه الكاتب.',
  'comments.actionEdit': 'تعديل',
  'comments.actionDelete': 'حذف',
  'comments.actionReport': 'إبلاغ',

  // ── Video card ──
  'videoCard.masterclass': 'درس متقدّم',

  // ── Report sheet ──
  'report.title': 'الإبلاغ عن @target',
  'report.targetDefault': 'هذا',
  'report.subtitle': 'اختر السبب الأقرب. يراجع فريقنا كل بلاغ.',
  'report.detailsLabel': 'تفاصيل (اختياري)',
  'report.detailsHint': 'أي شيء يساعد فريق الإشراف…',
  'report.pickReason': 'اختر سبباً أولاً.',
  'report.submit': 'إرسال البلاغ',
};
