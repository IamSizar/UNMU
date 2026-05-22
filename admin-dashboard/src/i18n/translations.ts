// Translation tables for the admin dashboard.
//
// Two languages: English (default) + Arabic. Adding a third later is
// just another object literal that mirrors `en`'s keys — the i18n
// context will pick it up automatically.
//
// Conventions:
//   * Keys are dot-namespaced by surface ("nav.posts", "post.delete").
//   * If a string isn't translated, the t() fn falls back to English so
//     half-translated strings never blow up the UI.
//   * Dynamic content (post bodies, user names, audit-log event types)
//     is NOT in here — those flow through unchanged.
//   * Large feature surfaces live in ./sections/*.ts and are merged into
//     `en`/`ar` below via spreads, so they can be localized independently
//     without everyone editing this one file.

import {
  shellEn,
  shellAr,
  communitiesEn,
  communitiesAr,
  monetizationEn,
  monetizationAr,
  contentEn,
  contentAr,
  systemEn,
  systemAr,
  extrasEn,
  extrasAr,
} from './sections'

export type Locale = 'en' | 'ar'

export const LOCALES: { code: Locale; label: string; native: string }[] = [
  { code: 'en', label: 'English', native: 'English' },
  { code: 'ar', label: 'Arabic', native: 'العربية' },
]

export type TranslationKey = keyof typeof en

