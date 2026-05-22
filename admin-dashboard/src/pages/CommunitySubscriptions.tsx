import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Check,
  X,
  AlertCircle,
  Loader2,
  Inbox,
  Banknote,
  Building2,
  MessageSquare,
  RefreshCw,
  Hash,
  Users as UsersIcon,
  Search,
  Image as ImageIcon,
  TrendingUp,
} from 'lucide-react'
import { api } from '../api/client'
import { useRealtime } from '../api/realtime'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'
import type { Locale } from '../i18n/translations'

// Mirrors backend `repositories.CommunitySubscription` (mig 0022 + 0025).
type CommunitySub = {
  id: number
  userId: number
  userEmail?: string
  userName?: string
  communityId: string
  communityName?: string
  plan: 'monthly' | 'yearly'
  status: 'pending' | 'active' | 'rejected' | 'cancelled' | 'expired'
  priceCents: number
  currency: string
  paymentMethod: 'cash' | 'fib'
  paymentRef?: string
  receiptUrl?: string | null
  userNote?: string
  rejectionReason?: string
  createdAt: string
  expiresAt?: string | null
}

type Totals = {
  activeCount: number
  pendingCount: number
  activeRevenueCents: number
  currency: string
}

const TABS = [
  { id: 'pending', label: 'Pending' },
  { id: 'active', label: 'Active' },
  { id: 'rejected', label: 'Rejected' },
  { id: 'cancelled', label: 'Cancelled' },
  { id: 'expired', label: 'Expired' },
] as const

const STATUS_STYLES: Record<string, { ring: string; bg: string; text: string }> = {
  pending: { ring: 'ring-amber-500/30', bg: 'bg-amber-500/12', text: 'text-amber-300' },
  active: { ring: 'ring-emerald-500/30', bg: 'bg-emerald-500/12', text: 'text-emerald-300' },
  rejected: { ring: 'ring-rose-500/30', bg: 'bg-rose-500/15', text: 'text-rose-300' },
  cancelled: { ring: 'ring-slate-500/30', bg: 'bg-slate-500/15', text: 'text-slate-300' },
  expired: { ring: 'ring-slate-500/30', bg: 'bg-slate-500/15', text: 'text-slate-300' },
}

