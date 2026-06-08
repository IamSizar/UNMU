import { useEffect, useState } from 'react'
import {
  Plus,
  Copy,
  Edit,
  Trash2,
  TicketPercent,
  Loader2,
  AlertTriangle,
  CheckCircle2,
  X,
} from 'lucide-react'
import { api, ApiError } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtDate, fmtNum } from '../i18n/datefmt'

// Mirrors backend models.PromoCodeJSON.
//   /** @typedef {Object} Promo
//    * @property {number} id
//    * @property {string} code
//    * @property {'PERCENTAGE'|'FIXED'} discountType
//    * @property {number} discountValue
//    * @property {number|null} maxUses
//    * @property {number} usedCount
//    * @property {boolean} isActive
//    * @property {string|null} validFrom
//    * @property {string|null} validUntil
//    * @property {string} createdAt
//    */

function statusOf(p) {
  if (!p.isActive) return 'Paused'
  const now = new Date()
  if (p.validFrom && new Date(p.validFrom) > now) return 'Scheduled'
  if (p.validUntil && new Date(p.validUntil) < now) return 'Expired'
  return 'Active'
}

const STATUS_STYLES = {
  Active: 'bg-emerald-500/15 text-emerald-400 ring-emerald-500/20',
  Paused: 'bg-slate-500/15 text-slate-400 ring-slate-500/20',
  Expired: 'bg-rose-500/15 text-rose-400 ring-rose-500/20',
  Scheduled: 'bg-cyan-500/15 text-cyan-400 ring-cyan-500/20',
}

const STATUS_TKEY = {
  Active: 'promos.status.active',
  Paused: 'promos.status.paused',
  Expired: 'promos.status.expired',
  Scheduled: 'promos.status.scheduled',
}

function formatDiscount(p) {
  if (p.discountType === 'PERCENTAGE') {
    return `${Math.round(p.discountValue)}%`
  }
  // FIXED — USD cents-less amount in the discount_value column.
  return `$${p.discountValue.toFixed(2)}`
}

function formatDate(iso, locale) {
  if (!iso) return '—'
  try {
    return fmtDate(iso, locale)
  } catch {
    return iso
  }
}

