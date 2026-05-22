import { useEffect, useMemo, useState } from 'react'
import {
  Wallet,
  Filter,
  CheckCircle2,
  XCircle,
  Loader2,
  AlertTriangle,
  Banknote,
  Building2,
  Smartphone,
  CreditCard,
  Calendar,
  User as UserIcon,
  Copy,
} from 'lucide-react'
import { api, ApiError } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate, fmtDateTime } from '../i18n/datefmt'

// Wire shape mirrors backend repositories.Payout (mig 0042). Joined
// fields (userEmail / userName / processorEmail) are populated by the
// admin list endpoint; user-facing reads leave them empty.
type Payout = {
  id: number
  userId: number
  expertId: string
  amountCents: number
  currency: string
  method: 'bank' | 'fib' | 'paypal' | 'other'
  paymentDetails: Record<string, unknown>
  status: 'pending' | 'paid' | 'rejected' | 'cancelled'
  adminNote?: string
  processedAt?: string
  requestedAt: string
  userEmail?: string
  userName?: string
  processorEmail?: string
}

type ListResponse = {
  payouts: Payout[]
  total: number
  limit: number
  offset: number
}

const STATUS_FILTERS = [
  { value: 'pending', tkey: 'payouts.filter.pending' },
  { value: '', tkey: 'payouts.filter.all' },
  { value: 'paid', tkey: 'payouts.filter.paid' },
  { value: 'rejected', tkey: 'payouts.filter.rejected' },
  { value: 'cancelled', tkey: 'payouts.filter.cancelled' },
] as const

const STATUS_STYLES: Record<Payout['status'], string> = {
  pending: 'text-amber-300 bg-amber-500/10 ring-1 ring-amber-500/30',
  paid: 'text-emerald-300 bg-emerald-500/10 ring-1 ring-emerald-500/30',
  rejected: 'text-rose-300 bg-rose-500/10 ring-1 ring-rose-500/30',
  cancelled: 'text-slate-300 bg-slate-500/10 ring-1 ring-slate-500/30',
}

const STATUS_TKEY: Record<Payout['status'], string> = {
  pending: 'payouts.status.pending',
  paid: 'payouts.status.paid',
  rejected: 'payouts.status.rejected',
  cancelled: 'payouts.status.cancelled',
}

const METHOD_TKEY: Record<Payout['method'], string> = {
  bank: 'payouts.method.bank',
  fib: 'payouts.method.fib',
  paypal: 'payouts.method.paypal',
  other: 'payouts.method.other',
}

const METHOD_ICON: Record<Payout['method'], React.ElementType> = {
  bank: Building2,
  fib: Smartphone,
  paypal: CreditCard,
  other: Banknote,
}

function moneyOf(cents: number, currency: string): string {
  const dollars = cents / 100
  const symbol = currency.toLowerCase() === 'usd' ? '$' : `${currency.toUpperCase()} `
  return `${symbol}${dollars.toLocaleString('en-US', {
    minimumFractionDigits: dollars === Math.floor(dollars) ? 0 : 2,
    maximumFractionDigits: 2,
  })}`
}

