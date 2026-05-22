import 'package:get/get.dart';

// Feature string maps — kept in their own files so large feature areas can be
// localized independently, then merged into the single central table below.
import 'i18n_stocks.dart';
import 'i18n_community_core.dart';
import 'i18n_community_more.dart';
import 'i18n_feed_hub.dart';
import 'i18n_posts_profile.dart';
import 'i18n_experts_become.dart';
import 'i18n_experts_dashboard.dart';
import 'i18n_experts_money.dart';
import 'i18n_subscriptions.dart';
import 'i18n_monetization.dart';
import 'i18n_feed_media.dart';
import 'i18n_reels_video.dart';
import 'i18n_notifications.dart';
import 'i18n_saved_interactions.dart';
import 'i18n_profile_account.dart';
import 'i18n_edit_profile.dart';
import 'i18n_support.dart';
import 'i18n_legal.dart';
import 'i18n_misc.dart';
import 'i18n_widgets.dart';
import 'i18n_widgets2.dart';

/// =============================================================================
/// Centralized app translations (GetX i18n) — the single source of truth.
///
/// Usage:
///   • Simple:   'auth.login.cta'.tr
///   • Params:   'auth.login.oauthFailed'.trParams({'label': 'Google'})
///               (GetX replaces the `@label` token in the string)
///
/// Key naming convention — dotted, lowerCamel segments grouped by feature:
///   `area.screen.thing`      e.g. auth.login.welcomeBack, nav.discover
///
/// RULES (per product owner):
///   • EVERYTHING that is app chrome (buttons, labels, menus, errors, empty
///     states, tooltips) MUST have an Arabic entry — zero English in Arabic.
///   • User-generated content is NEVER put here (post bodies/titles, names,
///     chat messages, tickers like AAPL, promo codes, the brand "UNMU").
///   • Numbers/prices stay Western digits (see LocaleFormat) — only labels,
///     month names and relative-time words get translated.
///
/// New phases ADD their keys to both maps below. Keep the two maps in the
/// same order so it's easy to eyeball that every key has an Arabic pair.
/// =============================================================================
class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'en': {
          ..._en,
          ...stocksEn,
          ...communityCoreEn,
          ...communityMoreEn,
          ...feedHubEn,
          ...postsProfileEn,
          ...expertsBecomeEn,
          ...expertsDashboardEn,
          ...expertsMoneyEn,
          ...subscriptionsEn,
          ...monetizationEn,
          ...feedMediaEn,
          ...reelsVideoEn,
          ...notificationsEn,
          ...savedInteractionsEn,
          ...profileAccountEn,
          ...editProfileEn,
          ...supportEn,
          ...legalEn,
          ...miscEn,
          ...widgetsEn,
          ...widgets2En,
        },
        'ar': {
          ..._ar,
          ...stocksAr,
          ...communityCoreAr,
          ...communityMoreAr,
          ...feedHubAr,
          ...postsProfileAr,
          ...expertsBecomeAr,
          ...expertsDashboardAr,
          ...expertsMoneyAr,
          ...subscriptionsAr,
          ...monetizationAr,
          ...feedMediaAr,
          ...reelsVideoAr,
          ...notificationsAr,
          ...savedInteractionsAr,
          ...profileAccountAr,
          ...editProfileAr,
          ...supportAr,
          ...legalAr,
          ...miscAr,
          ...widgetsAr,
          ...widgets2Ar,
        },
      };
}

