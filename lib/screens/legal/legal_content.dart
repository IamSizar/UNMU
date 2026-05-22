/// Production-ready legal copy for Privacy Policy and Terms of Service.
/// Kept as Dart constants (no asset files) so the screens render
/// instantly with zero IO, and so the strings survive `flutter clean`
/// without an extra pub-asset declaration.
///
/// The text is intentionally App-Store-safe: it names the legal entity,
/// lists every data category the backend actually stores, identifies
/// the third-party processors we ship today (Firebase, Apple IAP), and
/// provides a contact email for data-subject requests.
library;

const String kLegalLastUpdated = '2026-05-19';
const String kLegalContactEmail = 'support@unmu.app';

const String kPrivacyPolicyEn = '''
# Privacy Policy

**Last updated:** 2026-05-19

UNMU ("we", "us", "our") operates the UNMU mobile application and the
website at unmu.app (collectively, the "Service"). This Privacy Policy
explains what information we collect, how we use it, and the choices
you have.

## 1. Information we collect

**Account information.** When you create an account we collect your
email address, display name, and a salted hash of your password. If you
sign in with Apple or Google, we receive your email address and the
identity token issued by that provider.

**Profile information.** Anything you add to your profile — an avatar,
biography, or expert credentials — is stored so we can render your
account inside the app.

**Content you submit.** Posts, comments, community messages, polls,
voice notes, payment requests, expert applications, and support
messages are stored so other users can see them and so we can
investigate abuse.

**Device information.** When the app makes API requests we receive
your IP address (from the request itself), the operating system and
app version (sent as a User-Agent), and the Firebase Cloud Messaging
push token if you grant notification permission.

**Purchase information.** When you buy a subscription we receive the
purchase receipt from Apple. We do not see your payment card details —
Apple processes the payment and only tells us whether it succeeded.

## 2. How we use information

We use the information above to (a) operate and secure the Service,
(b) deliver the content you ask for, (c) send transactional messages
(verification codes, password resets, purchase confirmations,
moderation notices), (d) detect fraud and abuse, and (e) comply with
applicable law.

We do **not** sell your personal data. We do not use your data to
train third-party AI models.

## 3. Who we share information with

- **Apple** — receives in-app purchase events and (on iOS) the Apple
  Sign-In token. Subject to Apple's privacy policy.
- **Google Firebase** — processes authentication tokens and delivers
  push notifications. Hosted by Google LLC under Google's privacy
  policy.
- **Our hosting provider** — runs the API servers and database that
  store the data described above.
- **Law-enforcement authorities** — only when we receive a valid legal
  request.

We do not share data with advertising networks or analytics brokers.

## 4. Data retention

We keep your account data while your account exists. When you delete
your account from Settings → Security & data → Delete account, we
remove your profile, posts, comments, and message history within 30
days. Aggregate usage statistics (counts and timestamps with no
personal identifiers) may be kept longer for service-quality
monitoring.

## 5. Your rights

You can:

- view and edit your profile at any time from Settings,
- export the content you have created by contacting us,
- delete your account from Settings → Security & data,
- withdraw consent for push notifications from the device settings,
- email us with any privacy question or complaint.

Users in jurisdictions with statutory data-protection laws (EEA, UK,
California, GCC) have the additional rights granted by those laws —
access, correction, erasure, restriction, and portability. To
exercise them, email us using the address below.

## 6. Children

UNMU is not directed to children under 13 (or under 16 in the EEA).
We do not knowingly collect personal data from children. If you
believe a child has registered, contact us and we will delete the
account.

## 7. Security

We protect your data with TLS in transit, encrypted databases at rest,
hashed passwords, and signed authentication tokens. No system is
perfectly secure — please pick a strong, unique password and report
any suspected breach to us immediately.

## 8. Changes to this policy

We may update this Policy. Material changes are announced in-app
before they take effect. Continued use after a change means you
accept the new Policy.

## 9. Contact

Privacy questions, deletion requests, or complaints — email
**support@unmu.app**.
''';

