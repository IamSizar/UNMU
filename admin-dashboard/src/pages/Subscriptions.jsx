import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Check, X, AlertCircle, Loader2, Inbox, Crown,
  Banknote, Building2, MessageSquare, RefreshCw, Hash,
  Search, Image as ImageIcon, TrendingUp,
} from 'lucide-react'
import { api } from '../api/client'
import { useRealtime } from '../api/realtime'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'

const TABS = [
  { id: 'pending',   tkey: 'subscriptions.tab.pending',   live: true },
  { id: 'active',    tkey: 'subscriptions.tab.active' },
  { id: 'rejected',  tkey: 'subscriptions.tab.rejected' },
  { id: 'cancelled', tkey: 'subscriptions.tab.cancelled' },
  { id: 'expired',   tkey: 'subscriptions.tab.expired' },
]

const STATUS_STYLES = {
  pending:   { ring: 'ring-amber-500/30',   bg: 'bg-amber-500/12',   text: 'text-amber-300' },
  active:    { ring: 'ring-emerald-500/30', bg: 'bg-emerald-500/12', text: 'text-emerald-300' },
  rejected:  { ring: 'ring-rose-500/30',    bg: 'bg-rose-500/15',    text: 'text-rose-300' },
  cancelled: { ring: 'ring-slate-500/30',   bg: 'bg-slate-500/15',   text: 'text-slate-300' },
  expired:   { ring: 'ring-slate-500/30',   bg: 'bg-slate-500/15',   text: 'text-slate-300' },
}

