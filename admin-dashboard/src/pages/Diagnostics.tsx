import { useEffect, useState } from 'react'
import {
  CheckCircle2,
  XCircle,
  RefreshCw,
  Link as LinkIcon,
  Share2,
  AlertTriangle,
} from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDateTime } from '../i18n/datefmt'

// ── Deep-link diagnostics ─────────────────────────────────────────────

type DeepLinkCheck = {
  host: string
  url: string
  reachable: boolean
  statusCode: number
  contentType: string
  bodyBytes: number
  jsonValid: boolean
  error?: string
  bundleIdOk?: boolean
  packageIdOk?: boolean
  fingerprintOk?: boolean
}
type DeepLinkResponse = {
  checks: DeepLinkCheck[]
  checkedAt: string
}

// ── Events summary ────────────────────────────────────────────────────

type SummaryRow = { eventType: string; count: number }
type SummaryResponse = {
  windowHours: number
  counts: SummaryRow[]
}

// Maps each event type to its translation key (resolved at render).
const EVENT_LABEL: Record<string, string> = {
  share_tapped: 'diag.events.shareTapped',
  deep_link_opened: 'diag.events.deepLinkOpened',
  reel_load_failed: 'diag.events.reelLoadFailed',
}

/**
 * Diagnostics — admin operational dashboard for the things we shipped
 * today:
 *
 *   * Universal Link / App Link reachability — server-side fetches the
 *     well-known files and validates appID / package / SHA-256.
 *   * Engagement & reliability events — share taps, deep-link opens,
 *     reel-load failures, in 24h / 7d / 30d windows.
 *
 * Lives under /diagnostics in the admin nav.
 */
export default function Diagnostics() {
  const { t } = useI18n()
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-white">{t('diag.title')}</h1>
        <p className="text-sm text-slate-400 mt-1">{t('diag.subtitle')}</p>
      </div>

      <DeepLinksPanel />
      <EventsPanel />
    </div>
  )
}

// ──────────────────────────────────────────────────────────────────────
// Deep-link verification panel
// ──────────────────────────────────────────────────────────────────────

function DeepLinksPanel() {
  const { t, locale } = useI18n()
  const [data, setData] = useState<DeepLinkResponse | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<DeepLinkResponse>('/admin/diagnostics/deep-links')
      setData(res)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [])

  return (
    <section className="space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <LinkIcon className="w-5 h-5 text-cyan-300" />
          <h2 className="text-lg font-semibold text-white">
            {t('diag.deepLinks.title')}
          </h2>
        </div>
        <button
          onClick={load}
          disabled={loading}
          className="flex items-center gap-2 px-3 py-1.5 rounded-md bg-white/5 hover:bg-white/10 text-slate-300 text-xs ring-1 ring-white/10 disabled:opacity-50"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
          {t('diag.deepLinks.recheck')}
        </button>
      </div>

      <p className="text-xs text-slate-500">{t('diag.deepLinks.help')}</p>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm">
          {error}
        </div>
      )}

      {data && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {data.checks.map((c) => (
            <DeepLinkCard key={`${c.host}-${c.url}`} check={c} />
          ))}
        </div>
      )}

      {data && (
        <p className="text-xs text-slate-500">
          {t('diag.deepLinks.lastChecked', { time: fmtDateTime(data.checkedAt, locale) })}
        </p>
      )}
    </section>
  )
}

function DeepLinkCard({ check }: { check: DeepLinkCheck }) {
  const { t } = useI18n()
  const isAASA = check.url.endsWith('apple-app-site-association')
  const passed = isAASA
    ? check.bundleIdOk === true
    : check.packageIdOk === true && check.fingerprintOk === true

  return (
    <div
      className={`rounded-xl p-4 ring-1 ${
        passed
          ? 'bg-emerald-500/5 ring-emerald-500/20'
          : 'bg-rose-500/5 ring-rose-500/20'
      }`}
    >
      <div className="flex items-start gap-3">
        {passed ? (
          <CheckCircle2 className="w-5 h-5 text-emerald-400 mt-0.5" />
        ) : (
          <XCircle className="w-5 h-5 text-rose-400 mt-0.5" />
        )}
        <div className="flex-1 min-w-0">
          <p className="font-semibold text-white">
            {isAASA ? t('diag.deepLinks.ios') : t('diag.deepLinks.android')} · {check.host}
          </p>
          <p className="text-xs text-slate-500 truncate font-mono mt-0.5">
            {check.url}
          </p>
          <ul className="mt-3 space-y-1 text-xs">
            <CheckRow ok={check.reachable} label={t('diag.deepLinks.reachable', { code: check.statusCode || '—' })} />
            <CheckRow ok={check.jsonValid} label={t('diag.deepLinks.validJson')} />
            {isAASA ? (
              <CheckRow ok={check.bundleIdOk === true} label={t('diag.deepLinks.bundleMatch')} />
            ) : (
              <>
                <CheckRow ok={check.packageIdOk === true} label={t('diag.deepLinks.packageMatch')} />
                <CheckRow ok={check.fingerprintOk === true} label={t('diag.deepLinks.fingerprintMatch')} />
              </>
            )}
          </ul>
          {check.error && (
            <p className="mt-2 text-xs text-rose-300 flex items-center gap-1">
              <AlertTriangle className="w-3.5 h-3.5" />
              {check.error}
            </p>
          )}
        </div>
      </div>
    </div>
  )
}

