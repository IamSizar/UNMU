/// Arabic / English localization map for the *profile & account* surface:
/// the profile screen (hero, stats, quick actions, preferences, language
/// switcher, about, test mode, logout) plus the change-email,
/// change-password and delete-account flows.
///
/// This file is OWNED by the profile/account localization worker. The
/// central table at `app_translations.dart` merges these two maps in — do
/// NOT add these keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   profile.  account.  changeEmail.  changePassword.  deleteAccount.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally.
///
/// SPECIAL CASE: the two language OPTION names ("English" / "العربية") are
/// shown in their own native script regardless of UI locale, so they are
/// NOT routed through these maps.
///
/// INVARIANT: `profileAccountEn` and `profileAccountAr` MUST contain the
/// exact same set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> profileAccountEn = {
  // ── Profile screen — chrome ──
  'profile.title': 'Profile',
  'profile.settingsTooltip': 'Settings',

  // Sign-in hero (unauthenticated).
  'profile.signInWelcome': 'Welcome to UNMU',
  'profile.signInSubtitle':
      'Sign in to track your portfolio and unlock features',
  'profile.signIn': 'Sign in',

  // Hero tier / upgrade.
  'profile.premiumMember': 'Premium Member',
  'profile.freeMember': 'Free Member',
  'profile.upgrade': 'Upgrade',
  'profile.upgradeToUnlock': 'Upgrade to unlock all features',
  'profile.editPill': 'Edit',

  // Role badges (hero pill).
  'profile.badgeVerifiedExpert': 'VERIFIED EXPERT',
  'profile.badgeAdmin': 'ADMIN',
  'profile.badgeMember': 'MEMBER',

  // Stats strip.
  'profile.statWatchlist': 'Watchlist',
  'profile.statNetwork': 'Network',
  'profile.statMember': 'Member',

  // Section headers (eyebrow + title).
  'profile.sectionQuickEyebrow': 'Quick',
  'profile.sectionQuickTitle': 'Actions',
  'profile.sectionPrefsEyebrow': 'Preferences',
  'profile.sectionPrefsTitle': 'Settings',
  'profile.sectionAccountEyebrow': 'Account',
  'profile.sectionAccountTitle': 'Security & data',
  'profile.sectionTestEyebrow': 'Test mode',
  'profile.sectionTestTitle': 'Accounts',
  'profile.sectionAboutEyebrow': 'App',
  'profile.sectionAboutTitle': 'About',

  // Quick actions tiles.
  'profile.quickWatchlistTitle': 'Watchlist',
  'profile.quickWatchlistSubtitle': 'Stocks you track',
  'profile.quickToolsTitle': 'Tools',
  'profile.quickToolsSubtitle': 'Calculators & helpers',
  'profile.quickDcaTitle': 'DCA Calculator',
  'profile.quickDcaSubtitle': 'Monthly investing',
  'profile.quickZakatTitle': 'Zakat Calculator',
  'profile.quickZakatSubtitle': 'Annual obligation',
  'profile.quickSubscriptionsTitle': 'My Subscriptions',
  'profile.quickSubscriptionsSubtitle': 'Experts you follow',
  'profile.quickSavedTitle': 'Saved',
  'profile.quickSavedSubtitle': 'Posts you bookmarked',

  // Preferences card rows.
  'profile.darkMode': 'Dark Mode',
  'profile.language': 'Language',
  'profile.currency': 'Currency',

  // Test-mode card.
  'profile.currentRole': 'Current role',
  'profile.roleUser': 'User',
  'profile.roleExpert': 'Expert',
  'profile.roleScholar': 'Scholar',
  'profile.switchTestAccount': 'Switch test account',

  // About card rows + dialog.
  'profile.about': 'About',
  'profile.aboutBody': 'Halal Stocks Analytics App\nVersion 1.0.0',
  'profile.communityInvitations': 'Community invitations',
  'profile.contactAdmin': 'Contact Admin',
  'profile.privacyPolicy': 'Privacy Policy',
  'profile.termsOfService': 'Terms of Service',

  // Open Studio banner.
  'profile.openStudio': 'Open Studio',
  'profile.openStudioSubtitle':
      'Publish articles, videos, and reels to your subscribers.',

  // Logout.
  'profile.logout': 'Logout',
  'profile.logoutConfirmTitle': 'Logout',
  'profile.logoutConfirmBody': 'Are you sure you want to logout?',

  // ── Account card rows ──
  'account.notificationPrefs': 'Notification preferences',
  'account.changePassword': 'Change password',
  'account.changeEmail': 'Change email',
  'account.deleteAccount': 'Delete account',

  // ── Change email flow ──
  'changeEmail.title': 'Change email',
  'changeEmail.step1Intro':
      'Current email: @email\n\nEnter a new email and your password — we\'ll send a 6-digit code to the new address.',
  'changeEmail.newEmail': 'New email',
  'changeEmail.currentPassword': 'Current password',
  'changeEmail.sendCode': 'Send code',
  'changeEmail.step2Intro': 'We sent a code to @email. Paste it below to confirm.',
  'changeEmail.code': 'Verification code',
  'changeEmail.confirm': 'Confirm new email',
  'changeEmail.startOver': 'Start over',
  'changeEmail.updated': 'Email updated.',

  // ── Change password flow ──
  'changePassword.title': 'Change password',
  'changePassword.intro':
      'Enter your current password, then choose a new one (6+ characters).',
  'changePassword.current': 'Current password',
  'changePassword.new': 'New password',
  'changePassword.confirm': 'Confirm new password',
  'changePassword.mismatch': 'Passwords don\'t match',
  'changePassword.update': 'Update password',
  'changePassword.updated': 'Password updated.',

  // ── Delete account flow ──
  'deleteAccount.title': 'Delete account',
  'deleteAccount.warning':
      'Deletion is permanent. You\'ll lose access to @email and won\'t be able to sign back in. Your previous posts will show as "Deleted User".',
  'deleteAccount.password': 'Password',
  'deleteAccount.passwordHint': 'Leave blank if you sign in with Google / Apple',
  'deleteAccount.typeToConfirm': 'Type DELETE to confirm',
  'deleteAccount.deleteForever': 'Delete forever',
  'deleteAccount.confirmTitle': 'Delete account?',
  'deleteAccount.confirmBody':
      'This will deactivate your account, free your email for re-registration, and anonymize your authored content. There is no undo.',
  'deleteAccount.deletePermanently': 'Delete forever',
  'deleteAccount.deleted': 'Your account has been deleted.',
};

