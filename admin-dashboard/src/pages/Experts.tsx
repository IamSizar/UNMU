import { useEffect, useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  ShieldCheck,
  Search,
  RefreshCw,
  Mail,
  Calendar,
  DollarSign,
  Pencil,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'
import PricingModal, { type PricingExpert } from '../components/PricingModal'

// Mirrors backend `repositories.AdminUserRow` shape — same one Users
// page hits via `/admin/users`. We just filter ?role=EXPERT|SCHOLAR
// to get the experts subset.
type AdminUserRow = {
  id: number
  email: string
  name?: string
  role: string
  expertId?: string | null
  subscriptionTier: string
  subscriptionStatus: string
  createdAt: string
  updatedAt: string
}

type ListResponse = { users: AdminUserRow[] }

// Shape returned by /api/experts — used to enrich each user row with
// per-expert pricing (mig 0024). Indexed by expert id (e.g. "ex_26").
type ExpertProfile = {
  id: string
  name: string
  monthlyPriceCents: number
  yearlyPriceCents: number
  priceCurrency: string
  subscriberCount: number
}

/**
 * Experts — list every user whose role is EXPERT. Drives off the
 * existing `/admin/users?role=EXPERT` endpoint (no separate experts
 * endpoint exists, and the source of truth for "is this person
 * currently an expert?" is `users.role` anyway, not the legacy
 * `experts` table).
 *
 * SCHOLAR was retired (migration 0013) — every former scholar is now
 * EXPERT, so the page no longer needs role split / filter.
 *
 * Each row links to /users/:id so admin can see the expert's posts in
 * the same UserDetail flow used elsewhere.
 */
export default function Experts() {
  const { t } = useI18n()
  const [rows, setRows] = useState<AdminUserRow[]>([])
  // Pricing keyed by `expertId` — populated from a parallel call to
  // /api/experts. The Users endpoint doesn't carry pricing because
  // it lives on the experts table, not users.
  const [pricing, setPricing] = useState<Record<string, ExpertProfile>>({})
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  // Whichever expert is currently being edited in the modal. null = closed.
  const [editing, setEditing] = useState<PricingExpert | null>(null)

  // Tiny debounce so we don't hit the server per keystroke.
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [debouncedQuery, setDebouncedQuery] = useState('')
  useEffect(() => {
    if (searchTimer.current) clearTimeout(searchTimer.current)
    searchTimer.current = setTimeout(() => setDebouncedQuery(query), 250)
    return () => {
      if (searchTimer.current) clearTimeout(searchTimer.current)
    }
  }, [query])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      // Two requests in parallel — users (source of truth for the
      // expert's email/joined date) + experts (carries the pricing
      // from the experts table, mig 0024).
      const [usersRes, expertsRes] = await Promise.all([
        api.get<ListResponse>(buildQuery('EXPERT', debouncedQuery)),
        api.get<{ experts: ExpertProfile[] }>('/experts'),
      ])
      const list = usersRes.users ?? []
      list.sort(
        (a, b) =>
          new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime(),
      )
      setRows(list)

      // Build the {expertId → profile} index for fast lookup in
      // ExpertCard. Falls back to an empty object if the experts
      // endpoint failed.
      const idx: Record<string, ExpertProfile> = {}
      for (const e of expertsRes.experts ?? []) {
        idx[e.id] = e
      }
      setPricing(idx)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [debouncedQuery])

  // Stat strip total — derived from the loaded rows so the number
  // never lies about what the admin is currently looking at.
  const totalExperts = useMemo(() => rows.length, [rows])

  return (
    <div className="space-y-5">
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-white">{t('experts.title')}</h1>
          <p className="text-sm text-slate-400 mt-1">{t('experts.subtitle')}</p>
        </div>
        <button
          onClick={load}
          disabled={loading}
          className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 ring-1 ring-white/10 disabled:opacity-50"
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          {t('common.refresh')}
        </button>
      </div>

      {/* ── Stat strip ─────────────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-3">
        <Stat
          icon={<ShieldCheck className="w-5 h-5 text-cyan-300" />}
          label={t('experts.stat.experts')}
          value={totalExperts}
        />
      </div>

      {/* ── Filters ────────────────────────────────────────────── */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="ms-auto relative flex-1 min-w-[200px] max-w-md">
          <Search className="w-4 h-4 absolute start-2.5 top-1/2 -translate-y-1/2 text-slate-500" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('experts.search.placeholder')}
            className="w-full ps-8 pe-3 py-1.5 rounded-md bg-midnight-700 ring-1 ring-white/10 text-sm text-slate-200 placeholder:text-slate-500"
          />
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-4 py-3 text-rose-300 text-sm">
          {error}
        </div>
      )}

      {/* ── Cards ──────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {rows.length === 0 && !loading && (
          <p className="text-slate-500 text-sm col-span-full text-center py-10">
            {t('experts.empty')}
          </p>
        )}
        {rows.map((u) => (
          <ExpertCard
            key={u.id}
            user={u}
            profile={u.expertId ? pricing[u.expertId] : undefined}
            onEditPricing={(p) => setEditing(p)}
          />
        ))}
      </div>
      {loading && (
        <p className="text-xs text-slate-500 text-center">{t('common.loading')}</p>
      )}

      {/* Pricing edit modal — controlled by `editing` state. On save
          we splice the updated profile back into the local map so the
          card reflects the new price without a full reload. */}
      <PricingModal
        expert={editing}
        onClose={() => setEditing(null)}
        onSaved={(updated) => {
          setPricing((curr) => ({ ...curr, [updated.id]: { ...curr[updated.id], ...updated } }))
        }}
      />
    </div>
  )
}

