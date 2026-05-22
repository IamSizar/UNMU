// Feature string map — social widgets batch 2 (poll creator, new-message
// banner, chat search, trading chart, test-account switcher). Merged into the
// central table in app_translations.dart. Keep both maps key-identical.

const Map<String, String> widgets2En = {
  // Source badge (post origin: profile / community / member)
  'sourceBadge.from': 'FROM',
  'sourceBadge.fromProfile': 'FROM PROFILE',
  'sourceBadge.aMember': 'a member',
  'sourceBadge.communityFallback': 'Community',
  'sourceBadge.expertFallback': 'Expert',
  'sourceBadge.communityUnavailable': 'Community not available yet.',

  // Poll creator sheet
  'pollCreator.title': 'Create a poll',
  'pollCreator.question': 'Question',
  'pollCreator.questionHint': 'Will \$NVDA hit \$200 by Dec?',
  'pollCreator.options': 'Options (2..4)',
  'pollCreator.optionHint': 'Option @n',
  'pollCreator.addOption': 'Add option',
  'pollCreator.duration': 'Duration',
  'pollCreator.durationOpen': 'Open',
  'pollCreator.duration1Hour': '1 hour',
  'pollCreator.duration24Hours': '24 hours',
  'pollCreator.duration7Days': '7 days',
  'pollCreator.anonymousTitle': 'Anonymous voting',
  'pollCreator.anonymousSubtitle': 'Hide who voted for what — only counts shown.',
  'pollCreator.postPoll': 'Post poll',
  'pollCreator.errQuestionLength': 'Question must be 1..200 chars.',
  'pollCreator.errOptionLength': 'Each option must be ≤ 60 chars.',
  'pollCreator.errDuplicate': 'Duplicate option labels.',
  'pollCreator.errMinOptions': 'Need at least 2 options.',

  // New-message banner
  'msgBanner.voiceMessage': '🎙️  Voice message',
  'msgBanner.newMessage': 'New message',
  'msgBanner.community': 'Community',
  'msgBanner.open': 'Open',

  // Chat search
  'chatSearch.hint': 'Search this chat',
  'chatSearch.typeMin': 'Type at least 2 characters',
  'chatSearch.noMatches': 'No matches.',

  // Trading chart
  'tradingChart.liveDemo': 'Live demo · NASDAQ',
  'tradingChart.noData': 'No data',

  // Test-account switcher
  'testAccounts.switchAccount': 'Switch account',
  'testAccounts.countSuffix': 'in the database',
  'testAccounts.accountOne': 'account',
  'testAccounts.accountMany': 'accounts',
  'testAccounts.searchHint': 'Search by email or name',
  'testAccounts.fallbackError':
      'Couldn\'t reach the dev users endpoint. Falling back to preset accounts.',
  'testAccounts.noAccounts': 'No accounts found.',
  'testAccounts.noMatches': 'No matches for "@query".',
  'testAccounts.unverified': 'UNVERIFIED',
  'testAccounts.switchFailedTitle': 'Couldn\'t switch',
  'testAccounts.switchFailedBody':
      'The backend rejected the impersonation. Is APP_ENV=production?',
  'testAccounts.dangerZone': 'DANGER ZONE',
  'testAccounts.dangerDesc':
      'Wipe every account except admin, plus all communities, posts, experts, applications, audit logs. Reference data (stocks, shariah, ads) is kept.',
  'testAccounts.resetButton': 'Reset DB — keep admin only',
  'testAccounts.resetTitle': 'Reset everything?',
  'testAccounts.resetBody1':
      'This wipes ALL accounts except admin@test.com plus every community, post, expert, application, and audit log.',
  'testAccounts.resetBody2':
      'Stocks, prices, and shariah data are KEPT. This cannot be undone.',
  'testAccounts.resetTypePrompt': 'Type RESET to confirm:',
  'testAccounts.resetConfirm': 'Reset 🔥',
  'testAccounts.resettingTitle': 'Resetting database…',
  'testAccounts.resettingBody': 'Wiping all non-admin data',
  'testAccounts.resetFailedTitle': 'Reset failed',
  'testAccounts.resetFailedBody': 'Backend rejected the wipe. Check server logs.',
  'testAccounts.resetDoneTitle': 'Database reset ✓',
  'testAccounts.resetDoneBody':
      '@users users · @communities communities · @posts posts · @experts experts · @other other rows',
};

