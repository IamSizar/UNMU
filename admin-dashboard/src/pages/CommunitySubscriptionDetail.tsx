import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  RefreshCw,
  Check,
  X,
  Banknote,
  Building2,
  Hash,
  MessageSquare,
  Calendar,
  CreditCard,
  AlertOctagon,
  AlertTriangle,
  Users as UsersIcon,
  Image as ImageIcon,
  Receipt,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDateTime } from '../i18n/datefmt'

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
  paymentMethod: 'cash' | 'fib' | string
  paymentRef?: string
  receiptUrl?: string | null
  userNote?: string
  rejectionReason?: string
  createdAt: string
  acceptedAt?: string | null
  acceptedBy?: number | null
  reviewerEmail?: string
  rejectedAt?: string | null
  cancelledAt?: string | null
  expiresAt?: string | null
}

// VITE_API_BASE_URL matches api/client.ts. The shorter VITE_API_BASE
// was a typo — never set in .env.local — so /uploads/... images came
// back as broken icons because the Vite dev server doesn't serve them.
function absoluteUrl(path?: string | null) {
  if (!path) return ''
  if (path.startsWith('http')) return path
  const base = (import.meta as any).env?.VITE_API_BASE_URL ?? ''
  const origin = base.replace(/\/api\/?$/, '')
  return `${origin}${path}`
}

const STATUS_TINT: Record<string, string> = {
  pending: 'bg-amber-500/15 text-amber-300 ring-amber-500/30',
  active: 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30',
  rejected: 'bg-rose-500/15 text-rose-300 ring-rose-500/30',
  cancelled: 'bg-slate-500/15 text-slate-300 ring-slate-500/30',
  expired: 'bg-slate-500/15 text-slate-300 ring-slate-500/30',
}

/**
 * CommunitySubscriptionDetail — `/community-subscriptions/:id`.
 *
 * Drill-in from the Community Subscriptions list. Shows the full
 * payment proof + community context + Accept / Reject controls
 * with a textarea for the rejection reason. Accepting flips the row
 * to active AND inserts the community_members row in the same
 * backend transaction.
 */
