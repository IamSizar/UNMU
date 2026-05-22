import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import {
  RefreshCw,
  BarChart3,
  Lock,
  Unlock,
  Users,
  Clock,
  EyeOff,
  AlertTriangle,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDateTime } from '../i18n/datefmt'

// Mirrors backend `repositories.AdminPollRow` (mig 0021, item 5.21).
type AdminPoll = {
  id: number
  messageId: number
  communityId: string
  communityName: string
  authorId: number
  authorName: string
  question: string
  isAnonymous: boolean
  totalVotes: number
  optionCount: number
  closedAt?: string | null
  expiresAt?: string | null
  createdAt: string
}

type ListResponse = { polls: AdminPoll[] }

/**
 * Polls — admin moderation panel for chat polls.
 *
 * Lists every poll across every community, newest-first. Filter by
 * community (when an admin drills into one). Each row shows the
 * question, author, vote total, status (open / closed / anonymous),
 * and a quick "Force-close" action.
 *
 * Mig 0021, item 5.21.
 */
export default function Polls() {
  const { t } = useI18n()
  const [rows, setRows] = useState<AdminPoll[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState<number | null>(null)
  const [communityFilter, setCommunityFilter] = useState('')

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const qs = communityFilter
        ? `?communityId=${encodeURIComponent(communityFilter)}`
        : ''
      const res = await api.get<ListResponse>(`/admin/polls${qs}`)
      setRows(res.polls ?? [])
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [communityFilter])

  async function forceClose(p: AdminPoll) {
    if (
      !confirm(
        t('polls.confirm.forceClose', {
          id: p.id,
          question: p.question.slice(0, 60),
        }),
      )
    )
      return
    setBusy(p.id)
    try {
      await api.post(`/admin/polls/${p.id}/close`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setBusy(null)
    }
  }

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl font-bold text-white">{t('polls.title')}</h1>
          <p className="text-sm text-slate-400 mt-1">
            {t('polls.subtitle')}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <input
            value={communityFilter}
            onChange={(e) => setCommunityFilter(e.target.value)}
            placeholder={t('polls.filter.placeholder')}
            className="px-3 py-2 rounded-lg bg-white/5 ring-1 ring-white/10 text-slate-200 text-sm font-mono w-64"
          />
          <button
            onClick={load}
            disabled={loading}
            className="flex items-center gap-2 px-3 py-2 rounded-lg bg-white/5 hover:bg-white/10 text-slate-300 ring-1 ring-white/10 disabled:opacity-50"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            {t('common.refresh')}
          </button>
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-4 py-3 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" />
          {error}
        </div>
      )}

      {rows.length === 0 && !loading ? (
        <p className="text-slate-500 text-sm text-center py-10">
          {t('polls.empty')}
        </p>
      ) : (
        <div className="space-y-2">
          {rows.map((p) => (
            <PollRow
              key={p.id}
              poll={p}
              busy={busy === p.id}
              onForceClose={() => forceClose(p)}
            />
          ))}
        </div>
      )}
      {loading && <p className="text-xs text-slate-500 text-center">{t('common.loading')}</p>}
    </div>
  )
}

function PollRow({
  poll: p,
  busy,
  onForceClose,
}: {
  poll: AdminPoll
  busy: boolean
  onForceClose: () => void
}) {
  const { t, locale } = useI18n()
  const closed = !!p.closedAt
  const expired =
    !closed && p.expiresAt && new Date(p.expiresAt) < new Date()
  const status = closed ? 'closed' : expired ? 'expiring' : 'open'
  const statusCls = closed
    ? 'bg-rose-500/15 text-rose-300 ring-rose-500/30'
    : status === 'expiring'
    ? 'bg-gold-500/15 text-gold-300 ring-gold-500/30'
    : 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30'
  // Step-22 — whole row → /polls/:id detail page (with vote breakdown).
  const navigate = useNavigate()
  function onRowClick(e: React.MouseEvent) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    navigate(`/polls/${p.id}`)
  }
  return (
    <div
      onClick={onRowClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') navigate(`/polls/${p.id}`)
      }}
      className="cursor-pointer rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 hover:bg-white/[0.04] hover:ring-cyan-500/30 transition-colors">
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-xl bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center shrink-0">
          <BarChart3 className="w-5 h-5 text-cyan-300" />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <p className="font-bold text-white text-sm truncate">
                {p.question}
              </p>
              <p className="text-[11px] text-slate-500 mt-0.5">
                <Link
                  to={`/communities/${p.communityId}`}
                  onClick={(e) => e.stopPropagation()}
                  className="text-cyan-300 hover:text-cyan-200 font-mono"
                >
                  {p.communityName} ({p.communityId})
                </Link>
                {' · '}
                <Link
                  to={`/users/${p.authorId}`}
                  onClick={(e) => e.stopPropagation()}
                  className="hover:text-cyan-300"
                >
                  {p.authorName}
                </Link>
                {' · '}
                {fmtDateTime(p.createdAt, locale)}
              </p>
            </div>
            <span
              className={`px-1.5 py-0.5 rounded-md text-[10px] font-bold ring-1 ${statusCls}`}
            >
              {closed ? (
                <span className="inline-flex items-center gap-1">
                  <Lock className="w-3 h-3" /> {t('polls.status.closed')}
                </span>
              ) : (
                <span className="inline-flex items-center gap-1">
                  <Unlock className="w-3 h-3" /> {t('polls.status.open')}
                </span>
              )}
            </span>
          </div>
          <div className="mt-2 flex items-center gap-3 text-[11px] text-slate-400 flex-wrap">
            <span className="inline-flex items-center gap-1">
              <Users className="w-3 h-3" />
              {p.totalVotes}{' '}
              {p.totalVotes === 1 ? t('polls.vote.one') : t('polls.vote.many')}
            </span>
            <span>
              {t('polls.options', { count: p.optionCount })}
            </span>
            {p.isAnonymous && (
              <span className="inline-flex items-center gap-1 text-slate-300">
                <EyeOff className="w-3 h-3" />
                {t('polls.anonymous')}
              </span>
            )}
            {p.expiresAt && !closed && (
              <span className="inline-flex items-center gap-1">
                <Clock className="w-3 h-3" />
                {fmtDateTime(p.expiresAt, locale)}
              </span>
            )}
            <Link
              to={`/posts/${p.messageId}`}
              onClick={(e) => e.stopPropagation()}
              className="ms-auto text-cyan-300 hover:text-cyan-200 underline-offset-2 hover:underline"
            >
              {t('polls.hostMessage', { id: p.messageId })}
            </Link>
            {!closed && (
              <button
                onClick={(e) => {
                  e.stopPropagation()
                  onForceClose()
                }}
                disabled={busy}
                className="ms-2 px-2 py-1 rounded-md text-[10px] font-bold bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
              >
                {busy ? t('polls.action.closing') : t('polls.action.forceClose')}
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
