import { useEffect, useState } from 'react'
import {
  Plus,
  Megaphone,
  Edit,
  Trash2,
  Loader2,
  AlertTriangle,
  CheckCircle2,
  Globe,
  Power,
  PowerOff,
  X,
} from 'lucide-react'
import { api, ApiError } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate } from '../i18n/datefmt'

// Mirrors the backend models.AdJSON shape (handlers/ads.go).
type Ad = {
  id: number
  companyName: string
  title: string
  description?: string | null
  imageUrl?: string | null
  targetUrl?: string | null
  regionCode?: string | null
  isActive: boolean
  startDate?: string | null
  endDate?: string | null
  createdAt: string
}

type ListResponse = { ads: Ad[] }

const REGION_OPTIONS = ['GLOBAL', 'MENA', 'GCC', 'US', 'EU', 'ASIA', 'AFRICA'] as const

// Banner gradient palette — purely visual, picked deterministically by
// ad id so cards don't reflow when the list updates.
const BANNER_TINTS = [
  'from-cyan-500 to-cyan-700',
  'from-gold-500 to-gold-700',
  'from-emerald-500 to-emerald-700',
  'from-violet-500 to-violet-700',
  'from-rose-500 to-rose-700',
  'from-blue-500 to-blue-700',
]

export default function Ads() {
  const { t } = useI18n()
  const [ads, setAds] = useState<Ad[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [editing, setEditing] = useState<Ad | null>(null)
  const [creating, setCreating] = useState(false)
  const [busy, setBusy] = useState<number | null>(null)
  const [toast, setToast] = useState<string | null>(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get<ListResponse>('/admin/ads')
      setAds(res.ads ?? [])
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('ads.loadFailed'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [])

  const activeCount = ads.filter((a) => a.isActive).length

  async function toggleActive(ad: Ad) {
    setBusy(ad.id)
    try {
      const updated = await api.patch<Ad>(`/admin/ads/${ad.id}`, {
        isActive: !ad.isActive,
      })
      setAds((prev) => prev.map((a) => (a.id === ad.id ? updated : a)))
      setToast(
        !ad.isActive
          ? t('ads.activated', { title: ad.title })
          : t('ads.paused', { title: ad.title }),
      )
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('ads.updateFailed'))
    } finally {
      setBusy(null)
    }
  }

  async function remove(ad: Ad) {
    if (!confirm(t('ads.confirmDelete', { title: ad.title }))) return
    setBusy(ad.id)
    try {
      await api.delete(`/admin/ads/${ad.id}`)
      setAds((prev) => prev.filter((a) => a.id !== ad.id))
      setToast(t('ads.deleted', { title: ad.title }))
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('ads.deleteFailed'))
    } finally {
      setBusy(null)
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            {t('ads.title')}
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            {t('ads.subtitle', { active: activeCount, total: ads.length })}
          </p>
        </div>
        <button
          onClick={() => setCreating(true)}
          className="btn-primary whitespace-nowrap"
        >
          <Plus className="w-4 h-4" />
          <span className="hidden sm:inline">{t('ads.create')}</span>
          <span className="sm:hidden">{t('ads.createShort')}</span>
        </button>
      </div>

      {error && (
        <div className="rounded-lg p-3 text-sm bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300 flex items-start gap-2">
          <AlertTriangle className="w-4 h-4 shrink-0 mt-0.5" />
          <div>{error}</div>
        </div>
      )}
      {toast && (
        <div className="rounded-lg p-3 text-sm bg-emerald-500/10 ring-1 ring-emerald-500/30 text-emerald-300 flex items-center gap-2">
          <CheckCircle2 className="w-4 h-4 shrink-0" />
          <div className="flex-1">{toast}</div>
          <button
            onClick={() => setToast(null)}
            className="text-emerald-300 hover:text-emerald-200"
          >
            <X className="w-3.5 h-3.5" />
          </button>
        </div>
      )}

      {loading ? (
        <div className="card p-8 flex items-center justify-center text-slate-500 text-sm">
          <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('ads.loading')}
        </div>
      ) : ads.length === 0 ? (
        <div className="card p-8 text-center text-sm text-slate-500">
          <Megaphone className="w-10 h-10 mx-auto mb-3 opacity-40" />
          <p className="mb-4">{t('ads.empty')}</p>
          <button onClick={() => setCreating(true)} className="btn-primary">
            <Plus className="w-4 h-4" /> {t('ads.createFirst')}
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 lg:gap-5">
          {ads.map((ad, idx) => (
            <AdCard
              key={ad.id}
              ad={ad}
              tint={BANNER_TINTS[idx % BANNER_TINTS.length]}
              busy={busy === ad.id}
              onEdit={() => setEditing(ad)}
              onDelete={() => remove(ad)}
              onToggle={() => toggleActive(ad)}
            />
          ))}
        </div>
      )}

      {(creating || editing) && (
        <AdEditor
          initial={editing}
          onCancel={() => {
            setCreating(false)
            setEditing(null)
          }}
          onSaved={(saved, isNew) => {
            setCreating(false)
            setEditing(null)
            if (isNew) setAds((prev) => [saved, ...prev])
            else setAds((prev) => prev.map((a) => (a.id === saved.id ? saved : a)))
            setToast(
              isNew
                ? t('ads.created', { title: saved.title })
                : t('ads.updated', { title: saved.title }),
            )
          }}
        />
      )}
    </div>
  )
}

