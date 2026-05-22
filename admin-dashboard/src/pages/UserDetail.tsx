import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  ShieldCheck,
  User as UserIcon,
  Mail,
  Calendar,
  Users as UsersIcon,
  Crown,
  CreditCard,
  Trash2,
  AlertCircle,
  Loader2,
  ShieldOff,
} from 'lucide-react'
import { api, ApiError } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate, fmtDateTime } from '../i18n/datefmt'
import Posts from './Posts'

type AdminUser = {
  id: number
  email: string
  name?: string
  role: string
  createdAt?: string
  expertId?: string | null
}

type ListResponse = { users: AdminUser[] }

type SubBrief = {
  id: number
  plan: 'monthly' | 'yearly' | string
  status: 'pending' | 'active' | 'rejected' | 'cancelled' | 'expired' | string
  priceCents: number
  currency: string
  paymentMethod: string
  paymentRef?: string | null
  createdAt: string
  acceptedAt?: string | null
  expiresAt?: string | null
  cancelledAt?: string | null
  rejectedAt?: string | null
}

type UserCommunity = {
  communityId: string
  communityName: string
  isOwner: boolean
  role: string
  joinedAt: string
  isPaid: boolean
  monthlyPriceCents: number
  yearlyPriceCents: number
  currency: string
  subscription?: SubBrief | null
}

/**
 * UserDetail — `/users/:id`.
 *
 * Loads the user via the existing `/admin/users` endpoint (filtered
 * client-side because there's no per-id endpoint yet) and embeds the
 * unified Posts table pre-filtered to that user's posts.
 *
 * Fully read-only for now. Role changes still go through the existing
 * Users page row dropdown.
 */
