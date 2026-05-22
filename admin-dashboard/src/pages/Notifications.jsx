import { useState, useEffect } from 'react'
import {
  Send,
  Users,
  ShieldCheck,
  TrendingUp,
  AlertCircle,
  Smartphone,
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
  { key: 'ios', target: 'ios', labelKey: 'notifications.segIos', subKey: 'notifications.segIosSub', icon: Smartphone },
  { key: 'android', target: 'android', labelKey: 'notifications.segAndroid', subKey: 'notifications.segAndroidSub', icon: Smartphone },
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
  ],
}
function templatesFor(segment) {
  return [...(SEGMENT_TEMPLATES[segment] ?? []), ...COMMON_TEMPLATES]
}

export default function Notifications() {
  const { t } = useI18n()
  const [segment, setSegment] = useState('all')
  const [lang, setLang] = useState('en') // 'en' | 'ar' — language of the push content
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)
  const [result, setResult] = useState(null) // { ok, success_count, failure_count, recipients } | { ok:false, error }
  const [communities, setCommunities] = useState([])
  const [communityId, setCommunityId] = useState('')

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

  const isRTL = lang === 'ar'
  const needsCommunity = segment === 'community'
  const communityReady = !needsCommunity || Boolean(communityId)
  const canSend =
    title.trim().length > 0 && body.trim().length > 0 && communityReady && !sending

  function applyTemplate(tpl) {
    const v = tpl[lang] ?? tpl.en
    setTitle(v.title)
    setBody(v.body)
    setResult(null)
  }

  async function handleSend() {
    if (!canSend) return
    setSending(true)
    setResult(null)
    const seg = SEGMENTS.find((s) => s.key === segment) ?? SEGMENTS[0]
    const payload = { title: title.trim(), body: body.trim(), target: seg.target }
    if (seg.role) payload.role = seg.role
    if (seg.target === 'community') payload.communityId = communityId
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

  const templates = templatesFor(segment)

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">{t('notifications.title')}</h1>
        <p className="text-slate-400 text-sm mt-1">{t('notifications.subtitle')}</p>
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

          <div className="flex items-center justify-between mb-2">
            <label className="text-xs uppercase tracking-wider text-slate-500">{t('notifications.recommended')}</label>
            <LanguageToggle lang={lang} setLang={setLang} />
          </div>
          <div className="flex flex-wrap gap-2 mb-4">
            {templates.map((tpl) => {
              const v = tpl[lang] ?? tpl.en
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

          <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.titleLabel')}</label>
          <input
            className={`input mb-3 ${isRTL ? 'text-right' : ''}`}
            dir={isRTL ? 'rtl' : 'ltr'}
            placeholder={isRTL ? 'عيد أضحى مبارك...' : 'Eid Mubarak special...'}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            maxLength={120}
            disabled={sending}
          />

          <label className="block text-xs uppercase tracking-wider text-slate-500 mb-2">{t('notifications.messageLabel')}</label>
          <textarea
            rows={4}
            className={`input mb-4 resize-none ${isRTL ? 'text-right' : ''}`}
            dir={isRTL ? 'rtl' : 'ltr'}
            placeholder={isRTL ? 'اكتب نص الإشعار...' : 'Write your notification body...'}
            value={body}
            onChange={(e) => setBody(e.target.value)}
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
                  <>
                    {(result.recipients === 1
                      ? t('notifications.sentToOne', { count: result.recipients, delivered: t('notifications.delivered', { count: result.success_count }) })
                      : t('notifications.sentToMany', { count: result.recipients, delivered: t('notifications.delivered', { count: result.success_count }) }))}
                    {result.failure_count > 0 && t('notifications.failedSuffix', { count: result.failure_count })}
                    .
                  </>
                ) : (
                  result.error
                )}
              </div>
            </div>
          )}

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
        </div>

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
      </div>
    </div>
  )
}

function LanguageToggle({ lang, setLang }) {
  return (
    <div className="inline-flex rounded-lg bg-white/[0.03] ring-1 ring-white/10 p-0.5">
      <button
        type="button"
        onClick={() => setLang('en')}
        className={`px-2.5 py-1 rounded-md text-xs font-semibold transition-colors ${
          lang === 'en' ? 'bg-cyan-500/20 text-cyan-300' : 'text-slate-400 hover:text-slate-200'
        }`}
      >
        EN
      </button>
      <button
        type="button"
        onClick={() => setLang('ar')}
        className={`px-2.5 py-1 rounded-md text-xs font-semibold transition-colors ${
          lang === 'ar' ? 'bg-cyan-500/20 text-cyan-300' : 'text-slate-400 hover:text-slate-200'
        }`}
      >
        العربية
      </button>
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
