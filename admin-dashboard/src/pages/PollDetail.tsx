import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  RefreshCw,
  Lock,
  Unlock,
  EyeOff,
  Calendar,
  Users,
  Clock,
  AlertOctagon,
  AlertTriangle,
  BarChart3,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDateTime } from '../i18n/datefmt'

// Mirrors backend `repositories.AdminPollDetail` (mig 0021).
type Voter = {
  userId: number
  name: string
  email: string
  role: string
  votedAt: string
}
type Option = {
  id: number
  label: string
  sortOrder: number
  voteCount: number
  voters?: Voter[]
}
type PollDetailRow = {
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
  options: Option[]
}

/**
 * PollDetail — `/polls/:id`.
 *
 * Drill-in for a single chat poll. Shows the question, per-option
 * vote bars, voter avatar list (when not anonymous), and the
 * Force-close action.
 */
export default function PollDetail() {
  const { t, locale } = useI18n()
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [p, setP] = useState<PollDetailRow | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [actionBusy, setActionBusy] = useState<string | null>(null)

  async function load() {
    if (!id) return
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<PollDetailRow>(`/admin/polls/${id}`)
      setP(res)
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

  async function forceClose() {
    if (!p) return
    if (
      !confirm(
        t('polls.confirm.forceClose', {
          id: p.id,
          question: p.question.slice(0, 60),
        }),
      )
    )
      return
    setActionBusy('close')
    try {
      await api.post(`/admin/polls/${p.id}/close`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  if (loading && !p) return <p className="text-slate-500">{t('common.loading')}</p>
  if (error && !p) {
    return (
      <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
        <AlertOctagon className="w-4 h-4" /> {error}
      </div>
    )
  }
  if (!p) {
    return (
      <div>
        <Link to="/polls" className="text-cyan-300 text-sm">
          {t('pollDetail.back')}
        </Link>
        <p className="text-slate-500 mt-3">{t('pollDetail.notFound')}</p>
      </div>
    )
  }

  const closed = !!p.closedAt
  const expiredButOpen =
    !closed && p.expiresAt && new Date(p.expiresAt) < new Date()
  const tint = closed
    ? 'bg-rose-500/15 text-rose-300 ring-rose-500/30'
    : expiredButOpen
    ? 'bg-gold-500/15 text-gold-300 ring-gold-500/30'
    : 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30'

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => navigate('/polls')}
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('common.back')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </button>
        <p className="text-xs text-slate-500 font-mono flex-1">
          {t('pollDetail.label', { id: p.id })}
        </p>
        <span
          className={`px-2 py-0.5 rounded-md text-[10px] font-bold ring-1 uppercase inline-flex items-center gap-1 ${tint}`}
        >
          {closed ? (
            <>
              <Lock className="w-3 h-3" /> {t('polls.status.closed')}
            </>
          ) : (
            <>
              <Unlock className="w-3 h-3" /> {t('polls.status.open')}
            </>
          )}
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

      {/* Hero */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-5">
        <div className="flex items-start gap-4">
          <div className="w-12 h-12 rounded-xl bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300">
            <BarChart3 className="w-5 h-5" />
          </div>
          <div className="flex-1 min-w-0">
            <h1 className="text-base font-semibold text-white leading-snug">
              {p.question}
            </h1>
            <p className="text-xs text-slate-500 mt-1">
              {t('pollDetail.in')}{' '}
              <Link
                to={`/communities/${p.communityId}`}
                className="text-cyan-300 hover:text-cyan-200"
              >
                {p.communityName} ({p.communityId})
              </Link>
              {' · '}{t('pollDetail.by')}{' '}
              <Link
                to={`/users/${p.authorId}`}
                className="text-cyan-300 hover:text-cyan-200"
              >
                {p.authorName}
              </Link>
            </p>
            <div className="mt-2 flex items-center gap-3 text-[11px] text-slate-400 flex-wrap">
              <span className="inline-flex items-center gap-1">
                <Users className="w-3 h-3" />
                {p.totalVotes}{' '}
                {p.totalVotes === 1 ? t('polls.vote.one') : t('polls.vote.many')}
              </span>
              <span className="inline-flex items-center gap-1">
                <Calendar className="w-3 h-3" />
                {fmtDateTime(p.createdAt, locale)}
              </span>
              {p.expiresAt && !closed && (
                <span className="inline-flex items-center gap-1">
                  <Clock className="w-3 h-3" />
                  {t('pollDetail.expires', {
                    date: fmtDateTime(p.expiresAt, locale),
                  })}
                </span>
              )}
              {p.isAnonymous && (
                <span className="inline-flex items-center gap-1 text-slate-300">
                  <EyeOff className="w-3 h-3" />
                  {t('polls.anonymous')}
                </span>
              )}
              <Link
                to={`/posts/${p.messageId}`}
                className="ms-auto text-cyan-300 hover:text-cyan-200 underline-offset-2 hover:underline"
              >
                {t('polls.hostMessage', { id: p.messageId })}
              </Link>
            </div>
          </div>
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {error}
        </div>
      )}

      {/* Option breakdown */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3">
          {t('pollDetail.breakdown.title')}
        </h2>
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 space-y-3">
          {p.options.map((o) => (
            <OptionRow
              key={o.id}
              option={o}
              total={p.totalVotes}
              isAnonymous={p.isAnonymous}
            />
          ))}
        </div>
      </section>

      {/* Anonymous notice */}
      {p.isAnonymous && (
        <div className="rounded-lg bg-slate-500/10 ring-1 ring-slate-500/30 px-3 py-2 text-slate-400 text-xs flex items-center gap-2">
          <EyeOff className="w-3.5 h-3.5" />
          {t('pollDetail.anonymousNotice')}
        </div>
      )}

      {/* Action zone */}
      {!closed && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('pollDetail.action.title')}</h2>
          <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
            <button
              onClick={forceClose}
              disabled={actionBusy !== null}
              className="inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg text-sm font-bold bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
            >
              <Lock className="w-4 h-4" />
              {actionBusy === 'close'
                ? t('pollDetail.action.closing')
                : t('pollDetail.action.forceClose')}
            </button>
            <p className="text-[11px] text-slate-500 mt-2">
              {t('pollDetail.action.help')}
            </p>
          </div>
        </section>
      )}
    </div>
  )
}

