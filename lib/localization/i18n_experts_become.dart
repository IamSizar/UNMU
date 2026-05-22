/// Arabic / English localization map for the *become-an-expert* flow:
/// the apply/re-apply form screen, the profile-screen "become an expert"
/// banner (its CTA / pending / rejected state cards), and the celebratory
/// expert-welcome dialog shown the moment an application is approved.
///
/// This file is OWNED by the become-expert localization worker. The central
/// table at `app_translations.dart` merges these two maps in — do NOT add
/// these keys there directly.
///
/// Namespaces used here (avoids collisions with other workers):
///   apply.  becomeExpert.  expertWelcome.
///
/// `common.*` keys are intentionally NOT redefined — they live centrally
/// (common.cancel, common.remove, common.required, …).
///
/// INVARIANT: `expertsBecomeEn` and `expertsBecomeAr` MUST contain the exact
/// same set of keys. A missing Arabic key would leak English in RTL.
library;

const Map<String, String> expertsBecomeEn = {
  // ── Apply / re-apply form screen ──
  'apply.title': 'Apply to be an Expert',
  'apply.titleReapply': 'Update your application',
  'apply.introTitle': 'Become a verified expert',
  'apply.introSubtitle': 'Post articles and short videos. Earn from subscribers.',
  'apply.rejectionTitle': 'Why your last application was declined',
  'apply.avatarSection': 'Profile picture (optional)',
  'apply.avatarAdd': 'Add a profile picture',
  'apply.avatarUploaded': 'Picture uploaded',
  'apply.avatarHint': 'JPG / PNG / WebP · up to 8 MB',
  'apply.tapToReplace': 'Tap to replace',
  'apply.resumeSection': 'Resume / credentials (optional · PDF)',
  'apply.resumeAdd': 'Add resume / credentials',
  'apply.resumeUploaded': 'PDF uploaded',
  'apply.resumeHint': 'PDF only · up to 10 MB',
  'apply.detailsSection': 'Your details',
  'apply.fullNameLabel': 'Full name',
  'apply.fullNameHint': 'e.g. Sheikh Abdullah Al-Mansoori',
  'apply.expertiseLabel': 'Area of expertise',
  'apply.expertiseHint': 'e.g. Tech Stocks, Sukuk, Shariah Compliance',
  'apply.countryLabel': 'Country (optional)',
  'apply.countryHint': 'e.g. Saudi Arabia',
  'apply.bioLabel': 'Bio',
  'apply.bioHint':
      'Tell us about your background and what you\'ll cover. Min 20 chars.',
  'apply.bioTooShort': 'Please write at least 20 characters',
  'apply.credentialsSection': 'Credentials',
  'apply.credentialsHint': 'e.g. CFA Charterholder, AAOIFI Certified',
  'apply.sampleSection': 'Sample work (optional)',
  'apply.sampleHint': 'paste a link to an article or video',
  'apply.submit': 'Submit application',
  'apply.resubmit': 'Re-submit application',
  'apply.submitFailed': 'Submission failed',
  'apply.reviewNote': 'Our team typically reviews applications within 48 hours.',
  'apply.cooldownDays': 'You can re-apply in about @count day@plural.',
  'apply.cooldownHours': 'You can re-apply in about @count hour@plural.',

  // ── Become-expert banner (profile screen) ──
  'becomeExpert.ctaTitle': 'Become an Expert',
  'becomeExpert.ctaSubtitle': 'Post articles and reels. Earn from subscribers.',
  'becomeExpert.pendingTitle': 'Application pending',
  'becomeExpert.pendingSubtitle':
      'Submitted @when · usually reviewed within 48 hours.',
  'becomeExpert.whenToday': 'today',
  'becomeExpert.whenYesterday': 'yesterday',
  'becomeExpert.whenDaysAgo': '@count days ago',
  'becomeExpert.withdraw': 'Withdraw',
  'becomeExpert.withdrawTitle': 'Withdraw application?',
  'becomeExpert.withdrawBody':
      'Your pending application will be removed. You can submit a new one right away.',
  'becomeExpert.withdrawFailed': 'Withdraw failed',
  'becomeExpert.rejectedTitle': 'Application not approved',
  'becomeExpert.applyAgain': 'Apply again',

  // ── Expert-welcome dialog (post-approval) ──
  'expertWelcome.microLabel': 'APPLICATION APPROVED',
  'expertWelcome.headline': 'You\'re a\nVerified Expert',
  'expertWelcome.subtitle':
      'Publish articles, videos, and reels. Start earning from subscribers.',
  'expertWelcome.capArticles': 'Publish articles',
  'expertWelcome.capVideos': 'Upload videos & reels',
  'expertWelcome.capEarn': 'Earn from subscribers',
  'expertWelcome.capCommunity': 'Run your own community',
  'expertWelcome.cta': 'Reload to start',
  'expertWelcome.footer': 'The app restarts to apply your role',
};

