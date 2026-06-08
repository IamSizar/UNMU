import { useState, useEffect } from 'react'
import {
  Send,
  Users,
  ShieldCheck,
  TrendingUp,
  AlertCircle,
  Crown,
  GraduationCap,
  Loader2,
  CheckCircle2,
  XCircle,
  Sparkles,
  Moon,
  Calendar,
  Rocket,
  Wallet,
  Gift,
  MessageSquare,
  Clock,
  CalendarClock,
  CalendarDays,
  Timer,
  Trash2,
  Hourglass,
  Repeat,
  UserSearch,
  User,
  Search,
} from 'lucide-react'
import { api, ApiError } from '../api/client'
import { useI18n } from '../i18n/I18nContext'

// Mock delivery history — kept as a visual placeholder until we add a real
// /admin/push/history endpoint. The compose form on the left is fully wired
// to POST /api/admin/push/send.
const history = [
  { id: 1, title: 'Eid Mubarak — 30% off Premium Annual', segment: 'All users', sent: '14,238 users', date: 'Apr 30, 09:00', open: '38.2%', icon: Crown, tone: 'gold' },
  { id: 2, title: 'New article: Top 10 Halal Tech Stocks', segment: 'Premium subscribers', sent: '1,260 users', date: 'May 01, 12:30', open: '64.8%', icon: TrendingUp, tone: 'cyan' },
  { id: 3, title: 'AAPL status changed to Compliant (Grade B)', segment: 'AAPL watchers', sent: '842 users', date: 'May 02, 14:18', open: '74.2%', icon: ShieldCheck, tone: 'emerald' },
  { id: 4, title: 'Server maintenance — May 5, 02:00 UTC', segment: 'All users', sent: '14,238 users', date: 'May 02, 16:42', open: '22.4%', icon: AlertCircle, tone: 'rose' },
  { id: 5, title: '3 new experts joined this week', segment: 'All users', sent: '14,238 users', date: 'May 03, 10:00', open: '41.6%', icon: GraduationCap, tone: 'violet' }
]

const toneColors = {
  cyan: 'text-cyan-400 bg-cyan-500/10',
  gold: 'text-gold-400 bg-gold-500/10',
  emerald: 'text-emerald-400 bg-emerald-500/10',
  rose: 'text-rose-400 bg-rose-500/10',
  violet: 'text-violet-400 bg-violet-500/10'
}

// Audience segments. Each maps to a `target` the backend understands
// (see backend/internal/handlers/push.go AdminSend):
//   target=all|ios|android → token/platform filters
//   target=role  + role    → users.role join (USER/EXPERT/ADMIN)
//   target=community + communityId → community_members join
const SEGMENTS = [
  { key: 'all', target: 'all', labelKey: 'notifications.segAll', subKey: 'notifications.segAllSub', icon: Users },
  { key: 'experts', target: 'role', role: 'EXPERT', labelKey: 'notifications.segExperts', subKey: 'notifications.segExpertsSub', icon: GraduationCap },
  { key: 'users', target: 'role', role: 'USER', labelKey: 'notifications.segUsers', subKey: 'notifications.segUsersSub', icon: Users },
  { key: 'admins', target: 'role', role: 'ADMIN', labelKey: 'notifications.segAdmins', subKey: 'notifications.segAdminsSub', icon: ShieldCheck },
  { key: 'community', target: 'community', labelKey: 'notifications.segCommunity', subKey: 'notifications.segCommunitySub', icon: MessageSquare },
  { key: 'user', target: 'user', labelKey: 'notifications.segUser', subKey: 'notifications.segUserSub', icon: UserSearch },
]