export const en = {
  // Sidebar nav
  'nav.overview': 'Overview',
  'nav.network': 'Network',
  'nav.community': 'Community',
  'nav.users': 'Users',
  'nav.experts': 'Experts',
  'nav.applications': 'Applications',
  'nav.communities': 'Communities',
  'nav.communityProposals': 'Community Proposals',
  'nav.communitySubscriptions': 'Community Subs',
  'nav.polls': 'Chat Polls',
  'nav.content': 'Content',
  'nav.posts': 'Posts',
  'nav.market': 'Market',
  'nav.stocks': 'Stocks',
  'nav.monetization': 'Monetization',
  'nav.subscriptions': 'Subscriptions',
  'nav.payouts': 'Payouts',
  'nav.promos': 'Promo Codes',
  'nav.ads': 'Ads',
  // Mig 0029 — built-in user ↔ admin support chat.
  'nav.support': 'Support',
  'nav.system': 'System',
  'nav.notifications': 'Notifications',
  'nav.reports': 'Reports',
  'nav.auditLog': 'Audit Log',
  'nav.uploads': 'Uploads',
  'nav.diagnostics': 'Diagnostics',
  'nav.settings': 'Settings',

  // Header
  'header.search': 'Search users, experts, stocks…',
  'header.signOut': 'Sign out',
  'header.live': 'live',
  'header.offline': 'offline',

  // Common buttons
  'common.refresh': 'Refresh',
  'common.back': 'Back',
  'common.delete': 'Delete',
  'common.cancel': 'Cancel',
  'common.confirm': 'Confirm',
  'common.loading': 'Loading…',
  'common.viewAuthor': 'View author',
  'common.viewUser': 'View user',
  'common.tryAgain': 'Try again',
  'common.search': 'Search',

  // Posts page
  'posts.title': 'Posts',
  'posts.subtitle': 'Articles, videos and reels from every expert.',
  'posts.filter.all': 'All',
  'posts.filter.articles': 'Articles',
  'posts.filter.videos': 'Videos',
  'posts.filter.reels': 'Reels',
  'posts.status.allHidden': 'Active + hidden',
  'posts.status.activeOnly': 'Active only',
  'posts.status.hiddenOnly': 'Hidden only',
  'posts.sort.newest': 'Newest first',
  'posts.sort.oldest': 'Oldest first',
  'posts.sort.mostLiked': 'Most liked',
  'posts.sort.mostCommented': 'Most commented',
  'posts.search.placeholder': 'Search title or body…',
  'posts.empty': 'No posts match your filters.',
  'posts.col.id': 'ID',
  'posts.col.type': 'Type',
  'posts.col.author': 'Author',
  'posts.col.title': 'Title / body',
  'posts.col.date': 'Date',
  'posts.col.status': 'Status',
  'posts.status.active': 'Active',
  'posts.status.hidden': 'Hidden',

  // Post detail
  'post.detail.notFound': 'Not found.',
  'post.detail.noTitle': '(no title)',
  'post.detail.empty': '(empty)',
  'post.action.hide': 'Hide',
  'post.action.unhide': 'Unhide',
  'post.action.delete': 'Delete',
  'post.confirm.delete':
    'Delete post #{id}? This is permanent — every like, comment, and save on it will also be deleted.',
  'post.confirm.deleteComment': 'Delete this comment by {author}?',
  'post.posted': 'Posted {date}',
  'post.stat.likes': 'Likes',
  'post.stat.comments': 'Comments',
  'post.stat.saves': 'Saves',
  'post.stat.shares': 'Shares',
  'post.stat.deepLinks': 'Deep-link opens',
  'post.stat.reelFails': 'Reel load fails',
  'post.likedBy': 'Liked by ({count})',
  'post.likedBy.empty': 'No likes yet.',
  'post.comments': 'Comments ({count})',
  'post.comments.empty': 'No comments yet.',

  // Experts page
  'experts.title': 'Experts',
  'experts.subtitle': 'Every verified expert on the platform.',
  'experts.stat.experts': 'Experts',
  'experts.stat.scholars': 'Scholars',
  'experts.stat.total': 'Total',
  'experts.filter.all': 'All',
  'experts.filter.experts': 'Experts',
  'experts.filter.scholars': 'Scholars',
  'experts.search.placeholder': 'Search by email or name…',
  'experts.empty': 'No experts match your filters.',

  // User detail
  'user.notFound': 'User not found.',
  'user.invalidId': 'Invalid user id.',
  'user.posts': 'Posts by this user',
  'user.joined': 'joined {date}',

  // Uploads page
  'uploads.title': 'In-flight uploads',
  'uploads.subtitle':
    'Chunked video uploads still staged on disk. Successful uploads clean themselves up — anything sitting here for more than ~1h was probably abandoned.',
  'uploads.stat.inFlight': 'In-flight uploads',
  'uploads.stat.chunks': 'Total chunks staged',
  'uploads.stat.disk': 'Disk used',
  'uploads.sweep.title': 'Manual sweep',
  'uploads.sweep.help':
    'Delete every staging dir older than the chosen cutoff. The init endpoint runs the same sweep automatically with a 24h cutoff — use this only when you need a tighter cutoff (e.g. clearing a regression mid-deploy).',
  'uploads.sweep.minAge': 'Min age (hours):',
  'uploads.sweep.run': 'Run sweep',
  'uploads.sweep.result': 'Removed {count} dirs · {bytes} reclaimed',
  'uploads.empty': 'No in-flight uploads.',
  'uploads.col.uploadId': 'Upload ID',
  'uploads.col.chunks': 'Chunks',
  'uploads.col.size': 'Size',
  'uploads.col.started': 'Started',
  'uploads.col.age': 'Age',

  // Diagnostics page
  'diag.title': 'Diagnostics',
  'diag.subtitle':
    'Operational checks for sharing, deep links, and reel reliability.',
  'diag.deepLinks.title': 'Universal Links & App Links',
  'diag.deepLinks.recheck': 'Re-check',
  'diag.deepLinks.help':
    'Server-side fetches both well-known files and verifies the bundle ID / package / SHA-256 match what the apps shipped with. Until these are green, tapping a shared link opens a browser instead of the app.',
  'diag.deepLinks.lastChecked': 'Last checked {time}',
  'diag.events.title': 'Engagement & reliability events',
  'diag.events.help':
    'Logged from the mobile app. Share taps come from each share button; deep-link opens are counted server-side; reel-load failures fire when a reel video player gives up after 10s.',

  // Misc fallbacks
  'misc.justNow': 'just now',

  // ── Feature sections (merged from ./sections/*) ──────────────
  ...shellEn,
  ...communitiesEn,
  ...monetizationEn,
  ...contentEn,
  ...systemEn,
  ...extrasEn,
}