const Map<String, String> profileAccountAr = {
  // ── Profile screen — chrome ──
  'profile.title': 'حسابي',
  'profile.settingsTooltip': 'الإعدادات',

  // Sign-in hero (unauthenticated).
  'profile.signInWelcome': 'مرحباً بك',
  'profile.signInSubtitle': 'سجل دخولك لتتبع محفظتك واستثماراتك',
  'profile.signIn': 'تسجيل الدخول',

  // Hero tier / upgrade.
  'profile.premiumMember': 'عضو مميز',
  'profile.freeMember': 'عضو مجاني',
  'profile.upgrade': 'ترقية',
  'profile.upgradeToUnlock': 'قم بالترقية لفتح جميع الميزات',
  'profile.editPill': 'تعديل',

  // Role badges (hero pill).
  'profile.badgeVerifiedExpert': 'خبير موثّق',
  'profile.badgeAdmin': 'مشرف',
  'profile.badgeMember': 'عضو',

  // Stats strip.
  'profile.statWatchlist': 'متابعة',
  'profile.statNetwork': 'الشبكة',
  'profile.statMember': 'العضوية',

  // Section headers (eyebrow + title).
  'profile.sectionQuickEyebrow': 'سريع',
  'profile.sectionQuickTitle': 'الإجراءات',
  'profile.sectionPrefsEyebrow': 'تفضيلات',
  'profile.sectionPrefsTitle': 'الإعدادات',
  'profile.sectionAccountEyebrow': 'الحساب',
  'profile.sectionAccountTitle': 'الأمان والبيانات',
  'profile.sectionTestEyebrow': 'وضع الاختبار',
  'profile.sectionTestTitle': 'الحسابات',
  'profile.sectionAboutEyebrow': 'التطبيق',
  'profile.sectionAboutTitle': 'حول',

  // Quick actions tiles.
  'profile.quickWatchlistTitle': 'قائمة المتابعة',
  'profile.quickWatchlistSubtitle': 'الأسهم التي تتابعها',
  'profile.quickToolsTitle': 'الأدوات',
  'profile.quickToolsSubtitle': 'الحاسبات والأدوات',
  'profile.quickDcaTitle': 'حاسبة DCA',
  'profile.quickDcaSubtitle': 'استثمار شهري',
  'profile.quickZakatTitle': 'حاسبة الزكاة',
  'profile.quickZakatSubtitle': 'احسب زكاتك',
  'profile.quickSubscriptionsTitle': 'اشتراكاتي',
  'profile.quickSubscriptionsSubtitle': 'الخبراء الذين تتابعهم',
  'profile.quickSavedTitle': 'المحفوظات',
  'profile.quickSavedSubtitle': 'المنشورات التي حفظتها للقراءة لاحقًا',

  // Preferences card rows.
  'profile.darkMode': 'الوضع الداكن',
  'profile.language': 'اللغة',
  'profile.currency': 'العملة',

  // Test-mode card.
  'profile.currentRole': 'الدور الحالي',
  'profile.roleUser': 'مستخدم',
  'profile.roleExpert': 'خبير',
  'profile.roleScholar': 'فقيه',
  'profile.switchTestAccount': 'تبديل الحساب',

  // About card rows + dialog.
  'profile.about': 'حول التطبيق',
  'profile.aboutBody': 'تطبيق تحليل الأسهم الحلال\nالإصدار 1.0.0',
  'profile.communityInvitations': 'دعوات المجتمعات',
  'profile.contactAdmin': 'تواصل مع الإدارة',
  'profile.privacyPolicy': 'سياسة الخصوصية',
  'profile.termsOfService': 'شروط الخدمة',

  // Open Studio banner.
  'profile.openStudio': 'افتح الاستوديو',
  'profile.openStudioSubtitle':
      'انشر المقالات والفيديوهات والريلز لمشتركيك.',

  // Logout.
  'profile.logout': 'تسجيل الخروج',
  'profile.logoutConfirmTitle': 'تسجيل الخروج',
  'profile.logoutConfirmBody': 'هل أنت متأكد من تسجيل الخروج؟',

  // ── Account card rows ──
  'account.notificationPrefs': 'تفضيلات الإشعارات',
  'account.changePassword': 'تغيير كلمة المرور',
  'account.changeEmail': 'تغيير البريد',
  'account.deleteAccount': 'حذف الحساب',

  // ── Change email flow ──
  'changeEmail.title': 'تغيير البريد',
  'changeEmail.step1Intro':
      'بريدك الحالي: @email\n\nأدخل بريدًا جديدًا وكلمة المرور — سنرسل رمزًا إلى البريد الجديد للتأكيد.',
  'changeEmail.newEmail': 'البريد الجديد',
  'changeEmail.currentPassword': 'كلمة المرور الحالية',
  'changeEmail.sendCode': 'إرسال الرمز',
  'changeEmail.step2Intro': 'أرسلنا رمزًا إلى @email. الصقه أدناه للتأكيد.',
  'changeEmail.code': 'رمز التأكيد',
  'changeEmail.confirm': 'تأكيد البريد الجديد',
  'changeEmail.startOver': 'بدء من جديد',
  'changeEmail.updated': 'تم تحديث البريد.',

  // ── Change password flow ──
  'changePassword.title': 'تغيير كلمة المرور',
  'changePassword.intro':
      'أدخل كلمة المرور الحالية ثم اختر كلمة جديدة (6 أحرف على الأقل).',
  'changePassword.current': 'كلمة المرور الحالية',
  'changePassword.new': 'كلمة المرور الجديدة',
  'changePassword.confirm': 'أعد كتابة كلمة المرور',
  'changePassword.mismatch': 'كلمتا المرور غير متطابقتين',
  'changePassword.update': 'تحديث كلمة المرور',
  'changePassword.updated': 'تم تحديث كلمة المرور.',

  // ── Delete account flow ──
  'deleteAccount.title': 'حذف الحساب',
  'deleteAccount.warning':
      'حذف الحساب نهائي. سيُحذف الوصول إلى @email ولن تتمكن من تسجيل الدخول مرة أخرى. منشوراتك السابقة ستظهر باسم "مستخدم محذوف".',
  'deleteAccount.password': 'كلمة المرور',
  'deleteAccount.passwordHint': 'اتركها فارغة إن كنت تستخدم Google / Apple',
  'deleteAccount.typeToConfirm': 'اكتب DELETE للتأكيد',
  'deleteAccount.deleteForever': 'حذف الحساب نهائيًا',
  'deleteAccount.confirmTitle': 'حذف الحساب؟',
  'deleteAccount.confirmBody':
      'سيؤدي هذا إلى تعطيل حسابك وإتاحة بريدك لإعادة التسجيل وإخفاء هوية المحتوى الذي أنشأته. لا يمكن التراجع.',
  'deleteAccount.deletePermanently': 'حذف نهائي',
  'deleteAccount.deleted': 'تم حذف حسابك.',
};