export default function CommunitySubscriptionDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { t, locale } = useI18n()
  const [sub, setSub] = useState<CommunitySub | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [actionBusy, setActionBusy] = useState<string | null>(null)
  const [showRejectForm, setShowRejectForm] = useState(false)
  const [rejectReason, setRejectReason] = useState('')

  async function load() {
    if (!id) return
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<CommunitySub>(`/admin/community-subscriptions/${id}`)
      setSub(res)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id])

  async function accept() {
    if (!sub) return
    setActionBusy('accept')
    try {
      await api.post(`/admin/community-subscriptions/${sub.id}/accept`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  async function reject() {
    if (!sub) return
    setActionBusy('reject')
    try {
      await api.post(`/admin/community-subscriptions/${sub.id}/reject`, {
        reason: rejectReason.trim(),
      })
      setShowRejectForm(false)
      setRejectReason('')
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  if (loading && !sub) return <p className="text-slate-500">{t('common.loading')}</p>
  if (error && !sub) {
    return (
      <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
        <AlertOctagon className="w-4 h-4" /> {error}
      </div>
    )
  }
  if (!sub) {
    return (
      <div>
        <Link to="/community-subscriptions" className="text-cyan-300 text-sm">
          {t('communitySubs.backToSubs')}
        </Link>
        <p className="text-slate-500 mt-3">{t('communitySubs.notFound')}</p>
      </div>
    )
  }

  const dollars = (sub.priceCents / 100).toFixed(0)
  const tint = STATUS_TINT[sub.status] ?? STATUS_TINT.pending
  const isPending = sub.status === 'pending'

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => navigate('/community-subscriptions')}
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('common.back')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </button>
        <p className="text-xs text-slate-500 font-mono flex-1">
          {t('communitySubs.subscriptionNumber', { id: sub.id })}
        </p>
        <span
          className={`px-2 py-0.5 rounded-md text-[10px] font-bold ring-1 uppercase ${tint}`}
        >
          {sub.status}
        </span>
        <button
          onClick={load}
          disabled={loading}
          className="p-2 rounded-md bg-white/5 hover:bg-white/10 text-slate-300 disabled:opacity-50"
          title={t('common.refresh')}
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
        </button>
      </div>

      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-5">
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-2">
              {t('communitySubs.subscriber')}
            </p>
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold text-lg">
                {(sub.userName || sub.userEmail || '?')
                  .charAt(0)
                  .toUpperCase()}
              </div>
              <div className="min-w-0">
                <Link
                  to={`/users/${sub.userId}`}
                  className="font-bold text-white hover:text-cyan-300 truncate block"
                >
                  {sub.userName || sub.userEmail}
                </Link>
                <p className="text-xs text-slate-500 truncate">
                  {sub.userEmail}
                </p>
              </div>
            </div>
          </div>
          <div>
            <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-2">
              {t('communitySubs.community')}
            </p>
            <div className="flex items-center gap-3">
              <div className="w-12 h-12 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300">
                <UsersIcon className="w-5 h-5" />
              </div>
              <div className="min-w-0">
                <Link
                  to={`/communities/${sub.communityId}`}
                  className="font-bold text-white hover:text-cyan-300 truncate block"
                >
                  {sub.communityName || sub.communityId}
                </Link>
                <p className="text-xs text-slate-500 font-mono truncate">
                  {sub.communityId}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {error}
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <Stat
          icon={<CreditCard className="w-5 h-5 text-cyan-300" />}
          label={t('communitySubs.plan')}
          value={`${sub.plan === 'yearly' ? t('communitySubs.planYearly') : t('communitySubs.planMonthly')} · ${sub.currency.toUpperCase()} ${dollars}`}
        />
        <Stat
          icon={
            sub.paymentMethod === 'fib' ? (
              <Building2 className="w-5 h-5 text-cyan-300" />
            ) : (
              <Banknote className="w-5 h-5 text-emerald-300" />
            )
          }
          label={t('communitySubs.paymentMethod')}
          value={sub.paymentMethod.toUpperCase()}
        />
        <Stat
          icon={<Calendar className="w-5 h-5 text-slate-300" />}
          label={t('communitySubs.submitted')}
          value={fmtDateTime(sub.createdAt, locale)}
        />
      </div>

      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center gap-2">
          <Hash className="w-4 h-4" />
          {t('communitySubs.paymentProof')}
        </h2>
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 space-y-3">
          {sub.paymentRef ? (
            <div>
              <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-1">
                {t('communitySubs.reference')}
              </p>
              <p className="font-mono text-sm text-white break-all">
                {sub.paymentRef}
              </p>
            </div>
          ) : (
            <p className="text-slate-500 text-sm">{t('communitySubs.noPaymentRef')}</p>
          )}
          {sub.receiptUrl && (
            <div>
              <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-2 flex items-center gap-1">
                <Receipt className="w-3 h-3" />
                {t('communitySubs.cashReceipt')}
              </p>
              <a
                href={absoluteUrl(sub.receiptUrl)}
                target="_blank"
                rel="noreferrer"
                className="block rounded-md ring-1 ring-white/10 overflow-hidden hover:ring-cyan-500/40 transition-all max-w-xs"
              >
                <img
                  src={absoluteUrl(sub.receiptUrl)}
                  alt="receipt"
                  className="w-full max-h-64 object-cover"
                />
              </a>
            </div>
          )}
          {sub.userNote && (
            <div>
              <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-1 flex items-center gap-1">
                <MessageSquare className="w-3 h-3" />
                {t('communitySubs.userNote')}
              </p>
              <p className="text-sm text-slate-300 italic">"{sub.userNote}"</p>
            </div>
          )}
          {sub.rejectionReason && (
            <div className="rounded-md bg-rose-500/10 ring-1 ring-rose-500/30 p-3">
              <p className="text-[10px] uppercase tracking-wider text-rose-300 mb-1">
                {t('communitySubs.rejectionReason')}
              </p>
              <p className="text-sm text-rose-200">{sub.rejectionReason}</p>
            </div>
          )}
        </div>
      </section>

      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('communitySubs.timeline')}</h2>
        <ul className="space-y-2">
          <TimelineRow
            label={t('communitySubs.submitted')}
            ts={sub.createdAt}
            icon={<Calendar className="w-3 h-3" />}
            tone="slate"
          />
          {sub.acceptedAt && (
            <TimelineRow
              label={t('communitySubs.accepted')}
              ts={sub.acceptedAt}
              icon={<Check className="w-3 h-3" />}
              tone="emerald"
              extra={
                sub.acceptedBy ? (
                  <Link
                    to={`/users/${sub.acceptedBy}`}
                    className="text-cyan-300 hover:text-cyan-200"
                  >
                    {t('communitySubs.by', { who: sub.reviewerEmail || t('communitySubs.adminNumber', { id: sub.acceptedBy }) })}
                  </Link>
                ) : null
              }
            />
          )}
          {sub.rejectedAt && (
            <TimelineRow
              label={t('communitySubs.rejected')}
              ts={sub.rejectedAt}
              icon={<X className="w-3 h-3" />}
              tone="rose"
            />
          )}
          {sub.cancelledAt && (
            <TimelineRow
              label={t('communitySubs.cancelled')}
              ts={sub.cancelledAt}
              icon={<X className="w-3 h-3" />}
              tone="slate"
            />
          )}
          {sub.expiresAt && (
            <TimelineRow
              label={t('communitySubs.expiresLabel')}
              ts={sub.expiresAt}
              icon={<Calendar className="w-3 h-3" />}
              tone="slate"
            />
          )}
        </ul>
      </section>

      {isPending && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('communitySubs.action')}</h2>
          <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 space-y-3">
            {showRejectForm ? (
              <div className="space-y-2">
                <p className="text-[10px] uppercase tracking-wider text-slate-400">
                  {t('communitySubs.rejectionReasonOptionalDetail')}
                </p>
                <textarea
                  value={rejectReason}
                  onChange={(e) => setRejectReason(e.target.value)}
                  rows={3}
                  placeholder={t('communitySubs.rejectPlaceholderDetail')}
                  className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 resize-y"
                />
                <div className="flex items-center justify-end gap-2">
                  <button
                    onClick={() => {
                      setShowRejectForm(false)
                      setRejectReason('')
                    }}
                    className="px-3 py-2 rounded-md text-sm text-slate-300 hover:bg-white/5"
                  >
                    {t('common.cancel')}
                  </button>
                  <button
                    onClick={reject}
                    disabled={actionBusy === 'reject'}
                    className="inline-flex items-center gap-2 px-4 py-2 rounded-md text-sm font-bold bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
                  >
                    <X className="w-4 h-4" />
                    {actionBusy === 'reject' ? t('communitySubs.rejecting') : t('communitySubs.confirmReject')}
                  </button>
                </div>
              </div>
            ) : (
              <div className="flex items-center gap-3">
                <button
                  onClick={accept}
                  disabled={actionBusy !== null}
                  className="flex-1 inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg text-sm font-bold bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 ring-1 ring-emerald-500/30 disabled:opacity-50"
                >
                  <Check className="w-5 h-5" />
                  {actionBusy === 'accept' ? t('communitySubs.accepting') : t('communitySubs.acceptPayment')}
                </button>
                <button
                  onClick={() => setShowRejectForm(true)}
                  disabled={actionBusy !== null}
                  className="flex-1 inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg text-sm font-bold bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
                >
                  <X className="w-5 h-5" />
                  {t('communitySubs.rejectEllipsis')}
                </button>
              </div>
            )}
            <p className="text-[11px] text-slate-500">
              {sub.plan === 'yearly'
                ? t('communitySubs.acceptingNoteYearly')
                : t('communitySubs.acceptingNoteMonthly')}
            </p>
          </div>
        </section>
      )}

      {/* Step C11 — other community subs by the same user. Helps admins
          spot patterns (multiple paid communities, repeated rejections). */}
      <UserOtherSubsSection userId={sub.userId} excludeId={sub.id} />
    </div>
  )
}

