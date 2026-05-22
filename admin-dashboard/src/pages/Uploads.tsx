import { useEffect, useState } from 'react'
import { Trash2, RefreshCw, HardDrive, Clock } from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDateTime } from '../i18n/datefmt'

// Shape returned by `GET /admin/uploads/in-flight`. Each row is one
// staging directory under `uploads/.tmp/<uploadId>/` left over from a
// chunked video upload that hasn't called /complete (or has been
// abandoned mid-flight).
type InFlightUpload = {
  uploadId: string
  chunks: number
  bytes: number
  startedAt: string
  lastChunkAt: string
  ageHours: number
}

type ListResponse = { uploads: InFlightUpload[] }
type SweepResponse = { removed: string[]; bytesReclaimed: number }

function formatBytes(b: number): string {
  if (b < 1024) return `${b} B`
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(1)} KB`
  if (b < 1024 * 1024 * 1024) return `${(b / 1024 / 1024).toFixed(1)} MB`
  return `${(b / 1024 / 1024 / 1024).toFixed(2)} GB`
}

function formatAge(hours: number): string {
  if (hours < 1) return `${Math.round(hours * 60)} min`
  if (hours < 24) return `${hours.toFixed(1)} h`
  return `${(hours / 24).toFixed(1)} d`
}

/**
 * Uploads — admin monitor for chunked video uploads in flight.
 *
 * The chunked-upload endpoint stages bytes under
 * `uploads/.tmp/<uploadId>/` until /complete fires. Successful uploads
 * delete the staging dir on completion; abandoned uploads (user killed
 * the app, network died) leave it behind. The init endpoint sweeps
 * dirs older than 24h opportunistically — this page lets admin see
 * what's in flight + force a sweep with a smaller cutoff if needed.
 */
export default function Uploads() {
  const { t, locale } = useI18n()
  const [rows, setRows] = useState<InFlightUpload[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [sweepResult, setSweepResult] = useState<SweepResponse | null>(null)
  const [minAgeHours, setMinAgeHours] = useState(24)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<ListResponse>('/admin/uploads/in-flight')
      setRows(res.uploads ?? [])
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  async function sweep() {
    setLoading(true)
    setError(null)
    setSweepResult(null)
    try {
      const res = await api.post<SweepResponse>('/admin/uploads/sweep', {
        minAgeHours,
      })
      setSweepResult(res)
      await load()
    } catch (e) {
      setError((e as Error).message)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [])

  // Bytes total across every in-flight dir — loud number at the top so
  // admin can see at a glance whether staging is leaking storage.
  const totalBytes = rows.reduce((acc, r) => acc + r.bytes, 0)
  const totalChunks = rows.reduce((acc, r) => acc + r.chunks, 0)

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">{t('uploads.title')}</h1>
          <p className="text-sm text-slate-400 mt-1">{t('uploads.subtitle')}</p>
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

      {/* ── Top stat strip ─────────────────────────────────────────── */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <StatCard
          icon={<HardDrive className="w-5 h-5 text-cyan-300" />}
          label={t('uploads.stat.inFlight')}
          value={rows.length.toString()}
        />
        <StatCard
          icon={<HardDrive className="w-5 h-5 text-gold-400" />}
          label={t('uploads.stat.chunks')}
          value={totalChunks.toString()}
        />
        <StatCard
          icon={<HardDrive className="w-5 h-5 text-emerald-400" />}
          label={t('uploads.stat.disk')}
          value={formatBytes(totalBytes)}
        />
      </div>

      {/* ── Sweep panel ────────────────────────────────────────────── */}
      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 p-4 space-y-3">
        <div className="flex items-center gap-2 text-slate-200 font-semibold">
          <Trash2 className="w-4 h-4 text-rose-400" />
          {t('uploads.sweep.title')}
        </div>
        <p className="text-xs text-slate-500 leading-relaxed">
          {t('uploads.sweep.help')}
        </p>
        <div className="flex items-center gap-3">
          <label className="text-xs text-slate-400">{t('uploads.sweep.minAge')}</label>
          <input
            type="number"
            min={1}
            value={minAgeHours}
            onChange={(e) => setMinAgeHours(Number(e.target.value))}
            className="w-20 px-2 py-1 rounded-md bg-midnight-700 ring-1 ring-white/10 text-slate-200 text-sm"
          />
          <button
            onClick={sweep}
            disabled={loading}
            className="px-3 py-1.5 rounded-md bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 text-sm font-medium ring-1 ring-rose-500/30 disabled:opacity-50"
          >
            {t('uploads.sweep.run')}
          </button>
          {sweepResult && (
            <span className="text-xs text-emerald-400">
              {t('uploads.sweep.result', {
                count: sweepResult.removed.length,
                bytes: formatBytes(sweepResult.bytesReclaimed),
              })}
            </span>
          )}
        </div>
      </div>

      {/* ── Rows ───────────────────────────────────────────────────── */}
      {error && (
        <div className="rounded-lg bg-rose-500/10 ring-1 ring-rose-500/30 px-4 py-3 text-rose-300 text-sm">
          {error}
        </div>
      )}

      <div className="rounded-xl bg-white/[0.02] ring-1 ring-white/5 overflow-hidden">
        <table className="w-full text-sm">
          <thead className="text-xs text-slate-500 bg-white/[0.02]">
            <tr>
              <th className="text-start px-4 py-3 font-medium">{t('uploads.col.uploadId')}</th>
              <th className="text-start px-4 py-3 font-medium">{t('uploads.col.chunks')}</th>
              <th className="text-start px-4 py-3 font-medium">{t('uploads.col.size')}</th>
              <th className="text-start px-4 py-3 font-medium">{t('uploads.col.started')}</th>
              <th className="text-start px-4 py-3 font-medium">{t('uploads.col.age')}</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && !loading && (
              <tr>
                <td colSpan={5} className="text-center py-10 text-slate-500">
                  {t('uploads.empty')}
                </td>
              </tr>
            )}
            {rows.map((r) => (
              <tr key={r.uploadId} className="border-t border-white/5">
                <td className="px-4 py-3 font-mono text-xs text-slate-300">
                  {r.uploadId.slice(0, 8)}…{r.uploadId.slice(-4)}
                </td>
                <td className="px-4 py-3 text-slate-300">{r.chunks}</td>
                <td className="px-4 py-3 text-slate-300">{formatBytes(r.bytes)}</td>
                <td className="px-4 py-3 text-slate-400 text-xs">
                  {fmtDateTime(r.startedAt, locale)}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs font-medium ${
                      r.ageHours > 24
                        ? 'bg-rose-500/15 text-rose-300 ring-1 ring-rose-500/30'
                        : r.ageHours > 1
                        ? 'bg-gold-500/15 text-gold-300 ring-1 ring-gold-500/30'
                        : 'bg-emerald-500/15 text-emerald-300 ring-1 ring-emerald-500/30'
                    }`}
                  >
                    <Clock className="w-3 h-3" />
                    {formatAge(r.ageHours)}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function StatCard({
  icon,
  label,
  value,
}: {
  icon: React.ReactNode
  label: string
  value: string
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
