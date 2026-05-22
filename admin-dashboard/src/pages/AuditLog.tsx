import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import {
  LogIn, UserPlus, LogOut as LogOutIcon, FileSignature, ShieldCheck,
  ShieldX, ArrowLeftRight, FileText, EyeOff, CreditCard, Activity,
  AlertCircle, Loader2, Inbox, Filter, Pencil, Trash2, Pin, PinOff,
  XCircle, LifeBuoy, X,
} from 'lucide-react'
import { api } from '../api/client'
import { useRealtime } from '../api/realtime'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'
import type { Locale } from '../i18n/translations'

type AuditEvent = {
  id: number
  type: string
  severity: 'info' | 'success' | 'warning' | 'error'
  actorId?: number
  actorEmail?: string
  targetId?: string
  targetKind?: string
  summary: string
  metadata?: Record<string, unknown>
  createdAt: string
}

// Per-event-type metadata: which icon, which short label, which color category.
// Color comes from severity, but the icon and label are type-specific.
const TYPE_META: Record<string, { icon: any; labelKey: string }> = {
  AUTH_LOGIN: { icon: LogIn, labelKey: 'auditLog.typeLogin' },
  AUTH_REGISTER: { icon: UserPlus, labelKey: 'auditLog.typeRegister' },
  AUTH_LOGOUT: { icon: LogOutIcon, labelKey: 'auditLog.typeLogout' },
  EXPERT_APP_SUBMITTED: { icon: FileSignature, labelKey: 'auditLog.typeApplication' },
  EXPERT_APP_APPROVED: { icon: ShieldCheck, labelKey: 'auditLog.typeApproved' },
  EXPERT_APP_REJECTED: { icon: ShieldX, labelKey: 'auditLog.typeRejected' },
  USER_ROLE_CHANGED: { icon: ArrowLeftRight, labelKey: 'auditLog.typeRoleChange' },
  POST_CREATED: { icon: FileText, labelKey: 'auditLog.typeNewPost' },
  POST_HIDDEN: { icon: EyeOff, labelKey: 'auditLog.typePostHidden' },
  SUBSCRIPTION_CHANGED: { icon: CreditCard, labelKey: 'auditLog.typeSubscription' },
  // Mig 0030 — admin support chat moderation. Written by handlers/support.go
  // whenever an admin edits / deletes / pins / closes a thread.
  ADMIN_SUPPORT_MESSAGE_EDIT:   { icon: Pencil,   labelKey: 'auditLog.typeSupportEdit' },
  ADMIN_SUPPORT_MESSAGE_DELETE: { icon: Trash2,   labelKey: 'auditLog.typeSupportDelete' },
  ADMIN_SUPPORT_THREAD_PIN:     { icon: Pin,      labelKey: 'auditLog.typeSupportPin' },
  ADMIN_SUPPORT_THREAD_UNPIN:   { icon: PinOff,   labelKey: 'auditLog.typeSupportUnpin' },
  ADMIN_SUPPORT_THREAD_CLOSE:   { icon: XCircle,  labelKey: 'auditLog.typeSupportClose' },
}

const SEV_STYLES: Record<AuditEvent['severity'], { ring: string; bg: string; text: string }> = {
  info:    { ring: 'ring-cyan-500/30',    bg: 'bg-cyan-500/12',    text: 'text-cyan-300' },
  success: { ring: 'ring-emerald-500/30', bg: 'bg-emerald-500/12', text: 'text-emerald-300' },
  warning: { ring: 'ring-amber-500/40',   bg: 'bg-amber-500/15',   text: 'text-amber-300' },
  error:   { ring: 'ring-rose-500/40',    bg: 'bg-rose-500/15',    text: 'text-rose-300' },
}

