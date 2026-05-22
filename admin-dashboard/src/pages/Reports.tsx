import { useEffect, useMemo, useState } from 'react'
import {
  Flag,
  Filter,
  CheckCircle2,
  XCircle,
  Slash,
  Loader2,
  AlertTriangle,
} from 'lucide-react'
import { api, ApiError } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate, fmtDateTime } from '../i18n/datefmt'

// Mirrors backend handlers/reports.go::Report. Joined columns
// (reporterEmail etc.) are populated by the admin list endpoint.
type Report = {
  id: number
  reporterId: number
  reporterEmail: string
  reporterName: string
  targetType: string
  targetId: string
  reason: string
  details?: string
  status: 'open' | 'resolved_action_taken' | 'resolved_no_action' | 'dismissed'
  resolvedBy?: number
  resolvedAt?: string
  resolutionNote?: string
  resolverEmail?: string
  createdAt: string
  updatedAt: string
}

type ListResponse = {
  reports: Report[]
  total: number
  limit: number
  offset: number
}

// value → translation-key suffix (resolved via t() at render so the
// option labels flip with the active locale).
const STATUS_FILTERS = [
  { value: '', labelKey: 'reports.filter.allStatuses' },
  { value: 'open', labelKey: 'reports.filter.open' },
  { value: 'resolved_action_taken', labelKey: 'reports.filter.resolvedActionTaken' },
  { value: 'resolved_no_action', labelKey: 'reports.filter.resolvedNoAction' },
  { value: 'dismissed', labelKey: 'reports.filter.dismissed' },
] as const

const TARGET_FILTERS = [
  { value: '', labelKey: 'reports.filter.allTargets' },
  { value: 'post', labelKey: 'reports.filter.posts' },
  { value: 'user', labelKey: 'reports.filter.users' },
  { value: 'comment', labelKey: 'reports.filter.comments' },
  { value: 'community', labelKey: 'reports.filter.communities' },
  { value: 'message', labelKey: 'reports.filter.messages' },
] as const

const REASON_LABEL_KEYS: Record<string, string> = {
  spam: 'reports.reason.spam',
  harassment: 'reports.reason.harassment',
  hate_speech: 'reports.reason.hateSpeech',
  violence: 'reports.reason.violence',
  sexual_content: 'reports.reason.sexualContent',
  financial_scam: 'reports.reason.financialScam',
  impersonation: 'reports.reason.impersonation',
  misinformation: 'reports.reason.misinformation',
  copyright: 'reports.reason.copyright',
  underage: 'reports.reason.underage',
  self_harm: 'reports.reason.selfHarm',
  shariah_concern: 'reports.reason.shariahConcern',
  other: 'reports.reason.other',
}

const STATUS_STYLES: Record<Report['status'], string> = {
  open: 'text-amber-300 bg-amber-500/10 ring-1 ring-amber-500/30',
  resolved_action_taken:
    'text-emerald-300 bg-emerald-500/10 ring-1 ring-emerald-500/30',
  resolved_no_action: 'text-slate-300 bg-slate-500/10 ring-1 ring-slate-500/30',
  dismissed: 'text-rose-300 bg-rose-500/10 ring-1 ring-rose-500/30',
}

const STATUS_LABEL_KEY: Record<Report['status'], string> = {
  open: 'reports.status.open',
  resolved_action_taken: 'reports.status.actionTaken',
  resolved_no_action: 'reports.status.noAction',
  dismissed: 'reports.status.dismissed',
}