const Map<String, String> widgets2Ar = {
  // Source badge (post origin: profile / community / member)
  'sourceBadge.from': 'من',
  'sourceBadge.fromProfile': 'من الملف',
  'sourceBadge.aMember': 'عضو',
  'sourceBadge.communityFallback': 'مجتمع',
  'sourceBadge.expertFallback': 'خبير',
  'sourceBadge.communityUnavailable': 'المجتمع غير متاح بعد.',

  // Poll creator sheet
  'pollCreator.title': 'إنشاء استطلاع',
  'pollCreator.question': 'السؤال',
  'pollCreator.questionHint': 'هل سيصل \$NVDA إلى \$200 بحلول ديسمبر؟',
  'pollCreator.options': 'الخيارات (2..4)',
  'pollCreator.optionHint': 'الخيار @n',
  'pollCreator.addOption': 'إضافة خيار',
  'pollCreator.duration': 'المدة',
  'pollCreator.durationOpen': 'مفتوح',
  'pollCreator.duration1Hour': 'ساعة واحدة',
  'pollCreator.duration24Hours': '24 ساعة',
  'pollCreator.duration7Days': '7 أيام',
  'pollCreator.anonymousTitle': 'تصويت مجهول',
  'pollCreator.anonymousSubtitle': 'إخفاء من صوّت لماذا — تظهر الأعداد فقط.',
  'pollCreator.postPoll': 'نشر الاستطلاع',
  'pollCreator.errQuestionLength': 'يجب أن يكون السؤال بين 1 و200 حرفاً.',
  'pollCreator.errOptionLength': 'يجب ألا يتجاوز كل خيار 60 حرفاً.',
  'pollCreator.errDuplicate': 'خيارات مكررة.',
  'pollCreator.errMinOptions': 'يلزم خياران على الأقل.',

  // New-message banner
  'msgBanner.voiceMessage': '🎙️  رسالة صوتية',
  'msgBanner.newMessage': 'رسالة جديدة',
  'msgBanner.community': 'مجتمع',
  'msgBanner.open': 'فتح',

  // Chat search
  'chatSearch.hint': 'ابحث في هذه المحادثة',
  'chatSearch.typeMin': 'اكتب حرفين على الأقل',
  'chatSearch.noMatches': 'لا توجد نتائج.',

  // Trading chart
  'tradingChart.liveDemo': 'عرض مباشر · NASDAQ',
  'tradingChart.noData': 'لا توجد بيانات',

  // Test-account switcher
  'testAccounts.switchAccount': 'تبديل الحساب',
  'testAccounts.countSuffix': 'في قاعدة البيانات',
  'testAccounts.accountOne': 'حساب',
  'testAccounts.accountMany': 'حساب',
  'testAccounts.searchHint': 'ابحث بالبريد الإلكتروني أو الاسم',
  'testAccounts.fallbackError':
      'تعذّر الوصول إلى نقطة نهاية مستخدمي التطوير. سيتم استخدام الحسابات الافتراضية.',
  'testAccounts.noAccounts': 'لا توجد حسابات.',
  'testAccounts.noMatches': 'لا توجد نتائج لـ "@query".',
  'testAccounts.unverified': 'غير موثّق',
  'testAccounts.switchFailedTitle': 'تعذّر التبديل',
  'testAccounts.switchFailedBody':
      'رفض الخادم انتحال الهوية. هل APP_ENV=production؟',
  'testAccounts.dangerZone': 'منطقة الخطر',
  'testAccounts.dangerDesc':
      'حذف كل حساب باستثناء المسؤول، إضافة إلى جميع المجتمعات والمنشورات والخبراء والطلبات وسجلات التدقيق. تُحفَظ البيانات المرجعية (الأسهم، الشريعة، الإعلانات).',
  'testAccounts.resetButton': 'إعادة تعيين قاعدة البيانات — الإبقاء على المسؤول فقط',
  'testAccounts.resetTitle': 'إعادة تعيين كل شيء؟',
  'testAccounts.resetBody1':
      'سيؤدي هذا إلى حذف جميع الحسابات باستثناء admin@test.com إضافة إلى كل مجتمع ومنشور وخبير وطلب وسجل تدقيق.',
  'testAccounts.resetBody2':
      'تُحفَظ بيانات الأسهم والأسعار والشريعة. لا يمكن التراجع عن هذا الإجراء.',
  'testAccounts.resetTypePrompt': 'اكتب RESET للتأكيد:',
  'testAccounts.resetConfirm': 'إعادة تعيين 🔥',
  'testAccounts.resettingTitle': 'جارٍ إعادة تعيين قاعدة البيانات…',
  'testAccounts.resettingBody': 'جارٍ حذف جميع البيانات غير الخاصة بالمسؤول',
  'testAccounts.resetFailedTitle': 'فشلت إعادة التعيين',
  'testAccounts.resetFailedBody': 'رفض الخادم عملية الحذف. تحقق من سجلات الخادم.',
  'testAccounts.resetDoneTitle': 'تمت إعادة تعيين قاعدة البيانات ✓',
  'testAccounts.resetDoneBody':
      '@users مستخدم · @communities مجتمع · @posts منشور · @experts خبير · @other صف آخر',
};