export default function UserDetail() {
  const { id } = useParams<{ id: string }>()
  const { t, locale } = useI18n()
  const userId = id ? Number(id) : NaN

  const [user, setUser] = useState<AdminUser | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    if (!Number.isFinite(userId)) return
    setLoading(true)
    setError(null)
    try {
      // Reuse the existing list endpoint and filter locally — keeps the
      // backend surface small. Limit is generous so we always find the
      // target row in one round trip.
      const res = await api.get<ListResponse>('/admin/users?limit=500')
      const found = (res.users ?? []).find((u) => u.id === userId)
      setUser(found ?? null)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId])

  if (!Number.isFinite(userId)) {
    return <p className="text-rose-300">{t('user.invalidId')}</p>
  }
  if (loading && !user) {
    return <p className="text-slate-500">{t('common.loading')}</p>
  }
  if (error && !user) {
    return (
      <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm">
        {error}
      </div>
    )
  }
  if (!user) {
    return (
      <div>
        <Link to="/users" className="text-cyan-300 text-sm">
          ← {t('common.back')}
        </Link>
        <p className="text-slate-500 mt-3">{t('user.notFound')}</p>
      </div>
    )
  }

  // SCHOLAR retired (mig 0013) — only EXPERT and ADMIN remain.
  const isExpert = user.role === 'EXPERT'
  const isAdmin = user.role === 'ADMIN'

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <Link
          to="/users"
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('common.back')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </Link>
        <h1 className="text-xl font-bold text-white truncate flex-1 min-w-0">
          {user.name || user.email}
        </h1>
      </div>

      {/* ── User card ───────────────────────────────────────────── */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-5">
        <div className="flex items-start gap-4">
          <div className="w-14 h-14 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold text-2xl shrink-0">
            {(user.name || user.email).charAt(0).toUpperCase()}
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-lg font-bold text-white">{user.name || '—'}</p>
            <p className="text-xs text-slate-400 flex items-center gap-1.5 mt-0.5">
              <Mail className="w-3 h-3" />
              {user.email}
            </p>
            <div className="mt-3 flex flex-wrap gap-2">
              <RoleBadge role={user.role} />
              {isExpert && (
                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-cyan-500/15 text-cyan-300 text-xs ring-1 ring-cyan-500/30">
                  <ShieldCheck className="w-3 h-3" />
                  {user.expertId ? t('userDetail.expertWithId', { id: user.expertId }) : t('userDetail.expert')}
                </span>
              )}
              {isAdmin && (
                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-gold-500/15 text-gold-300 text-xs ring-1 ring-gold-500/30">
                  <ShieldCheck className="w-3 h-3" />
                  {t('userDetail.admin')}
                </span>
              )}
              {user.createdAt && (
                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-white/5 text-slate-400 text-xs ring-1 ring-white/10">
                  <Calendar className="w-3 h-3" />
                  {t('user.joined', { date: fmtDate(user.createdAt, locale) })}
                </span>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* ── Demote (admin override) — only meaningful for EXPERTs.
          Soft demote: flips role back to USER + nullifies expert_id;
          experts row stays intact so historical posts/subs survive. */}
      {isExpert && (
        <DemoteExpertButton userId={user.id} onDemoted={load} />
      )}

      {/* ── Communities this user belongs to + payments ─────────── */}
      <UserCommunitiesSection userId={user.id} />

      {/* ── Posts authored by this user ─────────────────────────── */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center gap-2">
          <UserIcon className="w-4 h-4" />
          {t('user.posts')}
        </h2>
        <Posts authorId={user.id} />
      </section>
    </div>
  )
}

// =============================================================================
// Communities section — every community this user is a member of, with their
// role within the community (owner / expert / member), the live subscription
// row when the community is paid, and a Remove button that calls the existing
// admin "kick member" endpoint.
// =============================================================================
function UserCommunitiesSection({ userId }: { userId: number }) {
  const { t } = useI18n()
  const [rows, setRows] = useState<UserCommunity[] | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<{ communities: UserCommunity[] }>(
        `/admin/users/${userId}/communities`,
      )
      setRows(res.communities ?? [])
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId])

  return (
    <section>
      <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center gap-2">
        <UsersIcon className="w-4 h-4" />
        {t('userDetail.communities')}
        {rows && (
          <span className="ms-1 text-xs text-slate-500 font-normal">
            ({rows.length})
          </span>
        )}
      </h2>

      {error && (
        <div className="mb-3 flex items-start gap-2 p-3 rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300 text-sm">
          <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {loading && !rows ? (
        <div className="flex items-center gap-2 text-slate-500 text-sm py-6">
          <Loader2 className="w-4 h-4 animate-spin" /> {t('userDetail.loadingCommunities')}
        </div>
      ) : !rows || rows.length === 0 ? (
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 px-4 py-6 text-slate-500 text-sm">
          {t('userDetail.noCommunities')}
        </div>
      ) : (
        <div className="space-y-3">
          {rows.map((c) => (
            <CommunityCard
              key={c.communityId}
              row={c}
              userId={userId}
              onChanged={load}
            />
          ))}
        </div>
      )}
    </section>
  )
}

function CommunityCard({
  row,
  userId,
  onChanged,
}: {
  row: UserCommunity
  userId: number
  onChanged: () => void
}) {
  const { t, locale } = useI18n()
  const [removing, setRemoving] = useState(false)
  const [removeError, setRemoveError] = useState<string | null>(null)

  async function onRemove() {
    if (row.isOwner) {
      // Owner can't be kicked — admin must transfer ownership first.
      setRemoveError(t('userDetail.cannotRemoveOwner'))
      return
    }
    const label = row.communityName || row.communityId
    if (!confirm(t('userDetail.removeConfirm', { name: label }))) {
      return
    }
    setRemoving(true)
    setRemoveError(null)
    try {
      await api.delete(
        `/admin/communities/${encodeURIComponent(row.communityId)}/members/${userId}`,
      )
      onChanged()
    } catch (e) {
      const msg =
        e instanceof ApiError ? e.message : (e as Error).message ?? t('userDetail.failed')
      setRemoveError(msg)
    } finally {
      setRemoving(false)
    }
  }

  const sub = row.subscription
  return (
    <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
      {/* Header — community name + role chips */}
      <div className="flex items-start gap-3 flex-wrap">
        <div className="w-10 h-10 rounded-lg bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold shrink-0">
          {row.communityName.charAt(0).toUpperCase()}
        </div>
        <div className="flex-1 min-w-0">
          <Link
            to={`/communities/${row.communityId}`}
            className="font-semibold text-white hover:text-cyan-300 truncate block"
          >
            {row.communityName}
          </Link>
          <p className="text-xs text-slate-500 truncate">
            {row.communityId} · {t('userDetail.joined', { date: fmtDate(row.joinedAt, locale) })}
          </p>
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            {row.isOwner && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-amber-500/15 text-amber-300 text-[11px] font-bold ring-1 ring-amber-500/30">
                <Crown className="w-3 h-3" /> {t('userDetail.owner')}
              </span>
            )}
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-white/5 text-slate-400 text-[11px] ring-1 ring-white/10">
              {row.role}
            </span>
            {row.isPaid && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-fuchsia-500/15 text-fuchsia-300 text-[11px] ring-1 ring-fuchsia-500/30">
                <CreditCard className="w-3 h-3" /> {t('userDetail.paidCommunity')}
              </span>
            )}
          </div>
        </div>
        <div className="flex flex-col gap-1.5 items-end shrink-0">
          {!row.isOwner && (
            <button
              onClick={onRemove}
              disabled={removing}
              className="btn-secondary text-xs whitespace-nowrap text-rose-300 hover:text-rose-200"
            >
              {removing ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
              ) : (
                <Trash2 className="w-3.5 h-3.5" />
              )}
              {t('userDetail.remove')}
            </button>
          )}
        </div>
      </div>

      {removeError && (
        <p className="mt-2 text-xs text-rose-400">{removeError}</p>
      )}

      {/* Pricing summary (only when the community charges) */}
      {row.isPaid && (
        <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
          <Stat
            label={t('userDetail.monthly')}
            value={
              row.monthlyPriceCents > 0
                ? formatMoney(row.monthlyPriceCents, row.currency)
                : '—'
            }
          />
          <Stat
            label={t('userDetail.yearly')}
            value={
              row.yearlyPriceCents > 0
                ? formatMoney(row.yearlyPriceCents, row.currency)
                : '—'
            }
          />
        </div>
      )}

      {/* Subscription detail — only when there's a row in community_subscriptions */}
      {sub ? (
        <div className="mt-3 rounded-lg bg-black/20 ring-1 ring-white/5 p-3">
          <div className="flex items-center justify-between gap-3 flex-wrap">
            <div className="flex items-center gap-2 flex-wrap">
              <Link
                to={`/community-subscriptions/${sub.id}`}
                className="text-xs font-bold text-cyan-300 hover:text-cyan-200"
              >
                {t('userDetail.subNo', { id: sub.id })}
              </Link>
              <SubStatusChip status={sub.status} />
              <span className="text-[11px] text-slate-400 capitalize">
                {sub.plan}
              </span>
              <span className="text-[11px] text-slate-300 font-bold">
                {formatMoney(sub.priceCents, sub.currency)}
              </span>
              <span className="text-[11px] text-slate-500">
                {t('userDetail.via', { method: sub.paymentMethod })}
              </span>
            </div>
          </div>
          <div className="mt-2 grid grid-cols-2 sm:grid-cols-4 gap-2 text-[11px]">
            <Stat
              label={t('userDetail.submitted')}
              value={fmtDateTime(sub.createdAt, locale)}
            />
            <Stat
              label={t('userDetail.accepted')}
              value={
                sub.acceptedAt
                  ? fmtDateTime(sub.acceptedAt, locale)
                  : '—'
              }
            />
            <Stat
              label={t('userDetail.expires')}
              value={
                sub.expiresAt ? fmtDateTime(sub.expiresAt, locale) : '—'
              }
            />
            <Stat
              label={t('userDetail.ref')}
              value={sub.paymentRef ? sub.paymentRef : '—'}
              mono
            />
            {sub.cancelledAt && (
              <Stat
                label={t('userDetail.cancelled')}
                value={fmtDateTime(sub.cancelledAt, locale)}
              />
            )}
            {sub.rejectedAt && (
              <Stat
                label={t('userDetail.rejected')}
                value={fmtDateTime(sub.rejectedAt, locale)}
              />
            )}
          </div>
        </div>
      ) : row.isPaid ? (
        <p className="mt-3 text-[11px] text-slate-500">
          {t('userDetail.noSubRow')}
        </p>
      ) : null}
    </div>
  )
}