export const ar: Partial<Record<TranslationKey, string>> = {
  // Sidebar nav
  'nav.overview': 'نظرة عامة',
  'nav.network': 'الشبكة',
  'nav.community': 'المجتمع',
  'nav.users': 'المستخدمون',
  'nav.experts': 'الخبراء',
  'nav.applications': 'الطلبات',
  'nav.communities': 'المجتمعات',
  'nav.communityProposals': 'مقترحات المجتمعات',
  'nav.communitySubscriptions': 'اشتراكات المجتمع',
  'nav.polls': 'استطلاعات الدردشة',
  'nav.content': 'المحتوى',
  'nav.posts': 'المنشورات',
  'nav.market': 'السوق',
  'nav.stocks': 'الأسهم',
  'nav.monetization': 'الاشتراكات والإيرادات',
  'nav.subscriptions': 'الاشتراكات',
  'nav.payouts': 'المدفوعات',
  'nav.promos': 'أكواد الخصم',
  'nav.ads': 'الإعلانات',
  'nav.support': 'الدعم',
  'nav.system': 'النظام',
  'nav.notifications': 'الإشعارات',
  'nav.reports': 'البلاغات',
  'nav.auditLog': 'سجل التدقيق',
  'nav.uploads': 'الرفوعات',
  'nav.diagnostics': 'التشخيصات',
  'nav.settings': 'الإعدادات',

  // Header
  'header.search': 'ابحث عن مستخدمين، خبراء، أسهم…',
  'header.signOut': 'تسجيل الخروج',
  'header.live': 'متصل',
  'header.offline': 'غير متصل',

  // Common buttons
  'common.refresh': 'تحديث',
  'common.back': 'رجوع',
  'common.delete': 'حذف',
  'common.cancel': 'إلغاء',
  'common.confirm': 'تأكيد',
  'common.loading': 'جارٍ التحميل…',
  'common.viewAuthor': 'عرض الكاتب',
  'common.viewUser': 'عرض المستخدم',
  'common.tryAgain': 'حاول مرة أخرى',
  'common.search': 'بحث',

  // Posts page
  'posts.title': 'المنشورات',
  'posts.subtitle': 'مقالات، فيديوهات، وريلز من كل الخبراء.',
  'posts.filter.all': 'الكل',
  'posts.filter.articles': 'مقالات',
  'posts.filter.videos': 'فيديوهات',
  'posts.filter.reels': 'ريلز',
  'posts.status.allHidden': 'النشطة + المخفية',
  'posts.status.activeOnly': 'النشطة فقط',
  'posts.status.hiddenOnly': 'المخفية فقط',
  'posts.sort.newest': 'الأحدث أولاً',
  'posts.sort.oldest': 'الأقدم أولاً',
  'posts.sort.mostLiked': 'الأكثر إعجاباً',
  'posts.sort.mostCommented': 'الأكثر تعليقاً',
  'posts.search.placeholder': 'ابحث في العنوان أو النص…',
  'posts.empty': 'لا توجد منشورات تطابق المرشحات.',
  'posts.col.id': 'المعرف',
  'posts.col.type': 'النوع',
  'posts.col.author': 'الكاتب',
  'posts.col.title': 'العنوان / النص',
  'posts.col.date': 'التاريخ',
  'posts.col.status': 'الحالة',
  'posts.status.active': 'نشط',
  'posts.status.hidden': 'مخفي',

  // Post detail
  'post.detail.notFound': 'غير موجود.',
  'post.detail.noTitle': '(بدون عنوان)',
  'post.detail.empty': '(فارغ)',
  'post.action.hide': 'إخفاء',
  'post.action.unhide': 'إظهار',
  'post.action.delete': 'حذف',
  'post.confirm.delete':
    'حذف المنشور #{id}؟ هذا نهائي — كل الإعجابات والتعليقات والحفظات سيتم حذفها أيضاً.',
  'post.confirm.deleteComment': 'حذف هذا التعليق من {author}؟',
  'post.posted': 'نُشر في {date}',
  'post.stat.likes': 'الإعجابات',
  'post.stat.comments': 'التعليقات',
  'post.stat.saves': 'الحفظات',
  'post.stat.shares': 'المشاركات',
  'post.stat.deepLinks': 'فتح الروابط العميقة',
  'post.stat.reelFails': 'فشل تحميل الريلز',
  'post.likedBy': 'أعجب بها ({count})',
  'post.likedBy.empty': 'لا توجد إعجابات بعد.',
  'post.comments': 'التعليقات ({count})',
  'post.comments.empty': 'لا توجد تعليقات بعد.',

  // Experts page
  'experts.title': 'الخبراء',
  'experts.subtitle': 'كل خبير موثّق على المنصة.',
  'experts.stat.experts': 'الخبراء',
  'experts.stat.scholars': 'العلماء',
  'experts.stat.total': 'الإجمالي',
  'experts.filter.all': 'الكل',
  'experts.filter.experts': 'الخبراء',
  'experts.filter.scholars': 'العلماء',
  'experts.search.placeholder': 'ابحث بالبريد أو الاسم…',
  'experts.empty': 'لا يوجد خبراء يطابقون المرشحات.',

  // User detail
  'user.notFound': 'المستخدم غير موجود.',
  'user.invalidId': 'معرف مستخدم غير صحيح.',
  'user.posts': 'منشورات هذا المستخدم',
  'user.joined': 'انضم في {date}',

  // Uploads page
  'uploads.title': 'الرفوعات قيد التنفيذ',
  'uploads.subtitle':
    'عمليات رفع الفيديو المجزّأة المخزّنة مؤقتاً. الرفعات الناجحة تُنظّف نفسها — أي شيء يبقى هنا أكثر من ساعة هو على الأرجح مهجور.',
  'uploads.stat.inFlight': 'الرفوعات قيد التنفيذ',
  'uploads.stat.chunks': 'إجمالي القطع المخزّنة',
  'uploads.stat.disk': 'مساحة القرص المستخدمة',
  'uploads.sweep.title': 'تنظيف يدوي',
  'uploads.sweep.help':
    'احذف كل مجلدات التخزين المؤقت الأقدم من العتبة المختارة. نقطة init تُشغّل نفس التنظيف تلقائياً بعتبة 24 ساعة — استخدم هذا فقط عند الحاجة لعتبة أضيق (مثلاً تنظيف بعد تراجع في النشر).',
  'uploads.sweep.minAge': 'أدنى عمر (ساعات):',
  'uploads.sweep.run': 'شغّل التنظيف',
  'uploads.sweep.result': 'حُذف {count} مجلد · استُرد {bytes}',
  'uploads.empty': 'لا توجد رفوعات قيد التنفيذ.',
  'uploads.col.uploadId': 'معرف الرفع',
  'uploads.col.chunks': 'القطع',
  'uploads.col.size': 'الحجم',
  'uploads.col.started': 'بدأ',
  'uploads.col.age': 'العمر',

  // Diagnostics page
  'diag.title': 'التشخيصات',
  'diag.subtitle': 'فحوصات تشغيلية للمشاركة والروابط العميقة وموثوقية الريلز.',
  'diag.deepLinks.title': 'الروابط الشاملة وروابط التطبيق',
  'diag.deepLinks.recheck': 'إعادة الفحص',
  'diag.deepLinks.help':
    'الخادم يجلب ملفات well-known ويتحقق من تطابق معرف الحزمة / الباقة / SHA-256 مع ما شُحن مع التطبيقات. حتى تصبح خضراء، النقر على رابط مشترك يفتح المتصفح بدلاً من التطبيق.',
  'diag.deepLinks.lastChecked': 'آخر فحص {time}',
  'diag.events.title': 'أحداث التفاعل والموثوقية',
  'diag.events.help':
    'مُسجَّلة من تطبيق الجوّال. نقرات المشاركة تأتي من زر المشاركة؛ فتح الروابط العميقة يُحسب من جهة الخادم؛ فشل تحميل الريلز يُسجَّل عندما يستسلم مشغّل الفيديو بعد 10 ثوانٍ.',

  // Misc
  'misc.justNow': 'الآن',

  // ── Feature sections (merged from ./sections/*) ──────────────
  ...shellAr,
  ...communitiesAr,
  ...monetizationAr,
  ...contentAr,
  ...systemAr,
  ...extrasAr,
}

export const TRANSLATIONS: Record<Locale, Partial<Record<TranslationKey, string>>> = {
  en,
  ar,
}
