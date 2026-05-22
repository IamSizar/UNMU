import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  RefreshCw,
  Activity,
  Calendar,
  AlertOctagon,
  AlertTriangle,
  ExternalLink,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDateTime } from '../i18n/datefmt'

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

const SEV_TINT: Record<string, string> = {
  info: 'bg-cyan-500/15 text-cyan-300 ring-cyan-500/30',
  success: 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30',
  warning: 'bg-amber-500/15 text-amber-300 ring-amber-500/30',
  error: 'bg-rose-500/15 text-rose-300 ring-rose-500/30',
}

/**
 * AuditLogDetail — `/audit-log/:id`.
 *
 * Drill-in for a single audit row. Shows the prettified metadata JSON
 * alongside actor + target links so admin can jump straight from the
 * audit row to the affected user / post / community / etc.
 *
 * Read-only — audit rows are immutable.
 */
export default function AuditLogDetail() {
  const { t, locale } = useI18n()
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [evt, setEvt] = useState<AuditEvent | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    if (!id) return
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<AuditEvent>(`/admin/audit-logs/${id}`)
      setEvt(res)
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

  if (loading && !evt) return <p className="text-slate-500">{t('common.loading')}</p>
  if (error && !evt) {
    return (
      <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
        <AlertOctagon className="w-4 h-4" /> {error}
      </div>
    )
  }
  if (!evt) {
    return (
      <div>
        <Link to="/audit-log" className="text-cyan-300 text-sm">
          {t('auditLog.detailBackToList')}
        </Link>
        <p className="text-slate-500 mt-3">{t('auditLog.detailNotFound')}</p>
      </div>
    )
  }

  const tint = SEV_TINT[evt.severity] ?? SEV_TINT.info
  const targetLink = resolveTargetLink(evt.targetKind, evt.targetId)

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => navigate('/audit-log')}
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('common.back')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </button>
        <p className="text-xs text-slate-500 font-mono flex-1">
          {t('auditLog.detailRowLabel', { id: evt.id })}
        </p>
        <span
          className={`px-2 py-0.5 rounded-md text-[10px] font-bold ring-1 ${tint}`}
        >
          {t(`auditLog.sev${evt.severity.charAt(0).toUpperCase() + evt.severity.slice(1)}` as Parameters<typeof t>[0])}
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
            <Activity className="w-5 h-5" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-[10px] uppercase tracking-wider text-slate-500 font-mono">
              {evt.type}
            </p>
            <h1 className="text-base font-semibold text-white mt-0.5 leading-snug">
              {evt.summary}
            </h1>
            <p className="text-xs text-slate-500 mt-1 inline-flex items-center gap-1">
              <Calendar className="w-3 h-3" />
              {fmtDateTime(evt.createdAt, locale)}
            </p>
          </div>
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {error}
        </div>
      )}

      {/* Actor + target strip */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
          <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-2">
            {t('auditLog.detailActor')}
          </p>
          {evt.actorId ? (
            <Link
              to={`/users/${evt.actorId}`}
              className="text-sm font-bold text-white hover:text-cyan-300 inline-flex items-center gap-1"
            >
              {evt.actorEmail || t('auditLog.detailUserFallback', { id: evt.actorId })}
              <ExternalLink className="w-3 h-3" />
            </Link>
          ) : (
            <p className="text-sm text-slate-400">{t('auditLog.detailSystem')}</p>
          )}
        </div>
        <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
          <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-2">
            {t('auditLog.detailTarget')}
          </p>
          {evt.targetKind && evt.targetId ? (
            targetLink ? (
              <Link
                to={targetLink}
                className="text-sm font-bold text-white hover:text-cyan-300 inline-flex items-center gap-1"
              >
                {evt.targetKind} · {evt.targetId}
                <ExternalLink className="w-3 h-3" />
              </Link>
            ) : (
              <p className="text-sm text-slate-200 font-mono">
                {evt.targetKind} · {evt.targetId}
              </p>
            )
          ) : (
            <p className="text-sm text-slate-500">—</p>
          )}
        </div>
      </div>

      {/* Metadata */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('auditLog.detailMetadata')}</h2>
        <div className="rounded-xl bg-black/20 ring-1 ring-white/5 p-4 overflow-x-auto">
          {evt.metadata && Object.keys(evt.metadata).length > 0 ? (
            <pre className="text-xs text-slate-300 font-mono whitespace-pre-wrap break-words">
              {JSON.stringify(evt.metadata, null, 2)}
            </pre>
          ) : (
            <p className="text-xs text-slate-500 italic">
              {t('auditLog.detailNoMetadata')}
            </p>
          )}
        </div>
      </section>
    </div>
  )
}

// resolveTargetLink — turn (kind, id) into a `/path` if we have a
// detail page for that kind. Returns null when there's no obvious
// destination, in which case the row renders a plain code badge.
function resolveTargetLink(
  kind: string | undefined,
  id: string | undefined,
): string | null {
  if (!kind || !id) return null
  const k = kind.toLowerCase()
  switch (k) {
    case 'user':
      return `/users/${id}`
    case 'post':
      return `/posts/${id}`
    case 'community':
      return `/communities/${id}`
    case 'subscription':
      return `/subscriptions/${id}`
    case 'application':
    case 'expert_application':
      return `/applications/${id}`
    case 'community_proposal':
    case 'proposal':
      return `/community-proposals/${id}`
    case 'poll':
      return `/polls/${id}`
    default:
      return null
  }
}