function AdCard({
  ad,
  tint,
  busy,
  onEdit,
  onDelete,
  onToggle,
}: {
  ad: Ad
  tint: string
  busy: boolean
  onEdit: () => void
  onDelete: () => void
  onToggle: () => void
}) {
  const { t, locale } = useI18n()
  const statusChip = ad.isActive
    ? 'bg-emerald-500/15 text-emerald-300 ring-emerald-500/20'
    : 'bg-slate-500/15 text-slate-300 ring-slate-500/20'

  return (
    <div className="card overflow-hidden hover:border-cyan-500/30 transition-colors">
      <div
        className={`h-32 bg-gradient-to-br ${tint} relative flex items-center justify-center`}
      >
        <div className="absolute inset-0 bg-black/20" />
        {ad.imageUrl ? (
          <img
            src={ad.imageUrl}
            alt={ad.title}
            className="absolute inset-0 w-full h-full object-cover opacity-80"
          />
        ) : (
          <Megaphone className="w-12 h-12 text-white/40" />
        )}
        <span
          className={`absolute top-3 end-3 chip ${statusChip} backdrop-blur`}
        >
          {ad.isActive ? t('ads.status.active') : t('ads.status.paused')}
        </span>
        <span className="absolute top-3 start-3 chip bg-black/30 text-white ring-white/20 backdrop-blur inline-flex items-center gap-1">
          <Globe className="w-3 h-3" />
          {ad.regionCode || 'GLOBAL'}
        </span>
      </div>
      <div className="p-4 sm:p-5">
        <h3 className="font-semibold text-white line-clamp-2">{ad.title}</h3>
        <p className="text-xs text-slate-400 mt-1 truncate">{t('ads.by', { company: ad.companyName })}</p>
        {ad.description && (
          <p className="text-xs text-slate-500 mt-2 line-clamp-2">
            {ad.description}
          </p>
        )}

        <div className="grid grid-cols-2 gap-3 mt-4 pt-4 border-t border-white/5 text-xs">
          <div>
            <p className="text-[10px] uppercase tracking-wider text-slate-500">
              {t('ads.starts')}
            </p>
            <p className="text-slate-300 mt-0.5">
              {ad.startDate
                ? fmtDate(ad.startDate, locale)
                : '—'}
            </p>
          </div>
          <div>
            <p className="text-[10px] uppercase tracking-wider text-slate-500">
              {t('ads.ends')}
            </p>
            <p className="text-slate-300 mt-0.5">
              {ad.endDate ? fmtDate(ad.endDate, locale) : '—'}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 mt-4">
          <button
            onClick={onToggle}
            disabled={busy}
            className="flex-1 btn-secondary justify-center text-xs disabled:opacity-50"
          >
            {busy ? (
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
            ) : ad.isActive ? (
              <PowerOff className="w-3.5 h-3.5" />
            ) : (
              <Power className="w-3.5 h-3.5" />
            )}
            {ad.isActive ? t('ads.pause') : t('ads.activate')}
          </button>
          <button
            onClick={onEdit}
            disabled={busy}
            className="px-2.5 py-2 rounded-lg bg-white/5 hover:bg-white/10 border border-white/10 text-slate-400 hover:text-white disabled:opacity-50"
          >
            <Edit className="w-4 h-4" />
          </button>
          <button
            onClick={onDelete}
            disabled={busy}
            className="px-2.5 py-2 rounded-lg bg-white/5 hover:bg-rose-500/10 border border-white/10 text-slate-400 hover:text-rose-400 disabled:opacity-50"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  )
}

