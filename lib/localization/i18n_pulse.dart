/// Arabic / English localization map for **UNMU Pulse (نبض أنمو)**:
///   * the Pulse home tab (daily briefing: four items, states, first-run tip)
///   * the item detail screen (badges, sources & evidence, save/share/stock)
///   * the archive + saved screen
///   * the Pulse notification settings screen
///
/// Merged into the central table by `app_translations.dart` — do NOT add these
/// keys there directly.
///
/// Namespaces: `pulse.*` and the tab label `nav.pulse`.
///
/// NEVER translated (DATA, not UI): the Pulse item titles / summaries / details
/// / evidence (they arrive in both languages from the backend), source names,
/// stock tickers, the brand "UNMU", and all NUMBERS / timestamps (digits stay
/// Western; dates come from `LocaleFormat`).
///
/// INVARIANT: `pulseEn` and `pulseAr` MUST contain the exact same set of keys
/// (a test enforces it). A missing Arabic key would leak English in RTL.
///
/// The Arabic is Modern Standard Arabic written by the engineering team; have a
/// native speaker review the wording before launch.
library;

const Map<String, String> pulseEn = {
  'nav.pulse': 'Pulse',

  // ── Home ──────────────────────────────────────────────────────────
  'pulse.title': 'Pulse',
  'pulse.today': 'Today',
  'pulse.updatedAt': 'Updated @time',
  'pulse.notificationsTooltip': 'Pulse notifications',
  'pulse.slot.global': 'Top global event',
  'pulse.slot.gulf': 'Top Gulf event',
  'pulse.slot.sharia': 'Sharia change',
  'pulse.slot.opportunity': 'Opportunity to follow',
  'pulse.slot.empty': 'Not published yet',
  'pulse.badge.confirmed': 'Confirmed',
  'pulse.badge.analysis': 'Analysis',
  'pulse.badge.new': 'New',
  'pulse.badge.updated': 'Updated',
  'pulse.badge.corrected': 'Corrected',
  'pulse.relation.portfolio': 'In your portfolio',
  'pulse.relation.watchlist': 'On your watchlist',
  'pulse.relation.none': 'Not on your lists',
  'pulse.readDetails': 'Read details',
  'pulse.openArchive': 'Open archive',
  'pulse.browseArchive': 'Browse earlier Pulse',

  // ── States ────────────────────────────────────────────────────────
  'pulse.empty.title': 'No Pulse published yet today',
  'pulse.empty.body':
      'Today\'s briefing is being prepared. Read earlier Pulse in the archive while you wait.',
  'pulse.error.offline.title': 'You\'re offline',
  'pulse.error.offline.body':
      'Check your connection and try again. Your saved items are still here.',
  'pulse.error.server.title': 'Couldn\'t load today\'s Pulse',
  'pulse.error.server.body':
      'Something went wrong on our side. Please try again in a moment.',
  'pulse.error.retry': 'Try again',
  'pulse.refreshFailed': 'Couldn\'t refresh. Showing the last update.',

  // ── First-run tip ─────────────────────────────────────────────────
  'pulse.tip.title': 'New: UNMU Pulse',
  'pulse.tip.body':
      'Four items every day: the biggest global and Gulf events, Sharia changes and one opportunity. Tap a card to see its source and evidence.',
  'pulse.tip.dismiss': 'Got it',

  // ── Detail ────────────────────────────────────────────────────────
  'pulse.detail.analysisTitle': 'Analysis, not a confirmed fact',
  'pulse.detail.analysisBody':
      'This item explains what the news may mean. It is interpretation and is labelled separately from confirmed information.',
  'pulse.detail.correctedNote': 'Corrected @time.',
  'pulse.detail.updatedNote': 'Updated @time.',
  'pulse.detail.sources': 'Sources & evidence',
  'pulse.detail.source': 'Source',
  'pulse.detail.link': 'Link',
  'pulse.detail.evidence': 'Evidence',
  'pulse.detail.verified': 'Verified',
  'pulse.detail.published': 'Published',
  'pulse.detail.openSource': 'Open source',
  'pulse.detail.openStock': 'Open stock',
  'pulse.detail.save': 'Save',
  'pulse.detail.saved': 'Saved',
  'pulse.detail.share': 'Share',
  'pulse.detail.notFoundTitle': 'This item isn\'t available',
  'pulse.detail.notFoundBody':
      'It may have been withdrawn. Go back to today\'s Pulse.',
  'pulse.detail.saveFailed': 'Couldn\'t update your saved items. Try again.',
  'pulse.detail.linkFailed': 'Couldn\'t open the link.',
  'pulse.share.text': '@title\n@summary\n\nvia UNMU Pulse',

  // ── Archive & saved ───────────────────────────────────────────────
  'pulse.archive.title': 'Archive',
  'pulse.archive.all': 'All',
  'pulse.archive.saved': 'Saved',
  'pulse.archive.search': 'Search past Pulse',
  'pulse.archive.allDays': 'All days',
  'pulse.archive.emptyTitle': 'No Pulse found',
  'pulse.archive.emptyBody': 'Try another day or a different search.',
  'pulse.saved.emptyTitle': 'Nothing saved yet',
  'pulse.saved.emptyBody':
      'Tap the bookmark on any Pulse item to keep it here.',
  'pulse.archive.loadMoreFailed': 'Couldn\'t load more. Pull to try again.',

  // ── Notification settings ─────────────────────────────────────────
  'pulse.prefs.title': 'Pulse notifications',
  'pulse.prefs.master': 'UNMU Pulse notifications',
  'pulse.prefs.masterHint': 'The master switch for everything below.',
  'pulse.prefs.header': 'Tell me when',
  'pulse.prefs.new': 'A new Pulse is published',
  'pulse.prefs.updates': 'A previous item is updated',
  'pulse.prefs.corrections': 'A previous item is corrected',
  'pulse.prefs.saved': 'A saved item changes',
  'pulse.prefs.footer':
      'Notifications use the app language you chose. You can turn them off at any time.',
  'pulse.prefs.pushOff':
      'Push notifications are turned off for UNMU, so none of these will arrive.',
  'pulse.prefs.saveFailed': 'Couldn\'t save your setting. Try again.',
  'pulse.prefs.loadFailed': 'Couldn\'t load your settings. Showing defaults.',
};