// -----------------------------------------------------------------------------
// English
// -----------------------------------------------------------------------------
const Map<String, String> _en = {
  // ── App / brand ──────────────────────────────────────────────
  'app.name': 'UNMU',

  // ── Common actions & states (used app-wide) ──────────────────
  'common.ok': 'OK',
  'common.cancel': 'Cancel',
  'common.save': 'Save',
  'common.delete': 'Delete',
  'common.edit': 'Edit',
  'common.remove': 'Remove',
  'common.retry': 'Retry',
  'common.refresh': 'Refresh',
  'common.loading': 'Loading...',
  'common.error': 'Error',
  'common.done': 'Done',
  'common.close': 'Close',
  'common.confirm': 'Confirm',
  'common.search': 'Search',
  'common.next': 'Next',
  'common.back': 'Back',
  'common.empty': 'No data available',
  'common.unknownError': 'Something went wrong. Please try again.',
  'common.sessionExpired': 'Session expired.',
  'common.required': 'Required',
  'common.success': 'Done',

  // ── Bottom navigation ────────────────────────────────────────
  'nav.discover': 'Discover',
  'nav.indexes': 'Indexes',
  'nav.social': 'Social',
  'nav.feed': 'Feed',
  'nav.profile': 'Profile',
  'nav.backToDiscover': 'Back to Discover',

  // ── Feed filter pills ────────────────────────────────────────
  'feed.filter.articles': 'Articles',
  'feed.filter.videos': 'Videos',
  'feed.filter.reels': 'Reels',

  // ── Splash ───────────────────────────────────────────────────
  'splash.tagline': 'Halal markets · Verified experts · Live.',
  'splash.live': 'LIVE',

  // ── Auth — shared fields ─────────────────────────────────────
  'auth.email': 'Email',
  'auth.emailHint': 'you@example.com',
  'auth.password': 'Password',
  'auth.name': 'Your name',
  'auth.nameHint': 'Jane Doe',
  'auth.createPassword': 'Create password',
  'auth.confirmPassword': 'Confirm password',
  'auth.forgotPassword': 'Forgot password?',
  'auth.signOut': 'Sign out',
  'auth.orContinueWith': 'or continue with',
  'auth.testAccount': 'Test account',
  'auth.passwordTooShort': 'Password must be at least 6 characters',
  'auth.passwordsDontMatch': "Passwords don't match",

  // ── Auth — login ─────────────────────────────────────────────
  'auth.login.welcomeBack': 'Welcome back',
  'auth.login.subtitle': 'Sign in to continue to your portfolio',
  'auth.login.cta': 'Log in',
  'auth.login.notRegistered':
      'This account is not registered. Use Google or Apple to create one.',
  'auth.login.oauthFailed': 'Sign-in with @label failed',

  // ── Auth — onboarding ────────────────────────────────────────
  'auth.onboarding.title': 'Finish setting up',
  'auth.onboarding.subtitle':
      'Pick a name and a password — you can also sign in later with @email',
  'auth.onboarding.cta': 'Get started',

  // ── Auth — forgot password ───────────────────────────────────
  'auth.forgot.title': 'Forgot password?',
  'auth.forgot.subtitle': "Enter your email and we'll send a reset link.",
  'auth.forgot.cta': 'Send reset link',
  'auth.forgot.haveCode': 'Already have a code? Enter it',

  // ── Auth — reset password ────────────────────────────────────
  'auth.reset.title': 'Reset password',
  'auth.reset.subtitleNoEmail':
      'Paste the code from your email and pick a new password.',
  'auth.reset.subtitleEmail':
      'We sent a code to @email. Paste it below and pick a new password.',
  'auth.reset.codeLabel': 'Reset code',
  'auth.reset.codeHint': 'Paste the link or code from your email',
  'auth.reset.newPassword': 'New password',
  'auth.reset.confirm': 'Confirm password',
  'auth.reset.cta': 'Update password',
  'auth.reset.successSnack':
      'Password updated. Please sign in with the new one.',
};