const TYPE_TABS = [
  { id: 'all',     labelKey: 'auditLog.tabAll',     types: [] as string[] },
  { id: 'auth',    labelKey: 'auditLog.tabAuth',    types: ['AUTH_LOGIN', 'AUTH_REGISTER', 'AUTH_LOGOUT'] },
  { id: 'apps',    labelKey: 'auditLog.tabApps',    types: ['EXPERT_APP_SUBMITTED', 'EXPERT_APP_APPROVED', 'EXPERT_APP_REJECTED'] },
  { id: 'users',   labelKey: 'auditLog.tabUsers',   types: ['USER_ROLE_CHANGED'] },
  { id: 'content', labelKey: 'auditLog.tabContent', types: ['POST_CREATED', 'POST_HIDDEN'] },
  { id: 'subs',    labelKey: 'auditLog.tabSubs',    types: ['SUBSCRIPTION_CHANGED'] },
  // Mig 0030 — Support moderation tab. Groups the 5 admin actions
  // emitted by handlers/support.go so an admin reviewing chat history
  // can scope the feed to just support events without scrolling past
  // unrelated login/post rows.
  { id: 'support', labelKey: 'auditLog.tabSupport', types: [
    'ADMIN_SUPPORT_MESSAGE_EDIT',
    'ADMIN_SUPPORT_MESSAGE_DELETE',
    'ADMIN_SUPPORT_THREAD_PIN',
    'ADMIN_SUPPORT_THREAD_UNPIN',
    'ADMIN_SUPPORT_THREAD_CLOSE',
  ] },
]

const SEV_FILTER = ['all', 'info', 'success', 'warning', 'error'] as const
type SevFilter = (typeof SEV_FILTER)[number]

