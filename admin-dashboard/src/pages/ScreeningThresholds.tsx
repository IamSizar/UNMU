import { useEffect, useState } from 'react'
import { ShieldAlert, Loader2, AlertTriangle, CheckCircle2, Save } from 'lucide-react'
import { api, ApiError } from '../api/client'
import { useI18n } from '../i18n/I18nContext'

// Mirrors backend handlers.screeningThresholdsPayload.
interface Thresholds {
  debtFail: number
  debtWarn: number
  debtPass: number
  debtGood: number
  haramFail: number
  haramWarn: number
  haramPass: number
  haramGood: number
}

export default function ScreeningThresholds() {
  const { t } = useI18n()
  const [saved, setSaved] = useState<Thresholds | null>(null)
  const [draft, setDraft] = useState<Thresholds | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [toast, setToast] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<Thresholds>('/admin/screening-thresholds')
      setSaved(res)
      setDraft(res)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('screening.loadFailed'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [])

  const isDirty = draft && saved && JSON.stringify(draft) !== JSON.stringify(saved)

  // Same ascending-order rule the backend enforces server-side — checked
  // here too so the Save button disables instead of round-tripping a
  // request the server will reject.
  const isValid =
    draft &&
    draft.debtGood >= 0 &&
    draft.debtPass >= draft.debtGood &&
    draft.debtWarn >= draft.debtPass &&
    draft.debtFail >= draft.debtWarn &&
    draft.debtFail <= 100 &&
    draft.haramGood >= 0 &&
    draft.haramPass >= draft.haramGood &&
    draft.haramWarn >= draft.haramPass &&
    draft.haramFail >= draft.haramWarn &&
    draft.haramFail <= 100

  function setField(key: keyof Thresholds, value: string) {
    if (!draft) return
    const num = Number(value)
    setDraft({ ...draft, [key]: Number.isFinite(num) ? num : draft[key] })
  }

  async function save() {
    if (!draft || !isValid) return
    setSaving(true)
    setError(null)
    try {
      const res = await api.put<Thresholds>('/admin/screening-thresholds', draft)
      setSaved(res)
      setDraft(res)
      setToast(t('screening.saved'))
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('screening.saveFailed'))
    } finally {
      setSaving(false)
    }
  }

  useEffect(() => {
    if (!toast) return
    const timer = setTimeout(() => setToast(null), 3000)
    return () => clearTimeout(timer)
  }, [toast])

  return (
    <div className="max-w-3xl mx-auto p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-100">{t('screening.title')}</h1>
        <p className="text-sm text-slate-400 mt-1">{t('screening.subtitle')}</p>
      </div>

      <div className="rounded-xl border border-amber-500/20 bg-amber-500/10 p-4 flex gap-3">
        <ShieldAlert className="h-5 w-5 text-amber-400 shrink-0 mt-0.5" />
        <p className="text-sm text-amber-200">{t('screening.reviewWarning')}</p>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-16 text-slate-400">
          <Loader2 className="h-6 w-6 animate-spin" />
        </div>
      ) : error && !draft ? (
        <div className="rounded-xl border border-rose-500/20 bg-rose-500/10 p-4 flex items-center gap-3">
          <AlertTriangle className="h-5 w-5 text-rose-400" />
          <span className="text-sm text-rose-200">{error}</span>
          <button
            onClick={load}
            className="ml-auto text-sm text-rose-300 underline hover:text-rose-100"
          >
            {t('screening.retry')}
          </button>
        </div>
      ) : draft ? (
        <>
          <ThresholdGroup
            title={t('screening.debtGroupTitle')}
            subtitle={t('screening.debtGroupSubtitle')}
            fields={[
              { key: 'debtGood', label: t('screening.debtGood') },
              { key: 'debtPass', label: t('screening.debtPass') },
              { key: 'debtWarn', label: t('screening.debtWarn') },
              { key: 'debtFail', label: t('screening.debtFail') },
            ]}
            draft={draft}
            onChange={setField}
          />
          <ThresholdGroup
            title={t('screening.haramGroupTitle')}
            subtitle={t('screening.haramGroupSubtitle')}
            fields={[
              { key: 'haramGood', label: t('screening.haramGood') },
              { key: 'haramPass', label: t('screening.haramPass') },
              { key: 'haramWarn', label: t('screening.haramWarn') },
              { key: 'haramFail', label: t('screening.haramFail') },
            ]}
            draft={draft}
            onChange={setField}
          />

          {!isValid && (
            <div className="rounded-xl border border-rose-500/20 bg-rose-500/10 p-3 text-sm text-rose-200">
              {t('screening.invalidOrder')}
            </div>
          )}
          {error && (
            <div className="rounded-xl border border-rose-500/20 bg-rose-500/10 p-3 text-sm text-rose-200">
              {error}
            </div>
          )}

          <div className="flex items-center gap-3">
            <button
              onClick={save}
              disabled={!isDirty || !isValid || saving}
              className="inline-flex items-center gap-2 rounded-lg bg-cyan-600 px-4 py-2 text-sm font-medium text-white disabled:opacity-40 disabled:cursor-not-allowed hover:bg-cyan-500 transition"
            >
              {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
              {t('screening.save')}
            </button>
            {toast && (
              <span className="inline-flex items-center gap-1.5 text-sm text-emerald-400">
                <CheckCircle2 className="h-4 w-4" />
                {toast}
              </span>
            )}
          </div>
        </>
      ) : null}
    </div>
  )
}

function ThresholdGroup({
  title,
  subtitle,
  fields,
  draft,
  onChange,
}: {
  title: string
  subtitle: string
  fields: Array<{ key: keyof Thresholds; label: string }>
  draft: Thresholds
  onChange: (key: keyof Thresholds, value: string) => void
}) {
  return (
    <div className="rounded-xl border border-slate-700/50 bg-slate-800/40 p-5 space-y-4">
      <div>
        <h2 className="text-sm font-semibold text-slate-200">{title}</h2>
        <p className="text-xs text-slate-500 mt-0.5">{subtitle}</p>
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        {fields.map((f) => (
          <label key={f.key} className="block">
            <span className="block text-xs text-slate-400 mb-1">{f.label}</span>
            <div className="relative">
              <input
                type="number"
                inputMode="decimal"
                min={0}
                max={100}
                step={0.5}
                value={draft[f.key]}
                onChange={(e) => onChange(f.key, e.target.value)}
                className="w-full rounded-lg border border-slate-700 bg-slate-900/60 px-3 py-2 text-sm text-slate-100 focus:outline-none focus:ring-2 focus:ring-cyan-500/50"
              />
              <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-slate-500">
                %
              </span>
            </div>
          </label>
        ))}
      </div>
    </div>
  )
}