function ExpertCard({
  user,
  profile,
  onEditPricing,
}: {
  user: AdminUserRow
  profile?: ExpertProfile
  onEditPricing: (p: PricingExpert) => void
}) {
  const { t, locale } = useI18n()
  const display = user.name || user.email.split('@')[0]
  // Pricing chip — shows current $/mo · $/yr when we have a profile,
  // else "—". Defaults from mig 0024 are $10/mo · $96/yr.
  const hasPricing = !!profile
  const monthly = profile ? (profile.monthlyPriceCents / 100).toFixed(0) : null
  const yearly = profile ? (profile.yearlyPriceCents / 100).toFixed(0) : null

  return (
    <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 hover:ring-cyan-500/20 transition-colors block">
      <Link to={`/users/${user.id}`} className="flex items-start gap-3">
        <div className="w-12 h-12 rounded-full flex items-center justify-center font-bold text-lg shrink-0 ring-1 bg-cyan-500/15 text-cyan-300 ring-cyan-500/30">
          {display.charAt(0).toUpperCase()}
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-bold text-white truncate">{display}</p>
          <p className="text-xs text-slate-500 truncate flex items-center gap-1 mt-0.5">
            <Mail className="w-3 h-3" />
            {user.email}
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-1.5">
            <RoleBadge role={user.role} />
            {user.expertId && (
              <span className="px-1.5 py-0.5 rounded-md bg-white/5 ring-1 ring-white/10 text-[10px] font-mono text-slate-400">
                {user.expertId}
              </span>
            )}
            <span className="px-1.5 py-0.5 rounded-md bg-white/5 ring-1 ring-white/10 text-[10px] text-slate-400 flex items-center gap-1">
              <Calendar className="w-3 h-3" />
              {fmtDate(user.createdAt, locale)}
            </span>
          </div>
        </div>
      </Link>

      {/* Pricing row — separated from the link so the "Edit pricing"
          button stays clickable without triggering the row navigation. */}
      <div className="mt-3 pt-3 border-t border-white/[0.06] flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-xs">
          <DollarSign className="w-3.5 h-3.5 text-emerald-400 shrink-0" />
          {hasPricing ? (
            <span className="font-mono tabular-nums text-slate-200">
              <span className="font-bold">${monthly}</span>
              <span className="text-slate-500">{t('experts.perMonth')}</span>
              <span className="text-slate-600 mx-1.5">·</span>
              <span className="font-bold">${yearly}</span>
              <span className="text-slate-500">{t('experts.perYear')}</span>
            </span>
          ) : (
            <span className="text-slate-500">{t('experts.noProfile')}</span>
          )}
        </div>
        {hasPricing && (
          <button
            onClick={(e) => {
              e.preventDefault()
              e.stopPropagation()
              onEditPricing(profile!)
            }}
            className="text-[11px] font-bold text-cyan-300 hover:text-cyan-200 flex items-center gap-1 px-2 h-7 rounded-md hover:bg-white/[0.04] transition-colors"
          >
            <Pencil className="w-3 h-3" />
            {t('experts.editPricing')}
          </button>
        )}
      </div>
    </div>
  )
}

function RoleBadge({ role }: { role: string }) {
  // SCHOLAR retired (mig 0013) — only EXPERT remains as a tinted role.
  const TONE: Record<string, string> = {
    EXPERT: 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30',
  }
  const cls = TONE[role.toUpperCase()] ?? 'bg-white/5 text-slate-300 ring-white/10'
  return (
    <span
      className={`px-1.5 py-0.5 rounded-md text-[10px] font-bold ring-1 ${cls}`}
    >
      {role}
    </span>
  )
}

function Stat({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode
  label: string
  value: number
}) {
  return (
    <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
      <div className="flex items-center gap-2 text-xs text-slate-400">
        {icon}
        {label}
      </div>
      <div className="mt-2 text-2xl font-bold text-white">{value}</div>
    </div>
  )
}

// buildQuery — `/admin/users?role=…&q=…` URL with sane defaults.
// `limit=200` covers the realistic ceiling for "all experts on the
// platform" without paginating; if you ever cross that threshold the
// page will need keyset pagination but it's a one-line fix.
function buildQuery(role: string, q: string): string {
  const params = new URLSearchParams()
  params.set('role', role)
  if (q.trim()) params.set('q', q.trim())
  params.set('limit', '200')
  return `/admin/users?${params.toString()}`
}