function CheckRow({ ok, label }: { ok: boolean; label: string }) {
  return (
    <li className="flex items-center gap-2 text-slate-300">
      {ok ? (
        <CheckCircle2 className="w-3.5 h-3.5 text-emerald-400" />
      ) : (
        <XCircle className="w-3.5 h-3.5 text-rose-400" />
      )}
      <span className={ok ? 'text-slate-300' : 'text-slate-400'}>{label}</span>
    </li>
  )
}

// ──────────────────────────────────────────────────────────────────────
// Engagement / reliability events panel
// ──────────────────────────────────────────────────────────────────────

function EventsPanel() {
  const { t } = useI18n()
  const [window, setWindow] = useState<'24h' | '7d' | '30d'>('24h')
  const [data, setData] = useState<SummaryResponse | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function load(w: typeof window) {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<SummaryResponse>(
        `/admin/events/summary?window=${w}`,
      )
      setData(res)
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load(window)
  }, [window])

  // Make sure every event type appears even when count is 0 — admin
  // shouldn't need to remember "huh, no shares means the row is just
  // missing".
  const merged = ['share_tapped', 'deep_link_opened', 'reel_load_failed'].map(
    (t) => ({
      eventType: t,
      count: data?.counts.find((c) => c.eventType === t)?.count ?? 0,
    }),
  )

  return (
    <section className="space-y-3">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Share2 className="w-5 h-5 text-cyan-300" />
          <h2 className="text-lg font-semibold text-white">
            {t('diag.events.title')}
          </h2>
        </div>
        <div className="flex items-center gap-1 bg-white/5 rounded-lg p-1 ring-1 ring-white/10">
          {(['24h', '7d', '30d'] as const).map((w) => (
            <button
              key={w}
              onClick={() => setWindow(w)}
              className={`px-2.5 py-1 rounded-md text-xs font-medium ${
                window === w
                  ? 'bg-cyan-500/20 text-cyan-300 ring-1 ring-cyan-500/30'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {w}
            </button>
          ))}
        </div>
      </div>

      <p className="text-xs text-slate-500">{t('diag.events.help')}</p>

      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-3 py-2 text-rose-300 text-sm">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {merged.map((row) => (
          <EventCard
            key={row.eventType}
            label={t(EVENT_LABEL[row.eventType] as Parameters<typeof t>[0])}
            count={row.count}
            tone={row.eventType === 'reel_load_failed' ? 'rose' : 'cyan'}
          />
        ))}
      </div>
      {loading && (
        <p className="text-xs text-slate-500">{t('common.loading')}</p>
      )}
    </section>
  )
}

function EventCard({
  label,
  count,
  tone,
}: {
  label: string
  count: number
  tone: 'cyan' | 'rose'
}) {
  const isRose = tone === 'rose'
  return (
    <div
      className={`rounded-xl p-4 ring-1 ${
        isRose
          ? count > 0
            ? 'bg-rose-500/5 ring-rose-500/20'
            : 'bg-emerald-500/5 ring-emerald-500/20'
          : 'bg-white/[0.02] ring-white/5'
      }`}
    >
      <p className="text-xs text-slate-400">{label}</p>
      <p
        className={`mt-1 text-3xl font-bold ${
          isRose
            ? count > 0
              ? 'text-rose-300'
              : 'text-emerald-300'
            : 'text-white'
        }`}
      >
        {count}
      </p>
    </div>
  )
}