export default function AuditLog() {
  const { t } = useI18n()
  // Read deep-link filters from the URL once on mount. Support page
  // links here as `/audit-log?targetId=42&targetKind=support_thread` —
  // when those are present we auto-switch to the Support tab so the
  // page makes sense without a manual tab click.
  const [searchParams, setSearchParams] = useSearchParams()
  const initialTargetId = searchParams.get('targetId') ?? ''
  const initialTargetKind = searchParams.get('targetKind') ?? ''
  const initialTab =
    initialTargetKind === 'support_thread' ? 'support' : 'all'

  const [activeTab, setActiveTab] = useState(initialTab)
  const [severity, setSeverity] = useState<SevFilter>('all')
  const [targetId, setTargetId] = useState(initialTargetId)
  const [targetKind, setTargetKind] = useState(initialTargetKind)
  const [events, setEvents] = useState<AuditEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const types = useMemo(
    () => TYPE_TABS.find((t) => t.id === activeTab)?.types ?? [],
    [activeTab],
  )

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const params = new URLSearchParams()
      if (types.length) params.set('type', types.join(','))
      if (severity !== 'all') params.set('severity', severity)
      if (targetId) params.set('targetId', targetId)
      if (targetKind) params.set('targetKind', targetKind)
      params.set('limit', '100')
      const res = await api.get<{ events: AuditEvent[] }>(`/admin/audit-logs?${params}`)
      setEvents(res.events ?? [])
    } catch (e: any) {
      setError(e?.message ?? t('auditLog.loadFailed'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [activeTab, severity, targetId, targetKind])

  // Clear the URL filter (chip's × button). Drops the search params
  // so a refresh doesn't re-apply the deep-link.
  function clearTargetFilter() {
    setTargetId('')
    setTargetKind('')
    const next = new URLSearchParams(searchParams)
    next.delete('targetId')
    next.delete('targetKind')
    setSearchParams(next, { replace: true })
  }

  // Live updates — every new audit row arrives as `audit_log_created`.
  // Prepend if it matches the current filters; otherwise just bump the count.
  useRealtime(['audit_log_created'], (ev) => {
    const e = ev.data as unknown as AuditEvent
    if (!e || !e.id) return
    if (types.length && !types.includes(e.type)) return
    if (severity !== 'all' && e.severity !== severity) return
    if (targetId && String(e.targetId ?? '') !== targetId) return
    if (targetKind && (e.targetKind ?? '') !== targetKind) return
    setEvents((curr) => [e, ...curr.filter((x) => x.id !== e.id)].slice(0, 200))
  })

  const eventCount = events.length

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">{t('auditLog.title')}</h1>
          <p className="text-slate-400 text-sm mt-1">
            {eventCount === 1
              ? t('auditLog.subtitleOne', { count: eventCount })
              : t('auditLog.subtitleMany', { count: eventCount })}
          </p>
        </div>
        <button onClick={load} className="btn-secondary">
          <Activity className="w-4 h-4" /> {t('common.refresh')}
        </button>
      </div>

      {/* Filters */}
      <div className="card p-3 space-y-3">
        {/* Target filter chip — shown only when deep-linked from another
            page (e.g. /support/:id → "View audit log"). Lives above the
            tabs so it's obvious why the feed is so short. */}
        {(targetId || targetKind) && (
          <div className="flex items-center gap-2 flex-wrap">
            <span className="text-xs uppercase tracking-wider text-slate-500">
              {t('auditLog.filteringBy')}
            </span>
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-cyan-500/15 ring-1 ring-cyan-500/30 text-cyan-300 text-xs font-bold">
              {targetKind === 'support_thread' && (
                <LifeBuoy className="w-3.5 h-3.5" />
              )}
              {targetKind || t('auditLog.targetFallback')}
              {targetId && <span className="opacity-70">#{targetId}</span>}
              <button
                onClick={clearTargetFilter}
                title={t('auditLog.clearTargetFilter')}
                className="ms-1 -me-1 p-0.5 rounded hover:bg-white/10"
              >
                <X className="w-3 h-3" />
              </button>
            </span>
          </div>
        )}
        <div className="flex items-center gap-2 overflow-x-auto whitespace-nowrap -mx-1 px-1 pb-1">
          {TYPE_TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`shrink-0 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                activeTab === tab.id
                  ? 'bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/20'
                  : 'text-slate-400 hover:bg-white/5'
              }`}
            >
              {t(tab.labelKey as Parameters<typeof t>[0])}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <Filter className="w-4 h-4 text-slate-500 shrink-0" />
          <span className="text-xs uppercase tracking-wider text-slate-500">{t('auditLog.severity')}</span>
          {SEV_FILTER.map((s) => (
            <button
              key={s}
              onClick={() => setSeverity(s)}
              className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                severity === s
                  ? 'bg-white/10 text-white ring-1 ring-white/20'
                  : 'text-slate-500 hover:bg-white/5'
              }`}
            >
              {t(`auditLog.sev${s.charAt(0).toUpperCase() + s.slice(1)}` as Parameters<typeof t>[0])}
            </button>
          ))}
        </div>
      </div>

      {/* Feed */}
      <div className="card overflow-hidden">
        {error && (
          <div className="m-4 flex items-start gap-2 p-3 rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300 text-sm">
            <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {loading && events.length === 0 ? (
          <div className="flex items-center justify-center py-16 text-slate-400">
            <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('common.loading')}
          </div>
        ) : events.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-slate-500">
            <Inbox className="w-10 h-10 mb-3 opacity-50" />
            <p className="text-sm">{t('auditLog.empty')}</p>
          </div>
        ) : (
          <ul className="divide-y divide-white/5">
            {events.map((e) => (
              <EventRow key={e.id} event={e} />
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}

function EventRow({ event }: { event: AuditEvent }) {
  const { t, locale } = useI18n()
  const meta = TYPE_META[event.type]
  const label = meta ? t(meta.labelKey as Parameters<typeof t>[0]) : event.type
  const Icon = meta?.icon ?? Activity
  const sev = SEV_STYLES[event.severity] ?? SEV_STYLES.info
  // Step-22 — whole row → /audit-log/:id detail page.
  const navigate = useNavigate()
  function onRowClick(e: React.MouseEvent) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    navigate(`/audit-log/${event.id}`)
  }

  return (
    <li
      onClick={onRowClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') navigate(`/audit-log/${event.id}`)
      }}
      className="cursor-pointer px-3 sm:px-5 py-3.5 flex items-start gap-3 hover:bg-white/[0.02] transition-colors">
      <div className={`w-9 h-9 rounded-lg flex items-center justify-center ring-1 shrink-0 ${sev.bg} ${sev.ring}`}>
        <Icon className={`w-4.5 h-4.5 ${sev.text}`} />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className={`text-[10px] uppercase tracking-wider font-bold ${sev.text}`}>
            {label}
          </span>
          <span className="text-[10px] uppercase tracking-wider text-slate-500">
            {event.type}
          </span>
        </div>
        <p className="text-sm text-slate-200 mt-0.5 truncate">{event.summary}</p>
        <div className="flex items-center gap-3 text-[11px] text-slate-500 mt-1">
          {event.actorEmail && <span>{event.actorEmail}</span>}
          {event.targetKind && (
            <span className="text-slate-600">
              {event.targetKind}#{event.targetId}
            </span>
          )}
          <span className="ms-auto">{relativeTime(new Date(event.createdAt), t, locale)}</span>
        </div>
      </div>
    </li>
  )
}

function relativeTime(date: Date, t: (key: any, vars?: Record<string, string | number>) => string, locale: Locale) {
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000))
  if (seconds < 60) return t('auditLog.secondsAgo', { n: seconds })
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return t('auditLog.minutesAgo', { n: minutes })
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return t('auditLog.hoursAgo', { n: hours })
  const days = Math.floor(hours / 24)
  if (days < 7) return t('auditLog.daysAgo', { n: days })
  return fmtDate(date, locale)
}