function UserOtherSubsSection({
  userId,
  excludeId,
}: {
  userId: number
  excludeId: number
}) {
  const { t } = useI18n()
  const [rows, setRows] = useState<CommunitySub[] | null>(null)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    let alive = true
    setLoading(true)
    api
      .get<{ subscriptions: CommunitySub[] }>(
        `/admin/users/${userId}/community-subscriptions`,
      )
      .then((res) => {
        if (!alive) return
        setRows((res.subscriptions ?? []).filter((s) => s.id !== excludeId))
      })
      .catch(() => {
        if (!alive) return
        setRows([])
      })
      .finally(() => {
        if (!alive) return
        setLoading(false)
      })
    return () => {
      alive = false
    }
  }, [userId, excludeId])

  return (
    <section>
      <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center gap-2">
        <UsersIcon className="w-4 h-4" />
        {t('communitySubs.otherSubs')}
        {rows && (
          <span className="ms-1 text-xs text-slate-500 font-normal">
            ({rows.length})
          </span>
        )}
      </h2>
      {loading ? (
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 text-sm text-slate-500">
          {t('common.loading')}
        </div>
      ) : !rows || rows.length === 0 ? (
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 text-sm text-slate-500">
          {t('communitySubs.noOtherSubs')}
        </div>
      ) : (
        <ul className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 divide-y divide-white/5">
          {rows.map((s) => (
            <li key={s.id}>
              <Link
                to={`/community-subscriptions/${s.id}`}
                className="flex items-center justify-between gap-3 px-4 py-3 hover:bg-white/[0.02] transition-colors"
              >
                <div className="min-w-0">
                  <p className="text-sm text-white truncate">
                    {s.communityName || s.communityId}
                  </p>
                  <p className="text-xs text-slate-500">
                    {s.plan} · {s.currency.toUpperCase()} {(s.priceCents / 100).toFixed(0)} ·{' '}
                    {s.paymentMethod}
                  </p>
                </div>
                <span
                  className={`px-1.5 py-0.5 rounded-md text-[10px] font-bold ring-1 uppercase ${
                    STATUS_TINT[s.status] ?? STATUS_TINT.pending
                  }`}
                >
                  {s.status}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

function Stat({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode
  label: string
  value: string
}) {
  return (
    <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
      <div className="flex items-center gap-2 text-xs text-slate-400">
        {icon}
        {label}
      </div>
      <div className="mt-2 text-base font-bold text-white truncate">
        {value}
      </div>
    </div>
  )
}

function TimelineRow({
  label,
  ts,
  icon,
  tone,
  extra,
}: {
  label: string
  ts: string
  icon: React.ReactNode
  tone: 'slate' | 'emerald' | 'rose'
  extra?: React.ReactNode
}) {
  const { locale } = useI18n()
  const dotCls = {
    slate: 'bg-slate-500/20 ring-slate-500/30 text-slate-300',
    emerald: 'bg-emerald-500/20 ring-emerald-500/30 text-emerald-300',
    rose: 'bg-rose-500/20 ring-rose-500/30 text-rose-300',
  }[tone]
  return (
    <li className="flex items-center gap-3 text-sm">
      <span
        className={`w-6 h-6 rounded-full ring-1 flex items-center justify-center ${dotCls}`}
      >
        {icon}
      </span>
      <span className="text-slate-200 font-semibold">{label}</span>
      <span className="text-slate-500 text-xs flex-1">
        {fmtDateTime(ts, locale)}
      </span>
      {extra && <span className="text-xs">{extra}</span>}
    </li>
  )
}