export default function Payouts() {
  const { t, locale } = useI18n()
  const [statusFilter, setStatusFilter] = useState<string>('pending')
  const [payouts, setPayouts] = useState<Payout[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<Payout | null>(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const qs = new URLSearchParams({
        limit: '50',
        ...(statusFilter ? { status: statusFilter } : {}),
      }).toString()
      const res = await api.get<ListResponse>(`/admin/payouts?${qs}`)
      setPayouts(res.payouts ?? [])
      setTotal(res.total ?? 0)
      // Keep the selection in sync — if the previously-selected row got
      // resolved in another tab and we just refreshed, swap in the
      // fresh copy or clear when it's filtered out.
      if (selected) {
        const fresh = (res.payouts ?? []).find((p) => p.id === selected.id)
        setSelected(fresh ?? null)
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('payouts.loadError'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [statusFilter])

  const pendingTotal = useMemo(
    () =>
      payouts
        .filter((p) => p.status === 'pending')
        .reduce((s, p) => s + p.amountCents, 0),
    [payouts],
  )
  const pendingCount = payouts.filter((p) => p.status === 'pending').length
  const currency = payouts[0]?.currency ?? 'usd'

  async function resolve(
    payout: Payout,
    status: 'paid' | 'rejected',
    note: string,
  ) {
    try {
      const updated = await api.post<Payout>(
        `/admin/payouts/${payout.id}/resolve`,
        { status, note },
      )
      setPayouts((prev) =>
        prev.map((p) => (p.id === payout.id ? updated : p)),
      )
      setSelected(updated)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('payouts.updateError'))
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            {t('payouts.title')}
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            {t('payouts.subtitle')}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Filter className="w-4 h-4 text-slate-500" />
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            className="input w-44"
          >
            {STATUS_FILTERS.map((f) => (
              <option key={f.value} value={f.value}>
                {t(f.tkey)}
              </option>
            ))}
          </select>
        </div>
      </div>

      {error && (
        <div className="rounded-lg p-3 text-sm bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300 flex items-start gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
          <div>{error}</div>
        </div>
      )}

      {/* Headline tiles — only render when pending rows exist so the
          "X pending, total $Y" framing isn't shown for all-resolved
          views (where it'd just read $0.00). */}
      {pendingCount > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 sm:gap-4">
          <Tile label={t('payouts.tile.pendingRequests')} value={pendingCount.toString()} />
          <Tile
            label={t('payouts.tile.pendingTotal')}
            value={moneyOf(pendingTotal, currency)}
            highlight
          />
          <Tile label={t('payouts.tile.totalInView')} value={total.toString()} />
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 lg:gap-5">
        {/* Queue */}
        <div className="lg:col-span-2 card overflow-hidden">
          <div className="px-4 sm:px-5 py-3 sm:py-4 border-b border-white/5 flex items-center justify-between">
            <h3 className="font-semibold text-white">
              {t('payouts.queue')}
              <span className="text-xs text-slate-500 ms-1 font-normal">
                {t('payouts.queueMeta', { total, pending: pendingCount })}
              </span>
            </h3>
            {loading && (
              <Loader2 className="w-4 h-4 animate-spin text-slate-500" />
            )}
          </div>
          {payouts.length === 0 && !loading ? (
            <div className="p-8 text-center text-slate-500 text-sm">
              <Wallet className="w-8 h-8 mx-auto mb-2 opacity-40" />
              {t('payouts.empty')}
            </div>
          ) : (
            <ul className="divide-y divide-white/5">
              {payouts.map((p) => {
                const Icon = METHOD_ICON[p.method] ?? Banknote
                return (
                  <li
                    key={p.id}
                    onClick={() => setSelected(p)}
                    className={`px-4 sm:px-5 py-3 sm:py-4 cursor-pointer hover:bg-white/[0.03] transition-colors ${
                      selected?.id === p.id ? 'bg-white/[0.04]' : ''
                    }`}
                  >
                    <div className="flex items-start gap-3">
                      <div className="w-9 h-9 rounded-lg bg-white/5 flex items-center justify-center shrink-0">
                        <Icon className="w-4 h-4 text-emerald-400" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="font-mono font-bold text-white">
                            {moneyOf(p.amountCents, p.currency)}
                          </p>
                          <span
                            className={`text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded ${STATUS_STYLES[p.status]}`}
                          >
                            {t(STATUS_TKEY[p.status])}
                          </span>
                          <span className="text-[11px] text-slate-500">
                            {t('payouts.via', { method: METHOD_TKEY[p.method] ? t(METHOD_TKEY[p.method]) : p.method })}
                          </span>
                        </div>
                        <p className="text-xs text-slate-400 mt-0.5 truncate">
                          {p.userName || p.userEmail || t('payouts.userFallback', { id: p.userId })}
                        </p>
                      </div>
                      <span className="text-[11px] text-slate-500 shrink-0">
                        {fmtDate(p.requestedAt, locale)}
                      </span>
                    </div>
                  </li>
                )
              })}
            </ul>
          )}
        </div>

        {/* Detail / resolution panel */}
        <div className="lg:col-span-1 card p-4 sm:p-5 h-fit sticky top-4">
          {!selected ? (
            <div className="text-sm text-slate-500 text-center py-8">
              {t('payouts.pickPrompt')}
            </div>
          ) : (
            <ResolutionPanel payout={selected} onResolve={resolve} />
          )}
        </div>
      </div>
    </div>
  )
}

function Tile({
  label,
  value,
  highlight,
}: {
  label: string
  value: string
  highlight?: boolean
}) {
  return (
    <div
      className={`card p-3 sm:p-4 ${
        highlight ? 'ring-1 ring-cyan-500/30' : ''
      }`}
    >
      <p className="text-[10px] sm:text-[11px] uppercase tracking-wider text-slate-500">
        {label}
      </p>
      <p
        className={`text-lg sm:text-xl font-bold mt-1 ${
          highlight ? 'text-cyan-300' : 'text-white'
        }`}
      >
        {value}
      </p>
    </div>
  )
}

function ResolutionPanel({
  payout,
  onResolve,
}: {
  payout: Payout
  onResolve: (
    p: Payout,
    status: 'paid' | 'rejected',
    note: string,
  ) => Promise<void>
}) {
  const { t, locale } = useI18n()
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState<string | null>(null)

  async function fire(status: 'paid' | 'rejected') {
    setBusy(status)
    await onResolve(payout, status, note)
    setBusy(null)
  }

  const isPending = payout.status === 'pending'
  const Icon = METHOD_ICON[payout.method] ?? Banknote

  // The free-form payment details are stored as JSONB. Today the
  // mobile client packs everything into a `note` key — render that
  // first when present, then any other keys for forward-compatibility.
  const detailEntries = Object.entries(payout.paymentDetails ?? {}).filter(
    ([, v]) => v !== '' && v != null,
  )

  function copyDetails() {
    const text = detailEntries
      .map(([k, v]) => `${k}: ${typeof v === 'string' ? v : JSON.stringify(v)}`)
      .join('\n')
    navigator.clipboard.writeText(text).catch(() => {})
  }

  return (
    <div className="space-y-4">
      <div>
        <span
          className={`text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded ${STATUS_STYLES[payout.status]}`}
        >
          {t(STATUS_TKEY[payout.status])}
        </span>
        <h3 className="font-mono font-bold text-white text-2xl mt-2">
          {moneyOf(payout.amountCents, payout.currency)}
        </h3>
        <p className="text-xs text-slate-500 mt-1">
          {t('payouts.requested', { date: fmtDateTime(payout.requestedAt, locale) })}
        </p>
      </div>

      <div className="space-y-2 text-sm">
        <Row icon={UserIcon} label={t('payouts.row.requester')}>
          <span className="text-slate-300">
            {payout.userName || '—'}{' '}
            <span className="text-slate-500">
              ({payout.userEmail || t('payouts.userFallback', { id: payout.userId })})
            </span>
          </span>
        </Row>
        <Row icon={Icon} label={t('payouts.row.method')}>
          <span className="text-slate-300">
            {METHOD_TKEY[payout.method] ? t(METHOD_TKEY[payout.method]) : payout.method}
          </span>
        </Row>
        {detailEntries.length > 0 && (
          <div className="rounded-md bg-white/5 ring-1 ring-white/10 p-3">
            <div className="flex items-center justify-between mb-2">
              <p className="text-[10px] uppercase tracking-wider text-slate-500">
                {t('payouts.paymentDetails')}
              </p>
              <button
                onClick={copyDetails}
                className="text-[11px] text-cyan-300 hover:text-cyan-200 flex items-center gap-1"
              >
                <Copy className="w-3 h-3" />
                {t('payouts.copy')}
              </button>
            </div>
            <dl className="space-y-1.5 text-xs">
              {detailEntries.map(([k, v]) => (
                <div key={k}>
                  <dt className="text-slate-500">{k}</dt>
                  <dd className="text-slate-200 break-words whitespace-pre-wrap font-mono text-[11px]">
                    {typeof v === 'string' ? v : JSON.stringify(v)}
                  </dd>
                </div>
              ))}
            </dl>
          </div>
        )}
        {payout.processedAt && (
          <>
            <Row icon={Calendar} label={t('payouts.row.processed')}>
              <span className="text-slate-300">
                {fmtDateTime(payout.processedAt, locale)}
              </span>
            </Row>
            {payout.processorEmail && (
              <Row icon={UserIcon} label={t('payouts.row.by')}>
                <span className="text-slate-300">{payout.processorEmail}</span>
              </Row>
            )}
            {payout.adminNote && (
              <Row icon={AlertTriangle} label={t('payouts.row.note')}>
                <span className="text-slate-300 italic">{payout.adminNote}</span>
              </Row>
            )}
          </>
        )}
      </div>

      {isPending && (
        <div className="space-y-3 pt-2 border-t border-white/5">
          <label className="block text-xs uppercase tracking-wider text-slate-500">
            {t('payouts.resolutionNote')}
          </label>
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={3}
            maxLength={2000}
            className="input resize-none"
            placeholder={t('payouts.resolutionPlaceholder')}
          />
          <div className="grid grid-cols-1 gap-2">
            <button
              onClick={() => fire('paid')}
              disabled={!!busy}
              className="btn-primary justify-center disabled:opacity-50"
            >
              {busy === 'paid' ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <CheckCircle2 className="w-4 h-4" />
              )}
              {t('payouts.markPaid')}
            </button>
            <button
              onClick={() => fire('rejected')}
              disabled={!!busy}
              className="btn-secondary justify-center disabled:opacity-50"
            >
              {busy === 'rejected' ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <XCircle className="w-4 h-4" />
              )}
              {t('payouts.reject')}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

function Row({
  icon: Icon,
  label,
  children,
}: {
  icon: React.ElementType
  label: string
  children: React.ReactNode
}) {
  return (
    <div className="flex items-start gap-2.5">
      <Icon className="w-3.5 h-3.5 text-slate-500 mt-1 shrink-0" />
      <div className="flex flex-col gap-0.5 flex-1 min-w-0">
        <span className="text-[10px] uppercase tracking-wider text-slate-500">
          {label}
        </span>
        <div>{children}</div>
      </div>
    </div>
  )
}