const Map<String, String> pulseAr = {
  'nav.pulse': 'نبض',

  'pulse.title': 'نبض',
  'pulse.today': 'اليوم',
  'pulse.updatedAt': 'آخر تحديث @time',
  'pulse.notificationsTooltip': 'إشعارات نبض',
  'pulse.slot.global': 'أهم حدث عالمي',
  'pulse.slot.gulf': 'أهم حدث خليجي',
  'pulse.slot.sharia': 'تغيّر شرعي',
  'pulse.slot.opportunity': 'فرصة للمتابعة',
  'pulse.slot.empty': 'لم يُنشر بعد',
  'pulse.badge.confirmed': 'مؤكدة',
  'pulse.badge.analysis': 'تحليل',
  'pulse.badge.new': 'جديد',
  'pulse.badge.updated': 'تم التحديث',
  'pulse.badge.corrected': 'تم التصحيح',
  'pulse.relation.portfolio': 'في محفظتك',
  'pulse.relation.watchlist': 'في قائمة مراقبتك',
  'pulse.relation.none': 'ليس في قوائمك',
  'pulse.readDetails': 'اقرأ التفاصيل',
  'pulse.openArchive': 'فتح الأرشيف',
  'pulse.browseArchive': 'تصفّح النبضات السابقة',

  'pulse.empty.title': 'لم يُنشر نبض اليوم بعد',
  'pulse.empty.body':
      'نبض اليوم قيد الإعداد. اقرأ النبضات السابقة في الأرشيف إلى حين نشره.',
  'pulse.error.offline.title': 'أنت غير متصل بالإنترنت',
  'pulse.error.offline.body':
      'تحقق من اتصالك وحاول مرة أخرى. عناصرك المحفوظة ما زالت متاحة.',
  'pulse.error.server.title': 'تعذّر تحميل نبض اليوم',
  'pulse.error.server.body': 'حدث خطأ من جانبنا. حاول مرة أخرى بعد قليل.',
  'pulse.error.retry': 'حاول مرة أخرى',
  'pulse.refreshFailed': 'تعذّر التحديث. نعرض آخر تحديث.',

  'pulse.tip.title': 'جديد: نبض أُنمُو',
  'pulse.tip.body':
      'أربعة عناصر كل يوم: أهم الأحداث العالمية والخليجية، والتغيّرات الشرعية، وفرصة واحدة. اضغط على أي بطاقة لترى مصدرها ودليلها.',
  'pulse.tip.dismiss': 'فهمت',

  'pulse.detail.analysisTitle': 'تحليل وتفسير، وليس معلومة مؤكدة',
  'pulse.detail.analysisBody':
      'يشرح هذا العنصر ما قد يعنيه الخبر. هو تفسير ويُعرض بشكل منفصل عن المعلومات المؤكدة.',
  'pulse.detail.correctedNote': 'تم التصحيح @time.',
  'pulse.detail.updatedNote': 'تم التحديث @time.',
  'pulse.detail.sources': 'المصادر والأدلة',
  'pulse.detail.source': 'المصدر',
  'pulse.detail.link': 'الرابط',
  'pulse.detail.evidence': 'الدليل',
  'pulse.detail.verified': 'وقت التحقق',
  'pulse.detail.published': 'وقت النشر',
  'pulse.detail.openSource': 'فتح المصدر',
  'pulse.detail.openStock': 'فتح السهم',
  'pulse.detail.save': 'حفظ',
  'pulse.detail.saved': 'تم الحفظ',
  'pulse.detail.share': 'مشاركة',
  'pulse.detail.notFoundTitle': 'هذا العنصر غير متاح',
  'pulse.detail.notFoundBody': 'ربما تم سحبه. ارجع إلى نبض اليوم.',
  'pulse.detail.saveFailed': 'تعذّر تحديث عناصرك المحفوظة. حاول مرة أخرى.',
  'pulse.detail.linkFailed': 'تعذّر فتح الرابط.',
  'pulse.share.text': '@title\n@summary\n\nعبر نبض أُنمُو',

  'pulse.archive.title': 'الأرشيف',
  'pulse.archive.all': 'الكل',
  'pulse.archive.saved': 'المحفوظ',
  'pulse.archive.search': 'ابحث في النبضات السابقة',
  'pulse.archive.allDays': 'كل الأيام',
  'pulse.archive.emptyTitle': 'لم نجد أي نبض',
  'pulse.archive.emptyBody': 'جرّب يومًا آخر أو بحثًا مختلفًا.',
  'pulse.saved.emptyTitle': 'لا يوجد شيء محفوظ بعد',
  'pulse.saved.emptyBody': 'اضغط على أيقونة الحفظ في أي عنصر لتبقيه هنا.',
  'pulse.archive.loadMoreFailed': 'تعذّر تحميل المزيد. اسحب للأسفل للمحاولة.',

  'pulse.prefs.title': 'إشعارات نبض',
  'pulse.prefs.master': 'إشعارات نبض أُنمُو',
  'pulse.prefs.masterHint': 'المفتاح الرئيسي لكل ما يلي.',
  'pulse.prefs.header': 'أخبرني عند',
  'pulse.prefs.new': 'نشر نبض جديد',
  'pulse.prefs.updates': 'تحديث عنصر سابق',
  'pulse.prefs.corrections': 'تصحيح عنصر سابق',
  'pulse.prefs.saved': 'تغيّر عنصر محفوظ',
  'pulse.prefs.footer':
      'تصلك الإشعارات بلغة التطبيق التي اخترتها. يمكنك إيقافها في أي وقت.',
  'pulse.prefs.pushOff':
      'الإشعارات متوقفة لتطبيق أُنمُو، لذلك لن يصلك أي مما يلي.',
  'pulse.prefs.saveFailed': 'تعذّر حفظ الإعداد. حاول مرة أخرى.',
  'pulse.prefs.loadFailed': 'تعذّر تحميل إعداداتك. نعرض الإعدادات الافتراضية.',
};