function AdEditor({
  initial,
  onCancel,
  onSaved,
}: {
  initial: Ad | null
  onCancel: () => void
  onSaved: (saved: Ad, isNew: boolean) => void
}) {
  const { t } = useI18n()
  const [companyName, setCompanyName] = useState(initial?.companyName ?? '')
  const [title, setTitle] = useState(initial?.title ?? '')
  const [description, setDescription] = useState(initial?.description ?? '')
  const [imageUrl, setImageUrl] = useState(initial?.imageUrl ?? '')
  const [targetUrl, setTargetUrl] = useState(initial?.targetUrl ?? '')
  const [regionCode, setRegionCode] = useState(initial?.regionCode ?? 'GLOBAL')
  const [isActive, setIsActive] = useState(initial?.isActive ?? true)
  const [startDate, setStartDate] = useState(
    initial?.startDate ? initial.startDate.slice(0, 10) : '',
  )
  const [endDate, setEndDate] = useState(
    initial?.endDate ? initial.endDate.slice(0, 10) : '',
  )
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save() {
    setError(null)
    if (!companyName.trim() || !title.trim()) {
      setError(t('ads.error.required'))
      return
    }
    setSaving(true)
    try {
      const body = {
        companyName: companyName.trim(),
        title: title.trim(),
        description,
        imageUrl,
        targetUrl,
        regionCode,
        isActive,
        startDate,
        endDate,
      }
      const saved = initial
        ? await api.patch<Ad>(`/admin/ads/${initial.id}`, body)
        : await api.post<Ad>('/admin/ads', body)
      onSaved(saved, !initial)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('ads.saveFailed'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div className="card w-full max-w-lg p-5 sm:p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-semibold text-white">
            {initial ? t('ads.editTitle') : t('ads.createTitle')}
          </h3>
          <button
            onClick={onCancel}
            className="text-slate-400 hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="space-y-3">
          <Field label={t('ads.field.companyName')} required>
            <input
              value={companyName}
              onChange={(e) => setCompanyName(e.target.value)}
              className="input"
              maxLength={120}
            />
          </Field>
          <Field label={t('ads.field.title')} required>
            <input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              className="input"
              maxLength={200}
            />
          </Field>
          <Field label={t('ads.field.description')}>
            <textarea
              value={description ?? ''}
              onChange={(e) => setDescription(e.target.value)}
              rows={2}
              className="input resize-none"
              maxLength={500}
            />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t('ads.field.region')}>
              <select
                value={regionCode ?? 'GLOBAL'}
                onChange={(e) => setRegionCode(e.target.value)}
                className="input"
              >
                {REGION_OPTIONS.map((r) => (
                  <option key={r} value={r}>
                    {r}
                  </option>
                ))}
              </select>
            </Field>
            <Field label={t('ads.field.status')}>
              <select
                value={isActive ? 'active' : 'paused'}
                onChange={(e) => setIsActive(e.target.value === 'active')}
                className="input"
              >
                <option value="active">{t('ads.option.active')}</option>
                <option value="paused">{t('ads.option.paused')}</option>
              </select>
            </Field>
          </div>
          <Field label={t('ads.field.imageUrl')}>
            <input
              value={imageUrl ?? ''}
              onChange={(e) => setImageUrl(e.target.value)}
              className="input"
              placeholder="https://…"
            />
          </Field>
          <Field label={t('ads.field.targetUrl')}>
            <input
              value={targetUrl ?? ''}
              onChange={(e) => setTargetUrl(e.target.value)}
              className="input"
              placeholder="https://…"
            />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t('ads.field.startDate')}>
              <input
                type="date"
                value={startDate}
                onChange={(e) => setStartDate(e.target.value)}
                className="input"
              />
            </Field>
            <Field label={t('ads.field.endDate')}>
              <input
                type="date"
                value={endDate}
                onChange={(e) => setEndDate(e.target.value)}
                className="input"
              />
            </Field>
          </div>

          {error && (
            <div className="text-rose-300 text-xs bg-rose-500/10 ring-1 ring-rose-500/30 rounded p-2">
              {error}
            </div>
          )}

          <div className="flex items-center gap-2 pt-2">
            <button
              onClick={onCancel}
              disabled={saving}
              className="flex-1 btn-secondary justify-center disabled:opacity-50"
            >
              {t('common.cancel')}
            </button>
            <button
              onClick={save}
              disabled={saving}
              className="flex-1 btn-primary justify-center disabled:opacity-50"
            >
              {saving ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : initial ? (
                t('ads.saveChanges')
              ) : (
                t('ads.createAd')
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

function Field({
  label,
  required,
  children,
}: {
  label: string
  required?: boolean
  children: React.ReactNode
}) {
  return (
    <div>
      <label className="block text-[10px] uppercase tracking-wider text-slate-500 mb-1.5">
        {label}
        {required && <span className="text-rose-400 ms-1">*</span>}
      </label>
      {children}
    </div>
  )
}