const Map<String, String> expertsBecomeAr = {
  // ── Apply / re-apply form screen ──
  'apply.title': 'تقدّم لتصبح خبيراً',
  'apply.titleReapply': 'تحديث طلبك',
  'apply.introTitle': 'كن خبيراً موثوقاً',
  'apply.introSubtitle': 'انشر المقالات والفيديوهات القصيرة. واكسب من المشتركين.',
  'apply.rejectionTitle': 'سبب رفض طلبك السابق',
  'apply.avatarSection': 'صورة الملف الشخصي (اختياري)',
  'apply.avatarAdd': 'أضف صورة للملف الشخصي',
  'apply.avatarUploaded': 'تم رفع الصورة',
  'apply.avatarHint': 'JPG / PNG / WebP · حتى 8 MB',
  'apply.tapToReplace': 'اضغط للاستبدال',
  'apply.resumeSection': 'السيرة الذاتية / الشهادات (اختياري · PDF)',
  'apply.resumeAdd': 'أضف السيرة الذاتية / الشهادات',
  'apply.resumeUploaded': 'تم رفع ملف PDF',
  'apply.resumeHint': 'PDF فقط · حتى 10 MB',
  'apply.detailsSection': 'بياناتك',
  'apply.fullNameLabel': 'الاسم الكامل',
  'apply.fullNameHint': 'مثال: الشيخ عبدالله المنصوري',
  'apply.expertiseLabel': 'مجال الخبرة',
  'apply.expertiseHint': 'مثال: أسهم التقنية، الصكوك، التوافق الشرعي',
  'apply.countryLabel': 'الدولة (اختياري)',
  'apply.countryHint': 'مثال: السعودية',
  'apply.bioLabel': 'نبذة تعريفية',
  'apply.bioHint':
      'أخبرنا عن خلفيتك وما الذي ستغطّيه. 20 حرفاً على الأقل.',
  'apply.bioTooShort': 'يرجى كتابة 20 حرفاً على الأقل',
  'apply.credentialsSection': 'الشهادات',
  'apply.credentialsHint': 'مثال: حاصل على CFA، معتمد من AAOIFI',
  'apply.sampleSection': 'أعمال نموذجية (اختياري)',
  'apply.sampleHint': 'الصق رابطاً لمقال أو فيديو',
  'apply.submit': 'إرسال الطلب',
  'apply.resubmit': 'إعادة إرسال الطلب',
  'apply.submitFailed': 'فشل إرسال الطلب',
  'apply.reviewNote': 'يراجع فريقنا الطلبات عادةً خلال 48 ساعة.',
  'apply.cooldownDays': 'يمكنك إعادة التقديم خلال @count يوم تقريباً.',
  'apply.cooldownHours': 'يمكنك إعادة التقديم خلال @count ساعة تقريباً.',

  // ── Become-expert banner (profile screen) ──
  'becomeExpert.ctaTitle': 'كن خبيراً',
  'becomeExpert.ctaSubtitle': 'انشر المقالات والريلز. واكسب من المشتركين.',
  'becomeExpert.pendingTitle': 'الطلب قيد المراجعة',
  'becomeExpert.pendingSubtitle':
      'أُرسل @when · تتم المراجعة عادةً خلال 48 ساعة.',
  'becomeExpert.whenToday': 'اليوم',
  'becomeExpert.whenYesterday': 'أمس',
  'becomeExpert.whenDaysAgo': 'قبل @count يوم',
  'becomeExpert.withdraw': 'سحب الطلب',
  'becomeExpert.withdrawTitle': 'سحب الطلب؟',
  'becomeExpert.withdrawBody':
      'سيتم حذف طلبك قيد المراجعة. يمكنك إرسال طلب جديد فوراً.',
  'becomeExpert.withdrawFailed': 'فشل سحب الطلب',
  'becomeExpert.rejectedTitle': 'لم تتم الموافقة على الطلب',
  'becomeExpert.applyAgain': 'التقديم مرة أخرى',

  // ── Expert-welcome dialog (post-approval) ──
  'expertWelcome.microLabel': 'تمت الموافقة على الطلب',
  'expertWelcome.headline': 'أنت\nخبير معتمد',
  'expertWelcome.subtitle':
      'انشر المقالات والفيديوهات والريلز. وابدأ بكسب الإيرادات من المشتركين.',
  'expertWelcome.capArticles': 'انشر المقالات',
  'expertWelcome.capVideos': 'ارفع الفيديوهات والريلز',
  'expertWelcome.capEarn': 'اكسب من المشتركين',
  'expertWelcome.capCommunity': 'أدر مجتمعك الخاص',
  'expertWelcome.cta': 'أعد التشغيل للبدء',
  'expertWelcome.footer': 'سيتم إعادة تشغيل التطبيق لتطبيق دورك الجديد',
};
