/// GetX i18n map for the "community more" cluster of social screens.
///
/// Worker-owned map (merged centrally into app_translations.dart by the
/// orchestrator). Namespaces: communityEdit. / communityDiscovery. /
/// communityPreview. / communityInvite. / inviteExpert. / fullChat.
///
/// Common keys (common.ok, common.retry, …) live centrally and are reused
/// here without redefinition.
///
/// INVARIANT: communityMoreEn and communityMoreAr MUST share the exact same
/// key set — a missing Arabic key would leak English in RTL.
library;

const Map<String, String> communityMoreEn = {
  // ---- communityEdit. (community_edit_sheet.dart) ----
  'communityEdit.title': 'Edit community',
  'communityEdit.name': 'Name',
  'communityEdit.nameHint': 'US Halal Tech',
  'communityEdit.tagline': 'Tagline',
  'communityEdit.taglineHint': 'Short summary line',
  'communityEdit.description': 'Description',
  'communityEdit.descriptionHint': 'Long-form description shown on detail',
  'communityEdit.rules': 'Rules',
  'communityEdit.rulesHint': 'Community rules / guidelines',
  'communityEdit.category': 'Category',
  'communityEdit.categoryNone': 'None',
  'communityEdit.tags': 'Tags',
  'communityEdit.tagHint': 'Add a tag',
  'communityEdit.maxTags': 'Max 10 tags per community.',
  'communityEdit.tagTooLong': 'Each tag must be 30 chars or less.',
  'communityEdit.coverHint': 'Tap to choose cover image',
  'communityEdit.removeCover': 'Remove cover',
  'communityEdit.change': 'Change',
  'communityEdit.avatarTitle': 'Community avatar',
  'communityEdit.avatarSubtitle':
      'Square logo shown in lists & on the detail page. Optional.',
  'communityEdit.upload': 'Upload',
  'communityEdit.public': 'Public',
  'communityEdit.private': 'Private',
  'communityEdit.publicDesc':
      'Anyone can read posts. Composing stays members-only.',
  'communityEdit.privateDesc': 'Only members can read posts.',
  'communityEdit.pricing': 'Pricing',
  'communityEdit.paidTitle': 'Paid community',
  'communityEdit.freeTitle': 'Free community',
  'communityEdit.paidDesc':
      'Users pay monthly or yearly — admin verifies the payment.',
  'communityEdit.freeDesc': 'One-tap join, no payment required.',
  'communityEdit.monthly': 'Monthly',
  'communityEdit.yearly': 'Yearly',
  'communityEdit.yearlySavings': 'Subscribers save @pct% on yearly',
  'communityEdit.disablePlanHint': 'Set one of the two to 0 to disable that plan.',
  'communityEdit.saveChanges': 'Save changes',

  // ---- communityDiscovery. (community_discovery_screen.dart) ----
  'communityDiscovery.title': 'Discover communities',
  'communityDiscovery.searchHint': 'Search by name, topic, or interest',
  'communityDiscovery.filteringByTag': 'Filtering by #@tag',
  'communityDiscovery.all': 'All',
  'communityDiscovery.empty': 'No matches. Try a different search.',
  'communityDiscovery.private': 'Private',
  'communityDiscovery.public': 'Public',
  'communityDiscovery.joined': 'Joined',
  'communityDiscovery.perMonthSuffix': '/mo',
  'communityDiscovery.perYearSuffix': '/yr',

  // ---- communityPreview. (community_preview_screen.dart) ----
  'communityPreview.couldNotJoin': 'Could not join.',
  'communityPreview.paymentSubmitted':
      'Payment submitted. You\'ll get access once admin verifies.',
  'communityPreview.couldNotLoad': 'Could not load preview.',
  'communityPreview.about': 'About',
  'communityPreview.experts': 'Experts',
  'communityPreview.recentPosts': 'Recent posts',
  'communityPreview.rules': 'Rules',
  'communityPreview.private': 'Private',
  'communityPreview.paid': 'Paid',
  'communityPreview.members': 'members',
  'communityPreview.active': 'active',
  'communityPreview.expertsStat': 'experts',
  'communityPreview.defaultExpertName': 'Expert',
  'communityPreview.oneSubscriber': '1 subscriber',
  'communityPreview.subsCount': '@count subs',
  'communityPreview.pendingBanner':
      'Payment submitted — admin will verify and activate your access soon.',
  'communityPreview.youreMember': 'You\'re a member',
  'communityPreview.subscriptionPending': 'Subscription pending review',
  'communityPreview.joining': 'Joining…',
  'communityPreview.joinCommunity': 'Join community',

  // ---- communityInvite. (community_invitations_screen.dart) ----
  'communityInvite.title': 'Community invitations',
  'communityInvite.accepted': 'Accepted',
  'communityInvite.acceptedBody': 'You are now a co-owner of "@name"',
  'communityInvite.acceptFailed': 'Accept failed',
  'communityInvite.somethingWrong': 'Something went wrong',
  'communityInvite.rejectFailed': 'Reject failed',
  'communityInvite.emptyTitle': 'No invitations',
  'communityInvite.emptyBody':
      'When a community owner invites you to be a co-owner, the invitation will show up here.',
  'communityInvite.fromName': 'Invitation from @name',
  'communityInvite.pitch':
      'Accept to become a co-owner — you\'ll be able to publish posts and moderate members in this community.',
  'communityInvite.decline': 'Decline',
  'communityInvite.accept': 'Accept',

  // ---- inviteExpert. (invite_expert_screen.dart) ----
  'inviteExpert.couldNotLoad': 'Could not load experts.',
  'inviteExpert.sent': 'Invitation sent',
  'inviteExpert.sentBody': '@name will see the invitation in their inbox.',
  'inviteExpert.couldNotSend': 'Could not send',
  'inviteExpert.errPending': 'This expert already has a pending invitation',
  'inviteExpert.errAlreadyOwner': 'This user is already an owner',
  'inviteExpert.errNotExpert': 'Only verified experts can be invited',
  'inviteExpert.somethingWrong': 'Something went wrong',
  'inviteExpert.title': 'Invite an expert',
  'inviteExpert.searchHint': 'Search by name or expertise',
  'inviteExpert.noneAvailable': 'No experts available to invite.',
  'inviteExpert.noMatches': 'No matching experts',
  'inviteExpert.invite': 'Invite',

  // ---- fullChat. (full_chat_screen.dart) ----
  'fullChat.today': 'TODAY',
  'fullChat.activeNow': 'active now',
  'fullChat.insertSymbol': 'Insert symbol',
  'fullChat.typeMessage': 'Type a message...',
};