export default function Reports() {
  const { t, locale } = useI18n()
  const [statusFilter, setStatusFilter] = useState<string>('open')
  const [targetFilter, setTargetFilter] = useState<string>('')
  const [reports, setReports] = useState<Report[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [selected, setSelected] = useState<Report | null>(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const qs = new URLSearchParams({
        limit: '50',
        ...(statusFilter ? { status: statusFilter } : {}),
        ...(targetFilter ? { targetType: targetFilter } : {}),
      }).toString()
      const res = await api.get<ListResponse>(`/admin/reports?${qs}`)
      setReports(res.reports ?? [])
      setTotal(res.total ?? 0)
    } catch (err) {
      const message =
        err instanceof ApiError ? err.message : t('reports.error.load')
      setError(message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [statusFilter, targetFilter])

  const openCount = useMemo(
    () => reports.filter((r) => r.status === 'open').length,
    [reports],
  )

  async function resolve(
    report: Report,
    status: Report['status'],
    note: string,
  ) {
    try {
      const updated = await api.post<Report>(
        `/admin/reports/${report.id}/resolve`,
        { status, note },
      )
      setReports((prev) =>
        prev.map((r) => (r.id === report.id ? updated : r)),
      )
      setSelected(updated)
    } catch (err) {
      const message =
        err instanceof ApiError ? err.message : t('reports.error.update')
      setError(message)
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            {t('reports.title')}
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            {t('reports.subtitle')}
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
                {t(f.labelKey as never)}
              </option>
            ))}
          </select>
          <select
            value={targetFilter}
            onChange={(e) => setTargetFilter(e.target.value)}
            className="input w-40"
          >
            {TARGET_FILTERS.map((f) => (
              <option key={f.value} value={f.value}>
                {t(f.labelKey as never)}
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

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 lg:gap-5">
        {/* Queue */}
        <div className="lg:col-span-2 card overflow-hidden">
          <div className="px-4 sm:px-5 py-3 sm:py-4 border-b border-white/5 flex items-center justify-between">
            <h3 className="font-semibold text-white">
              {t('reports.queue.title')}{' '}
              <span className="text-xs text-slate-500 ms-1 font-normal">
                {t('reports.queue.summary', { total, open: openCount })}
              </span>
            </h3>
            {loading && (
              <Loader2 className="w-4 h-4 animate-spin text-slate-500" />
            )}
          </div>
          {reports.length === 0 && !loading ? (
            <div className="p-8 text-center text-slate-500 text-sm">
              <Flag className="w-8 h-8 mx-auto mb-2 opacity-40" />
              {t('reports.queue.empty')}
            </div>
          ) : (
            <ul className="divide-y divide-white/5">
              {reports.map((r) => (
                <li
                  key={r.id}
                  onClick={() => setSelected(r)}
                  className={`px-4 sm:px-5 py-3 sm:py-4 cursor-pointer hover:bg-white/[0.03] transition-colors ${
                    selected?.id === r.id ? 'bg-white/[0.04]' : ''
                  }`}
                >
                  <div className="flex items-start gap-3">
                    <div className="w-9 h-9 rounded-lg bg-white/5 flex items-center justify-center shrink-0">
                      <Flag className="w-4 h-4 text-rose-400" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <p className="font-medium text-white text-sm">
                          {REASON_LABEL_KEYS[r.reason]
                            ? t(REASON_LABEL_KEYS[r.reason] as never)
                            : r.reason}
                        </p>
                        <span
                          className={`text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded ${STATUS_STYLES[r.status]}`}
                        >
                          {t(STATUS_LABEL_KEY[r.status] as never)}
                        </span>
                      </div>
                      <p className="text-xs text-slate-400 mt-0.5 truncate">
                        {r.targetType} #{r.targetId} · {t('reports.by')}{' '}
                        {r.reporterName || r.reporterEmail}
                      </p>
                      {r.details && (
                        <p className="text-xs text-slate-500 mt-1 line-clamp-2">
                          {r.details}
                        </p>
                      )}
                    </div>
                    <span className="text-[11px] text-slate-500 shrink-0">
                      {fmtDate(r.createdAt, locale)}
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Detail / resolution panel */}
        <div className="lg:col-span-1 card p-4 sm:p-5 h-fit sticky top-4">
          {!selected ? (
            <div className="text-sm text-slate-500 text-center py-8">
              {t('reports.detail.empty')}
            </div>
          ) : (
            <ResolutionPanel report={selected} onResolve={resolve} />
          )}
        </div>
      </div>
    </div>
  )
}

function ResolutionPanel({
  report,
  onResolve,
}: {
  report: Report
  onResolve: (
    r: Report,
    status: Report['status'],
    note: string,
  ) => Promise<void>
}) {
  const { t, locale } = useI18n()
  const [note, setNote] = useState('')
  const [busy, setBusy] = useState<string | null>(null)

  async function fire(status: Report['status']) {
    setBusy(status)
    await onResolve(report, status, note)
    setBusy(null)
  }

  const isOpen = report.status === 'open'

  return (
    <div className="space-y-4">
      <div>
        <span
          className={`text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded ${STATUS_STYLES[report.status]}`}
        >
          {t(STATUS_LABEL_KEY[report.status] as never)}
        </span>
        <h3 className="font-semibold text-white mt-2">
          {REASON_LABEL_KEYS[report.reason]
            ? t(REASON_LABEL_KEYS[report.reason] as never)
            : report.reason}
        </h3>
        <p className="text-xs text-slate-500 mt-1">
          {t('reports.detail.filed', {
            date: fmtDateTime(report.createdAt, locale),
          })}
        </p>
      </div>

      <div className="space-y-2 text-sm">
        <Row label={t('reports.detail.target')}>
          <span className="font-mono text-xs text-cyan-300">
            {report.targetType}#{report.targetId}
          </span>
        </Row>
        <Row label={t('reports.detail.reporter')}>
          <span className="text-slate-300">
            {report.reporterName || report.reporterEmail}{' '}
            <span className="text-slate-500">
              {t('reports.detail.reporterUser', { id: report.reporterId })}
            </span>
          </span>
        </Row>
        {report.details && (
          <Row label={t('reports.detail.details')}>
            <span className="text-slate-300">{report.details}</span>
          </Row>
        )}
        {report.resolvedAt && (
          <>
            <Row label={t('reports.detail.resolvedBy')}>
              <span className="text-slate-300">{report.resolverEmail}</span>
            </Row>
            <Row label={t('reports.detail.when')}>
              <span className="text-slate-300">
                {fmtDateTime(report.resolvedAt, locale)}
              </span>
            </Row>
            {report.resolutionNote && (
              <Row label={t('reports.detail.note')}>
                <span className="text-slate-300 italic">
                  {report.resolutionNote}
                </span>
              </Row>
            )}
          </>
        )}
      </div>

      {isOpen && (
        <div className="space-y-3 pt-2 border-t border-white/5">
          <label className="block text-xs uppercase tracking-wider text-slate-500">
            {t('reports.resolution.label')}
          </label>
          <textarea
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={3}
            maxLength={2000}
            className="input resize-none"
            placeholder={t('reports.resolution.placeholder')}
          />
          <div className="grid grid-cols-1 gap-2">
            <button
              onClick={() => fire('resolved_action_taken')}
              disabled={!!busy}
              className="btn-primary justify-center disabled:opacity-50"
            >
              {busy === 'resolved_action_taken' ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <CheckCircle2 className="w-4 h-4" />
              )}
              {t('reports.action.actionTaken')}
            </button>
            <button
              onClick={() => fire('resolved_no_action')}
              disabled={!!busy}
              className="btn-secondary justify-center disabled:opacity-50"
            >
              {busy === 'resolved_no_action' ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <XCircle className="w-4 h-4" />
              )}
              {t('reports.action.noAction')}
            </button>
            <button
              onClick={() => fire('dismissed')}
              disabled={!!busy}
              className="btn-secondary justify-center disabled:opacity-50"
            >
              {busy === 'dismissed' ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <Slash className="w-4 h-4" />
              )}
              {t('reports.action.dismiss')}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-0.5">
      <span className="text-[10px] uppercase tracking-wider text-slate-500">
        {label}
      </span>
      <div>{children}</div>
    </div>
  )
}
