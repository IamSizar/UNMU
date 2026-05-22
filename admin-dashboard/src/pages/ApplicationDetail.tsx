import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  RefreshCw,
  Check,
  X,
  Calendar,
  Award,
  FileText,
  AlertOctagon,
  AlertTriangle,
  Image as ImageIcon,
  ExternalLink,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDateTime } from '../i18n/datefmt'

// Mirrors the backend `models.ExpertApplication` row.
type Application = {
  id: number
  userId?: number
  userEmail?: string
  fullName?: string
  expertise?: string
  bio?: string
  country?: string
  credentials?: string[]
  sampleLinks?: string[]
  status: 'pending' | 'approved' | 'rejected'
  rejectionReason?: string
  submittedAt: string
  reviewedAt?: string | null
  reviewedBy?: number | null
  reviewerEmail?: string
  resumeUrl?: string | null
  avatarUrl?: string | null
}

// Canonical env var name is VITE_API_BASE_URL (matches api/client.ts).
// An older variant used VITE_API_BASE (no _URL) which was never set,
// causing /uploads/... images to resolve against the Vite dev server
// instead of the backend and render as broken icons.
function absoluteUrl(path?: string | null) {
  if (!path) return ''
  if (path.startsWith('http')) return path
  const base = (import.meta as any).env?.VITE_API_BASE_URL ?? ''
  const origin = base.replace(/\/api\/?$/, '')
  return `${origin}${path}`
}

const STATUS_TINT: Record<string, string> = {
  pending: 'bg-amber-500/15 text-amber-300 ring-amber-500/30',
  approved: 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/30',
  rejected: 'bg-rose-500/15 text-rose-300 ring-rose-500/30',
}

/**
 * ApplicationDetail — `/applications/:id`.
 *
 * Drill-in from the Expert Applications list. Shows the full bio,
 * credentials, sample links, country, and exposes Approve / Reject
 * with a proper textarea for the rejection reason.
 */