function Stat({
  label,
  value,
  mono = false,
}: {
  label: string
  value: string
  mono?: boolean
}) {
  return (
    <div className="min-w-0">
      <p className="uppercase tracking-wider text-[9.5px] font-bold text-slate-500">
        {label}
      </p>
      <p
        className={`text-slate-200 truncate ${
          mono ? 'font-mono text-[10.5px]' : ''
        }`}
        title={value}
      >
        {value}
      </p>
    </div>
  )
}

function SubStatusChip({ status }: { status: string }) {
  const TONE: Record<string, string> = {
    active:    'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30',
    pending:   'bg-amber-500/15 text-amber-300 ring-amber-500/30',
    rejected:  'bg-rose-500/15 text-rose-300 ring-rose-500/30',
    cancelled: 'bg-slate-500/15 text-slate-300 ring-slate-500/30',
    expired:   'bg-slate-500/15 text-slate-400 ring-slate-500/20',
  }
  const cls = TONE[status] ?? TONE.cancelled
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded-md text-[10.5px] font-bold uppercase tracking-wider ring-1 ${cls}`}
    >
      {status}
    </span>
  )
}

function formatMoney(cents: number, currency: string) {
  const dollars = cents / 100
  const sym =
    currency.toLowerCase() === 'usd'
      ? '$'
      : currency.toUpperCase() + ' '
  return `${sym}${dollars.toFixed(dollars % 1 === 0 ? 0 : 2)}`
}

/**
 * Demote-from-expert button (A8). Soft action: flips role → USER, nullifies
 * expert_id, leaves the `experts` row in place. Used for typo recovery on
 * approve. Backend writes a `user_role_changed` realtime event, an inbox
 * row, and (via the SQL trigger on users) an audit log entry.
 */
function DemoteExpertButton({
  userId,
  onDemoted,
}: {
  userId: number
  onDemoted: () => void
}) {
  const { t } = useI18n()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function onClick() {
    if (!confirm(t('userDetail.demoteConfirm'))) return
    setBusy(true)
    setError(null)
    try {
      await api.post(`/admin/users/${userId}/demote-expert`)
      onDemoted()
    } catch (e) {
      const msg =
        e instanceof ApiError ? e.message : (e as Error).message ?? t('userDetail.failed')
      setError(msg)
    } finally {
      setBusy(false)
    }
  }

  return (
    <section>
      <h2 className="text-sm font-semibold text-slate-300 mb-3 flex items-center gap-2">
        <ShieldOff className="w-4 h-4" />
        {t('userDetail.adminOverride')}
      </h2>
      <div className="rounded-xl bg-rose-500/[0.04] ring-1 ring-rose-500/20 p-4 flex items-start justify-between gap-3 flex-wrap">
        <div className="min-w-0">
          <p className="text-sm text-slate-200 font-semibold">{t('userDetail.demoteFromExpert')}</p>
          <p className="text-xs text-slate-400 mt-1 max-w-[42ch]">
            {t('userDetail.demoteHelp')}
          </p>
          {error && (
            <p className="mt-2 text-xs text-rose-400 flex items-center gap-1">
              <AlertCircle className="w-3 h-3" /> {error}
            </p>
          )}
        </div>
        <button
          onClick={onClick}
          disabled={busy}
          className="btn-secondary text-rose-300 hover:text-rose-200 whitespace-nowrap"
        >
          {busy ? (
            <Loader2 className="w-3.5 h-3.5 animate-spin" />
          ) : (
            <ShieldOff className="w-3.5 h-3.5" />
          )}
          {t('userDetail.demote')}
        </button>
      </div>
    </section>
  )
}

function RoleBadge({ role }: { role: string }) {
  // SCHOLAR retired (mig 0013) — only USER / EXPERT / ADMIN remain.
  const TONE: Record<string, string> = {
    ADMIN: 'bg-gold-500/15 text-gold-300 ring-gold-500/30',
    EXPERT: 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30',
    USER: 'bg-white/5 text-slate-300 ring-white/10',
  }
  const cls = TONE[role.toUpperCase()] ?? TONE.USER
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-md text-xs font-bold ring-1 ${cls}`}>
      {role}
    </span>
  )
}