const PLAN_BADGE = {
  monthly: { tkey: 'subscriptions.plan.monthly', color: 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30' },
  yearly:  { tkey: 'subscriptions.plan.yearly', color: 'bg-gold-500/15 text-gold-400 ring-gold-500/30' },
}

const METHOD_META = {
  cash: { icon: Banknote,    tkey: 'subscriptions.method.cash' },
  fib:  { icon: Building2,   tkey: 'subscriptions.method.fib' },
}

const STATUS_TKEY = {
  pending:   'subscriptions.status.pending',
  active:    'subscriptions.status.active',
  rejected:  'subscriptions.status.rejected',
  cancelled: 'subscriptions.status.cancelled',
  expired:   'subscriptions.status.expired',
}

const PAGE_SIZE = 25

export default function Subscriptions() {
  const { t } = useI18n()
  const [tab, setTab] = useState('pending')
  const [query, setQuery] = useState('')
  const [methodFilter, setMethodFilter] = useState('') // '' | 'cash' | 'fib'
  const [items, setItems] = useState([])
  const [hasMore, setHasMore] = useState(false)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [acting, setActing] = useState(null) // id currently being accepted/rejected
  const [pendingCount, setPendingCount] = useState(null)
  const [totals, setTotals] = useState(null)
  // Inline reject form: id of the row whose Reject button is expanded.
  const [rejectingId, setRejectingId] = useState(null)
  const [rejectReason, setRejectReason] = useState('')
  // Debounce timer for search input.
  const searchTimer = useRef(null)

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
      const res = await api.get(`/admin/subscriptions?${params}`)
      const next = res.subscriptions ?? []
      setHasMore(next.length === PAGE_SIZE)
      if (reset) {
        setItems(next)
      } else {
        setItems((curr) => [...curr, ...next])
      }
    } catch (e) {
      setError(e?.message ?? t('subscriptions.loadFailed'))
    } finally {
      setLoading(false)
    }
  }

  async function loadPendingCount() {
    try {
      const res = await api.get('/admin/subscriptions/pending-count')
      setPendingCount(res.count ?? 0)
    } catch {
      setPendingCount(0)
    }
  }

  async function loadTotals() {
    try {
      const res = await api.get('/admin/subscriptions/totals')
      setTotals(res ?? null)
    } catch {
      setTotals(null)
    }
  }

  useEffect(() => { load({ reset: true }) /* eslint-disable-next-line */ }, [tab, methodFilter])
  useEffect(() => {
    if (searchTimer.current) clearTimeout(searchTimer.current)
    searchTimer.current = setTimeout(() => load({ reset: true }), 250)
    return () => { if (searchTimer.current) clearTimeout(searchTimer.current) }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query])
  useEffect(() => {
    loadPendingCount()
    loadTotals()
  }, [])

  // Realtime — refresh on every subscription state transition.
  useRealtime(
    ['subscription_submitted', 'subscription_active', 'subscription_rejected',
     'subscription_cancelled', 'subscription_expired'],
    () => {
      load({ reset: true })
      loadPendingCount()
      loadTotals()
    },
  )

  async function accept(id) {
    setActing(id)
    try {
      await api.post(`/admin/subscriptions/${id}/accept`)
      setItems((curr) => curr.filter((s) => s.id !== id))
      loadPendingCount()
      loadTotals()
    } catch (e) {
      alert(e?.message ?? t('subscriptions.acceptFailed'))
    } finally {
      setActing(null)
    }
  }

  async function confirmReject(id) {
    setActing(id)
    try {
      await api.post(`/admin/subscriptions/${id}/reject`, { reason: rejectReason.trim() })
      setItems((curr) => curr.filter((s) => s.id !== id))
      setRejectingId(null)
      setRejectReason('')
      loadPendingCount()
    } catch (e) {
      alert(e?.message ?? t('subscriptions.rejectFailed'))
    } finally {
      setActing(null)
    }
  }

  function startReject(id) {
    setRejectingId(id)
    setRejectReason('')
  }

  function cancelReject() {
    setRejectingId(null)
    setRejectReason('')
  }

  const headline = useMemo(() => {
    const total = items.length
    const statusWord = t(STATUS_TKEY[tab] ?? STATUS_TKEY.pending)
    return t(
      total === 1 ? 'subscriptions.headline' : 'subscriptions.headlinePlural',
      { count: total, status: statusWord },
    )
  }, [items.length, tab, t])

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            {t('subscriptions.title')}
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            {pendingCount !== null && pendingCount > 0 ? (
              <>
                <span className="text-amber-400 font-semibold">{t('subscriptions.pendingHighlight', { count: pendingCount })}</span> · {headline}
              </>
            ) : (
              headline
            )}
            {' '}· {t('subscriptions.subtitle')}
          </p>
        </div>
        <button onClick={() => { load({ reset: true }); loadTotals() }} className="btn-secondary">
          <RefreshCw className="w-4 h-4" /> {t('common.refresh')}
        </button>
      </div>

      {/* Totals strip */}
      {totals && (
        <div className="grid grid-cols-3 gap-3">
          <TotalsTile
            label={t('subscriptions.totals.active')}
            value={String(totals.activeCount ?? 0)}
            tone="emerald"
            icon={<Check className="w-3.5 h-3.5" />}
          />
          <TotalsTile
            label={t('subscriptions.totals.pending')}
            value={String(totals.pendingCount ?? 0)}
            tone="amber"
            icon={<AlertCircle className="w-3.5 h-3.5" />}
          />
          <TotalsTile
            label={t('subscriptions.totals.revenue')}
            value={formatMoney(totals.activeRevenueCents ?? 0, totals.currency ?? 'usd')}
            tone="cyan"
            icon={<TrendingUp className="w-3.5 h-3.5" />}
          />
        </div>
      )}

      {/* Tabs + search + payment-method filter */}
      <div className="card p-3 space-y-3">
        <div className="flex items-center gap-2 overflow-x-auto whitespace-nowrap -mx-1 px-1 pb-1">
          {TABS.map((tabItem) => (
            <button
              key={tabItem.id}
              onClick={() => setTab(tabItem.id)}
              className={`shrink-0 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                tab === tabItem.id
                  ? 'bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/20'
                  : 'text-slate-400 hover:bg-white/5'
              }`}
            >
              {t(tabItem.tkey)}
              {tabItem.id === 'pending' && pendingCount !== null && pendingCount > 0 && (
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
              placeholder={t('subscriptions.searchPlaceholder')}
              className="input ps-9 w-full"
            />
          </div>
          <div className="flex items-center gap-1.5">
            <span className="text-[10px] uppercase tracking-wider text-slate-500 me-1">{t('subscriptions.methodLabel')}</span>
            {[
              { id: '', tkey: 'subscriptions.method.all' },
              { id: 'cash', tkey: 'subscriptions.method.cash' },
              { id: 'fib', tkey: 'subscriptions.method.fib' },
            ].map((m) => (
              <button
                key={m.id || 'all'}
                onClick={() => setMethodFilter(m.id)}
                className={`px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                  methodFilter === m.id
                    ? 'bg-white/10 text-white ring-1 ring-white/20'
                    : 'text-slate-500 hover:bg-white/5'
                }`}
              >
                {t(m.tkey)}
              </button>
            ))}
          </div>
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

        {loading && items.length === 0 ? (
          <div className="flex items-center justify-center py-16 text-slate-400">
            <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('common.loading')}
          </div>
        ) : items.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-slate-500">
            <Inbox className="w-10 h-10 mb-3 opacity-50" />
            <p className="text-sm">
              {query.trim()
                ? t('subscriptions.emptySearch', {
                    status: t(STATUS_TKEY[tab] ?? STATUS_TKEY.pending),
                    query: query.trim(),
                  })
                : t('subscriptions.empty', {
                    status: t(STATUS_TKEY[tab] ?? STATUS_TKEY.pending),
                  })}
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
                  className="btn-secondary"
                >
                  {t('subscriptions.loadMore')}
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}

function TotalsTile({ label, value, tone, icon }) {
  const TONE = {
    emerald: 'bg-emerald-500/10 ring-emerald-500/30 text-emerald-300',
    amber:   'bg-amber-500/10   ring-amber-500/30   text-amber-300',
    cyan:    'bg-cyan-500/10    ring-cyan-500/30    text-cyan-300',
  }
  const cls = TONE[tone] ?? TONE.cyan
  return (
    <div className={`rounded-xl px-3 py-2.5 ring-1 ${cls}`}>
      <div className="flex items-center gap-1.5 text-[10px] uppercase tracking-wider opacity-80">
        {icon}
        {label}
      </div>
      <p className="text-lg font-bold mt-0.5 truncate">{value}</p>
    </div>
  )
}

function formatMoney(cents, currency) {
  const dollars = cents / 100
  const sym = (currency || '').toLowerCase() === 'usd' ? '$' : `${currency.toUpperCase()} `
  return `${sym}${dollars.toFixed(dollars % 1 === 0 ? 0 : 2)}`
}

// Resolve `/uploads/...` against the API origin so receipt images load.
// Uses VITE_API_BASE_URL (matches api/client.ts). An earlier version
// read VITE_API_BASE (no _URL) which was never wired into .env.local —
// the absoluteUrl returned just the bare path, the browser resolved it
// against the Vite dev server, and images rendered as broken icons.
function absoluteUrl(path) {
  if (!path) return ''
  if (path.startsWith('http')) return path
  const base = import.meta.env?.VITE_API_BASE_URL ?? ''
  const origin = base.replace(/\/api\/?$/, '')
  return `${origin}${path}`
}

function SubCard({
  sub, showActions,
  acting, rejecting, rejectReason, setRejectReason,
  onAccept, onStartReject, onCancelReject, onConfirmReject,
}) {
  const { t, locale } = useI18n()
  const sev = STATUS_STYLES[sub.status] ?? STATUS_STYLES.pending
  const planMeta = PLAN_BADGE[sub.plan] ?? PLAN_BADGE.monthly
  const method = METHOD_META[sub.paymentMethod] ?? METHOD_META.cash
  const MethodIcon = method.icon
  const dollars = (sub.priceCents / 100).toFixed(0)
  // Step-22 — whole card is clickable → drill into the detail page.
  const navigate = useNavigate()
  function onCardClick(e) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    if (rejecting) return
    navigate(`/subscriptions/${sub.id}`)
  }

  return (
    <div
      onClick={onCardClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (rejecting) return
        if (e.key === 'Enter' || e.key === ' ') navigate(`/subscriptions/${sub.id}`)
      }}
      className={`cursor-pointer rounded-xl bg-white/[0.02] border border-white/5 p-4 ring-1 hover:ring-cyan-500/30 transition-shadow ${sev.ring}`}>
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold shrink-0">
          {(sub.userName || sub.userEmail || '?').charAt(0).toUpperCase()}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-semibold text-white truncate">{sub.userName || sub.userEmail}</p>
              <p className="text-xs text-slate-500 truncate">{sub.userEmail}</p>
            </div>
            <span className={`chip ${sev.bg} ${sev.text} ring-1 ${sev.ring} uppercase`}>
              {t(STATUS_TKEY[sub.status] ?? STATUS_TKEY.pending)}
            </span>
          </div>
          <div className="mt-2 flex items-center gap-2 text-sm">
            <Crown className="w-3.5 h-3.5 text-gold-400" />
            <span className="text-slate-300 truncate">
              {t('subscriptions.subscribingTo')} <span className="text-white font-semibold">{sub.expertName || sub.expertId}</span>
            </span>
          </div>
        </div>
      </div>

      <div className="mt-3 grid grid-cols-2 gap-2">
        <div className="rounded-lg bg-white/[0.03] p-2.5 ring-1 ring-white/5">
          <p className="text-[10px] uppercase tracking-wider text-slate-500">{t('subscriptions.field.plan')}</p>
          <div className="flex items-center gap-2 mt-1">
            <span className={`chip text-[10px] ring-1 ${planMeta.color}`}>{t(planMeta.tkey)}</span>
            <span className="font-bold text-white">${dollars}</span>
          </div>
        </div>
        <div className="rounded-lg bg-white/[0.03] p-2.5 ring-1 ring-white/5">
          <p className="text-[10px] uppercase tracking-wider text-slate-500">{t('subscriptions.field.payment')}</p>
          <div className="flex items-center gap-2 mt-1 text-sm text-white">
            <MethodIcon className="w-3.5 h-3.5 text-cyan-400" />
            {t(method.tkey)}
          </div>
        </div>
      </div>

      {/* Receipt image preview (cash payments) */}
      {sub.receiptUrl && (
        <a
          href={absoluteUrl(sub.receiptUrl)}
          target="_blank"
          rel="noreferrer"
          onClick={(e) => e.stopPropagation()}
          className="mt-2 inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-cyan-500/15 ring-1 ring-cyan-500/30 text-[11px] text-cyan-300 hover:bg-cyan-500/25"
        >
          <ImageIcon className="w-3 h-3" /> {t('subscriptions.viewReceipt')}
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
          <span className="font-semibold">{t('subscriptions.reasonLabel')}</span> {sub.rejectionReason}
        </div>
      )}

      <div className="mt-3 flex items-center justify-between text-[11px] text-slate-500">
        <span>{relativeTime(new Date(sub.createdAt), t, locale)}</span>
        {sub.expiresAt && sub.status === 'active' && (
          <span>{t('subscriptions.expires', { date: fmtDate(sub.expiresAt, locale) })}</span>
        )}
      </div>

      {showActions && (
        <div onClick={(e) => e.stopPropagation()}>
          {rejecting ? (
            <div className="mt-3 space-y-2">
              <label className="text-[10px] uppercase tracking-wider text-slate-400">
                {t('subscriptions.rejectReasonLabel')}
              </label>
              <textarea
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                rows={2}
                placeholder={t('subscriptions.rejectReasonPlaceholder')}
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
                  {t('subscriptions.confirmReject')}
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
                {t('subscriptions.acceptPayment')}
              </button>
              <button
                disabled={acting}
                onClick={onStartReject}
                className="flex-1 inline-flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-rose-500/15 hover:bg-rose-500/25 text-rose-400 ring-1 ring-rose-500/20 text-sm font-semibold transition-colors disabled:opacity-50"
              >
                <X className="w-4 h-4" /> {t('subscriptions.reject')}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

function relativeTime(date, t, locale) {
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000))
  if (seconds < 60) return t('subscriptions.relative.seconds', { n: seconds })
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return t('subscriptions.relative.minutes', { n: minutes })
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return t('subscriptions.relative.hours', { n: hours })
  const days = Math.floor(hours / 24)
  if (days < 7) return t('subscriptions.relative.days', { n: days })
  return fmtDate(date, locale)
}
