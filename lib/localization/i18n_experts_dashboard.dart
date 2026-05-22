/// Arabic / English localization map for the *expert studio* surface:
/// the expert dashboard ("Studio") with its metrics / posts / proposals,
/// the post composer (article / video / reel), the drafts & scheduled list,
/// and the "propose a community" bottom-sheet.
///
/// This file is OWNED by the expert-dashboard localization worker. The
/// central table at `app_translations.dart` merges these two maps in — do
/// NOT add these keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   dashboard.  createPostX.  drafts.  proposeCommunity.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally
/// (common.cancel, common.delete, common.save, common.required, …).
///
/// INVARIANT: `expertsDashboardEn` and `expertsDashboardAr` MUST contain the
/// exact same set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> expertsDashboardEn = {
  // ── Studio dashboard (expert_dashboard_screen.dart) ──
  'dashboard.title': 'Studio',
  'dashboard.draftsTooltip': 'Drafts & Scheduled',
  'dashboard.newPost': 'New Post',
  'dashboard.couldNotLoadPosts': 'Could not load posts',
  'dashboard.noPostsTitle': 'No posts yet',
  'dashboard.noPostsSubtitle':
      'Tap "New Post" to publish your first article, video, or reel.',
  // Stats row
  'dashboard.statTotal': 'Total',
  'dashboard.statArticles': 'Articles',
  'dashboard.statVideos': 'Videos',
  'dashboard.statReels': 'Reels',
  // Filter tabs
  'dashboard.filterAll': 'All',
  'dashboard.filterArticles': 'Articles',
  'dashboard.filterVideos': 'Videos',
  'dashboard.filterReels': 'Reels',
  // Post tile pills
  'dashboard.pillHidden': 'HIDDEN',
  'dashboard.pillPublic': 'PUBLIC',
  'dashboard.pillSubsOnly': 'SUBS ONLY',
  // Studio action menu
  'dashboard.menuTooltip': 'More',
  'dashboard.actionEdit': 'Edit',
  'dashboard.actionUnhide': 'Unhide',
  'dashboard.actionHide': 'Hide from others',
  'dashboard.actionDelete': 'Delete',
  // Hide / unhide snackbars
  'dashboard.nowVisible': 'Post is now visible to others.',
  'dashboard.nowHidden': 'Post hidden from others.',
  // Delete dialog
  'dashboard.deletePostTitle': 'Delete this post?',
  'dashboard.deletePostBody':
      'This permanently removes the post for everyone. This cannot be undone.',
  'dashboard.postDeleted': 'Post deleted.',
  // Proposals section
  'dashboard.proposalAwaiting': 'Proposal awaiting review',
  'dashboard.createCommunity': 'Create new community',
  'dashboard.proposalAwaitingSub':
      "You'll be notified when an admin approves it.",
  'dashboard.createCommunitySub':
      'Build your own subscriber community. Admin reviews each request.',
  'dashboard.myProposals': 'My proposals',
  'dashboard.statusPending': 'PENDING',
  'dashboard.statusApproved': 'APPROVED',
  'dashboard.statusRejected': 'REJECTED',
  'dashboard.statusUnknown': 'UNKNOWN',
  'dashboard.reasonPrefix': 'Reason: @reason',
  // Metrics block
  'dashboard.performance': 'PERFORMANCE',
  'dashboard.metricSubscribers': 'Subscribers',
  'dashboard.metricRevenue': 'Revenue',
  'dashboard.metricLikes': 'Likes',
  'dashboard.metricComments': 'Comments',
  'dashboard.pendingCount': '+@count pending',
  'dashboard.activeNow': 'active now',
  'dashboard.lifetimeActive': 'lifetime · @amount active',
  'dashboard.acrossYourPosts': 'across your posts',
  'dashboard.savesShares': '@saves saves · @shares shares',
  // Pricing tile
  'dashboard.pricingTitle': 'Subscription pricing',
  'dashboard.pricingValue': '@monthly / mo  ·  @yearly / yr',
  // Earnings tile
  'dashboard.earningsTitle': 'Earnings',
  'dashboard.earningsSubtitle': 'Daily revenue history',

  // ── Post composer (create_post_screen.dart) ──
  'createPostX.editTitle': 'Edit Post',
  'createPostX.newTitle': 'New Post',
  'createPostX.saveDraftTooltip': 'Save as draft',
  'createPostX.save': 'Save',
  'createPostX.publish': 'Publish',
  // Cards
  'createPostX.cardFormat': 'Format',
  'createPostX.cardContent': 'Content',
  'createPostX.cardTickers': 'Tickers',
  'createPostX.cardAudience': 'Audience',
  'createPostX.cardVisibility': 'Visibility',
  // Type descriptions
  'createPostX.descArticle':
      'Long-form research with charts, takeaways, and stance.',
  'createPostX.descVideo':
      'Recorded analysis or news take. Auto-rotates landscape.',
  'createPostX.descReel':
      'Quick clip up to 60 seconds. Vertical 9:16 preferred.',
  // Field labels
  'createPostX.labelTitle': 'Title',
  'createPostX.labelBody': 'Body',
  'createPostX.labelCaption': 'Caption',
  'createPostX.labelReelVideo': 'Reel video',
  'createPostX.labelVideoFile': 'Video file',
  'createPostX.labelCover': 'Cover image (optional)',
  // Field hints
  'createPostX.hintHeadlineArticle': 'Headline of your article',
  'createPostX.hintHeadlineOptional': 'Optional headline',
  'createPostX.hintBodyArticle': 'Write your article here. Markdown is fine.',
  'createPostX.hintBodyCaption': 'Short caption to go with the video.',
  'createPostX.hintTickers': 'e.g. AAPL, NVDA',
  // Media picker tiles
  'createPostX.pickReelVideo': 'Pick a video (max 60 seconds)',
  'createPostX.pickVideoFile': 'Pick a video file',
  'createPostX.pickThumbnail': 'Pick a thumbnail image',
  'createPostX.coverAuto':
      'Auto-generated from your video — tap Replace to use a custom one',
  'createPostX.uploading': 'Uploading…',
  'createPostX.uploadingPct': 'Uploading… @pct',
  'createPostX.uploaded': 'Uploaded',
  'createPostX.replace': 'Replace',
  'createPostX.removeTooltip': 'Remove',
  // Detected duration
  'createPostX.detectedDuration': 'Detected duration: @seconds' 's',
  'createPostX.detectedDurationReel': 'Detected duration: @seconds' 's / 60s',
  // Sub-labels (audience card)
  'createPostX.subVisibility': 'Visibility',
  'createPostX.subPublishTo': 'Publish to',
  'createPostX.subStance': 'Stance (community)',
  // Visibility picker
  'createPostX.visPublic': 'Public',
  'createPostX.visSubscribers': 'Subscribers',
  // Destination picker
  'createPostX.yourProfile': 'Your profile',
  'createPostX.yourProfileSub': 'Subscribers see this',
  'createPostX.loadingCommunities': 'Loading your communities…',
  'createPostX.articlesOnly': 'Articles only — switch type to enable',
  // Validation / errors
  'createPostX.required': 'Required',
  'createPostX.couldNotReadVideo': 'Could not read video.\n@error',
  'createPostX.couldNotDetectDuration':
      'Could not detect duration. Try a different file.',
  'createPostX.reelTooLong':
      'Reels must be 60 seconds or less. Selected: @duration.',
  'createPostX.pickReelToUpload': 'Pick a reel video to upload',
  'createPostX.pickVideoToUpload': 'Pick a video to upload',
  'createPostX.onlyExperts': 'Only experts can publish posts.',
  'createPostX.updateFailed': 'Update failed',
  'createPostX.pickDestination':
      'Pick at least one destination — your profile or a community.',
  'createPostX.tickerRequired':
      'Add at least one ticker — community posts require a primary symbol.',
  // Snackbars
  'createPostX.savedToDrafts': 'Saved to Drafts',
  'createPostX.yourProfileFailLabel': 'your profile',
  'createPostX.publishedButFailed': 'Published, but failed for: @list',

  // ── Drafts & scheduled (drafts_screen.dart) ──
  'drafts.title': 'Drafts & Scheduled',
  'drafts.published': 'Published',
  'drafts.deleteTitle': 'Delete draft?',
  'drafts.deleteBodyTitled': '"@title" — this can\'t be undone.',
  'drafts.deleteBodyUntitled': 'This draft can\'t be recovered.',
  'drafts.emptyTitle':
      'No drafts yet — your saved-but-unpublished work shows here.',
  'drafts.scheduledLabel': 'Scheduled · @when',
  'drafts.draftLabel': 'Draft',
  'drafts.deleteTooltip': 'Delete',
  'drafts.edit': 'Edit',
  'drafts.publishNow': 'Publish now',

  // ── Propose community sheet (propose_community_sheet.dart) ──
  'proposeCommunity.submitFailed': 'Submit failed',
  'proposeCommunity.headerTitle': 'Propose your community',
  'proposeCommunity.headerSubtitle': 'Submit for admin review',
  'proposeCommunity.infoBanner':
      "An admin will review your proposal. You'll be notified the moment it's approved or rejected.",
  'proposeCommunity.nameLabel': 'Community name',
  'proposeCommunity.nameHint': 'e.g. Halal Tech Saudi',
  'proposeCommunity.regionLabel': 'Region (optional)',
  'proposeCommunity.descLabel': 'Description',
  'proposeCommunity.descHint': 'What is this community about? Who is it for?',
  'proposeCommunity.submit': 'Submit for review',
  'proposeCommunity.cancel': 'Cancel',
  // Region names
  'proposeCommunity.regionNone': 'No specific region',
  'proposeCommunity.regionGlobal': 'Global',
  'proposeCommunity.regionUS': 'United States',
  'proposeCommunity.regionGCC': 'GCC',
  'proposeCommunity.regionMENA': 'MENA',
  'proposeCommunity.regionEU': 'Europe',
  'proposeCommunity.regionAsia': 'Asia',
  'proposeCommunity.regionCN': 'China',
};