// Recommended ready-to-send templates — bilingual. Clicking one fills the
// title + message inputs in the currently-selected language (EN or AR),
// still fully editable afterward. Segment-specific picks come first, then
// the common greetings/announcements everyone can use.
//
// Each template carries an `en` and `ar` variant with its own chip label,
// title, and body so the Arabic copy reads naturally (not machine-style).
const COMMON_TEMPLATES = [
  {
    key: 'eid_adha',
    icon: Moon,
    labelKey: 'notifications.tplEidAdha',
    en: {
      label: 'Eid al-Adha',
      title: 'Eid al-Adha Mubarak 🐑',
      body: 'From all of us at UNMU — may this blessed Eid al-Adha fill your home with peace, joy, and barakah. May your sacrifice and good deeds be accepted. Taqabbal Allahu minna wa minkum. 🤲',
    },
    ar: {
      label: 'عيد الأضحى',
      title: 'عيد أضحى مبارك 🐑',
      body: 'من كل فريق UNMU، كل عام وأنتم بخير 🌙 تقبّل الله منّا ومنكم صالح الأعمال، وأضحيتكم، وأعاده عليكم وعلى أهلكم بالخير واليُمن والبركات 🤲',
    },
  },
  {
    key: 'eid_fitr',
    icon: Sparkles,
    labelKey: 'notifications.tplEidFitr',
    en: {
      label: 'Eid al-Fitr',
      title: 'Eid al-Fitr Mubarak 🌙',
      body: 'Eid Mubarak from everyone at UNMU! May your fasting and prayers be accepted, and may your days ahead be filled with blessings. 🎉',
    },
    ar: {
      label: 'عيد الفطر',
      title: 'عيد فطر مبارك 🌙',
      body: 'عيد مبارك من فريق UNMU! تقبّل الله صيامكم وقيامكم، وكل عام وأنتم إلى الله أقرب 🎉',
    },
  },
  {
    key: 'jumua',
    icon: Calendar,
    labelKey: 'notifications.tplJumua',
    en: {
      label: "Jumu'ah",
      title: "Jumu'ah Mubarak 🕌",
      body: 'Wishing you a blessed Friday. Take a moment to review your portfolio and renew your intentions.',
    },
    ar: {
      label: 'جمعة مباركة',
      title: 'جمعة مباركة 🕌',
      body: 'نتمنى لك يوم جمعة مبارك. خذ لحظة لمراجعة محفظتك وتجديد نيّتك.',
    },
  },
  {
    key: 'new_feature',
    icon: Rocket,
    labelKey: 'notifications.tplNewFeature',
    en: {
      label: 'New feature',
      title: 'Something new just landed ✨',
      body: "We just shipped a feature we think you'll love. Open UNMU to take a look.",
    },
    ar: {
      label: 'ميزة جديدة',
      title: 'وصلت ميزة جديدة ✨',
      body: 'أطلقنا للتو ميزة نعتقد أنها ستعجبك. افتح تطبيق UNMU لتجربتها.',
    },
  },
  {
    key: 'market',
    icon: TrendingUp,
    labelKey: 'notifications.tplMarket',
    en: {
      label: 'Market movers',
      title: 'Market movers today 📈',
      body: 'Several stocks saw big moves today. Tap to see what changed on your watchlist.',
    },
    ar: {
      label: 'تحركات السوق',
      title: 'تحركات السوق اليوم 📈',
      body: 'شهدت عدة أسهم تحركات كبيرة اليوم. اضغط لمعرفة ما تغيّر في قائمتك.',
    },
  },
  {
    key: 'ramadan',
    icon: Moon,
    labelKey: 'notifications.tplRamadan',
    en: {
      label: 'Ramadan',
      title: 'Ramadan Kareem 🌙',
      body: 'Ramadan Mubarak from everyone at UNMU. May this blessed month bring you peace, growth, and halal barakah in all you do. 🤲',
    },
    ar: {
      label: 'رمضان',
      title: 'رمضان كريم 🌙',
      body: 'رمضان مبارك من فريق UNMU. نسأل الله أن يجعله شهر خيرٍ وبركة، وأن يبارك لك في رزقك ومحفظتك. 🤲',
    },
  },
  {
    key: 'zakat',
    icon: Wallet,
    labelKey: 'notifications.tplZakat',
    en: {
      label: 'Zakat reminder',
      title: "Time to calculate your Zakat 🤲",
      body: "Purify your wealth — review your halal portfolio and calculate the Zakat due on your holdings this year.",
    },
    ar: {
      label: 'تذكير الزكاة',
      title: 'حان وقت حساب زكاتك 🤲',
      body: 'طهّر مالك — راجع محفظتك الحلال واحسب الزكاة المستحقة على أصولك هذا العام.',
    },
  },
  {
    key: 'weekly_recap',
    icon: TrendingUp,
    labelKey: 'notifications.tplWeeklyRecap',
    en: {
      label: 'Weekly recap',
      title: 'Your week in the markets 📊',
      body: "Here's how your watchlist moved this week. Open UNMU for the full halal market recap.",
    },
    ar: {
      label: 'ملخص الأسبوع',
      title: 'أسبوعك في الأسواق 📊',
      body: 'إليك كيف تحرّكت قائمتك هذا الأسبوع. افتح UNMU لقراءة ملخص السوق الحلال كاملًا.',
    },
  },
  {
    key: 'new_compliant',
    icon: ShieldCheck,
    labelKey: 'notifications.tplNewCompliant',
    en: {
      label: 'New halal stocks',
      title: 'New Shariah-compliant stocks added ✅',
      body: "We've added newly screened halal stocks. Explore fresh compliant opportunities on UNMU.",
    },
    ar: {
      label: 'أسهم حلال جديدة',
      title: 'أضفنا أسهمًا متوافقة مع الشريعة ✅',
      body: 'أضفنا أسهمًا حلال تم فحصها حديثًا. استكشف فرصًا متوافقة جديدة على UNMU.',
    },
  },
  {
    key: 'price_alert',
    icon: TrendingUp,
    labelKey: 'notifications.tplPriceAlert',
    en: {
      label: 'Price alert',
      title: 'A stock on your watchlist is moving 🔔',
      body: "One of your watched stocks just made a notable move. Tap to check the price now.",
    },
    ar: {
      label: 'تنبيه سعر',
      title: 'سهم في قائمتك يتحرّك 🔔',
      body: 'أحد الأسهم في قائمتك سجّل تحرّكًا ملحوظًا. اضغط لمتابعة السعر الآن.',
    },
  },
  {
    key: 'app_update',
    icon: Rocket,
    labelKey: 'notifications.tplAppUpdate',
    en: {
      label: 'Update available',
      title: 'A new version is ready ⬆️',
      body: "Update UNMU to the latest version for new features, fixes, and a smoother experience.",
    },
    ar: {
      label: 'تحديث متاح',
      title: 'إصدار جديد جاهز ⬆️',
      body: 'حدّث UNMU إلى أحدث إصدار للحصول على ميزات جديدة وإصلاحات وتجربة أسلس.',
    },
  },
  {
    key: 'maintenance',
    icon: AlertCircle,
    labelKey: 'notifications.tplMaintenance',
    en: {
      label: 'Maintenance',
      title: 'Scheduled maintenance 🛠️',
      body: "UNMU will be briefly unavailable for scheduled maintenance. We'll be back shortly — thanks for your patience.",
    },
    ar: {
      label: 'صيانة',
      title: 'صيانة مجدولة 🛠️',
      body: 'سيكون UNMU غير متاح لفترة قصيرة لإجراء صيانة مجدولة. سنعود قريبًا — شكرًا لتفهّمك.',
    },
  },
  {
    key: 'invite',
    icon: Gift,
    labelKey: 'notifications.tplInvite',
    en: {
      label: 'Invite friends',
      title: 'Invite a friend to UNMU 🎁',
      body: 'Know someone investing the halal way? Invite them to UNMU and grow the community together.',
    },
    ar: {
      label: 'ادعُ أصدقاءك',
      title: 'ادعُ صديقًا إلى UNMU 🎁',
      body: 'تعرف شخصًا يستثمر بالطريقة الحلال؟ ادعُه إلى UNMU ولنبنِ المجتمع معًا.',
    },
  },
  {
    key: 'rate_app',
    icon: Sparkles,
    labelKey: 'notifications.tplRateApp',
    en: {
      label: 'Rate the app',
      title: 'Enjoying UNMU? ⭐',
      body: "If UNMU is helping you invest the halal way, a quick rating on the store means the world to us.",
    },
    ar: {
      label: 'قيّم التطبيق',
      title: 'هل يعجبك UNMU؟ ⭐',
      body: 'إذا كان UNMU يساعدك على الاستثمار بالطريقة الحلال، فإن تقييمًا سريعًا على المتجر يعني لنا الكثير.',
    },
  },
]
const SEGMENT_TEMPLATES = {
  experts: [
    {
      key: 'payout',
      icon: Wallet,
      labelKey: 'notifications.tplPayout',
      en: { label: 'Payout ready', title: 'Your earnings are ready 💰', body: 'You have a payout available. Open Studio → Earnings to request it.' },
      ar: { label: 'أرباحك جاهزة', title: 'أرباحك جاهزة 💰', body: 'لديك مبلغ متاح للسحب. افتح الاستوديو ← الأرباح لطلب الدفع.' },
    },
    {
      key: 'post_idea',
      icon: Rocket,
      labelKey: 'notifications.tplPostIdea',
      en: { label: 'Share insight', title: 'Share your insight 🎬', body: 'Your subscribers are waiting — post a new reel or article today and grow your audience.' },
      ar: { label: 'شارك خبرتك', title: 'شارك خبرتك 🎬', body: 'متابعوك بانتظارك — انشر مقطعًا أو مقالًا جديدًا اليوم ووسّع جمهورك.' },
    },
    {
      key: 'milestone',
      icon: Crown,
      labelKey: 'notifications.tplMilestone',
      en: { label: 'Milestone', title: 'You hit a new milestone 🎉', body: 'Your audience is growing fast. Keep the momentum — share something new with your subscribers today.' },
      ar: { label: 'إنجاز', title: 'حقّقت إنجازًا جديدًا 🎉', body: 'جمهورك ينمو بسرعة. حافظ على الزخم — شارك متابعيك جديدك اليوم.' },
    },
    {
      key: 'payout_tax',
      icon: Wallet,
      labelKey: 'notifications.tplPayoutTax',
      en: { label: 'Tax season', title: 'Get your earnings ready for tax season 🧾', body: 'Download your earnings statement from Studio → Earnings to stay organized this season.' },
      ar: { label: 'موسم الضرائب', title: 'جهّز أرباحك لموسم الضرائب 🧾', body: 'نزّل كشف أرباحك من الاستوديو ← الأرباح لتبقى منظّمًا هذا الموسم.' },
    },
  ],
  users: [
    {
      key: 'premium',
      icon: Crown,
      labelKey: 'notifications.tplPremium',
      en: { label: 'Premium offer', title: 'Limited time: 30% off Premium 👑', body: 'Unlock expert insights and advanced Shariah screening. Offer ends soon.' },
      ar: { label: 'عرض Premium', title: 'لفترة محدودة: خصم 30% على Premium 👑', body: 'افتح رؤى الخبراء والفحص الشرعي المتقدّم. العرض ينتهي قريبًا.' },
    },
    {
      key: 'welcome_back',
      icon: Gift,
      labelKey: 'notifications.tplWelcomeBack',
      en: { label: 'Welcome back', title: 'We miss you 👋', body: "It's been a while! Come see the latest halal opportunities on UNMU." },
      ar: { label: 'اشتقنا لك', title: 'اشتقنا لك 👋', body: 'مرّ وقت طويل! تعال لاكتشاف أحدث الفرص الحلال على UNMU.' },
    },
    {
      key: 'complete_profile',
      icon: Users,
      labelKey: 'notifications.tplCompleteProfile',
      en: { label: 'Complete profile', title: 'Finish setting up your profile ✨', body: 'Add your details and build your watchlist to get personalized halal insights.' },
      ar: { label: 'أكمل ملفك', title: 'أكمل إعداد ملفك ✨', body: 'أضف بياناتك وابنِ قائمة متابعتك لتحصل على رؤى حلال مخصّصة لك.' },
    },
    {
      key: 'reengage',
      icon: Sparkles,
      labelKey: 'notifications.tplReengage',
      en: { label: 'New this week', title: "Here's what's new this week ✨", body: 'Fresh experts, new compliant stocks, and trending discussions are waiting for you on UNMU.' },
      ar: { label: 'جديد هذا الأسبوع', title: 'إليك جديد هذا الأسبوع ✨', body: 'خبراء جدد، أسهم حلال جديدة، ونقاشات رائجة بانتظارك على UNMU.' },
    },
  ],
  community: [
    {
      key: 'welcome_comm',
      icon: MessageSquare,
      labelKey: 'notifications.tplWelcomeComm',
      en: { label: 'Welcome', title: 'Welcome to the community 🤝', body: 'Thanks for joining! Introduce yourself and start the conversation.' },
      ar: { label: 'ترحيب', title: 'مرحبًا بك في المجتمع 🤝', body: 'شكرًا لانضمامك! عرّف بنفسك وابدأ النقاش.' },
    },
    {
      key: 'new_post',
      icon: Sparkles,
      labelKey: 'notifications.tplNewPost',
      en: { label: 'New discussion', title: 'New discussion in your community 💬', body: "There's a new post worth your take. Jump in and share your view." },
      ar: { label: 'نقاش جديد', title: 'نقاش جديد في مجتمعك 💬', body: 'هناك منشور جديد يستحق رأيك. شارك وجهة نظرك.' },
    },
    {
      key: 'comm_digest',
      icon: MessageSquare,
      labelKey: 'notifications.tplCommDigest',
      en: { label: 'Weekly digest', title: 'Your community this week 📰', body: 'Catch up on the top posts and discussions you missed in your community this week.' },
      ar: { label: 'ملخص أسبوعي', title: 'مجتمعك هذا الأسبوع 📰', body: 'تابع أبرز المنشورات والنقاشات التي فاتتك في مجتمعك هذا الأسبوع.' },
    },
    {
      key: 'comm_event',
      icon: Calendar,
      labelKey: 'notifications.tplCommEvent',
      en: { label: 'Live session', title: 'Live session starting soon 🎙️', body: 'Your community is going live shortly. Join the conversation and ask your questions.' },
      ar: { label: 'جلسة مباشرة', title: 'جلسة مباشرة تبدأ قريبًا 🎙️', body: 'مجتمعك سيبدأ بثًّا مباشرًا قريبًا. انضم إلى النقاش واطرح أسئلتك.' },
    },
  ],
}
function templatesFor(segment) {
  return [...(SEGMENT_TEMPLATES[segment] ?? []), ...COMMON_TEMPLATES]
}

