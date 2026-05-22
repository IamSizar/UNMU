import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  Search, RefreshCw, AlertCircle, Loader2, Inbox,
  User as UserIcon, GraduationCap, BookOpen, ShieldCheck, Crown, Check,
  Users as UsersIcon,
} from 'lucide-react'
import { api } from '../api/client'
import { useRealtime } from '../api/realtime'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'

// SCHOLAR retired (migration 0013). Filter dropdown + counts strip
// only show USER / EXPERT / ADMIN now.
const ROLES = ['USER', 'EXPERT', 'ADMIN']

const ROLE_META = {
  USER:   { labelKey: 'users.roleMember', icon: UserIcon,    color: 'bg-slate-500/15 text-slate-300 ring-slate-500/30' },
  EXPERT: { labelKey: 'users.roleExpert', icon: ShieldCheck, color: 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30' },
  ADMIN:  { labelKey: 'users.roleAdmin',  icon: BookOpen,    color: 'bg-violet-500/15 text-violet-300 ring-violet-500/30' },
}

export default function Users() {
  const { t } = useI18n()
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [query, setQuery] = useState('')
  const [roleFilter, setRoleFilter] = useState('')

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const params = new URLSearchParams()
      if (query) params.set('q', query)
      if (roleFilter) params.set('role', roleFilter)
      params.set('limit', '100')
      const res = await api.get(`/admin/users?${params}`)
      setUsers(res.users ?? [])
    } catch (e) {
      setError(e?.message ?? t('users.failedLoad'))
    } finally {
      setLoading(false)
    }
  }

  // Reload on filter changes (debounce search slightly so it's not chatty).
  useEffect(() => {
    const t = setTimeout(load, query ? 250 : 0)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, roleFilter])

  // Realtime — refresh when any role changes (admin elsewhere, approval flow,
  // self-service via Flutter, etc.) or new user registers / logs in.
  useRealtime(
    ['user_role_changed', 'application_approved', 'application_rejected'],
    () => load(),
  )

  const counts = useMemo(() => {
    const c = { USER: 0, EXPERT: 0, ADMIN: 0 }
    for (const u of users) c[u.role] = (c[u.role] ?? 0) + 1
    return c
  }, [users])

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">{t('users.title')}</h1>
          <p className="text-slate-400 text-sm mt-1">
            {t('users.summary', { total: users.length, experts: counts.EXPERT, admins: counts.ADMIN })}
          </p>
        </div>
        <button onClick={load} className="btn-secondary">
          <RefreshCw className="w-4 h-4" /> {t('common.refresh')}
        </button>
      </div>

      {/* Filters */}
      <div className="card p-3 flex flex-col sm:flex-row sm:flex-wrap sm:items-center gap-3">
        <div className="relative flex-1 sm:min-w-64">
          <Search className="w-4 h-4 absolute start-3 top-1/2 -translate-y-1/2 text-slate-500" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('users.searchPlaceholder')}
            className="input ps-9"
          />
        </div>
        <div className="flex items-center gap-1.5 overflow-x-auto -mx-1 px-1 pb-1 sm:pb-0">
          <button
            onClick={() => setRoleFilter('')}
            className={`shrink-0 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
              roleFilter === ''
                ? 'bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/20'
                : 'text-slate-400 hover:bg-white/5'
            }`}
          >
            {t('users.filterAll')}
          </button>
          {ROLES.map((r) => (
            <button
              key={r}
              onClick={() => setRoleFilter(r)}
              className={`shrink-0 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                roleFilter === r
                  ? 'bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/20'
                  : 'text-slate-400 hover:bg-white/5'
              }`}
            >
              {t(ROLE_META[r].labelKey)}
            </button>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="card overflow-hidden">
        {error && (
          <div className="m-4 flex items-start gap-2 p-3 rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300 text-sm">
            <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {loading && users.length === 0 ? (
          <div className="flex items-center justify-center py-16 text-slate-400">
            <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('common.loading')}
          </div>
        ) : users.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-slate-500">
            <Inbox className="w-10 h-10 mb-3 opacity-50" />
            <p className="text-sm">{t('users.empty')}</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-white/[0.02] text-slate-500">
                <tr className="text-start">
                  <th className="px-3 sm:px-5 py-3 font-medium">{t('users.colUser')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium">{t('users.colRole')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden sm:table-cell">{t('users.colCommunities')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden md:table-cell">{t('users.colSubscription')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden lg:table-cell">{t('users.colJoined')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium text-end">{t('users.colActions')}</th>
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <UserRow key={u.id} user={u} onRoleSaved={load} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}

function UserRow({ user, onRoleSaved }) {
  const { t, locale } = useI18n()
  const [editing, setEditing] = useState(false)
  const [pending, setPending] = useState(null) // role being saved
  const [error, setError] = useState(null)

  const meta = ROLE_META[user.role] ?? ROLE_META.USER
  const Icon = meta.icon

  async function changeRole(newRole) {
    if (newRole === user.role) {
      setEditing(false)
      return
    }
    setPending(newRole)
    setError(null)
    try {
      await api.patch(`/admin/users/${user.id}/role`, { role: newRole })
      setEditing(false)
      // Realtime user_role_changed will trigger a refresh via the hook,
      // but call onRoleSaved as well to be snappy.
      onRoleSaved?.()
    } catch (e) {
      setError(e?.message ?? t('users.failedRole'))
    } finally {
      setPending(null)
    }
  }

  return (
    <tr className="border-t border-white/5 hover:bg-white/[0.02]">
      <td className="px-3 sm:px-5 py-3">
        <div className="flex items-center gap-3 min-w-0">
          <div className="w-9 h-9 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold shrink-0">
            {(user.name ?? user.email).charAt(0).toUpperCase()}
          </div>
          <div className="min-w-0">
            <Link
              to={`/users/${user.id}`}
              className="font-semibold text-white truncate max-w-[10rem] sm:max-w-none hover:text-cyan-300 block"
            >
              {user.name || user.email.split('@')[0]}
            </Link>
            <p className="text-xs text-slate-500 truncate max-w-[10rem] sm:max-w-[16rem]">{user.email}</p>
            {/* Subscription pill inlined on small screens since the column is hidden. */}
            <span className="md:hidden mt-1 inline-flex items-center gap-1 text-[11px] text-slate-400">
              {user.subscriptionTier === 'PREMIUM' && <Crown className="w-3 h-3 text-gold-400" />}
              {user.subscriptionTier}
            </span>
          </div>
        </div>
      </td>
      <td className="px-3 sm:px-5 py-3">
        <span className={`chip ring-1 ${meta.color}`}>
          <Icon className="w-3 h-3 me-1" />
          {t(meta.labelKey)}
        </span>
      </td>
      <td className="px-3 sm:px-5 py-3 hidden sm:table-cell">
        <UserCommunitiesCount userId={user.id} />
      </td>
      <td className="px-3 sm:px-5 py-3 hidden md:table-cell">
        <span className="inline-flex items-center gap-1 text-xs text-slate-400">
          {user.subscriptionTier === 'PREMIUM' && <Crown className="w-3 h-3 text-gold-400" />}
          {user.subscriptionTier}
        </span>
      </td>
      <td className="px-3 sm:px-5 py-3 text-xs text-slate-500 hidden lg:table-cell whitespace-nowrap">
        {fmtDate(user.createdAt, locale)}
      </td>
      <td className="px-3 sm:px-5 py-3">
        <div className="flex items-center justify-end gap-2 flex-wrap">
          {error && <span className="text-xs text-rose-400">{error}</span>}
          {editing ? (
            <>
              <select
                disabled={!!pending}
                value={pending ?? user.role}
                onChange={(e) => changeRole(e.target.value)}
                className="input py-1.5 text-xs w-32 sm:w-36"
              >
                {ROLES.map((r) => (
                  <option key={r} value={r}>{t(ROLE_META[r].labelKey)}</option>
                ))}
              </select>
              <button
                onClick={() => setEditing(false)}
                className="btn-ghost text-xs"
                disabled={!!pending}
              >
                {t('common.cancel')}
              </button>
              {pending && <Loader2 className="w-4 h-4 animate-spin text-cyan-400" />}
            </>
          ) : (
            <button onClick={() => setEditing(true)} className="btn-secondary text-xs whitespace-nowrap">
              <Check className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">{t('users.changeRole')}</span>
              <span className="sm:hidden">{t('users.edit')}</span>
            </button>
          )}
        </div>
      </td>
    </tr>
  )
}

/**
 * Lazy per-row count chip — fetches /admin/users/:id/communities once.
 *
 * Each row makes its own request, but list pages are 100 rows max and the
 * endpoint is cheap (single LATERAL join). If this becomes hot we can move
 * the count into the /admin/users response itself.
 */
function UserCommunitiesCount({ userId }) {
  const { t } = useI18n()
  const [count, setCount] = useState(null)
  const [paid, setPaid] = useState(0)
  useEffect(() => {
    let alive = true
    api
      .get(`/admin/users/${userId}/communities`)
      .then((res) => {
        if (!alive) return
        const list = res.communities ?? []
        setCount(list.length)
        setPaid(list.filter((c) => c.subscription?.status === 'active').length)
      })
      .catch(() => {
        if (!alive) return
        setCount(0)
      })
    return () => {
      alive = false
    }
  }, [userId])
  if (count === null) {
    return <Loader2 className="w-3.5 h-3.5 animate-spin text-slate-500" />
  }
  if (count === 0) {
    return <span className="text-xs text-slate-600">—</span>
  }
  return (
    <span className="inline-flex items-center gap-1.5">
      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-white/5 text-slate-300 text-xs ring-1 ring-white/10">
        <UsersIcon className="w-3 h-3" />
        {count}
      </span>
      {paid > 0 && (
        <span
          title={t('users.paidTooltip', { n: paid })}
          className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-amber-500/15 text-amber-300 text-[10px] font-bold ring-1 ring-amber-500/30"
        >
          <Crown className="w-3 h-3" />
          {paid}
        </span>
      )}
    </span>
  )
}