const String kPrivacyPolicyAr = '''
# سياسة الخصوصية

**آخر تحديث:** 2026-05-19

تشغّل UNMU («نحن») تطبيق UNMU للهواتف الذكية وموقع unmu.app
(مجتمعَين «الخدمة»). تشرح هذه السياسة البيانات التي نجمعها وكيف
نستخدمها والخيارات المتاحة لك.

## 1. البيانات التي نجمعها

**بيانات الحساب.** عند إنشاء الحساب نحفظ بريدك الإلكتروني واسم العرض
ونسخة مُشفَّرة (Hash) من كلمة المرور. وعند تسجيل الدخول عبر Apple أو
Google نستلم منهما بريدك ورمز الهوية الصادر عنهما.

**بيانات الملف الشخصي.** الصورة الرمزية والنبذة والشهادات الخبيرة —
كل ما تضيفه يُحفظ ليظهر داخل التطبيق.

**المحتوى الذي تنشره.** المنشورات والتعليقات ورسائل المجتمعات
واستطلاعات الرأي والرسائل الصوتية وطلبات الدفع وطلبات الانضمام كخبير
ورسائل الدعم — تُخزَّن ليراها المستخدمون الآخرون وللتعامل مع البلاغات.

**بيانات الجهاز.** خلال طلبات API نستلم عنوان IP، ونظام التشغيل
ورقم إصدار التطبيق، ورمز إشعارات Firebase Cloud Messaging إذا
سمحت بالإشعارات.

**بيانات الشراء.** عند شراء اشتراك نستلم إيصال الشراء من Apple. لا
نرى بيانات بطاقتك المالية — تتولى Apple معالجة الدفع وتُخبرنا فقط
بنجاحه.

## 2. كيف نستخدم البيانات

نستخدمها لـ(أ) تشغيل الخدمة وتأمينها، (ب) تقديم المحتوى الذي تطلبه،
(ج) إرسال الرسائل التشغيلية (رموز التحقق، استرجاع كلمة المرور،
تأكيدات الشراء، إشعارات الإشراف)، (د) رصد الاحتيال والإساءة،
(هـ) الالتزام بالقوانين السارية.

لا نبيع بياناتك الشخصية. ولا نستخدمها لتدريب نماذج ذكاء اصطناعي
طرف ثالث.

## 3. مع مَن نشاركها

- **Apple** — تستلم أحداث الشراء داخل التطبيق ورمز Sign-In على iOS.
- **Google Firebase** — تتولى رموز المصادقة وإرسال الإشعارات.
- **مزود الاستضافة** — يُشغّل خوادم API وقاعدة البيانات.
- **الجهات القانونية** — فقط عند ورود طلب قانوني صحيح.

لا نشارك بياناتك مع شبكات إعلانية أو وسطاء تحليلات.

## 4. مدة الاحتفاظ

نحتفظ بالبيانات طوال وجود حسابك. وعند حذف الحساب من «الإعدادات →
الأمان والبيانات → حذف الحساب» نُزيل ملفك ومنشوراتك وتعليقاتك
وسجل رسائلك خلال 30 يومًا. قد نحتفظ بإحصائيات مُجمَّعة (دون
مُعرِّفات شخصية) لمدة أطول لمراقبة جودة الخدمة.

## 5. حقوقك

يمكنك:

- مراجعة وتعديل ملفك الشخصي في أي وقت من «الإعدادات».
- تصدير المحتوى الذي أنشأته عبر التواصل معنا.
- حذف الحساب من «الأمان والبيانات».
- سحب الإذن بالإشعارات من إعدادات الجهاز.
- مراسلتنا بأي سؤال أو شكوى عن الخصوصية.

يحق للمستخدمين في الدول ذات قوانين حماية البيانات (EEA, UK,
California, دول الخليج) ممارسة الحقوق الإضافية التي تكفلها تلك
القوانين — الوصول، التصحيح، الحذف، التقييد، النقل. للممارسة
راسلنا على البريد أدناه.

## 6. الأطفال

التطبيق ليس موجَّهًا لمن هم دون 13 سنة (أو 16 في الاتحاد الأوروبي).
لا نجمع عمدًا بيانات الأطفال. وعند علمنا بتسجيل طفل نقوم بحذف
الحساب.

## 7. الأمان

نحمي بياناتك بـ TLS أثناء النقل، وتشفير قاعدة البيانات، وتجزئة
كلمات المرور، ورموز توقيع المصادقة. لا يوجد نظام آمن بالكامل —
اختر كلمة مرور قوية وأبلغنا فورًا بأي اختراق محتمل.

## 8. التحديثات

قد نُحدِّث هذه السياسة. تُعلَن التغييرات الجوهرية داخل التطبيق قبل
سريانها. واستمرار الاستخدام بعد التحديث يُعدّ موافقة.

## 9. التواصل

للأسئلة وطلبات الحذف والشكاوى — راسلنا على
**support@unmu.app**.
''';

