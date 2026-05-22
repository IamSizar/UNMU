// Final-sweep extras (D4.3) — strings the per-cluster passes missed:
// the Users list page, plus leftover hardcoded labels in PostDetail,
// UserDetail, Experts, Diagnostics, Header, Posts. Keep En/Ar key sets
// identical. Plain object literals so keys stay literal.

export const extrasEn = {
  // ── Users list page ─────────────────────────────────────────────
  'users.title': 'Users',
  'users.summary': '{total} total · {experts} experts · {admins} admin',
  'users.searchPlaceholder': 'Search by email or name...',
  'users.filterAll': 'All',
  'users.roleMember': 'Member',
  'users.roleExpert': 'Verified Expert',
  'users.roleAdmin': 'Admin',
  'users.colUser': 'User',
  'users.colRole': 'Role',
  'users.colCommunities': 'Communities',
  'users.colSubscription': 'Subscription',
  'users.colJoined': 'Joined',
  'users.colActions': 'Actions',
  'users.empty': 'No users match those filters.',
  'users.changeRole': 'Change role',
  'users.edit': 'Edit',
  'users.paidTooltip': '{n} active paid memberships',
  'users.failedLoad': 'Failed to load',
  'users.failedRole': 'Failed to change role',

  // ── Header chrome (titles / aria-labels) ────────────────────────
  'header.openMenu': 'Open menu',
  'header.language': 'Language',
  'header.switchToLight': 'Switch to light mode',
  'header.switchToDark': 'Switch to dark mode',
  'header.muteNotifications': 'Mute notifications',
  'header.unmuteNotifications': 'Unmute notifications',
  'header.closeSearch': 'Close search',

  // ── Diagnostics: events summary labels ──────────────────────────
  'diag.events.shareTapped': 'Share tapped',
  'diag.events.deepLinkOpened': 'Deep links opened',
  'diag.events.reelLoadFailed': 'Reels failed to load',

  // ── Diagnostics: deep-link verification rows ────────────────────
  'diag.deepLinks.ios': 'iOS Universal Links',
  'diag.deepLinks.android': 'Android App Links',
  'diag.deepLinks.reachable': 'Reachable (HTTP {code})',
  'diag.deepLinks.validJson': 'Valid JSON',
  'diag.deepLinks.bundleMatch': 'Bundle ID matches',
  'diag.deepLinks.packageMatch': 'Package name matches',
  'diag.deepLinks.fingerprintMatch': 'SHA-256 fingerprint matches',

  // ── PostDetail ──────────────────────────────────────────────────
  'postDetail.coverAlt': 'cover',
  'postDetail.editHistory': 'Edit history ({count})',
  'postDetail.editor': 'editor #{id}',
  'postDetail.deleteComment': 'Delete comment',
  'postDetail.userFallback': 'user',
  'postDetail.roleSuffix.expert': ' · expert',
  'postDetail.roleSuffix.admin': ' · admin',

  // ── Posts ───────────────────────────────────────────────────────
  'posts.target.all': 'All sources',
  'posts.target.expert': 'Expert',
  'posts.target.community': 'Community',
  'posts.status.draft': 'Draft',
  'posts.status.draftTooltip': 'Saved as draft — not yet published',
  'posts.status.scheduled': 'Scheduled',
  'posts.status.scheduledFor': 'Scheduled for {date}',

  // ── Experts ─────────────────────────────────────────────────────
  'experts.noProfile': 'No expert profile',
  'experts.editPricing': 'Edit pricing',
  'experts.perMonth': '/mo',
  'experts.perYear': '/yr',

  // ── UserDetail ──────────────────────────────────────────────────
  'userDetail.expert': 'expert',
  'userDetail.expertWithId': 'expert: {id}',
  'userDetail.admin': 'admin',
  'userDetail.communities': 'Communities',
  'userDetail.loadingCommunities': 'Loading communities…',
  'userDetail.noCommunities': "This user isn't a member of any community yet.",
  'userDetail.cannotRemoveOwner':
    'Cannot remove the owner. Transfer ownership from the community page first.',
  'userDetail.removeConfirm':
    'Remove this user from "{name}"?\n\nThis revokes their membership immediately. If they have an active paid subscription it stays in the table — you should cancel it from the Subscriptions page if you also want to stop the billing record.',
  'userDetail.failed': 'Failed',
  'userDetail.joined': 'joined {date}',
  'userDetail.owner': 'Owner',
  'userDetail.paidCommunity': 'Paid community',
  'userDetail.remove': 'Remove',
  'userDetail.monthly': 'Monthly',
  'userDetail.yearly': 'Yearly',
  'userDetail.subNo': 'Sub #{id}',
  'userDetail.via': 'via {method}',
  'userDetail.submitted': 'Submitted',
  'userDetail.accepted': 'Accepted',
  'userDetail.expires': 'Expires',
  'userDetail.ref': 'Ref',
  'userDetail.cancelled': 'Cancelled',
  'userDetail.rejected': 'Rejected',
  'userDetail.noSubRow':
    'Joined this paid community before the paywall, or via admin override — no subscription row.',
  'userDetail.adminOverride': 'Admin override',
  'userDetail.demoteFromExpert': 'Demote from expert',
  'userDetail.demoteHelp':
    'Reverses an accidental approval. Soft — preserves their posts and existing subscribers.',
  'userDetail.demote': 'Demote',
  'userDetail.demoteConfirm':
    "Demote this expert back to a regular user?\n\nTheir EXPERT role and expert profile link will be removed. Existing posts and subscriptions stay intact (historical record), so subscribers won't lose their access until renewal time.",

  // ── Sidebar chrome ──────────────────────────────────────────────
  'sidebar.adminBadge': 'Admin',
  'sidebar.primaryNav': 'Primary navigation',
  'sidebar.closeMenu': 'Close menu',
  'sidebar.realtimeConnected': 'Realtime: connected',
  'sidebar.realtimeOffline': 'Realtime: offline',

  // ── Communities: create-modal placeholders (prose) ──────────────
  'communities.phName': 'Halal ETFs',
  'communities.phTagline': 'Discussion for halal-screened ETFs.',
  'communities.phOwnerId': 'e.g. 1002',
}