// -----------------------------------------------------------------------------
// Arabic
// -----------------------------------------------------------------------------
const Map<String, String> _ar = {
  // ── App / brand ──────────────────────────────────────────────
  'app.name': 'UNMU',

  // ── Common actions & states ──────────────────────────────────
  'common.ok': 'حسناً',
  'common.cancel': 'إلغاء',
  'common.save': 'حفظ',
  'common.delete': 'حذف',
  'common.edit': 'تعديل',
  'common.remove': 'إزالة',
  'common.retry': 'إعادة المحاولة',
  'common.refresh': 'تحديث',
  'common.loading': 'جارٍ التحميل...',
  'common.error': 'خطأ',
  'common.done': 'تم',
  'common.close': 'إغلاق',
  'common.confirm': 'تأكيد',
  'common.search': 'بحث',
  'common.next': 'التالي',
  'common.back': 'رجوع',
  'common.empty': 'لا توجد بيانات',
  'common.unknownError': 'حدث خطأ ما. حاول مرة أخرى.',
  'common.sessionExpired': 'انتهت الجلسة.',
  'common.required': 'مطلوب',
  'common.success': 'تم',

  // ── Bottom navigation ────────────────────────────────────────
  'nav.discover': 'استكشف',
  'nav.indexes': 'المؤشرات',
  'nav.social': 'المجتمع',
  'nav.feed': 'المتابعات',
  'nav.profile': 'حسابي',
  'nav.backToDiscover': 'العودة إلى الاستكشاف',

  // ── Feed filter pills ────────────────────────────────────────
  'feed.filter.articles': 'مقالات',
  'feed.filter.videos': 'فيديوهات',
  'feed.filter.reels': 'ريلز',

  // ── Splash ───────────────────────────────────────────────────
  'splash.tagline': 'أسواق حلال · خبراء موثوقون · مباشر',
  'splash.live': 'مباشر',

  // ── Auth — shared fields ─────────────────────────────────────
  'auth.email': 'البريد الإلكتروني',
  'auth.emailHint': 'بريدك الإلكتروني',
  'auth.password': 'كلمة المرور',
  'auth.name': 'الاسم',
  'auth.nameHint': 'اسمك',
  'auth.createPassword': 'كلمة المرور',
  'auth.confirmPassword': 'تأكيد كلمة المرور',
  'auth.forgotPassword': 'نسيت كلمة المرور؟',
  'auth.signOut': 'تسجيل الخروج',
  'auth.orContinueWith': 'أو تابع باستخدام',
  'auth.testAccount': 'حساب تجريبي',
  'auth.passwordTooShort': 'كلمة المرور يجب أن تكون 6 أحرف على الأقل',
  'auth.passwordsDontMatch': 'كلمتا المرور غير متطابقتين',

  // ── Auth — login ─────────────────────────────────────────────
  'auth.login.welcomeBack': 'مرحباً بعودتك',
  'auth.login.subtitle': 'سجّل الدخول للمتابعة إلى محفظتك',
  'auth.login.cta': 'تسجيل الدخول',
  'auth.login.notRegistered':
      'هذا الحساب غير مسجّل. سجّل عبر Google أو Apple أولاً.',
  'auth.login.oauthFailed': 'فشل تسجيل الدخول عبر @label',

  // ── Auth — onboarding ────────────────────────────────────────
  'auth.onboarding.title': 'أكمل إعداد حسابك',
  'auth.onboarding.subtitle':
      'اختر اسمك وكلمة مرور — ستتمكن من الدخول لاحقًا بالبريد @email',
  'auth.onboarding.cta': 'ابدأ الآن',

  // ── Auth — forgot password ───────────────────────────────────
  'auth.forgot.title': 'هل نسيت كلمة المرور؟',
  'auth.forgot.subtitle': 'سنرسل لك رابطًا لإعادة تعيين كلمة المرور إلى بريدك.',
  'auth.forgot.cta': 'إرسال رابط الإعادة',
  'auth.forgot.haveCode': 'لديك رمز بالفعل؟',

  // ── Auth — reset password ────────────────────────────────────
  'auth.reset.title': 'إعادة تعيين كلمة المرور',
  'auth.reset.subtitleNoEmail':
      'الصق الرمز الذي تلقيته في بريدك ثم اختر كلمة جديدة.',
  'auth.reset.subtitleEmail': 'أرسلنا رمزًا إلى @email. الصقه واختر كلمة جديدة.',
  'auth.reset.codeLabel': 'رمز الإعادة',
  'auth.reset.codeHint': 'الصق الرابط أو الرمز من بريدك',
  'auth.reset.newPassword': 'كلمة المرور الجديدة',
  'auth.reset.confirm': 'أعد كتابة كلمة المرور',
  'auth.reset.cta': 'تحديث كلمة المرور',
  'auth.reset.successSnack': 'تم تحديث كلمة المرور. سجّل الدخول بالكلمة الجديدة.',
};