const String kTermsOfServiceEn = '''
# Terms of Service

**Last updated:** 2026-05-19

These Terms govern your use of the UNMU mobile application and the
website at unmu.app (the "Service"). By creating an account or using
the Service you agree to these Terms. If you do not agree, do not
use the Service.

## 1. Eligibility

You must be at least 13 years old (16 in the EEA) and capable of
entering into a binding contract. If you use the Service on behalf
of an organization, you confirm you have authority to bind it.

## 2. Your account

You are responsible for the activity that happens under your
account. Keep your password safe. Notify us at the address below if
you suspect any unauthorized use. We may suspend or terminate an
account that violates these Terms.

## 3. Acceptable use

You agree not to:

- post content that is unlawful, defamatory, hateful, sexual,
  violent, or that infringes someone else's rights;
- impersonate any person or misrepresent your credentials;
- harass, stalk, or threaten any user;
- attempt to break the Service, scrape it at scale, reverse-engineer
  it, or interfere with its operation;
- use the Service to send spam, malware, or unsolicited promotion;
- collect personal data about other users without their consent;
- use any automated system, bot, or scraper to access the Service
  without our written permission.

We may remove content or restrict access at our discretion when these
rules are broken.

## 4. User content & licence

You keep ownership of the content you post. By posting, you grant
UNMU a worldwide, non-exclusive, royalty-free licence to host,
display, reproduce, translate, and distribute that content inside
the Service and in promotional materials for the Service. This
licence ends when you delete the content, except for copies
necessary for operational backups or legal compliance.

You represent that you have all rights necessary to post the
content and that it does not violate any law or third-party right.

## 5. Subscriptions & in-app purchases

Some features require a paid subscription billed through the Apple
App Store. Apple's terms apply to the payment itself; we receive
only confirmation that a purchase succeeded. Subscriptions renew
automatically through your App Store account unless you cancel at
least 24 hours before the renewal. Manage or cancel from your
Apple ID → Subscriptions. Refund requests are handled by Apple.

## 6. Expert programme

Users approved as "experts" may publish paid content and receive a
share of subscriber revenue. The current revenue share, payout
threshold, and payout cadence are documented inside Settings →
Expert dashboard. We may adjust them with reasonable notice.
Experts are independent contributors, not employees, agents, or
partners of UNMU.

## 7. No investment advice

UNMU is an information service and a community for Muslim
investors. Nothing in the app — including Shariah ratings, expert
posts, or community discussion — is investment, legal, tax, or
religious advice. You are solely responsible for your investment
decisions. Past performance does not guarantee future results.

## 8. Third-party content

The Service may display content created by other users, links to
external websites, and market data sourced from third parties. We
do not endorse this content and we are not responsible for its
accuracy.

## 9. Disclaimer & limitation of liability

The Service is provided "as is" and "as available" without
warranties of any kind. To the maximum extent permitted by law,
UNMU is not liable for indirect, incidental, consequential, or
punitive damages, or for any loss of profit, revenue, data, or
goodwill. Our total liability for any claim arising from the
Service is limited to the amount you paid us in the 12 months
before the claim.

## 10. Indemnity

You agree to indemnify and hold UNMU harmless from any claim
arising out of (a) your use of the Service, (b) your violation of
these Terms, or (c) your violation of any third-party right.

## 11. Termination

You may stop using the Service at any time by deleting your
account. We may suspend or terminate your access if you breach
these Terms or if we are required to do so by law. Sections that
by their nature should survive termination — licences, disclaimers,
limitation of liability, indemnity, and governing law — will
survive.

## 12. Changes

We may update these Terms. Material changes are announced in-app
before they take effect. Continued use after a change means you
accept the new Terms.

## 13. Governing law

These Terms are governed by the laws of the jurisdiction in which
UNMU's legal entity is registered, without regard to conflict-of-
laws rules. Any dispute will be resolved in the courts of that
jurisdiction, unless mandatory consumer-protection law gives you a
different forum.

## 14. Contact

For questions about these Terms — email **support@unmu.app**.
''';