export const extrasAr = {
  // ── Users list page ─────────────────────────────────────────────
  'users.title': 'المستخدمون',
  'users.summary': '{total} الإجمالي · {experts} خبراء · {admins} مدير',
  'users.searchPlaceholder': 'ابحث بالبريد الإلكتروني أو الاسم...',
  'users.filterAll': 'الكل',
  'users.roleMember': 'عضو',
  'users.roleExpert': 'خبير موثّق',
  'users.roleAdmin': 'مدير',
  'users.colUser': 'المستخدم',
  'users.colRole': 'الدور',
  'users.colCommunities': 'المجتمعات',
  'users.colSubscription': 'الاشتراك',
  'users.colJoined': 'تاريخ الانضمام',
  'users.colActions': 'الإجراءات',
  'users.empty': 'لا يوجد مستخدمون مطابقون لتلك المرشحات.',
  'users.changeRole': 'تغيير الدور',
  'users.edit': 'تعديل',
  'users.paidTooltip': '{n} اشتراك مدفوع نشط',
  'users.failedLoad': 'فشل التحميل',
  'users.failedRole': 'فشل تغيير الدور',

  // ── Header chrome (titles / aria-labels) ────────────────────────
  'header.openMenu': 'فتح القائمة',
  'header.language': 'اللغة',
  'header.switchToLight': 'التبديل إلى الوضع الفاتح',
  'header.switchToDark': 'التبديل إلى الوضع الداكن',
  'header.muteNotifications': 'كتم الإشعارات',
  'header.unmuteNotifications': 'إلغاء كتم الإشعارات',
  'header.closeSearch': 'إغلاق البحث',

  // ── Diagnostics: events summary labels ──────────────────────────
  'diag.events.shareTapped': 'نقرات المشاركة',
  'diag.events.deepLinkOpened': 'فتح الروابط العميقة',
  'diag.events.reelLoadFailed': 'فشل تحميل الريلز',

  // ── Diagnostics: deep-link verification rows ────────────────────
  'diag.deepLinks.ios': 'روابط iOS العامّة',
  'diag.deepLinks.android': 'روابط تطبيق Android',
  'diag.deepLinks.reachable': 'يمكن الوصول (HTTP {code})',
  'diag.deepLinks.validJson': 'JSON صالح',
  'diag.deepLinks.bundleMatch': 'معرّف الحزمة (Bundle ID) متطابق',
  'diag.deepLinks.packageMatch': 'اسم الحزمة متطابق',
  'diag.deepLinks.fingerprintMatch': 'بصمة SHA-256 متطابقة',

  // ── PostDetail ──────────────────────────────────────────────────
  'postDetail.coverAlt': 'الغلاف',
  'postDetail.editHistory': 'سجل التعديلات ({count})',
  'postDetail.editor': 'المحرّر #{id}',
  'postDetail.deleteComment': 'حذف التعليق',
  'postDetail.userFallback': 'مستخدم',
  'postDetail.roleSuffix.expert': ' · خبير',
  'postDetail.roleSuffix.admin': ' · مدير',

  // ── Posts ───────────────────────────────────────────────────────
  'posts.target.all': 'كل المصادر',
  'posts.target.expert': 'خبير',
  'posts.target.community': 'مجتمع',
  'posts.status.draft': 'مسودة',
  'posts.status.draftTooltip': 'محفوظ كمسودة — لم يُنشر بعد',
  'posts.status.scheduled': 'مجدول',
  'posts.status.scheduledFor': 'مجدول في {date}',

  // ── Experts ─────────────────────────────────────────────────────
  'experts.noProfile': 'لا يوجد ملف خبير',
  'experts.editPricing': 'تعديل التسعير',
  'experts.perMonth': '/شهرياً',
  'experts.perYear': '/سنوياً',

  // ── UserDetail ──────────────────────────────────────────────────
  'userDetail.expert': 'خبير',
  'userDetail.expertWithId': 'خبير: {id}',
  'userDetail.admin': 'مدير',
  'userDetail.communities': 'المجتمعات',
  'userDetail.loadingCommunities': 'جارٍ تحميل المجتمعات…',
  'userDetail.noCommunities': 'هذا المستخدم ليس عضواً في أي مجتمع بعد.',
  'userDetail.cannotRemoveOwner':
    'لا يمكن إزالة المالك. انقل الملكية من صفحة المجتمع أولاً.',
  'userDetail.removeConfirm':
    'إزالة هذا المستخدم من "{name}"؟\n\nهذا يلغي عضويته فوراً. إذا كان لديه اشتراك مدفوع نشط فإنه يبقى في الجدول — يجب إلغاؤه من صفحة الاشتراكات إذا كنت تريد أيضاً إيقاف سجل الفوترة.',
  'userDetail.failed': 'فشل',
  'userDetail.joined': 'انضم في {date}',
  'userDetail.owner': 'المالك',
  'userDetail.paidCommunity': 'مجتمع مدفوع',
  'userDetail.remove': 'إزالة',
  'userDetail.monthly': 'شهري',
  'userDetail.yearly': 'سنوي',
  'userDetail.subNo': 'اشتراك #{id}',
  'userDetail.via': 'عبر {method}',
  'userDetail.submitted': 'قُدّم',
  'userDetail.accepted': 'قُبل',
  'userDetail.expires': 'ينتهي',
  'userDetail.ref': 'المرجع',
  'userDetail.cancelled': 'أُلغي',
  'userDetail.rejected': 'رُفض',
  'userDetail.noSubRow':
    'انضم إلى هذا المجتمع المدفوع قبل تفعيل الدفع، أو عبر تجاوز إداري — لا يوجد سجل اشتراك.',
  'userDetail.adminOverride': 'تجاوز إداري',
  'userDetail.demoteFromExpert': 'إنزال من رتبة الخبير',
  'userDetail.demoteHelp':
    'يعكس موافقة عرضية. ناعم — يحافظ على منشوراته ومشتركيه الحاليين.',
  'userDetail.demote': 'إنزال',
  'userDetail.demoteConfirm':
    'إنزال هذا الخبير إلى مستخدم عادي؟\n\nسيتم إزالة رتبة الخبير ورابط ملف الخبير. تبقى المنشورات والاشتراكات الحالية كما هي (سجل تاريخي)، لذا لن يفقد المشتركون وصولهم حتى وقت التجديد.',

  // ── Sidebar chrome ──────────────────────────────────────────────
  'sidebar.adminBadge': 'الإدارة',
  'sidebar.primaryNav': 'التنقل الرئيسي',
  'sidebar.closeMenu': 'إغلاق القائمة',
  'sidebar.realtimeConnected': 'الوقت الفعلي: متصل',
  'sidebar.realtimeOffline': 'الوقت الفعلي: غير متصل',

  // ── Communities: create-modal placeholders (prose) ──────────────
  'communities.phName': 'صناديق المؤشرات الحلال',
  'communities.phTagline': 'نقاش حول صناديق المؤشرات المتوافقة مع الشريعة.',
  'communities.phOwnerId': 'مثال: 1002',
}