const Map<String, String> communityMoreAr = {
  // ---- communityEdit. ----
  'communityEdit.title': 'تعديل المجتمع',
  'communityEdit.name': 'الاسم',
  'communityEdit.nameHint': 'US Halal Tech',
  'communityEdit.tagline': 'العنوان الفرعي',
  'communityEdit.taglineHint': 'سطر ملخّص قصير',
  'communityEdit.description': 'الوصف',
  'communityEdit.descriptionHint': 'وصف مفصّل يظهر في صفحة التفاصيل',
  'communityEdit.rules': 'القواعد',
  'communityEdit.rulesHint': 'قواعد وإرشادات المجتمع',
  'communityEdit.category': 'التصنيف',
  'communityEdit.categoryNone': 'بدون',
  'communityEdit.tags': 'الوسوم',
  'communityEdit.tagHint': 'أضف وسمًا واضغط +',
  'communityEdit.maxTags': 'حد أقصى 10 وسوم لكل مجتمع.',
  'communityEdit.tagTooLong': 'يجب ألا يتجاوز كل وسم 30 حرفًا.',
  'communityEdit.coverHint': 'اضغط لاختيار صورة الغلاف',
  'communityEdit.removeCover': 'إزالة الغلاف',
  'communityEdit.change': 'تغيير',
  'communityEdit.avatarTitle': 'صورة المجتمع',
  'communityEdit.avatarSubtitle':
      'شعار مربع يظهر في القوائم وصفحة التفاصيل. اختياري.',
  'communityEdit.upload': 'رفع',
  'communityEdit.public': 'مجتمع عام',
  'communityEdit.private': 'مجتمع خاص',
  'communityEdit.publicDesc': 'يمكن للجميع رؤية المنشورات. النشر للأعضاء فقط.',
  'communityEdit.privateDesc': 'الأعضاء فقط يرون المنشورات.',
  'communityEdit.pricing': 'الأسعار',
  'communityEdit.paidTitle': 'مجتمع مدفوع',
  'communityEdit.freeTitle': 'مجتمع مجاني',
  'communityEdit.paidDesc':
      'يدفع المستخدمون شهريًا أو سنويًا — يعتمد المسؤول الدفع.',
  'communityEdit.freeDesc': 'انضمام بنقرة واحدة بدون دفع.',
  'communityEdit.monthly': 'شهري',
  'communityEdit.yearly': 'سنوي',
  'communityEdit.yearlySavings': 'يوفّر المشتركون @pct٪ بالخطة السنوية',
  'communityEdit.disablePlanHint': 'اضبط أحد الحقلين على 0 لتعطيل تلك الخطة.',
  'communityEdit.saveChanges': 'حفظ التغييرات',

  // ---- communityDiscovery. ----
  'communityDiscovery.title': 'اكتشاف المجتمعات',
  'communityDiscovery.searchHint': 'ابحث بالاسم أو الموضوع أو الاهتمام',
  'communityDiscovery.filteringByTag': 'تصفية حسب #@tag',
  'communityDiscovery.all': 'الكل',
  'communityDiscovery.empty': 'لا توجد نتائج. جرّب كلمات أخرى.',
  'communityDiscovery.private': 'خاص',
  'communityDiscovery.public': 'عام',
  'communityDiscovery.joined': 'منضم',
  'communityDiscovery.perMonthSuffix': '/شهر',
  'communityDiscovery.perYearSuffix': '/سنة',

  // ---- communityPreview. ----
  'communityPreview.couldNotJoin': 'تعذّر الانضمام.',
  'communityPreview.paymentSubmitted':
      'تم استلام الدفع. سيتم منحك الوصول بعد تحقق الإدارة.',
  'communityPreview.couldNotLoad': 'تعذّر تحميل المعاينة.',
  'communityPreview.about': 'الوصف',
  'communityPreview.experts': 'الخبراء',
  'communityPreview.recentPosts': 'منشورات حديثة',
  'communityPreview.rules': 'القواعد',
  'communityPreview.private': 'خاص',
  'communityPreview.paid': 'مدفوع',
  'communityPreview.members': 'عضو',
  'communityPreview.active': 'نشط',
  'communityPreview.expertsStat': 'خبراء',
  'communityPreview.defaultExpertName': 'خبير',
  'communityPreview.oneSubscriber': 'مشترك واحد',
  'communityPreview.subsCount': '@count مشترك',
  'communityPreview.pendingBanner':
      'تم استلام الدفع — ستتحقق الإدارة وتفعّل وصولك قريبًا.',
  'communityPreview.youreMember': 'أنت عضو في هذا المجتمع',
  'communityPreview.subscriptionPending': 'الاشتراك قيد المراجعة',
  'communityPreview.joining': 'جارٍ الانضمام…',
  'communityPreview.joinCommunity': 'انضمام مجاني',

  // ---- communityInvite. ----
  'communityInvite.title': 'دعوات المجتمعات',
  'communityInvite.accepted': 'تم القبول',
  'communityInvite.acceptedBody': 'أنت الآن مالك مشارك في "@name"',
  'communityInvite.acceptFailed': 'فشل القبول',
  'communityInvite.somethingWrong': 'حدث خطأ',
  'communityInvite.rejectFailed': 'فشل الرفض',
  'communityInvite.emptyTitle': 'لا توجد دعوات',
  'communityInvite.emptyBody':
      'عندما يدعوك مالك مجتمع لتكون مالكًا مشاركًا، ستظهر الدعوة هنا.',
  'communityInvite.fromName': 'دعوة من @name',
  'communityInvite.pitch':
      'بالقبول ستصبح مالكًا مشاركًا — يمكنك نشر المنشورات وإدارة الأعضاء في هذا المجتمع.',
  'communityInvite.decline': 'رفض',
  'communityInvite.accept': 'قبول',

  // ---- inviteExpert. ----
  'inviteExpert.couldNotLoad': 'تعذّر تحميل الخبراء.',
  'inviteExpert.sent': 'تم إرسال الدعوة',
  'inviteExpert.sentBody': 'سيرى @name الدعوة في صندوق الوارد.',
  'inviteExpert.couldNotSend': 'تعذّر الإرسال',
  'inviteExpert.errPending': 'هذا الخبير لديه دعوة معلّقة بالفعل',
  'inviteExpert.errAlreadyOwner': 'هذا المستخدم مالك بالفعل',
  'inviteExpert.errNotExpert': 'يمكن دعوة الخبراء المعتمدين فقط',
  'inviteExpert.somethingWrong': 'حدث خطأ',
  'inviteExpert.title': 'ادعُ خبيراً',
  'inviteExpert.searchHint': 'ابحث بالاسم أو التخصص',
  'inviteExpert.noneAvailable': 'لا يوجد خبراء يمكن دعوتهم.',
  'inviteExpert.noMatches': 'لا نتائج',
  'inviteExpert.invite': 'دعوة',

  // ---- fullChat. ----
  'fullChat.today': 'اليوم',
  'fullChat.activeNow': 'نشط الآن',
  'fullChat.insertSymbol': 'إدراج رمز',
  'fullChat.typeMessage': 'اكتب رسالة...',
};