const PLAN_BADGE: Record<string, { label: string; color: string }> = {
  monthly: { label: 'Monthly', color: 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30' },
  yearly: { label: 'Yearly', color: 'bg-gold-500/15 text-gold-400 ring-gold-500/30' },
}

const METHOD_META: Record<string, { Icon: React.ComponentType<{ className?: string }>; label: string }> = {
  cash: { Icon: Banknote, label: 'Cash' },
  fib: { Icon: Building2, label: 'FIB' },
}

const PAGE_SIZE = 25

// VITE_API_BASE_URL is the canonical name (set in .env.local). The old
// VITE_API_BASE name was never wired into the env file, so /uploads
// images resolved against the Vite dev server and rendered as broken.
function absoluteUrl(path?: string | null) {
  if (!path) return ''
  if (path.startsWith('http')) return path
  const base = (import.meta as any).env?.VITE_API_BASE_URL ?? ''
  const origin = base.replace(/\/api\/?$/, '')
  return `${origin}${path}`
}

function formatMoney(cents: number, currency: string) {
  const dollars = cents / 100
  const sym = (currency || '').toLowerCase() === 'usd' ? '$' : `${currency.toUpperCase()} `
  return `${sym}${dollars.toFixed(dollars % 1 === 0 ? 0 : 2)}`
}

/**
 * CommunitySubscriptions — admin queue for paid community membership
 * payments (mig 0022 / 0025). Mirrors the expert Subscriptions page so
 * the admin's mental model stays the same: same totals strip, same
 * search box, same payment-method chips, same inline accept/reject.
 */
export default function CommunitySubscriptions() {
  const { t } = useI18n()
  // Status label per tab id — maps the server status enum to a localized
  // word. Used in the headline and the empty-state copy.
  const statusLabel = (id: string) =>
    ({
      pending: t('communitySubs.statusPending'),
      active: t('communitySubs.statusActive'),
      rejected: t('communitySubs.statusRejected'),
      cancelled: t('communitySubs.statusCancelled'),
      expired: t('communitySubs.statusExpired'),
    }[id] ?? id)
  const [tab, setTab] = useState<typeof TABS[number]['id']>('pending')
  const [query, setQuery] = useState('')
  const [methodFilter, setMethodFilter] = useState<'' | 'cash' | 'fib'>('')
  const [items, setItems] = useState<CommunitySub[]>([])
  const [hasMore, setHasMore] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [pendingCount, setPendingCount] = useState<number | null>(null)
  const [totals, setTotals] = useState<Totals | null>(null)
  const [acting, setActing] = useState<number | null>(null)
  const [rejectingId, setRejectingId] = useState<number | null>(null)
  const [rejectReason, setRejectReason] = useState('')
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  async function load({ reset = true, cursor = 0 } = {}) {
    if (reset) setLoading(true)
    setError(null)
    try {
      const params = new URLSearchParams()
      params.set('status', tab)
      if (methodFilter) params.set('paymentMethod', methodFilter)
      if (query.trim()) params.set('q', query.trim())
      params.set('limit', String(PAGE_SIZE))
      if (cursor > 0) params.set('cursor', String(cursor))
      const res = await api.get<{ subscriptions: CommunitySub[] }>(
        `/admin/community-subscriptions?${params}`,
      )
      const next = res.subscriptions ?? []
      setHasMore(next.length === PAGE_SIZE)
      if (reset) setItems(next)
      else setItems((curr) => [...curr, ...next])
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  async function loadPendingCount() {
    try {
      const res = await api.get<{ count: number }>(
        '/admin/community-subscriptions/pending-count',
      )
      setPendingCount(res.count ?? 0)
    } catch {
      setPendingCount(0)
    }
  }

  async function loadTotals() {
    try {
      const res = await api.get<Totals>(
        '/admin/community-subscriptions/totals',
      )
      setTotals(res ?? null)
    } catch {
      setTotals(null)
    }
  }

  useEffect(() => {
    load({ reset: true })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tab, methodFilter])

  useEffect(() => {
    if (searchTimer.current) clearTimeout(searchTimer.current)
    searchTimer.current = setTimeout(() => load({ reset: true }), 250)
    return () => {
      if (searchTimer.current) clearTimeout(searchTimer.current)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query])

  useEffect(() => {
    loadPendingCount()
    loadTotals()
  }, [])

  // Auto-refresh on lifecycle events.
  useRealtime(
    [
      'community_subscription_submitted',
      'community_subscription_active',
      'community_subscription_rejected',
      'community_subscription_cancelled',
      'community_subscription_expired',
    ],
    () => {
      load({ reset: true })
      loadPendingCount()
      loadTotals()
    },
  )

  async function accept(id: number) {
    setActing(id)
    try {
      await api.post(`/admin/community-subscriptions/${id}/accept`)
      setItems((curr) => curr.filter((s) => s.id !== id))
      loadPendingCount()
      loadTotals()
    } catch (e) {
      alert((e as Error).message ?? t('communitySubs.acceptFailed'))
    } finally {
      setActing(null)
    }
  }

  async function confirmReject(id: number) {
    setActing(id)
    try {
      await api.post(`/admin/community-subscriptions/${id}/reject`, {
        reason: rejectReason.trim(),
      })
      setItems((curr) => curr.filter((s) => s.id !== id))
      setRejectingId(null)
      setRejectReason('')
      loadPendingCount()
    } catch (e) {
      alert((e as Error).message ?? t('communitySubs.rejectFailed'))
    } finally {
      setActing(null)
    }
  }

  function startReject(id: number) {
    setRejectingId(id)
    setRejectReason('')
  }
  function cancelReject() {
    setRejectingId(null)
    setRejectReason('')
  }

  const headline = useMemo(() => {
    const total = items.length
    const status = statusLabel(tab)
    return total === 1
      ? t('communitySubs.headlineOne', { count: total, status })
      : t('communitySubs.headline', { count: total, status })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [items.length, tab])

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            {t('communitySubs.title')}
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            {pendingCount !== null && pendingCount > 0 ? (
              <>
                <span className="text-amber-400 font-semibold">{t('communitySubs.pendingHeadline', { count: pendingCount })}</span> · {headline.toLowerCase()}
              </>
            ) : (
              headline
            )}
            {t('communitySubs.subtitleSuffix')}
          </p>
        </div>
        <button
          onClick={() => { load({ reset: true }); loadTotals() }}
          className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 ring-1 ring-white/10"
        >
          <RefreshCw className="w-4 h-4" /> {t('common.refresh')}
        </button>
      </div>

      {/* Totals strip */}
      {totals && (
        <div className="grid grid-cols-3 gap-3">
          <TotalsTile
            label={t('communitySubs.activeSubscriptions')}
            value={String(totals.activeCount ?? 0)}
            tone="emerald"
            icon={<Check className="w-3.5 h-3.5" />}
          />
          <TotalsTile
            label={t('communitySubs.pendingReview')}
            value={String(totals.pendingCount ?? 0)}
            tone="amber"
            icon={<AlertCircle className="w-3.5 h-3.5" />}
          />
          <TotalsTile
            label={t('communitySubs.activeRevenue')}
            value={formatMoney(totals.activeRevenueCents ?? 0, totals.currency ?? 'usd')}
            tone="cyan"
            icon={<TrendingUp className="w-3.5 h-3.5" />}
          />
        </div>
      )}

      {/* Tabs + search + filter */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-3 space-y-3">
        <div className="flex items-center gap-2 overflow-x-auto whitespace-nowrap -mx-1 px-1 pb-1">
          {TABS.map((tabDef) => (
            <button
              key={tabDef.id}
              onClick={() => setTab(tabDef.id)}
              className={`shrink-0 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                tab === tabDef.id
                  ? 'bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/20'
                  : 'text-slate-400 hover:bg-white/5'
              }`}
            >
              {statusLabel(tabDef.id)}
              {tabDef.id === 'pending' && pendingCount !== null && pendingCount > 0 && (
                <span className="ms-1.5 text-[10px] bg-amber-500/20 text-amber-400 px-1.5 py-0.5 rounded-full">
                  {pendingCount}
                </span>
              )}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-3 flex-wrap">
          <div className="flex-1 min-w-[12rem] relative">
            <Search className="w-4 h-4 absolute start-3 top-1/2 -translate-y-1/2 text-slate-500" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={t('communitySubs.searchPlaceholder')}
              className="input ps-9 w-full"
            />
          </div>
          <div className="flex items-center gap-1.5">
            <span className="text-[10px] uppercase tracking-wider text-slate-500 me-1">{t('communitySubs.method')}</span>
            {([
              { id: '', label: t('communitySubs.methodAll') },
              { id: 'cash', label: t('communitySubs.methodCash') },
              { id: 'fib', label: t('communitySubs.methodFib') },
            ] as const).map((m) => (
              <button
                key={m.id || 'all'}
                onClick={() => setMethodFilter(m.id as '' | 'cash' | 'fib')}
                className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                  methodFilter === m.id
                    ? 'bg-white/10 text-white ring-1 ring-white/20'
                    : 'text-slate-500 hover:bg-white/5'
                }`}
              >
                {m.label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Feed */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 overflow-hidden">
        {error && (
          <div className="m-4 flex items-start gap-2 p-3 rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300 text-sm">
            <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {loading && items.length === 0 ? (
          <div className="flex items-center justify-center py-16 text-slate-400">
            <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('common.loading')}
          </div>
        ) : items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-slate-500">
            <Inbox className="w-10 h-10 mb-3 opacity-50" />
            <p className="text-sm">
              {query.trim()
                ? t('communitySubs.noMatch', { status: statusLabel(tab), query: query.trim() })
                : t('communitySubs.noneStatus', { status: statusLabel(tab) })}
            </p>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 p-4">
              {items.map((s) => (
                <SubCard
                  key={s.id}
                  sub={s}
                  showActions={tab === 'pending'}
                  acting={acting === s.id}
                  rejecting={rejectingId === s.id}
                  rejectReason={rejectReason}
                  setRejectReason={setRejectReason}
                  onAccept={() => accept(s.id)}
                  onStartReject={() => startReject(s.id)}
                  onCancelReject={cancelReject}
                  onConfirmReject={() => confirmReject(s.id)}
                />
              ))}
            </div>
            {hasMore && (
              <div className="px-4 pb-4 flex items-center justify-center">
                <button
                  onClick={() => {
                    const lastId = items.length > 0 ? items[items.length - 1].id : 0
                    load({ reset: false, cursor: lastId })
                  }}
                  className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 ring-1 ring-white/10"
                >
                  {t('communitySubs.loadMore')}
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}

function TotalsTile({
  label,
  value,
  tone,
  icon,
}: {
  label: string
  value: string
  tone: 'emerald' | 'amber' | 'cyan'
  icon: React.ReactNode
}) {
  const TONE: Record<string, string> = {
    emerald: 'bg-emerald-500/10 ring-emerald-500/30 text-emerald-300',
    amber: 'bg-amber-500/10 ring-amber-500/30 text-amber-300',
    cyan: 'bg-cyan-500/10 ring-cyan-500/30 text-cyan-300',
  }
  return (
    <div className={`rounded-xl px-3 py-2.5 ring-1 ${TONE[tone]}`}>
      <div className="flex items-center gap-1.5 text-[10px] uppercase tracking-wider opacity-80">
        {icon}
        {label}
      </div>
      <p className="text-lg font-bold mt-0.5 truncate">{value}</p>
    </div>
  )
}

function SubCard({
  sub,
  showActions,
  acting,
  rejecting,
  rejectReason,
  setRejectReason,
  onAccept,
  onStartReject,
  onCancelReject,
  onConfirmReject,
}: {
  sub: CommunitySub
  showActions: boolean
  acting: boolean
  rejecting: boolean
  rejectReason: string
  setRejectReason: (s: string) => void
  onAccept: () => void
  onStartReject: () => void
  onCancelReject: () => void
  onConfirmReject: () => void
}) {
  const { t, locale } = useI18n()
  const sev = STATUS_STYLES[sub.status] ?? STATUS_STYLES.pending
  const planMeta = PLAN_BADGE[sub.plan] ?? PLAN_BADGE.monthly
  const planLabel = sub.plan === 'yearly' ? t('communitySubs.planYearly') : t('communitySubs.planMonthly')
  const method = METHOD_META[sub.paymentMethod] ?? METHOD_META.cash
  const methodLabel = sub.paymentMethod === 'fib' ? t('communitySubs.methodFib') : t('communitySubs.methodCash')
  const MethodIcon = method.Icon
  const dollars = (sub.priceCents / 100).toFixed(0)
  const navigate = useNavigate()

  return (
    <div
      onClick={(e) => {
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
        if (rejecting) return
        navigate(`/community-subscriptions/${sub.id}`)
      }}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (rejecting) return
        if (e.key === 'Enter' || e.key === ' ')
          navigate(`/community-subscriptions/${sub.id}`)
      }}
      className={`cursor-pointer rounded-xl bg-white/[0.02] border border-white/5 p-4 ring-1 hover:ring-cyan-500/30 transition-shadow ${sev.ring}`}
    >
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold shrink-0">
          {(sub.userName || sub.userEmail || '?').charAt(0).toUpperCase()}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-semibold text-white truncate">
                {sub.userName || sub.userEmail}
              </p>
              <p className="text-xs text-slate-500 truncate">{sub.userEmail}</p>
            </div>
            <span
              className={`px-1.5 py-0.5 rounded-md text-[10px] font-bold ring-1 uppercase ${sev.bg} ${sev.text} ${sev.ring}`}
            >
              {sub.status}
            </span>
          </div>
          <div className="mt-2 flex items-center gap-2 text-sm">
            <UsersIcon className="w-3.5 h-3.5 text-cyan-300" />
            <span className="text-slate-300 truncate">
              {t('communitySubs.joining')}{' '}
              <span className="text-white font-semibold">
                {sub.communityName || sub.communityId}
              </span>
            </span>
          </div>
        </div>
      </div>

      <div className="mt-3 grid grid-cols-2 gap-2">
        <div className="rounded-lg bg-white/[0.03] p-2.5 ring-1 ring-white/5">
          <p className="text-[10px] uppercase tracking-wider text-slate-500">{t('communitySubs.plan')}</p>
          <div className="flex items-center gap-2 mt-1">
            <span
              className={`px-1.5 py-0.5 rounded-md text-[10px] font-bold ring-1 ${planMeta.color}`}
            >
              {planLabel}
            </span>
            <span className="font-bold text-white">
              {sub.currency.toUpperCase()} {dollars}
            </span>
          </div>
        </div>
        <div className="rounded-lg bg-white/[0.03] p-2.5 ring-1 ring-white/5">
          <p className="text-[10px] uppercase tracking-wider text-slate-500">{t('communitySubs.payment')}</p>
          <div className="flex items-center gap-2 mt-1 text-sm text-white">
            <MethodIcon className="w-3.5 h-3.5 text-cyan-400" />
            {methodLabel}
          </div>
        </div>
      </div>

      {sub.receiptUrl && (
        <a
          href={absoluteUrl(sub.receiptUrl)}
          target="_blank"
          rel="noreferrer"
          onClick={(e) => e.stopPropagation()}
          className="mt-2 inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-cyan-500/15 ring-1 ring-cyan-500/30 text-[11px] text-cyan-300 hover:bg-cyan-500/25"
        >
          <ImageIcon className="w-3 h-3" /> {t('communitySubs.viewReceipt')}
        </a>
      )}
      {sub.paymentRef && (
        <div className="mt-2 flex items-center gap-2 text-xs text-slate-400">
          <Hash className="w-3 h-3" />
          <span className="font-mono truncate">{sub.paymentRef}</span>
        </div>
      )}
      {sub.userNote && (
        <div className="mt-2 flex items-start gap-2 text-xs text-slate-400">
          <MessageSquare className="w-3 h-3 mt-0.5 shrink-0" />
          <span className="italic">"{sub.userNote}"</span>
        </div>
      )}
      {sub.rejectionReason && (
        <div className="mt-2 p-2 rounded-md bg-rose-500/10 ring-1 ring-rose-500/20 text-xs text-rose-300">
          <span className="font-semibold">{t('communitySubs.reason')}</span> {sub.rejectionReason}
        </div>
      )}

      <div className="mt-3 flex items-center justify-between text-[11px] text-slate-500">
        <span>{relativeTime(new Date(sub.createdAt), t, locale)}</span>
        {sub.expiresAt && sub.status === 'active' && (
          <span>{t('communitySubs.expires', { date: fmtDate(sub.expiresAt, locale) })}</span>
        )}
      </div>

      {showActions && (
        <div onClick={(e) => e.stopPropagation()}>
          {rejecting ? (
            <div className="mt-3 space-y-2">
              <label className="text-[10px] uppercase tracking-wider text-slate-400">
                {t('communitySubs.rejectionReasonOptional')}
              </label>
              <textarea
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                rows={2}
                placeholder={t('communitySubs.rejectPlaceholderList')}
                className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 resize-y"
              />
              <div className="flex items-center justify-end gap-2">
                <button
                  onClick={onCancelReject}
                  className="px-3 py-1.5 rounded-md text-sm text-slate-300 hover:bg-white/5"
                >
                  {t('common.cancel')}
                </button>
                <button
                  disabled={acting}
                  onClick={onConfirmReject}
                  className="inline-flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-bold bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
                >
                  {acting ? <Loader2 className="w-4 h-4 animate-spin" /> : <X className="w-4 h-4" />}
                  {t('communitySubs.confirmReject')}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex items-center gap-2 mt-3">
              <button
                disabled={acting}
                onClick={onAccept}
                className="flex-1 inline-flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-400 ring-1 ring-emerald-500/20 text-sm font-semibold transition-colors disabled:opacity-50"
              >
                {acting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
                {t('communitySubs.acceptPayment')}
              </button>
              <button
                disabled={acting}
                onClick={onStartReject}
                className="flex-1 inline-flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-rose-500/15 hover:bg-rose-500/25 text-rose-400 ring-1 ring-rose-500/20 text-sm font-semibold transition-colors disabled:opacity-50"
              >
                <X className="w-4 h-4" /> {t('communitySubs.reject')}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function relativeTime(
  date: Date,
  t: (key: any, vars?: Record<string, string | number>) => string,
  locale: Locale,
) {
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000))
  if (seconds < 60) return t('communitySubs.secondsAgo', { n: seconds })
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return t('communitySubs.minutesAgo', { n: minutes })
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return t('communitySubs.hoursAgo', { n: hours })
  const days = Math.floor(hours / 24)
  if (days < 7) return t('communitySubs.daysAgo', { n: days })
  return fmtDate(date, locale)
}