// Status badge tones for scheduled rows — match backend status values
// (pending|sending|sent|failed|cancelled).
const SCHEDULED_TONE = {
  pending: 'text-cyan-300 bg-cyan-500/10 ring-cyan-500/30',
  sending: 'text-amber-300 bg-amber-500/10 ring-amber-500/30',
  sent: 'text-emerald-300 bg-emerald-500/10 ring-emerald-500/30',
  failed: 'text-rose-300 bg-rose-500/10 ring-rose-500/30',
  cancelled: 'text-slate-400 bg-white/5 ring-white/10',
}

// "Upcoming" = still waiting to fire; everything else is history.
function isUpcoming(p) {
  const s = p.status ?? 'pending'
  return s === 'pending' || s === 'sending'
}

// Status → icon + circle tint, so the list is scannable at a glance.
const SCHEDULED_ICON = {
  pending: { tint: 'bg-cyan-500/10 text-cyan-400' },
  sending: { tint: 'bg-amber-500/10 text-amber-400' },
  sent: { tint: 'bg-emerald-500/10 text-emerald-400' },
  failed: { tint: 'bg-rose-500/10 text-rose-400' },
  cancelled: { tint: 'bg-white/5 text-slate-500' },
}

// Left accent bar per status — reinforces sent vs. not-sent at a glance.
const SCHEDULED_ACCENT = {
  pending: 'border-cyan-500/60',
  sending: 'border-amber-500/60',
  sent: 'border-emerald-500/60',
  failed: 'border-rose-500/60',
  cancelled: 'border-white/10',
}

// Compact "1d 5h 5m 5s" countdown text — omits leading zero units but always
// shows at least seconds so a live ticker never renders empty.
function fmtCountdown(totalSec) {
  if (totalSec <= 0) return '0s'
  const d = Math.floor(totalSec / 86400)
  const h = Math.floor((totalSec % 86400) / 3600)
  const m = Math.floor((totalSec % 3600) / 60)
  const s = totalSec % 60
  const parts = []
  if (d) parts.push(`${d}d`)
  if (h) parts.push(`${h}h`)
  if (m) parts.push(`${m}m`)
  if (s || parts.length === 0) parts.push(`${s}s`)
  return parts.join(' ')
}

// "YYYY-MM-DDTHH:MM:SS" in LOCAL time, for a datetime-local input's value/min.
function toLocalInput(ms) {
  const d = new Date(ms - new Date(ms).getTimezoneOffset() * 60000)
  return d.toISOString().slice(0, 19)
}

// Human, locale-friendly date+time for previews ("Mon, May 25, 2026, 2:30:45 PM").
function fmtDateTime(ms) {
  try {
    return new Date(ms).toLocaleString(undefined, {
      weekday: 'short', year: 'numeric', month: 'short', day: 'numeric',
      hour: '2-digit', minute: '2-digit', second: '2-digit',
    })
  } catch {
    return new Date(ms).toString()
  }
}

// Just the clock time ("2:30 PM") — used in recurring badges.
function fmtTimeOnly(ms) {
  try {
    return new Date(ms).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' })
  } catch {
    return ''
  }
}

// Weekday i18n keys, index 0=Sun … 6=Sat (matches JS getDay() and the backend).
const DOW_KEYS = [
  'notifications.dowSun', 'notifications.dowMon', 'notifications.dowTue',
  'notifications.dowWed', 'notifications.dowThu', 'notifications.dowFri',
  'notifications.dowSat',
]

// Build the "Repeats …" badge text for a recurring row from its kind/days/time.
function recurrenceLabel(push, t) {
  const kind = push.repeatKind
  if (!kind || kind === 'none') return ''
  const time = push.sendAt ? fmtTimeOnly(new Date(push.sendAt).getTime()) : ''
  switch (kind) {
    case 'minutely': return t('notifications.freqMinutely')
    case 'hourly':   return t('notifications.freqHourly')
    case 'daily':    return `${t('notifications.freqDaily')} · ${time}`
    case 'weekly': {
      const days = (push.repeatDays ?? []).slice().sort((a, b) => a - b)
        .map((d) => t(DOW_KEYS[d] ?? 'notifications.dowSun')).join(', ')
      return `${days} · ${time}`
    }
    case 'monthly':  return t('notifications.freqDaily') // (monthly not exposed in UI yet)
    default:         return kind
  }
}

