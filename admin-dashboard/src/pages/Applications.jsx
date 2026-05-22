import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Check, X, FileText, Award, AlertCircle, Loader2, Inbox,
  Search, RefreshCw, Image as ImageIcon, FileText as FileTextIcon,
} from 'lucide-react'
import { api } from '../api/client'
import { useRealtime } from '../api/realtime'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'

const tabs = ['pending', 'approved', 'rejected']
const PAGE_SIZE = 25

export default function Applications() {
  const { t } = useI18n()
  const [status, setStatus] = useState('pending')
  const [query, setQuery] = useState('')
  const [apps, setApps] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [acting, setActing] = useState(null) // id currently being approved/rejected
  const [hasMore, setHasMore] = useState(false)
  // Inline reject form: id of the row whose Reject button is expanded.
  const [rejectingId, setRejectingId] = useState(null)
  const [rejectReason, setRejectReason] = useState('')
  // Debounce timer for search input.
  const searchTimer = useRef(null)

  async function load({ reset = true, cursor = 0 } = {}) {
    if (reset) setLoading(true)
    setError(null)
    try {
      const params = new URLSearchParams()
      if (status) params.set('status', status)
      if (query.trim()) params.set('q', query.trim())
      params.set('limit', String(PAGE_SIZE))
      if (cursor > 0) params.set('cursor', String(cursor))
      const res = await api.get(`/admin/expert-applications?${params}`)
      const next = res.applications ?? []
      setHasMore(next.length === PAGE_SIZE)
      if (reset) {
        setApps(next)
      } else {
        setApps((curr) => [...curr, ...next])
      }
    } catch (e) {
      setError(e?.message ?? t('applications.loadFailed'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load({ reset: true }) /* eslint-disable-next-line */ }, [status])

  // Debounce search — refire 250ms after the last keystroke so the admin
  // doesn't burn a request per character.
  useEffect(() => {
    if (searchTimer.current) clearTimeout(searchTimer.current)
    searchTimer.current = setTimeout(() => load({ reset: true }), 250)
    return () => {
      if (searchTimer.current) clearTimeout(searchTimer.current)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query])

  // Realtime — auto-refresh whenever the server says applications changed.
  useRealtime(
    ['application_submitted', 'application_resolved', 'application_approved', 'application_rejected'],
    () => load({ reset: true }),
  )

  async function approve(id) {
    setActing(id)
    try {
      await api.post(`/admin/expert-applications/${id}/approve`)
      setApps((curr) => curr.filter((a) => a.id !== id))
    } catch (e) {
      alert(e?.message ?? t('applications.approveFailed'))
    } finally {
      setActing(null)
    }
  }

  async function confirmReject(id) {
    setActing(id)
    try {
      await api.post(`/admin/expert-applications/${id}/reject`, { reason: rejectReason.trim() })
      setApps((curr) => curr.filter((a) => a.id !== id))
      setRejectingId(null)
      setRejectReason('')
    } catch (e) {
      alert(e?.message ?? t('applications.rejectFailed'))
    } finally {
      setActing(null)
    }
  }

  function startReject(id) {
    setRejectingId(id)
    setRejectReason('')
  }

  function cancelReject() {
    setRejectingId(null)
    setRejectReason('')
  }

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">{t('applications.title')}</h1>
          <p className="text-slate-400 text-sm mt-1">{t('applications.subtitle')}</p>
        </div>
        <button onClick={() => load({ reset: true })} className="btn-secondary">
          <RefreshCw className="w-4 h-4" /> {t('common.refresh')}
        </button>
      </div>

      <div className="card overflow-hidden">
        <div className="px-3 sm:px-5 py-3 sm:py-4 border-b border-white/5 flex items-center gap-3 flex-wrap">
          <div className="flex items-center gap-2 overflow-x-auto whitespace-nowrap">
            {tabs.map((tab) => (
              <button
                key={tab}
                onClick={() => setStatus(tab)}
                className={`shrink-0 px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                  status === tab ? 'bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/20' : 'text-slate-400 hover:bg-white/5'
                }`}
              >
                {t(`applications.tab${tab.charAt(0).toUpperCase() + tab.slice(1)}`)}
              </button>
            ))}
          </div>
          <div className="flex-1 min-w-[12rem] relative">
            <Search className="w-4 h-4 absolute start-3 top-1/2 -translate-y-1/2 text-slate-500" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={t('applications.searchPlaceholder')}
              className="input ps-9 w-full"
            />
          </div>
        </div>

        <div className="p-4 sm:p-5">
          {error && (
            <div className="flex items-start gap-2 p-3 rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300 text-sm mb-4">
              <AlertCircle className="w-4 h-4 mt-0.5 shrink-0" />
              <span>{error}</span>
            </div>
          )}

          {loading ? (
            <div className="flex items-center justify-center py-16 text-slate-400">
              <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('applications.loading')}
            </div>
          ) : apps.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-16 text-slate-500">
              <Inbox className="w-10 h-10 mb-3 opacity-50" />
              <p className="text-sm">
                {query.trim()
                  ? t('applications.emptyFiltered', { status: t(`applications.status${status.charAt(0).toUpperCase() + status.slice(1)}`), query: query.trim() })
                  : t('applications.empty', { status: t(`applications.status${status.charAt(0).toUpperCase() + status.slice(1)}`) })}
              </p>
            </div>
          ) : (
            <>
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-5">
                {apps.map((a) => (
                  <ApplicationCard
                    key={a.id}
                    app={a}
                    status={status}
                    acting={acting === a.id}
                    rejecting={rejectingId === a.id}
                    rejectReason={rejectReason}
                    setRejectReason={setRejectReason}
                    onApprove={() => approve(a.id)}
                    onStartReject={() => startReject(a.id)}
                    onCancelReject={cancelReject}
                    onConfirmReject={() => confirmReject(a.id)}
                  />
                ))}
              </div>
              {hasMore && (
                <div className="mt-5 flex items-center justify-center">
                  <button
                    onClick={() => {
                      const lastId = apps.length > 0 ? apps[apps.length - 1].id : 0
                      load({ reset: false, cursor: lastId })
                    }}
                    className="btn-secondary"
                  >
                    {t('applications.loadMore')}
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

function ApplicationCard({
  app, status,
  acting, rejecting, rejectReason, setRejectReason,
  onApprove, onStartReject, onCancelReject, onConfirmReject,
}) {
  const { t, locale } = useI18n()
  const submitted = new Date(app.submittedAt)
  const reviewed = app.reviewedAt ? new Date(app.reviewedAt) : null
  const credentials = app.credentials ?? []
  const sampleLinks = app.sampleLinks ?? []
  // Step-22 — whole card → /applications/:id detail page.
  const navigate = useNavigate()
  function onCardClick(e) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
    if (rejecting) return // don't navigate while the inline form is open
    navigate(`/applications/${app.id}`)
  }

  return (
    <div
      onClick={onCardClick}
      role="button"
      tabIndex={0}
      onKeyDown={(e) => {
        if (rejecting) return
        if (e.key === 'Enter' || e.key === ' ') navigate(`/applications/${app.id}`)
      }}
      className="cursor-pointer rounded-xl bg-white/[0.02] border border-white/5 p-4 sm:p-5 hover:ring-1 hover:ring-cyan-500/30 transition-shadow">
      <div className="flex items-start gap-3">
        <div className="w-12 h-12 rounded-full bg-cyan-500/15 ring-1 ring-cyan-500/30 flex items-center justify-center text-cyan-300 font-bold shrink-0 overflow-hidden">
          {app.avatarUrl ? (
            <img src={absoluteUrl(app.avatarUrl)} alt="" className="w-full h-full object-cover" />
          ) : (
            (app.fullName || app.userEmail || '?').charAt(0).toUpperCase()
          )}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <h3 className="font-semibold text-white truncate">{app.fullName}</h3>
              <p className="text-xs text-cyan-400 truncate">{app.expertise}</p>
            </div>
            <span className="text-[11px] text-slate-500 shrink-0">{relativeTime(submitted, t, locale)}</span>
          </div>
          <p className="text-xs text-slate-400 mt-0.5 truncate">
            {app.userEmail}
            {app.country ? ` · ${app.country}` : ''}
          </p>
        </div>
      </div>

      <p className="text-sm text-slate-300 mt-4 leading-relaxed line-clamp-3">{app.bio}</p>

      {/* Resume + avatar evidence row */}
      {(app.resumeUrl || app.avatarUrl) && (
        <div className="mt-3 flex items-center gap-2 flex-wrap">
          {app.resumeUrl && (
            <a
              href={absoluteUrl(app.resumeUrl)}
              target="_blank"
              rel="noreferrer"
              onClick={(e) => e.stopPropagation()}
              className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-fuchsia-500/15 ring-1 ring-fuchsia-500/30 text-[11px] text-fuchsia-300 hover:bg-fuchsia-500/25"
            >
              <FileTextIcon className="w-3 h-3" /> {t('applications.resume')}
            </a>
          )}
          {app.avatarUrl && (
            <a
              href={absoluteUrl(app.avatarUrl)}
              target="_blank"
              rel="noreferrer"
              onClick={(e) => e.stopPropagation()}
              className="inline-flex items-center gap-1 px-2 py-0.5 rounded-md bg-cyan-500/15 ring-1 ring-cyan-500/30 text-[11px] text-cyan-300 hover:bg-cyan-500/25"
            >
              <ImageIcon className="w-3 h-3" /> {t('applications.photo')}
            </a>
          )}
        </div>
      )}

      {credentials.length > 0 && (
        <div className="mt-4">
          <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-2">{t('applications.credentials')}</p>
          <div className="flex flex-wrap gap-1.5">
            {credentials.map((c, i) => (
              <span key={i} className="px-2 py-0.5 rounded-md bg-white/5 ring-1 ring-white/10 text-xs text-slate-300 inline-flex items-center gap-1">
                <Award className="w-3 h-3 text-gold-400" />
                {c}
              </span>
            ))}
          </div>
        </div>
      )}

      {sampleLinks.length > 0 && (
        <div className="mt-3">
          <p className="text-[10px] uppercase tracking-wider text-slate-500 mb-1.5">{t('applications.sampleWork')}</p>
          <ul className="text-xs space-y-0.5">
            {sampleLinks.map((l, i) => (
              <li key={i}>
                <a href={l} target="_blank" rel="noreferrer" onClick={(e) => e.stopPropagation()} className="text-cyan-400 hover:text-cyan-300 inline-flex items-center gap-1 truncate max-w-full">
                  <FileText className="w-3 h-3" /> {l}
                </a>
              </li>
            ))}
          </ul>
        </div>
      )}

      {status === 'rejected' && app.rejectionReason && (
        <div className="mt-4 p-3 rounded-lg bg-rose-500/10 ring-1 ring-rose-500/20 text-xs text-rose-300">
          <span className="font-semibold">{t('applications.rejectedLabel')}</span> {app.rejectionReason}
        </div>
      )}

      {reviewed && (
        <p className="mt-3 text-[11px] text-slate-500">
          {t('applications.reviewed', { time: relativeTime(reviewed, t, locale) })}
        </p>
      )}

      {status === 'pending' && (
        <div onClick={(e) => e.stopPropagation()}>
          {rejecting ? (
            <div className="mt-4 space-y-2">
              <label className="text-[10px] uppercase tracking-wider text-slate-400">
                {t('applications.rejectReasonLabel')}
              </label>
              <textarea
                value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)}
                rows={2}
                placeholder={t('applications.rejectReasonPlaceholder')}
                className="w-full px-3 py-2 rounded-md bg-white/5 ring-1 ring-white/10 text-sm text-slate-200 resize-y"
              />
              <div className="flex items-center justify-end gap-2">
                <button
                  onClick={onCancelReject}
                  className="px-3 py-1.5 rounded-md text-sm text-slate-300 hover:bg-white/5"
                >
                  {t('common.cancel')}
                </button>
                <button
                  disabled={acting}
                  onClick={onConfirmReject}
                  className="inline-flex items-center gap-2 px-3 py-1.5 rounded-md text-sm font-bold bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 ring-1 ring-rose-500/30 disabled:opacity-50"
                >
                  {acting ? <Loader2 className="w-4 h-4 animate-spin" /> : <X className="w-4 h-4" />}
                  {t('applications.confirmReject')}
                </button>
              </div>
            </div>
          ) : (
            <div className="flex items-center gap-2 mt-4">
              <button
                disabled={acting}
                onClick={onApprove}
                className="flex-1 inline-flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-emerald-500/15 hover:bg-emerald-500/25 text-emerald-400 ring-1 ring-emerald-500/20 text-sm font-semibold transition-colors disabled:opacity-50"
              >
                {acting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Check className="w-4 h-4" />}
                {t('applications.approve')}
              </button>
              <button
                disabled={acting}
                onClick={onStartReject}
                className="flex-1 inline-flex items-center justify-center gap-2 px-3 py-2 rounded-lg bg-rose-500/15 hover:bg-rose-500/25 text-rose-400 ring-1 ring-rose-500/20 text-sm font-semibold transition-colors disabled:opacity-50"
              >
                <X className="w-4 h-4" /> {t('applications.reject')}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  )
}

// Resume / avatar paths come back as `/uploads/...`. Resolve against the
// admin's API origin so they resolve in the iframe regardless of the
// dev proxy or production CDN.
//
// Reads VITE_API_BASE_URL (the canonical env var used by api/client.ts
// + everywhere else). An earlier version read VITE_API_BASE (no _URL
// suffix) which is never set, so absoluteUrl silently returned the raw
// `/uploads/...` path. Browsers then resolved that against
// http://localhost:5174 (the Vite dev server) which serves the SPA's
// index.html as a fallback for unknown paths — the <img> rendered as
// "broken image" because the HTML wasn't a valid JPG.
function absoluteUrl(path) {
  if (!path) return ''
  if (path.startsWith('http')) return path
  const base = import.meta.env?.VITE_API_BASE_URL || ''
  // Trim trailing /api so `/uploads/...` lands at the static mount.
  const origin = base.replace(/\/api\/?$/, '')
  return `${origin}${path}`
}

function relativeTime(date, t, locale) {
  const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000))
  if (seconds < 60) return t('applications.secondsAgo', { n: seconds })
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return t('applications.minutesAgo', { n: minutes })
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return t('applications.hoursAgo', { n: hours })
  const days = Math.floor(hours / 24)
  if (days < 7) return t('applications.daysAgo', { n: days })
  return fmtDate(date, locale)
}