function OptionRow({
  option,
  total,
  isAnonymous,
}: {
  option: Option
  total: number
  isAnonymous: boolean
}) {
  const pct = total === 0 ? 0 : (option.voteCount / total) * 100
  const voters = option.voters ?? []
  return (
    <div>
      <div className="flex items-center justify-between text-sm mb-1">
        <span className="font-bold text-white truncate flex-1 me-3">
          {option.label}
        </span>
        <span className="text-slate-300 font-bold">
          {option.voteCount} <span className="text-slate-500">·</span>{' '}
          <span className="text-cyan-300">{pct.toFixed(0)}%</span>
        </span>
      </div>
      <div className="h-2 rounded-full bg-white/5 overflow-hidden ring-1 ring-white/10">
        <div
          className="h-full bg-cyan-500/60"
          style={{ width: `${pct}%` }}
        />
      </div>
      {!isAnonymous && voters.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-1.5">
          {voters.map((v) => (
            <Link
              key={v.userId}
              to={`/users/${v.userId}`}
              className="inline-flex items-center gap-1 px-1.5 py-0.5 rounded-md bg-white/5 ring-1 ring-white/10 text-[10px] text-slate-300 hover:text-cyan-300"
            >
              <span className="w-3.5 h-3.5 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-[8px] font-bold text-cyan-300">
                {v.name.charAt(0).toUpperCase()}
              </span>
              {v.name}
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}