export default function Notifications() {
  const { t } = useI18n()
  const [mode, setMode] = useState('send') // 'send' | 'scheduled'
  const [segment, setSegment] = useState('all')
  // Bilingual content. The admin writes BOTH the English and the Arabic copy;
  // delivery is split by each user's chosen language on the server, so there
  // is no per-send language choice. title/body = English, titleAr/bodyAr = Arabic.
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [titleAr, setTitleAr] = useState('')
  const [bodyAr, setBodyAr] = useState('')
  const [sending, setSending] = useState(false)
  const [result, setResult] = useState(null) // { ok, success_count, failure_count, recipients } | { ok:false, error }
  const [communities, setCommunities] = useState([])
  const [communityId, setCommunityId] = useState('')
  // Specific-user target: search by email → pick one user.
  const [userQuery, setUserQuery] = useState('')
  const [userResults, setUserResults] = useState([])
  const [userSearching, setUserSearching] = useState(false)
  const [selectedUser, setSelectedUser] = useState(null)

  // Countdown picker (scheduled mode) + the server-side queue.
  const [days, setDays] = useState(0)
  const [hours, setHours] = useState(0)
  const [minutes, setMinutes] = useState(5)
  const [seconds, setSeconds] = useState(0)
  const [dateTime, setDateTime] = useState('') // datetime-local value (local "YYYY-MM-DDTHH:MM:SS")
  // Recurring (Repeat tab)
  const [repeatFreq, setRepeatFreq] = useState('daily') // minutely|hourly|daily|weekly
  const [repeatWeekdays, setRepeatWeekdays] = useState(() => [new Date().getDay()]) // 0=Sun..6=Sat
  const [repeatTime, setRepeatTime] = useState('09:00') // HH:MM for daily/weekly
  const [scheduling, setScheduling] = useState(false)
  const [scheduled, setScheduled] = useState([])
  const [scheduledErr, setScheduledErr] = useState(null)
  const [schedFilter, setSchedFilter] = useState('all') // 'all' | 'upcoming' | 'sent'
  const [now, setNow] = useState(() => Date.now())

  const isScheduling = mode === 'countdown' || mode === 'datetime' || mode === 'repeat'
  const totalSeconds = days * 86400 + hours * 3600 + minutes * 60 + seconds
  const dateTimeMs = dateTime ? new Date(dateTime).getTime() : 0
  const dateTimeFuture = dateTimeMs > Date.now()

  // First fire time for a recurring schedule, derived from frequency + time/days.
  function computeRepeatStart() {
    const now = new Date()
    const [hh, mm] = repeatTime.split(':').map((n) => parseInt(n, 10))
    if (repeatFreq === 'minutely') return new Date(now.getTime() + 60_000)
    if (repeatFreq === 'hourly') return new Date(now.getTime() + 3_600_000)
    if (repeatFreq === 'daily') {
      const d = new Date(now)
      d.setHours(hh || 0, mm || 0, 0, 0)
      if (d.getTime() <= now.getTime()) d.setDate(d.getDate() + 1)
      return d
    }
    // weekly: soonest selected weekday at the chosen time
    for (let i = 0; i < 8; i++) {
      const d = new Date(now)
      d.setDate(now.getDate() + i)
      d.setHours(hh || 0, mm || 0, 0, 0)
      if (repeatWeekdays.includes(d.getDay()) && d.getTime() > now.getTime()) return d
    }
    return null
  }
  const repeatStart = mode === 'repeat' ? computeRepeatStart() : null
  const repeatReady =
    mode === 'repeat' &&
    Boolean(repeatStart) &&
    (repeatFreq !== 'weekly' || repeatWeekdays.length > 0)

  // Load the community list once so the "Specific community" segment can
  // offer a picker. Failure is non-fatal — the segment just shows empty.
  useEffect(() => {
    let cancelled = false
    api
      .get('/admin/communities')
      .then((res) => {
        if (cancelled) return
        const list = res?.communities ?? []
        setCommunities(list)
        if (list.length > 0) setCommunityId((cur) => cur || list[0].id)
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [])

  // Debounced user search (only while the "Specific user" target is active and
  // no user is selected yet). Hits GET /admin/users?q=<email>. Failure is
  // non-fatal — the results list just stays empty.
  useEffect(() => {
    if (segment !== 'user' || selectedUser) return
    const q = userQuery.trim()
    if (q.length < 2) {
      setUserResults([])
      setUserSearching(false)
      return
    }
    let cancelled = false
    setUserSearching(true)
    const handle = setTimeout(() => {
      api
        .get(`/admin/users?q=${encodeURIComponent(q)}&limit=8`)
        .then((res) => {
          if (!cancelled) setUserResults(res?.users ?? [])
        })
        .catch(() => {
          if (!cancelled) setUserResults([])
        })
        .finally(() => {
          if (!cancelled) setUserSearching(false)
        })
    }, 300)
    return () => {
      cancelled = true
      clearTimeout(handle)
    }
  }, [userQuery, segment, selectedUser])

  // Fetch the scheduled queue when entering either scheduling tab.
  useEffect(() => {
    if (!isScheduling) return
    loadScheduled()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isScheduling])

  // Tick once a second so the live countdowns update — only while a
  // scheduling tab is open with at least one pending/sending row.
  useEffect(() => {
    if (!isScheduling) return
    const hasPending = scheduled.some((p) => p.status === 'pending' || p.status === 'sending')
    if (!hasPending) return
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [isScheduling, scheduled])

  async function loadScheduled() {
    try {
      const res = await api.get('/admin/push/scheduled')
      setScheduled(res?.scheduled ?? res?.items ?? [])
      setScheduledErr(null)
    } catch (err) {
      setScheduledErr(
        err instanceof ApiError ? err.message : t('notifications.networkError'),
      )
    }
  }

  const needsCommunity = segment === 'community'
  const communityReady = !needsCommunity || Boolean(communityId)
  const needsUser = segment === 'user'
  const userReady = !needsUser || Boolean(selectedUser)
  // English copy is mandatory; Arabic is optional and falls back to English on
  // the server when blank, so a one-language send still reaches every user.
  const contentReady = title.trim().length > 0 && body.trim().length > 0
  const canSend = contentReady && communityReady && userReady && !sending

  // Fill both languages at once from a preset so the admin never has to pick a
  // language — the user's device decides which copy it shows.
  function applyTemplate(tpl) {
    setTitle(tpl.en?.title ?? '')
    setBody(tpl.en?.body ?? '')
    setTitleAr(tpl.ar?.title ?? '')
    setBodyAr(tpl.ar?.body ?? '')
    setResult(null)
  }

  // Lock in a searched user as the push target.
  function pickUser(u) {
    setSelectedUser(u)
    setUserQuery(u.email)
    setUserResults([])
  }

  // Clear the selection so the admin can search for a different user.
  function clearUser() {
    setSelectedUser(null)
    setUserQuery('')
    setUserResults([])
  }

  async function handleSend() {
    if (!canSend) return
    setSending(true)
    setResult(null)
    const seg = SEGMENTS.find((s) => s.key === segment) ?? SEGMENTS[0]
    const payload = {
      title: title.trim(),
      body: body.trim(),
      titleAr: titleAr.trim(),
      bodyAr: bodyAr.trim(),
      target: seg.target,
    }
    if (seg.role) payload.role = seg.role
    if (seg.target === 'community') payload.communityId = communityId
    if (seg.target === 'user' && selectedUser) payload.userId = selectedUser.id
    try {
      const res = await api.post('/admin/push/send', payload)
      setResult({
        ok: true,
        success_count: res.success_count ?? 0,
        failure_count: res.failure_count ?? 0,
        recipients: res.recipients ?? 0,
      })
      setTitle('')
      setBody('')
      setTitleAr('')
      setBodyAr('')
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.status === 503
            ? t('notifications.fcmNotConfigured')
            : err.message
          : t('notifications.networkError')
      setResult({ ok: false, error: message })
    } finally {
      setSending(false)
    }
  }

  // Time is "ready" depending on which scheduling tab is active.
  const timeReady =
    mode === 'countdown' ? totalSeconds > 0
      : mode === 'datetime' ? Boolean(dateTime) && dateTimeFuture
      : mode === 'repeat' ? repeatReady
      : false
  const canSchedule =
    contentReady && communityReady && userReady && timeReady && !scheduling

  async function handleSchedule() {
    if (!canSchedule) return
    setScheduling(true)
    setResult(null)
    const seg = SEGMENTS.find((s) => s.key === segment) ?? SEGMENTS[0]
    const payload = {
      title: title.trim(),
      body: body.trim(),
      titleAr: titleAr.trim(),
      bodyAr: bodyAr.trim(),
      target: seg.target,
    }
    if (seg.role) payload.role = seg.role
    if (seg.target === 'community') payload.communityId = communityId
    if (seg.target === 'user' && selectedUser) payload.userId = selectedUser.id
    // Repeat → sendAt(first occurrence) + repeat fields.
    // Absolute date/time → sendAt (RFC3339). Countdown → sendInSeconds.
    if (mode === 'repeat') {
      payload.sendAt = repeatStart.toISOString()
      payload.repeat = repeatFreq
      if (repeatFreq === 'weekly') payload.repeatDays = repeatWeekdays
    } else if (mode === 'datetime') {
      payload.sendAt = new Date(dateTime).toISOString()
    } else {
      payload.sendInSeconds = totalSeconds
    }
    try {
      await api.post('/admin/push/schedule', payload)
      if (mode === 'repeat') {
        setResult({ ok: true, scheduled: true, repeat: true, at: fmtDateTime(repeatStart.getTime()) })
      } else if (mode === 'datetime') {
        setResult({ ok: true, scheduled: true, at: fmtDateTime(dateTimeMs) })
        setDateTime('')
      } else {
        setResult({ ok: true, scheduled: true, duration: fmtCountdown(totalSeconds) })
      }
      setTitle('')
      setBody('')
      setTitleAr('')
      setBodyAr('')
      await loadScheduled()
    } catch (err) {
      const message =
        err instanceof ApiError
          ? err.status === 503
            ? t('notifications.fcmNotConfigured')
            : err.message
          : t('notifications.networkError')
      setResult({ ok: false, error: message })
    } finally {
      setScheduling(false)
    }
  }

  async function handleCancel(id) {
    // Optimistic flip to cancelled; reconcile from server afterward.
    setScheduled((list) =>
      list.map((p) => (p.id === id ? { ...p, status: 'cancelled' } : p)),
    )
    try {
      await api.delete(`/admin/push/scheduled/${id}`)
    } catch {
      /* ignore — the refresh below restores true state */
    }
    await loadScheduled()
  }

  const templates = templatesFor(segment)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">{t('notifications.title')}</h1>
        <p className="text-slate-400 text-sm mt-1">{t('notifications.subtitle')}</p>
      </div>

      {/* Send now | Countdown | Date & time tabs */}
      <div className="inline-flex flex-wrap rounded-xl bg-white/[0.03] ring-1 ring-white/10 p-1 gap-1">
        <button
          type="button"
          onClick={() => { setMode('send'); setResult(null) }}
          className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${
            mode === 'send' ? 'bg-cyan-500/20 text-cyan-300 ring-1 ring-cyan-500/30' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <Send className="w-4 h-4" /> {t('notifications.tabSendNow')}
        </button>
        <button
          type="button"
          onClick={() => { setMode('countdown'); setResult(null) }}
          className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${
            mode === 'countdown' ? 'bg-cyan-500/20 text-cyan-300 ring-1 ring-cyan-500/30' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <Timer className="w-4 h-4" /> {t('notifications.tabCountdown')}
        </button>
        <button
          type="button"
          onClick={() => { setMode('datetime'); setResult(null) }}
          className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${
            mode === 'datetime' ? 'bg-cyan-500/20 text-cyan-300 ring-1 ring-cyan-500/30' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <CalendarDays className="w-4 h-4" /> {t('notifications.tabDateTime')}
        </button>
        <button
          type="button"
          onClick={() => { setMode('repeat'); setResult(null) }}
          className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-semibold transition-colors ${
            mode === 'repeat' ? 'bg-cyan-500/20 text-cyan-300 ring-1 ring-cyan-500/30' : 'text-slate-400 hover:text-slate-200'
          }`}
        >
          <Repeat className="w-4 h-4" /> {t('notifications.tabRepeat')}
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 lg:gap-5">
        <div className="lg:col-span-1 card p-4 sm:p-5">
          <h3 className="font-semibold text-white mb-1">{t('notifications.compose')}</h3>
          <p className="text-xs text-slate-500 mb-4">{t('notifications.composeSub')}</p>

          <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.audience')}</label>
          <div className="grid grid-cols-1 gap-2 mb-3">
            {SEGMENTS.map((s) => (
              <SegmentOption
                key={s.key}
                icon={s.icon}
                label={t(s.labelKey)}
                sub={t(s.subKey)}
                active={segment === s.key}
                onClick={() => setSegment(s.key)}
              />
            ))}
          </div>

          {needsCommunity && (
            <div className="mb-4">
              <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.community')}</label>
              {communities.length > 0 ? (
                <select
                  className="input"
                  value={communityId}
                  onChange={(e) => setCommunityId(e.target.value)}
                  disabled={sending}
                >
                  {communities.map((c) => (
                    <option key={c.id} value={c.id}>
                      {t('notifications.communityMembers', { name: c.name, count: c.memberCount ?? 0 })}
                    </option>
                  ))}
                </select>
              ) : (
                <p className="text-xs text-slate-500">{t('notifications.noCommunities')}</p>
              )}
            </div>
          )}

          {needsUser && (
            <div className="mb-4">
              <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.userSearchLabel')}</label>
              {selectedUser ? (
                <div className="flex items-center gap-2 rounded-lg bg-cyan-500/10 ring-1 ring-cyan-500/30 px-3 py-2">
                  <div className="w-8 h-8 rounded-full bg-cyan-500/20 text-cyan-300 flex items-center justify-center shrink-0">
                    <User className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-white truncate">{selectedUser.name || selectedUser.email}</p>
                    <p className="text-xs text-slate-400 truncate" dir="ltr">{selectedUser.email}</p>
                  </div>
                  <button
                    type="button"
                    onClick={clearUser}
                    disabled={sending || scheduling}
                    className="shrink-0 text-xs font-semibold text-cyan-300 hover:text-cyan-200 disabled:opacity-50"
                  >
                    {t('notifications.userChange')}
                  </button>
                </div>
              ) : (
                <div>
                  <div className="relative">
                    <Search className="absolute start-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-500 pointer-events-none" />
                    <input
                      type="search"
                      className="input ps-9"
                      dir="ltr"
                      placeholder={t('notifications.userSearchPlaceholder')}
                      value={userQuery}
                      onChange={(e) => setUserQuery(e.target.value)}
                      disabled={sending || scheduling}
                    />
                  </div>
                  {userSearching && (
                    <p className="text-[11px] text-slate-500 mt-1.5 flex items-center gap-1.5">
                      <Loader2 className="w-3 h-3 animate-spin" /> {t('notifications.userSearching')}
                    </p>
                  )}
                  {!userSearching && userQuery.trim().length >= 2 && userResults.length === 0 && (
                    <p className="text-[11px] text-slate-500 mt-1.5">{t('notifications.userNoResults')}</p>
                  )}
                  {!userQuery && (
                    <p className="text-[11px] text-slate-500 mt-1.5">{t('notifications.userPickHint')}</p>
                  )}
                  {userResults.length > 0 && (
                    <ul className="mt-2 max-h-52 overflow-auto rounded-lg ring-1 ring-white/10 bg-[#0e1117] divide-y divide-white/5">
                      {userResults.map((u) => (
                        <li key={u.id}>
                          <button
                            type="button"
                            onClick={() => pickUser(u)}
                            className="w-full text-start px-3 py-2 hover:bg-cyan-500/10 transition-colors flex items-center gap-2"
                          >
                            <div className="w-7 h-7 rounded-full bg-white/5 text-slate-300 flex items-center justify-center shrink-0">
                              <User className="w-3.5 h-3.5" />
                            </div>
                            <div className="flex-1 min-w-0">
                              <p className="text-sm text-white truncate">{u.name || u.email}</p>
                              <p className="text-xs text-slate-500 truncate" dir="ltr">{u.email}</p>
                            </div>
                            <span className="text-[10px] uppercase tracking-wider text-slate-500 shrink-0">{u.role}</span>
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
              )}
            </div>
          )}

          <div className="mb-2">
            <label className="text-xs uppercase tracking-wider text-slate-500">{t('notifications.recommended')}</label>
          </div>
          <div className="flex flex-wrap gap-2 mb-3">
            {templates.map((tpl) => {
              const v = tpl.en
              const TplIcon = tpl.icon
              return (
                <button
                  key={tpl.key}
                  type="button"
                  onClick={() => applyTemplate(tpl)}
                  disabled={sending}
                  title={`${v.title} — ${v.body}`}
                  className="inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium bg-white/[0.03] ring-1 ring-white/10 text-slate-300 hover:bg-cyan-500/10 hover:ring-cyan-500/30 hover:text-cyan-300 transition-colors disabled:opacity-50"
                >
                  <TplIcon className="w-3.5 h-3.5" />
                  {t(tpl.labelKey)}
                </button>
              )
            })}
          </div>

          {/* Both languages are written once; the server sends each user the
              copy matching their chosen app language automatically. */}
          <p className="text-[11px] text-slate-500 mb-4 leading-relaxed">
            {t('notifications.bilingualHint')}
          </p>

          {/* English copy */}
          <div className="flex items-center gap-2 mb-2">
            <span className="text-[11px] font-bold uppercase tracking-wider text-cyan-300/80">English</span>
            <span className="h-px flex-1 bg-white/10" />
          </div>
          <input
            className="input mb-3"
            dir="ltr"
            placeholder="Notification title…"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={120}
            disabled={sending}
          />
          <textarea
            rows={3}
            className="input mb-4 resize-none"
            dir="ltr"
            placeholder="Write your notification message…"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            maxLength={500}
            disabled={sending}
          />

          {/* Arabic copy */}
          <div className="flex items-center gap-2 mb-2">
            <span className="text-[11px] font-bold uppercase tracking-wider text-cyan-300/80">العربية</span>
            <span className="h-px flex-1 bg-white/10" />
          </div>
          <input
            className="input mb-3 text-right"
            dir="rtl"
            placeholder="عنوان الإشعار…"
            value={titleAr}
            onChange={(e) => setTitleAr(e.target.value)}
            maxLength={120}
            disabled={sending}
          />
          <textarea
            rows={3}
            className="input mb-4 resize-none text-right"
            dir="rtl"
            placeholder="اكتب نص الإشعار…"
            value={bodyAr}
            onChange={(e) => setBodyAr(e.target.value)}
            maxLength={500}
            disabled={sending}
          />

          {result && (
            <div
              className={`mb-4 rounded-lg p-3 text-xs flex items-start gap-2 ${
                result.ok
                  ? 'bg-emerald-500/10 ring-1 ring-emerald-500/30 text-emerald-300'
                  : 'bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300'
              }`}
            >
              {result.ok ? (
                <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5" />
              ) : (
                <XCircle className="w-4 h-4 shrink-0 mt-0.5" />
              )}
              <div className="leading-relaxed">
                {result.ok ? (
                  result.scheduled ? (
                    result.repeat
                      ? t('notifications.scheduledRepeatOk', { time: result.at })
                      : result.at
                        ? t('notifications.scheduledAtOk', { time: result.at })
                        : t('notifications.scheduledOk', { duration: result.duration })
                  ) : (
                    <>
                      {(result.recipients === 1
                        ? t('notifications.sentToOne', { count: result.recipients, delivered: t('notifications.delivered', { count: result.success_count }) })
                        : t('notifications.sentToMany', { count: result.recipients, delivered: t('notifications.delivered', { count: result.success_count }) }))}
                      {result.failure_count > 0 && t('notifications.failedSuffix', { count: result.failure_count })}
                      .
                    </>
                  )
                ) : (
                  result.error
                )}
              </div>
            </div>
          )}

          {mode === 'send' ? (
            <div className="flex items-center gap-2">
              <button className="flex-1 btn-secondary justify-center" disabled={sending}>
                {t('notifications.saveDraft')}
              </button>
              <button
                className="flex-1 btn-primary justify-center disabled:opacity-50 disabled:cursor-not-allowed"
                onClick={handleSend}
                disabled={!canSend}
              >
                {sending ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" /> {t('notifications.sending')}
                  </>
                ) : (
                  <>
                    <Send className="w-4 h-4" /> {t('notifications.sendNow')}
                  </>
                )}
              </button>
            </div>
          ) : (
            <>
              {mode === 'countdown' ? (
                <>
                  <div className="rounded-lg bg-cyan-500/[0.06] ring-1 ring-cyan-500/15 p-3 mb-4 flex items-start gap-2">
                    <Hourglass className="w-4 h-4 text-cyan-400 shrink-0 mt-0.5" />
                    <p className="text-xs text-cyan-200/80 leading-relaxed">{t('notifications.scheduleHint')}</p>
                  </div>
                  <div className="grid grid-cols-4 gap-2 mb-2">
                    <TimeField label={t('notifications.days')} value={days} setValue={setDays} max={365} disabled={scheduling} />
                    <TimeField label={t('notifications.hours')} value={hours} setValue={setHours} max={23} disabled={scheduling} />
                    <TimeField label={t('notifications.minutes')} value={minutes} setValue={setMinutes} max={59} disabled={scheduling} />
                    <TimeField label={t('notifications.seconds')} value={seconds} setValue={setSeconds} max={59} disabled={scheduling} />
                  </div>
                  <p className="text-[11px] text-slate-500 mb-4 flex items-center gap-1.5">
                    <Clock className="w-3.5 h-3.5" />
                    {totalSeconds > 0 ? `${t('notifications.firesIn')} ${fmtCountdown(totalSeconds)}` : t('notifications.pickTime')}
                  </p>
                </>
              ) : mode === 'datetime' ? (
                <>
                  <div className="rounded-lg bg-cyan-500/[0.06] ring-1 ring-cyan-500/15 p-3 mb-4 flex items-start gap-2">
                    <CalendarDays className="w-4 h-4 text-cyan-400 shrink-0 mt-0.5" />
                    <p className="text-xs text-cyan-200/80 leading-relaxed">{t('notifications.dateTimeHint')}</p>
                  </div>
                  <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.pickDateTime')}</label>
                  <input
                    type="datetime-local"
                    step={1}
                    min={toLocalInput(Date.now())}
                    value={dateTime}
                    disabled={scheduling}
                    onChange={(e) => setDateTime(e.target.value)}
                    className="input mb-2 tabular-nums [color-scheme:dark]"
                  />
                  <p className="text-[11px] mb-4 flex items-center gap-1.5">
                    {dateTime && dateTimeFuture ? (
                      <span className="text-cyan-300 flex items-center gap-1.5">
                        <CalendarClock className="w-3.5 h-3.5" />
                        {t('notifications.sendsAt')} {fmtDateTime(dateTimeMs)} · {t('notifications.firesIn')} {fmtCountdown(Math.max(0, Math.round((dateTimeMs - now) / 1000)))}
                      </span>
                    ) : (
                      <span className="text-slate-500 flex items-center gap-1.5">
                        <Clock className="w-3.5 h-3.5" />
                        {t('notifications.pastTime')}
                      </span>
                    )}
                  </p>
                </>
              ) : (
                <>
                  <div className="rounded-lg bg-cyan-500/[0.06] ring-1 ring-cyan-500/15 p-3 mb-4 flex items-start gap-2">
                    <Repeat className="w-4 h-4 text-cyan-400 shrink-0 mt-0.5" />
                    <p className="text-xs text-cyan-200/80 leading-relaxed">{t('notifications.repeatHint')}</p>
                  </div>
                  <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.repeatFrequency')}</label>
                  <div className="grid grid-cols-2 gap-2 mb-3">
                    {[
                      ['minutely', 'notifications.freqMinutely'],
                      ['hourly', 'notifications.freqHourly'],
                      ['daily', 'notifications.freqDaily'],
                      ['weekly', 'notifications.freqWeekly'],
                    ].map(([key, lk]) => (
                      <button
                        key={key}
                        type="button"
                        disabled={scheduling}
                        onClick={() => setRepeatFreq(key)}
                        className={`px-3 py-2 rounded-lg text-sm font-medium transition-colors ring-1 ${
                          repeatFreq === key
                            ? 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30'
                            : 'bg-white/[0.02] text-slate-300 ring-white/10 hover:bg-white/5'
                        }`}
                      >
                        {t(lk)}
                      </button>
                    ))}
                  </div>

                  {repeatFreq === 'weekly' && (
                    <>
                      <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.onDays')}</label>
                      <div className="flex flex-wrap gap-1.5 mb-3">
                        {DOW_KEYS.map((dk, idx) => {
                          const on = repeatWeekdays.includes(idx)
                          return (
                            <button
                              key={idx}
                              type="button"
                              disabled={scheduling}
                              onClick={() =>
                                setRepeatWeekdays((cur) =>
                                  cur.includes(idx) ? cur.filter((d) => d !== idx) : [...cur, idx],
                                )
                              }
                              className={`w-10 h-9 rounded-lg text-xs font-semibold transition-colors ring-1 ${
                                on
                                  ? 'bg-cyan-500/20 text-cyan-300 ring-cyan-500/30'
                                  : 'bg-white/[0.02] text-slate-400 ring-white/10 hover:bg-white/5'
                              }`}
                            >
                              {t(dk)}
                            </button>
                          )
                        })}
                      </div>
                    </>
                  )}

                  {(repeatFreq === 'daily' || repeatFreq === 'weekly') && (
                    <>
                      <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.timeOfDay')}</label>
                      <input
                        type="time"
                        value={repeatTime}
                        disabled={scheduling}
                        onChange={(e) => setRepeatTime(e.target.value)}
                        className="input mb-2 tabular-nums [color-scheme:dark]"
                      />
                    </>
                  )}

                  <p className="text-[11px] mb-4 flex items-center gap-1.5">
                    {repeatReady ? (
                      <span className="text-cyan-300 flex items-center gap-1.5">
                        <Repeat className="w-3.5 h-3.5" />
                        {t('notifications.sendsAt')} {fmtDateTime(repeatStart.getTime())}
                      </span>
                    ) : (
                      <span className="text-slate-500 flex items-center gap-1.5">
                        <Clock className="w-3.5 h-3.5" />
                        {t('notifications.pickWeekday')}
                      </span>
                    )}
                  </p>
                </>
              )}
              <button
                className="w-full btn-primary justify-center disabled:opacity-50 disabled:cursor-not-allowed"
                onClick={handleSchedule}
                disabled={!canSchedule}
              >
                {scheduling ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" /> {t('notifications.scheduling')}
                  </>
                ) : (
                  <>
                    <CalendarClock className="w-4 h-4" /> {t('notifications.scheduleBtn')}
                  </>
                )}
              </button>
            </>
          )}
        </div>

        {mode === 'send' ? (
          <div className="lg:col-span-2 card overflow-hidden">
            <div className="px-4 sm:px-5 py-3 sm:py-4 border-b border-white/5 flex items-center justify-between gap-2 flex-wrap">
              <h3 className="font-semibold text-white">{t('notifications.recent')}</h3>
              <span className="text-[10px] uppercase tracking-wider text-slate-500 font-medium">{t('notifications.mockData')}</span>
            </div>
            <ul className="divide-y divide-white/5">
              {history.map((n) => (
                <li key={n.id} className="px-3 sm:px-5 py-3 sm:py-4 hover:bg-white/[0.02] transition-colors">
                  <div className="flex items-start gap-3">
                    <div className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${toneColors[n.tone]}`}>
                      <n.icon className="w-5 h-5" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-medium text-white line-clamp-2">{n.title}</p>
                      <div className="flex items-center gap-x-2 gap-y-0.5 text-xs text-slate-500 mt-1 flex-wrap">
                        <span className="truncate max-w-[10rem]">{n.segment}</span>
                        <span className="hidden sm:inline">·</span>
                        <span className="truncate max-w-[10rem]">{n.sent}</span>
                        <span className="hidden sm:inline">·</span>
                        <span className="hidden sm:inline">{n.date}</span>
                      </div>
                    </div>
                    <div className="text-end shrink-0">
                      <p className="text-[11px] text-slate-500">{t('notifications.openRate')}</p>
                      <p className="text-sm font-bold text-cyan-400">{n.open}</p>
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        ) : (
          (() => {
            // Split into the two buckets the user cares about.
            const upcoming = scheduled
              .filter(isUpcoming)
              .sort((a, b) => new Date(a.sendAt) - new Date(b.sendAt)) // soonest first
            const past = scheduled
              .filter((p) => !isUpcoming(p))
              .sort((a, b) => new Date(b.sendAt) - new Date(a.sendAt)) // most recent first
            const showUpcoming = schedFilter === 'all' || schedFilter === 'upcoming'
            const showPast = schedFilter === 'all' || schedFilter === 'sent'
            const renderSection = (label, count, rows, emptyKey) => (
              <div>
                <div className="px-4 sm:px-5 py-2 bg-white/[0.015] border-b border-white/5 flex items-center gap-2">
                  <span className="text-[10px] uppercase tracking-wider text-slate-500 font-semibold">{label}</span>
                  <span className="text-[10px] font-bold text-slate-400 bg-white/5 rounded-full px-1.5 py-0.5 tabular-nums">{count}</span>
                </div>
                {rows.length === 0 ? (
                  <p className="px-5 py-6 text-center text-xs text-slate-600">{t(emptyKey)}</p>
                ) : (
                  <ul className="divide-y divide-white/5">
                    {rows.map((p) => (
                      <ScheduledRow key={p.id} push={p} now={now} t={t} onCancel={() => handleCancel(p.id)} />
                    ))}
                  </ul>
                )}
              </div>
            )
            return (
              <div className="lg:col-span-2 card overflow-hidden flex flex-col">
                <div className="px-4 sm:px-5 py-3 sm:py-4 border-b border-white/5 flex items-center justify-between gap-3 flex-wrap">
                  <h3 className="font-semibold text-white flex items-center gap-2">
                    {t('notifications.scheduledList')}
                    {upcoming.length > 0 && (
                      <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-cyan-300 bg-cyan-500/10 ring-1 ring-cyan-500/25 rounded-full px-2 py-0.5">
                        <span className="relative flex h-1.5 w-1.5">
                          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-cyan-400 opacity-60" />
                          <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-cyan-400" />
                        </span>
                        {upcoming.length}
                      </span>
                    )}
                  </h3>
                  {/* All · Upcoming · Sent filter */}
                  <div className="inline-flex rounded-lg bg-white/[0.03] ring-1 ring-white/10 p-0.5 text-xs">
                    {[
                      ['all', 'notifications.filterAll'],
                      ['upcoming', 'notifications.filterUpcoming'],
                      ['sent', 'notifications.filterSent'],
                    ].map(([key, lk]) => (
                      <button
                        key={key}
                        type="button"
                        onClick={() => setSchedFilter(key)}
                        className={`px-2.5 py-1 rounded-md font-semibold transition-colors ${
                          schedFilter === key ? 'bg-cyan-500/20 text-cyan-300' : 'text-slate-400 hover:text-slate-200'
                        }`}
                      >
                        {t(lk)}
                      </button>
                    ))}
                  </div>
                </div>
                {scheduledErr ? (
                  <div className="px-5 py-8 text-center text-sm text-rose-300">{scheduledErr}</div>
                ) : scheduled.length === 0 ? (
                  <div className="px-5 py-12 text-center">
                    <CalendarClock className="w-8 h-8 text-slate-600 mx-auto mb-3" />
                    <p className="text-sm text-slate-500">{t('notifications.noScheduled')}</p>
                  </div>
                ) : (
                  <div className="divide-y divide-white/5">
                    {showUpcoming && renderSection(t('notifications.sectionUpcoming'), upcoming.length, upcoming, 'notifications.noUpcoming')}
                    {showPast && renderSection(t('notifications.sectionPast'), past.length, past, 'notifications.noSent')}
                  </div>
                )}
              </div>
            )
          })()
        )}
      </div>
    </div>
  )
}

// One scheduled-push row: live countdown for pending rows, status badge for
// the rest, and a Cancel button while still pending.
function ScheduledRow({ push, now, t, onCancel }) {
  const status = push.status ?? 'pending'
  const sendAtMs = push.sendAt ? new Date(push.sendAt).getTime() : 0
  const remaining = Math.max(0, Math.round((sendAtMs - now) / 1000))
  const tone = SCHEDULED_TONE[status] ?? SCHEDULED_TONE.pending
  const iconTint = (SCHEDULED_ICON[status] ?? SCHEDULED_ICON.pending).tint
  const accent = SCHEDULED_ACCENT[status] ?? SCHEDULED_ACCENT.pending
  const StatusIcon =
    status === 'sent' ? CheckCircle2 : status === 'failed' ? XCircle : status === 'cancelled' ? XCircle : Clock
  const statusLabel = {
    pending: t('notifications.statusPending'),
    sending: t('notifications.statusSending'),
    sent: t('notifications.statusSent'),
    failed: t('notifications.statusFailed'),
    cancelled: t('notifications.statusCancelled'),
  }[status] ?? status
  const dimmed = status === 'cancelled'
  const recurring = Boolean(push.repeatKind) && push.repeatKind !== 'none'

  return (
    <li className={`px-3 sm:px-5 py-3 sm:py-4 border-s-2 ${accent} hover:bg-white/[0.02] transition-colors ${dimmed ? 'opacity-60' : ''}`}>
      <div className="flex items-start gap-3">
        <div className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${iconTint}`}>
          <StatusIcon className="w-5 h-5" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="font-medium text-white truncate">{push.title}</p>
            <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider ring-1 ${tone}`}>
              {statusLabel}
            </span>
            {recurring && (
              <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-semibold ring-1 text-violet-300 bg-violet-500/10 ring-violet-500/25">
                <Repeat className="w-3 h-3" /> {recurrenceLabel(push, t)}
              </span>
            )}
          </div>
          {push.body && <p className="text-xs text-slate-500 mt-0.5 line-clamp-1">{push.body}</p>}
          <div className="text-xs text-slate-500 mt-1">
            {status === 'pending' ? (
              <span className="flex items-center gap-1.5 flex-wrap">
                <span className="text-cyan-300 font-semibold tabular-nums">
                  {t('notifications.firesIn')} {fmtCountdown(remaining)}
                </span>
                {sendAtMs > 0 && <span className="text-slate-600">· {fmtDateTime(sendAtMs)}</span>}
                {recurring && push.repeatCount > 0 && (
                  <span className="text-violet-300/80">· {t('notifications.runsCount', { count: push.repeatCount })}</span>
                )}
              </span>
            ) : status === 'sending' ? (
              <span className="text-amber-300 font-medium">{t('notifications.statusSending')}…</span>
            ) : status === 'sent' ? (
              <span className="flex items-center gap-1.5 flex-wrap">
                <span className="text-emerald-300/90 font-medium">{t('notifications.sentLabel')}</span>
                <span className="text-slate-600">· {t('notifications.delivered', { count: push.successCount ?? 0 })}</span>
                {push.sentAt && <span className="text-slate-600">· {fmtDateTime(new Date(push.sentAt).getTime())}</span>}
              </span>
            ) : status === 'failed' ? (
              <span className="text-rose-300 truncate">{push.error || t('notifications.statusFailed')}</span>
            ) : (
              <span>{t('notifications.statusCancelled')}</span>
            )}
          </div>
        </div>
        {status === 'pending' && (
          <button
            type="button"
            onClick={onCancel}
            title={t('notifications.cancelBtn')}
            className="shrink-0 inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium text-rose-300 bg-rose-500/10 ring-1 ring-rose-500/20 hover:bg-rose-500/20 transition-colors"
          >
            <Trash2 className="w-3.5 h-3.5" /> {t('notifications.cancelBtn')}
          </button>
        )}
      </div>
    </li>
  )
}

// Small labelled number input for the Days/Hours/Minutes/Seconds picker.
function TimeField({ label, value, setValue, max, disabled }) {
  return (
    <div>
      <label className="block text-[10px] uppercase tracking-wider text-slate-500 mb-1 text-center">{label}</label>
      <input
        type="number"
        min={0}
        max={max}
        value={value}
        disabled={disabled}
        onChange={(e) => {
          const n = parseInt(e.target.value, 10)
          if (Number.isNaN(n)) return setValue(0)
          setValue(Math.max(0, Math.min(max, n)))
        }}
        className="input text-center tabular-nums px-1"
      />
    </div>
  )
}

function SegmentOption({ icon: Icon, label, sub, active, onClick }) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-3 p-3 rounded-lg text-start transition-colors ${
        active
          ? 'bg-cyan-500/10 ring-1 ring-cyan-500/30'
          : 'bg-white/[0.02] ring-1 ring-white/5 hover:bg-white/5'
      }`}
    >
      <div className={`w-9 h-9 rounded-lg flex items-center justify-center ${active ? 'bg-cyan-500/20 text-cyan-400' : 'bg-white/5 text-slate-400'}`}>
        <Icon className="w-4 h-4" />
      </div>
      <div className="flex-1 min-w-0">
        <p className={`text-sm font-medium ${active ? 'text-white' : 'text-slate-200'}`}>{label}</p>
        <p className="text-xs text-slate-500">{sub}</p>
      </div>
      {active && <span className="w-2 h-2 rounded-full bg-cyan-400" />}
    </button>
  )
}