export default function ApplicationDetail() {
  const { t } = useI18n()
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const [app, setApp] = useState<Application | null>(null)
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
      const res = await api.get<Application>(`/admin/expert-applications/${id}`)
      setApp(res)
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

  async function approve() {
    if (!app) return
    setActionBusy('approve')
    try {
      await api.post(`/admin/expert-applications/${app.id}/approve`)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setActionBusy(null)
    }
  }

  async function reject() {
    if (!app) return
    setActionBusy('reject')
    try {
      await api.post(`/admin/expert-applications/${app.id}/reject`, {
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

  if (loading && !app) return <p className="text-slate-500">{t('common.loading')}</p>
  if (error && !app) {
    return (
      <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
        <AlertOctagon className="w-4 h-4" /> {error}
      </div>
    )
  }
  if (!app) {
    return (
      <div>
        <Link to="/applications" className="text-cyan-300 text-sm">
          {t('applicationDetail.backToList')}
        </Link>
        <p className="text-slate-500 mt-3">{t('applicationDetail.notFound')}</p>
      </div>
    )
  }

  const tint = STATUS_TINT[app.status] ?? STATUS_TINT.pending
  const isPending = app.status === 'pending'
  const credentials = app.credentials ?? []
  const sampleLinks = app.sampleLinks ?? []

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <button
          onClick={() => navigate('/applications')}
          className="p-1.5 rounded-md hover:bg-white/5 text-slate-400 hover:text-white"
          title={t('common.back')}
        >
          <ArrowLeft className="w-4 h-4 rtl:-scale-x-100" />
        </button>
        <p className="text-xs text-slate-500 font-mono flex-1">
          {t('applicationDetail.rowLabel', { id: app.id })}
        </p>
        <span
          className={`px-2 py-0.5 rounded-md text-[10px] font-bold ring-1 ${tint}`}
        >
          {t(`applicationDetail.status${app.status.charAt(0).toUpperCase() + app.status.slice(1)}` as Parameters<typeof t>[0])}
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
          <div className="w-16 h-16 rounded-2xl bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold text-2xl overflow-hidden">
            {app.avatarUrl ? (
              <img src={absoluteUrl(app.avatarUrl)} alt="" className="w-full h-full object-cover" />
            ) : (
              (app.fullName || app.userEmail || '?').charAt(0).toUpperCase()
            )}
          </div>
          <div className="flex-1 min-w-0">
            <h1 className="text-2xl font-bold text-white truncate">
              {app.fullName || app.userEmail}
            </h1>
            <p className="text-sm text-cyan-400 truncate">{app.expertise}</p>
            <p className="text-xs text-slate-500 mt-0.5 truncate">
              {app.userEmail}
              {app.country ? ` · ${app.country}` : ''}
            </p>
            {app.userId && (
              <Link
                to={`/users/${app.userId}`}
                className="text-xs text-cyan-300 hover:text-cyan-200 mt-1 inline-block"
              >
                {t('applicationDetail.viewUserProfile')}
              </Link>
            )}
          </div>
        </div>
      </div>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm flex items-center gap-2">
          <AlertTriangle className="w-4 h-4" /> {error}
        </div>
      )}

      {/* Documents — resume PDF + avatar image (mig 0023) */}
      {(app.resumeUrl || app.avatarUrl) && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('applicationDetail.documents')}</h2>
          <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 flex flex-wrap items-center gap-2">
            {app.resumeUrl && (
              <a
                href={absoluteUrl(app.resumeUrl)}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-fuchsia-500/15 hover:bg-fuchsia-500/25 ring-1 ring-fuchsia-500/30 text-fuchsia-300 text-sm font-semibold"
              >
                <FileText className="w-4 h-4" />
                {t('applicationDetail.openResume')}
                <ExternalLink className="w-3.5 h-3.5 opacity-70" />
              </a>
            )}
            {app.avatarUrl && (
              <a
                href={absoluteUrl(app.avatarUrl)}
                target="_blank"
                rel="noreferrer"
                className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-cyan-500/15 hover:bg-cyan-500/25 ring-1 ring-cyan-500/30 text-cyan-300 text-sm font-semibold"
              >
                <ImageIcon className="w-4 h-4" />
                {t('applicationDetail.openPhoto')}
                <ExternalLink className="w-3.5 h-3.5 opacity-70" />
              </a>
            )}
          </div>
        </section>
      )}

      {/* Bio */}
      {app.bio && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('applicationDetail.bio')}</h2>
          <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
            <p className="text-sm text-slate-200 leading-relaxed whitespace-pre-line">
              {app.bio}
            </p>
          </div>
        </section>
      )}

      {/* Credentials */}
      {credentials.length > 0 && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">
            {t('applicationDetail.credentials')}
          </h2>
          <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
            <div className="flex flex-wrap gap-2">
              {credentials.map((c, i) => (
                <span
                  key={i}
                  className="inline-flex items-center gap-1 px-2.5 py-1 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-300"
                >
                  <Award className="w-3.5 h-3.5 text-gold-400" />
                  {c}
                </span>
              ))}
            </div>
          </div>
        </section>
      )}

      {/* Sample links */}
      {sampleLinks.length > 0 && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">
            {t('applicationDetail.sampleWork')}
          </h2>
          <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4">
            <ul className="space-y-1.5">
              {sampleLinks.map((l, i) => (
                <li key={i}>
                  <a
                    href={l}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-1.5 text-sm text-cyan-400 hover:text-cyan-300 break-all"
                  >
                    <FileText className="w-3.5 h-3.5 shrink-0" />
                    {l}
                  </a>
                </li>
              ))}
            </ul>
          </div>
        </section>
      )}

      {/* Rejection reason banner */}
      {app.rejectionReason && (
        <section>
          <div className="rounded-xl bg-rose-500/10 ring-1 ring-rose-500/30 p-4">
            <p className="text-[10px] uppercase tracking-wider text-rose-300 mb-1">
              {t('applicationDetail.rejectionReason')}
            </p>
            <p className="text-sm text-rose-200">{app.rejectionReason}</p>
          </div>
        </section>
      )}

      {/* Timeline */}
      <section>
        <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('applicationDetail.timeline')}</h2>
        <ul className="space-y-2">
          <TimelineRow
            label={t('applicationDetail.submitted')}
            ts={app.submittedAt}
            icon={<Calendar className="w-3 h-3" />}
            tone="slate"
          />
          {app.reviewedAt && (
            <TimelineRow
              label={app.status === 'approved' ? t('applicationDetail.approved') : t('applicationDetail.reviewed')}
              ts={app.reviewedAt}
              icon={
                app.status === 'approved' ? (
                  <Check className="w-3 h-3" />
                ) : (
                  <X className="w-3 h-3" />
                )
              }
              tone={app.status === 'approved' ? 'emerald' : 'rose'}
              extra={
                app.reviewedBy ? (
                  <Link
                    to={`/users/${app.reviewedBy}`}
                    className="text-cyan-300 hover:text-cyan-200"
                  >
                    {t('applicationDetail.byActor', { actor: app.reviewerEmail || t('applicationDetail.adminFallback', { id: app.reviewedBy }) })}
                  </Link>
                ) : null
              }
            />
          )}
        </ul>
      </section>

      {/* Action zone */}
      {isPending && (
        <section>
          <h2 className="text-sm font-semibold text-slate-300 mb-3">{t('applicationDetail.action')}</h2>
          <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 space-y-3">
            {showRejectForm ? (
              <div className="space-y-2">
                <p className="text-[10px] uppercase tracking-wider text-slate-400">
                  {t('applicationDetail.rejectReasonLabel')}
                </p>
                <textarea
                  value={rejectReason}
                  onChange={(e) => setRejectReason(e.target.value)}
                  rows={3}
                  placeholder={t('applicationDetail.rejectReasonPlaceholder')}
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
                    {actionBusy === 'reject' ? t('applicationDetail.rejecting') : t('applicationDetail.confirmReject')}
                  </button>
                </div>
              </div>
            ) : (
              <div className="flex items-center gap-3">
                <button
                  onClick={approve}
                  disabled={actionBusy !== null}
                  className="flex-1 inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg text-sm font-bold bg-emerald-500/20 hover:bg-emerald-500/30 text-emerald-300 ring-1 ring-emerald-500/30 disabled:opacity-50"
                >
                  <Check className="w-5 h-5" />
                  {actionBusy === 'approve' ? t('applicationDetail.approving') : t('applicationDetail.approve')}
                </button>
                <button
                  onClick={() => setShowRejectForm(true)}
                  disabled={actionBusy !== null}
                  className="flex-1 inline-flex items-center justify-center gap-2 px-4 py-3 rounded-lg text-sm font-bold bg-rose-500/15 hover:bg-rose-500/25 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
                >
                  <X className="w-5 h-5" />
                  {t('applicationDetail.rejectAction')}
                </button>
              </div>
            )}
          </div>
        </section>
      )}
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