export default function Promos() {
  const { t, locale } = useI18n()
  const [promos, setPromos] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [editing, setEditing] = useState(null)
  const [creating, setCreating] = useState(false)
  const [busy, setBusy] = useState(null)
  const [toast, setToast] = useState(null)

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const res = await api.get('/admin/promos')
      setPromos(res.promos ?? [])
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('promos.loadFailed'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [])

  const activeCount = promos.filter((p) => statusOf(p) === 'Active').length
  const totalRedemptions = promos.reduce((s, p) => s + (p.usedCount || 0), 0)

  async function remove(p) {
    if (!confirm(t('promos.confirmDelete', { code: p.code }))) return
    setBusy(p.id)
    try {
      await api.delete(`/admin/promos/${p.id}`)
      setPromos((prev) => prev.filter((x) => x.id !== p.id))
      setToast(t('promos.deleted', { code: p.code }))
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('promos.deleteFailed'))
    } finally {
      setBusy(null)
    }
  }

  async function copy(p) {
    try {
      await navigator.clipboard.writeText(p.code)
      setToast(t('promos.copied', { code: p.code }))
    } catch {
      setToast(t('promos.copyBlocked'))
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            {t('promos.title')}
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            {t('promos.subtitle', {
              active: activeCount,
              total: promos.length,
              redemptions: fmtNum(totalRedemptions),
            })}
          </p>
        </div>
        <button
          onClick={() => setCreating(true)}
          className="btn-primary whitespace-nowrap"
        >
          <Plus className="w-4 h-4" />
          <span className="hidden sm:inline">{t('promos.newCode')}</span>
          <span className="sm:hidden">{t('promos.new')}</span>
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

      <div className="card overflow-hidden">
        {loading ? (
          <div className="p-8 flex items-center justify-center text-slate-500 text-sm">
            <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('promos.loading')}
          </div>
        ) : promos.length === 0 ? (
          <div className="p-8 text-center text-sm text-slate-500">
            <TicketPercent className="w-10 h-10 mx-auto mb-3 opacity-40" />
            <p className="mb-4">{t('promos.empty')}</p>
            <button onClick={() => setCreating(true)} className="btn-primary">
              <Plus className="w-4 h-4" /> {t('promos.createFirst')}
            </button>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-white/[0.02]">
                <tr className="text-start text-[11px] text-slate-500 uppercase tracking-wider">
                  <th className="px-3 sm:px-5 py-3 font-medium">{t('promos.col.code')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium">{t('promos.col.discount')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden md:table-cell">
                    {t('promos.col.usage')}
                  </th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden lg:table-cell">
                    {t('promos.col.validity')}
                  </th>
                  <th className="px-3 sm:px-5 py-3 font-medium">{t('promos.col.status')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {promos.map((p) => {
                  const status = statusOf(p)
                  const pct = p.maxUses
                    ? Math.min(100, (p.usedCount / p.maxUses) * 100)
                    : null
                  return (
                    <tr
                      key={p.id}
                      className="border-t border-white/5 hover:bg-white/[0.02]"
                    >
                      <td className="px-3 sm:px-5 py-3">
                        <div className="flex items-center gap-2 min-w-0">
                          <div className="w-8 h-8 rounded-lg bg-cyan-500/15 ring-1 ring-cyan-500/20 flex items-center justify-center shrink-0">
                            <TicketPercent className="w-4 h-4 text-cyan-400" />
                          </div>
                          <span className="font-mono font-bold text-white truncate">
                            {p.code}
                          </span>
                          <button
                            onClick={() => copy(p)}
                            className="p-1 rounded-md hover:bg-white/5 text-slate-500 hover:text-white shrink-0 hidden sm:block"
                            title={t('promos.copy')}
                          >
                            <Copy className="w-3.5 h-3.5" />
                          </button>
                        </div>
                        {p.scope && p.scope !== 'all' && (
                          <span className="inline-block mt-1 text-[10px] uppercase tracking-wide font-bold text-cyan-300/80">
                            {p.scope === 'expert'
                              ? t('promos.scope.expert')
                              : t('promos.scope.community')}
                          </span>
                        )}
                      </td>
                      <td className="px-3 sm:px-5 py-3">
                        <span className="chip bg-gold-500/15 text-gold-400 ring-gold-500/20 font-bold whitespace-nowrap">
                          {t('promos.off', { value: formatDiscount(p) })}
                        </span>
                      </td>
                      <td className="px-3 sm:px-5 py-3 hidden md:table-cell">
                        <div className="text-xs text-slate-300 mb-1 whitespace-nowrap">
                          {p.usedCount} / {p.maxUses ?? '∞'}
                        </div>
                        {pct !== null && (
                          <div className="h-1.5 w-24 lg:w-32 rounded-full bg-white/5 overflow-hidden">
                            <div
                              className="h-full bg-gradient-to-r from-cyan-500 to-cyan-400"
                              style={{ width: `${pct}%` }}
                            />
                          </div>
                        )}
                      </td>
                      <td className="px-3 sm:px-5 py-3 text-slate-400 text-xs hidden lg:table-cell whitespace-nowrap">
                        {formatDate(p.validFrom, locale)} → {formatDate(p.validUntil, locale)}
                      </td>
                      <td className="px-3 sm:px-5 py-3">
                        <span className={`chip ${STATUS_STYLES[status]}`}>
                          {t(STATUS_TKEY[status])}
                        </span>
                      </td>
                      <td className="px-3 sm:px-5 py-3">
                        <div className="flex items-center gap-1 justify-end">
                          <button
                            onClick={() => setEditing(p)}
                            disabled={busy === p.id}
                            className="p-1.5 rounded-md hover:bg-white/5 text-slate-500 hover:text-white disabled:opacity-50"
                          >
                            <Edit className="w-4 h-4" />
                          </button>
                          <button
                            onClick={() => remove(p)}
                            disabled={busy === p.id}
                            className="p-1.5 rounded-md hover:bg-rose-500/10 text-slate-500 hover:text-rose-400 disabled:opacity-50"
                          >
                            {busy === p.id ? (
                              <Loader2 className="w-4 h-4 animate-spin" />
                            ) : (
                              <Trash2 className="w-4 h-4" />
                            )}
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {(creating || editing) && (
        <PromoEditor
          initial={editing}
          onCancel={() => {
            setCreating(false)
            setEditing(null)
          }}
          onSaved={(saved, isNew) => {
            setCreating(false)
            setEditing(null)
            if (isNew) setPromos((prev) => [saved, ...prev])
            else
              setPromos((prev) =>
                prev.map((x) => (x.id === saved.id ? saved : x)),
              )
            setToast(
              isNew
                ? t('promos.created', { code: saved.code })
                : t('promos.updated', { code: saved.code }),
            )
          }}
        />
      )}
    </div>
  )
}

function PromoEditor({ initial, onCancel, onSaved }) {
  const { t } = useI18n()
  const [code, setCode] = useState(initial?.code ?? '')
  const [discountType, setDiscountType] = useState(
    initial?.discountType ?? 'PERCENTAGE',
  )
  const [discountValue, setDiscountValue] = useState(
    initial?.discountValue?.toString() ?? '',
  )
  // Scope — which kind of purchase the code applies to.
  const [scope, setScope] = useState(initial?.scope ?? 'all')
  const [maxUses, setMaxUses] = useState(
    initial?.maxUses?.toString() ?? '',
  )
  const [isActive, setIsActive] = useState(initial?.isActive ?? true)
  const [validFrom, setValidFrom] = useState(
    initial?.validFrom ? initial.validFrom.slice(0, 10) : '',
  )
  const [validUntil, setValidUntil] = useState(
    initial?.validUntil ? initial.validUntil.slice(0, 10) : '',
  )
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState(null)

  async function save() {
    setError(null)
    const codeTrimmed = code.trim()
    if (!codeTrimmed) {
      setError(t('promos.error.codeRequired'))
      return
    }
    const value = parseFloat(discountValue)
    if (!discountValue || isNaN(value) || value <= 0) {
      setError(t('promos.error.valueGreater'))
      return
    }
    if (discountType === 'PERCENTAGE' && value > 100) {
      setError(t('promos.error.percentMax'))
      return
    }
    const maxUsesParsed = maxUses === '' ? null : parseInt(maxUses, 10)
    if (maxUses !== '' && (isNaN(maxUsesParsed) || maxUsesParsed < 0)) {
      setError(t('promos.error.maxUses'))
      return
    }

    setSaving(true)
    try {
      const body = {
        code: codeTrimmed.toUpperCase(),
        discountType,
        discountValue: value,
        scope,
        maxUses: maxUsesParsed === null ? 0 : maxUsesParsed,
        isActive,
        validFrom,
        validUntil,
      }
      const saved = initial
        ? await api.patch(`/admin/promos/${initial.id}`, body)
        : await api.post('/admin/promos', body)
      onSaved(saved, !initial)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('promos.saveFailed'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div className="card w-full max-w-md p-5 sm:p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-semibold text-white">
            {initial ? t('promos.editTitle') : t('promos.newTitle')}
          </h3>
          <button
            onClick={onCancel}
            className="text-slate-400 hover:text-white"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="space-y-3">
          <Field label={t('promos.field.code')} required>
            <input
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              className="input font-mono"
              maxLength={32}
              placeholder="EID25"
            />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t('promos.field.discountType')} required>
              <select
                value={discountType}
                onChange={(e) => setDiscountType(e.target.value)}
                className="input"
              >
                <option value="PERCENTAGE">{t('promos.type.percentage')}</option>
                <option value="FIXED">{t('promos.type.fixed')}</option>
              </select>
            </Field>
            <Field
              label={
                discountType === 'PERCENTAGE'
                  ? t('promos.field.discountPercent')
                  : t('promos.field.discountUsd')
              }
              required
            >
              <input
                type="number"
                value={discountValue}
                onChange={(e) => setDiscountValue(e.target.value)}
                className="input"
                step="0.01"
                min="0"
                placeholder={discountType === 'PERCENTAGE' ? '25' : '10.00'}
              />
            </Field>
          </div>
          <Field label={t('promos.field.scope')}>
            <select
              value={scope}
              onChange={(e) => setScope(e.target.value)}
              className="input"
            >
              <option value="all">{t('promos.scope.all')}</option>
              <option value="expert">{t('promos.scope.expert')}</option>
              <option value="community">{t('promos.scope.community')}</option>
            </select>
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t('promos.field.maxUses')}>
              <input
                type="number"
                value={maxUses}
                onChange={(e) => setMaxUses(e.target.value)}
                className="input"
                min="0"
                placeholder="∞"
              />
            </Field>
            <Field label={t('promos.field.status')}>
              <select
                value={isActive ? 'active' : 'paused'}
                onChange={(e) => setIsActive(e.target.value === 'active')}
                className="input"
              >
                <option value="active">{t('promos.option.active')}</option>
                <option value="paused">{t('promos.option.paused')}</option>
              </select>
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label={t('promos.field.validFrom')}>
              <input
                type="date"
                value={validFrom}
                onChange={(e) => setValidFrom(e.target.value)}
                className="input"
              />
            </Field>
            <Field label={t('promos.field.validUntil')}>
              <input
                type="date"
                value={validUntil}
                onChange={(e) => setValidUntil(e.target.value)}
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
                t('promos.saveChanges')
              ) : (
                t('promos.createCode')
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

function Field({ label, required, children }) {
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