const Map<String, String> expertsDashboardAr = {
  // ── Studio dashboard (expert_dashboard_screen.dart) ──
  'dashboard.title': 'الاستوديو',
  'dashboard.draftsTooltip': 'المسودات والمجدولة',
  'dashboard.newPost': 'منشور جديد',
  'dashboard.couldNotLoadPosts': 'تعذّر تحميل المنشورات',
  'dashboard.noPostsTitle': 'لا توجد منشورات بعد',
  'dashboard.noPostsSubtitle':
      'اضغط على "منشور جديد" لنشر أول مقال أو فيديو أو ريل لك.',
  // Stats row
  'dashboard.statTotal': 'الإجمالي',
  'dashboard.statArticles': 'المقالات',
  'dashboard.statVideos': 'الفيديوهات',
  'dashboard.statReels': 'الريلز',
  // Filter tabs
  'dashboard.filterAll': 'الكل',
  'dashboard.filterArticles': 'المقالات',
  'dashboard.filterVideos': 'الفيديوهات',
  'dashboard.filterReels': 'الريلز',
  // Post tile pills
  'dashboard.pillHidden': 'مخفي',
  'dashboard.pillPublic': 'عام',
  'dashboard.pillSubsOnly': 'للمشتركين',
  // Studio action menu
  'dashboard.menuTooltip': 'المزيد',
  'dashboard.actionEdit': 'تعديل',
  'dashboard.actionUnhide': 'إظهار',
  'dashboard.actionHide': 'إخفاء عن الآخرين',
  'dashboard.actionDelete': 'حذف',
  // Hide / unhide snackbars
  'dashboard.nowVisible': 'أصبح المنشور ظاهراً للآخرين.',
  'dashboard.nowHidden': 'تم إخفاء المنشور عن الآخرين.',
  // Delete dialog
  'dashboard.deletePostTitle': 'حذف هذا المنشور؟',
  'dashboard.deletePostBody':
      'سيؤدي هذا إلى حذف المنشور نهائياً للجميع. لا يمكن التراجع عن ذلك.',
  'dashboard.postDeleted': 'تم حذف المنشور.',
  // Proposals section
  'dashboard.proposalAwaiting': 'الاقتراح قيد المراجعة',
  'dashboard.createCommunity': 'إنشاء مجتمع جديد',
  'dashboard.proposalAwaitingSub': 'سيصلك إشعار عند موافقة المشرف عليه.',
  'dashboard.createCommunitySub':
      'أنشئ مجتمع مشتركين خاصاً بك. يراجع المشرف كل طلب.',
  'dashboard.myProposals': 'اقتراحاتي',
  'dashboard.statusPending': 'قيد المراجعة',
  'dashboard.statusApproved': 'مقبول',
  'dashboard.statusRejected': 'مرفوض',
  'dashboard.statusUnknown': 'غير معروف',
  'dashboard.reasonPrefix': 'السبب: @reason',
  // Metrics block
  'dashboard.performance': 'الأداء',
  'dashboard.metricSubscribers': 'المشتركون',
  'dashboard.metricRevenue': 'الإيرادات',
  'dashboard.metricLikes': 'الإعجابات',
  'dashboard.metricComments': 'التعليقات',
  'dashboard.pendingCount': '+@count قيد الانتظار',
  'dashboard.activeNow': 'نشط الآن',
  'dashboard.lifetimeActive': 'إجمالي · @amount نشط',
  'dashboard.acrossYourPosts': 'عبر منشوراتك',
  'dashboard.savesShares': '@saves حفظ · @shares مشاركة',
  // Pricing tile
  'dashboard.pricingTitle': 'أسعار الاشتراك',
  'dashboard.pricingValue': '@monthly / شهرياً  ·  @yearly / سنوياً',
  // Earnings tile
  'dashboard.earningsTitle': 'الأرباح',
  'dashboard.earningsSubtitle': 'سجل الإيرادات اليومية',

  // ── Post composer (create_post_screen.dart) ──
  'createPostX.editTitle': 'تعديل المنشور',
  'createPostX.newTitle': 'منشور جديد',
  'createPostX.saveDraftTooltip': 'حفظ كمسودة',
  'createPostX.save': 'حفظ',
  'createPostX.publish': 'نشر',
  // Cards
  'createPostX.cardFormat': 'الصيغة',
  'createPostX.cardContent': 'المحتوى',
  'createPostX.cardTickers': 'الرموز',
  'createPostX.cardAudience': 'الجمهور',
  'createPostX.cardVisibility': 'الظهور',
  // Type descriptions
  'createPostX.descArticle': 'بحث مطوّل مع رسوم بيانية وخلاصات وموقف.',
  'createPostX.descVideo': 'تحليل مسجّل أو رأي إخباري. يدور تلقائياً للوضع الأفقي.',
  'createPostX.descReel': 'مقطع سريع حتى 60 ثانية. يُفضّل العمودي 9:16.',
  // Field labels
  'createPostX.labelTitle': 'العنوان',
  'createPostX.labelBody': 'النص',
  'createPostX.labelCaption': 'التعليق',
  'createPostX.labelReelVideo': 'فيديو الريل',
  'createPostX.labelVideoFile': 'ملف الفيديو',
  'createPostX.labelCover': 'صورة الغلاف (اختياري)',
  // Field hints
  'createPostX.hintHeadlineArticle': 'عنوان مقالك',
  'createPostX.hintHeadlineOptional': 'عنوان اختياري',
  'createPostX.hintBodyArticle': 'اكتب مقالك هنا. يمكنك استخدام Markdown.',
  'createPostX.hintBodyCaption': 'تعليق قصير يرافق الفيديو.',
  'createPostX.hintTickers': 'مثال: AAPL، NVDA',
  // Media picker tiles
  'createPostX.pickReelVideo': 'اختر فيديو (60 ثانية كحد أقصى)',
  'createPostX.pickVideoFile': 'اختر ملف فيديو',
  'createPostX.pickThumbnail': 'اختر صورة مصغّرة',
  'createPostX.coverAuto':
      'تم إنشاؤها تلقائياً من الفيديو — اضغط استبدال لاستخدام صورة مخصصة',
  'createPostX.uploading': 'جارٍ الرفع…',
  'createPostX.uploadingPct': 'جارٍ الرفع… @pct',
  'createPostX.uploaded': 'تم الرفع',
  'createPostX.replace': 'استبدال',
  'createPostX.removeTooltip': 'إزالة',
  // Detected duration
  'createPostX.detectedDuration': 'المدة المكتشفة: @seconds ث',
  'createPostX.detectedDurationReel': 'المدة المكتشفة: @seconds ث / 60 ث',
  // Sub-labels (audience card)
  'createPostX.subVisibility': 'الظهور',
  'createPostX.subPublishTo': 'النشر إلى',
  'createPostX.subStance': 'الموقف (المجتمع)',
  // Visibility picker
  'createPostX.visPublic': 'عام',
  'createPostX.visSubscribers': 'المشتركون',
  // Destination picker
  'createPostX.yourProfile': 'ملفك الشخصي',
  'createPostX.yourProfileSub': 'يراه المشتركون',
  'createPostX.loadingCommunities': 'جارٍ تحميل مجتمعاتك…',
  'createPostX.articlesOnly': 'المقالات فقط — غيّر النوع للتفعيل',
  // Validation / errors
  'createPostX.required': 'مطلوب',
  'createPostX.couldNotReadVideo': 'تعذّرت قراءة الفيديو.\n@error',
  'createPostX.couldNotDetectDuration': 'تعذّر اكتشاف المدة. جرّب ملفاً آخر.',
  'createPostX.reelTooLong': 'يجب ألا تتجاوز الريلز 60 ثانية. المحدد: @duration.',
  'createPostX.pickReelToUpload': 'اختر فيديو ريل لرفعه',
  'createPostX.pickVideoToUpload': 'اختر فيديو لرفعه',
  'createPostX.onlyExperts': 'يمكن للخبراء فقط نشر المنشورات.',
  'createPostX.updateFailed': 'فشل التحديث',
  'createPostX.pickDestination': 'اختر وجهة واحدة على الأقل — ملفك أو مجتمعاً.',
  'createPostX.tickerRequired':
      'أضف رمزاً واحداً على الأقل — منشورات المجتمع تتطلب رمزاً رئيسياً.',
  // Snackbars
  'createPostX.savedToDrafts': 'تم الحفظ في المسودات',
  'createPostX.yourProfileFailLabel': 'ملفك الشخصي',
  'createPostX.publishedButFailed': 'تم النشر، لكن فشل في: @list',

  // ── Drafts & scheduled (drafts_screen.dart) ──
  'drafts.title': 'المسودات والمجدولة',
  'drafts.published': 'تم النشر',
  'drafts.deleteTitle': 'حذف المسودة؟',
  'drafts.deleteBodyTitled': '"@title" — لا يمكن التراجع عن هذا.',
  'drafts.deleteBodyUntitled': 'لا يمكن استرجاع هذه المسودة.',
  'drafts.emptyTitle': 'لا توجد مسودات بعد — يظهر هنا عملك المحفوظ غير المنشور.',
  'drafts.scheduledLabel': 'مجدول · @when',
  'drafts.draftLabel': 'مسودة',
  'drafts.deleteTooltip': 'حذف',
  'drafts.edit': 'تعديل',
  'drafts.publishNow': 'انشر الآن',

  // ── Propose community sheet (propose_community_sheet.dart) ──
  'proposeCommunity.submitFailed': 'فشل الإرسال',
  'proposeCommunity.headerTitle': 'اقترح مجتمعك',
  'proposeCommunity.headerSubtitle': 'أرسل للمراجعة من الإدارة',
  'proposeCommunity.infoBanner':
      'سيراجع المشرف اقتراحك. ستصلك إشعار فور الموافقة أو الرفض.',
  'proposeCommunity.nameLabel': 'اسم المجتمع',
  'proposeCommunity.nameHint': 'مثال: التقنية الحلال السعودية',
  'proposeCommunity.regionLabel': 'المنطقة (اختياري)',
  'proposeCommunity.descLabel': 'الوصف',
  'proposeCommunity.descHint': 'عن ماذا هذا المجتمع؟ ولمن هو موجّه؟',
  'proposeCommunity.submit': 'إرسال للمراجعة',
  'proposeCommunity.cancel': 'إلغاء',
  // Region names
  'proposeCommunity.regionNone': 'بدون منطقة محددة',
  'proposeCommunity.regionGlobal': 'عالمي',
  'proposeCommunity.regionUS': 'الولايات المتحدة',
  'proposeCommunity.regionGCC': 'دول الخليج',
  'proposeCommunity.regionMENA': 'الشرق الأوسط',
  'proposeCommunity.regionEU': 'أوروبا',
  'proposeCommunity.regionAsia': 'آسيا',
  'proposeCommunity.regionCN': 'الصين',
};