const String kTermsOfServiceAr = '''
# شروط الخدمة

**آخر تحديث:** 2026-05-19

تحكم هذه الشروط استخدامك تطبيق UNMU وموقع unmu.app («الخدمة»). بإنشاء
حساب أو استخدام الخدمة فإنك توافق على هذه الشروط؛ وإن لم توافق فلا
تستخدم الخدمة.

## 1. الأهلية

يجب أن يكون عمرك 13 سنة فأكثر (16 في الاتحاد الأوروبي) وأن تكون
أهلًا لإبرام عقد ملزم. إن استخدمت الخدمة بالنيابة عن جهة فأنت تقرّ
بأنك مخوَّل لإلزامها.

## 2. حسابك

أنت مسؤول عن النشاط الذي يجري ضمن حسابك. احفظ كلمة المرور، وأبلغنا
فورًا عند الاشتباه بأي استخدام غير مصرّح. ولنا الحق بتعليق أو إنهاء
أي حساب يخالف هذه الشروط.

## 3. الاستخدام المقبول

تتعهد بألّا تقوم بـ:

- نشر محتوى مخالف للقانون أو تشهيري أو يحرّض على الكراهية أو جنسي
  أو عنيف أو ينتهك حقوق الآخرين؛
- انتحال شخصية أحد أو تحريف مؤهلاتك؛
- مضايقة المستخدمين أو ملاحقتهم أو تهديدهم؛
- محاولة كسر الخدمة، أو سحب بياناتها بكميات كبيرة، أو هندستها
  العكسية، أو التشويش على عملها؛
- استخدام الخدمة لإرسال سبام أو برمجيات خبيثة أو ترويج غير مرغوب؛
- جمع بيانات شخصية عن المستخدمين دون إذنهم؛
- استخدام أي نظام آلي أو روبوت أو سكربت لاستخراج البيانات دون
  إذننا الكتابي.

ولنا الحق في إزالة المحتوى أو تقييد الوصول وفقًا لتقديرنا عند مخالفة
هذه القواعد.

## 4. محتوى المستخدم والرخصة

تبقى ملكية المحتوى لك. وبنشره تمنح UNMU ترخيصًا عالميًا غير حصري
وبلا مقابل لاستضافة المحتوى وعرضه ونسخه وترجمته ونشره داخل الخدمة
وفي موادها التسويقية. ينتهي هذا الترخيص عند حذف المحتوى، باستثناء
النسخ الضرورية للنسخ الاحتياطي أو للالتزام القانوني.

تُقرّ بأن لديك كل الحقوق اللازمة لنشر المحتوى وأنه لا ينتهك أي قانون
أو حقوق طرف ثالث.

## 5. الاشتراكات والمشتريات داخل التطبيق

تتطلب بعض الميزات اشتراكًا مدفوعًا يُحصَّل عبر App Store. تنطبق شروط
Apple على الدفع نفسه؛ ونحن نستلم فقط تأكيد نجاح الشراء. تتجدد
الاشتراكات تلقائيًا عبر حساب App Store ما لم تُلغِها قبل التجديد
بـ 24 ساعة. للإدارة أو الإلغاء: Apple ID ← الاشتراكات. تتولى Apple
طلبات استرداد المبالغ.

## 6. برنامج الخبراء

يحق للمستخدمين المعتمدين كـ«خبراء» نشر محتوى مدفوع والحصول على
حصة من إيرادات المشتركين. الحصة الحالية وحدّ السحب ووتيرة الدفع
موثَّقة في «الإعدادات ← لوحة الخبير». يمكننا تعديلها مع إشعار
مناسب. الخبراء مساهمون مستقلون وليسوا موظفين أو وكلاء أو شركاء
لـ UNMU.

## 7. ليست نصيحة استثمارية

UNMU خدمة معلومات ومجتمع للمستثمرين المسلمين. لا شيء في التطبيق —
بما في ذلك تصنيفات الشريعة ومنشورات الخبراء والنقاشات — يُعدّ
نصيحة استثمارية أو قانونية أو ضريبية أو شرعية. أنت وحدك مسؤول عن
قرارات الاستثمار. الأداء الماضي لا يضمن النتائج المستقبلية.

## 8. محتوى الأطراف الثالثة

قد تعرض الخدمة محتوى من مستخدمين آخرين أو روابط لمواقع خارجية أو
بيانات سوقية من مصادر طرف ثالث. لا نتحمل مسؤولية صحة هذا المحتوى
ولا نُقرّه.

## 9. إخلاء المسؤولية وتحديدها

تُقدَّم الخدمة «كما هي» و«حسب توفّرها» دون أي ضمانات. وإلى أقصى حد
يسمح به القانون، لا تتحمل UNMU أي أضرار غير مباشرة أو تبعية أو
عرضية أو عقابية، ولا أي خسائر في الأرباح أو الإيرادات أو البيانات
أو السمعة. وتقتصر مسؤوليتنا الإجمالية عن أي مطالبة على المبلغ الذي
دفعته خلال 12 شهرًا السابقة للمطالبة.

## 10. التعويض

توافق على تعويض UNMU وإبراء ذمّتها من أي مطالبة ناشئة عن
(أ) استخدامك للخدمة، (ب) مخالفتك لهذه الشروط، أو (ج) انتهاكك
لحقوق طرف ثالث.

## 11. الإنهاء

يمكنك التوقّف عن استخدام الخدمة في أي وقت بحذف حسابك. ولنا الحق
في تعليق وصولك أو إنهائه عند مخالفة هذه الشروط أو عند الحاجة
لذلك قانونيًا. تبقى البنود التي تستلزم طبيعتها الاستمرار —
التراخيص، إخلاء المسؤولية، تحديد المسؤولية، التعويض، القانون
الحاكم — سارية بعد الإنهاء.

## 12. التعديلات

قد نُحدِّث هذه الشروط. تُعلَن التغييرات الجوهرية داخل التطبيق قبل
سريانها. ويُعدّ استمرار الاستخدام بعد التحديث موافقة.

## 13. القانون الحاكم

تحكم هذه الشروط قوانين الولاية التي سُجِّلت فيها كيان UNMU
القانوني، دون اعتبار لقواعد تنازع القوانين. وتختص محاكم تلك
الولاية بحلّ النزاعات، ما لم يمنحك قانون حماية المستهلك الإلزامي
حقّ التقاضي في جهة أخرى.

## 14. التواصل

لأي استفسار عن هذه الشروط — راسلنا على **support@unmu.app**.
''';
