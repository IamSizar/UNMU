import { useEffect, useMemo, useRef, useState } from 'react'
import {
  RefreshCw,
  ShieldCheck,
  ShieldX,
  ShieldQuestion,
  Loader2,
  AlertTriangle,
  CheckCircle2,
  X,
  Edit,
  Search,
} from 'lucide-react'
import { api, ApiError } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { fmtNum } from '../i18n/datefmt'

// Wire shape mirrors backend handlers/admin_stocks.go::adminStockRow.
type Stock = {
  id: number
  ticker: string
  exchange: string
  name: string
  region: string
  sector: string
  status: string // HALAL | MIXED | HARAM | DOUBTFUL | UNKNOWN
  grade: string // A | B | C | F | ""
  debtRatio: number // 0..100
  haramIncome: number // 0..100
  isActive: boolean
}

type ListResponse = {
  stocks: Stock[]
  total: number
  limit: number
  offset: number
}

type TotalsResponse = {
  total: number
  compliant: number
  mixed: number
  nonCompliant: number
  unknown: number
  byGrade: Record<string, number>
}

const STATUS_OPTIONS = ['HALAL', 'MIXED', 'DOUBTFUL', 'HARAM', 'UNKNOWN']
const GRADE_OPTIONS = ['A', 'B', 'C', 'F']

const STATUS_STYLES: Record<string, string> = {
  HALAL: 'bg-emerald-500/15 text-emerald-400 ring-emerald-500/20',
  MIXED: 'bg-gold-500/15 text-gold-400 ring-gold-500/20',
  DOUBTFUL: 'bg-gold-500/15 text-gold-400 ring-gold-500/20',
  HARAM: 'bg-rose-500/15 text-rose-400 ring-rose-500/20',
  UNKNOWN: 'bg-slate-500/15 text-slate-400 ring-slate-500/20',
}

// Maps backend status code → translation key suffix (resolved via t()
// at render so the label flips with the active locale).
const STATUS_LABEL_KEY: Record<string, string> = {
  HALAL: 'stocks.status.compliant',
  MIXED: 'stocks.status.mixed',
  DOUBTFUL: 'stocks.status.doubtful',
  HARAM: 'stocks.status.nonCompliant',
  UNKNOWN: 'stocks.status.unknown',
}

const GRADE_STYLES: Record<string, string> = {
  A: 'bg-emerald-500/15 text-emerald-400 ring-emerald-500/30',
  B: 'bg-cyan-500/15 text-cyan-400 ring-cyan-500/30',
  C: 'bg-gold-500/15 text-gold-400 ring-gold-500/30',
  F: 'bg-rose-500/15 text-rose-400 ring-rose-500/30',
}

const REGIONS = ['ALL', 'GLOBAL', 'GCC', 'MENA', 'US', 'EU', 'ASIA', 'CN']

function formatRatio(v: number): string {
  if (!v && v !== 0) return '—'
  return `${v.toFixed(1)}%`
}

export default function Stocks() {
  const { t } = useI18n()
  const [region, setRegion] = useState('ALL')
  const [grade, setGrade] = useState('ALL')
  const [query, setQuery] = useState('')
  const [stocks, setStocks] = useState<Stock[]>([])
  const [totals, setTotals] = useState<TotalsResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [toast, setToast] = useState<string | null>(null)
  const [editing, setEditing] = useState<Stock | null>(null)

  // Debounced search.
  const searchTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const [debouncedQuery, setDebouncedQuery] = useState('')
  useEffect(() => {
    if (searchTimer.current) clearTimeout(searchTimer.current)
    searchTimer.current = setTimeout(() => setDebouncedQuery(query), 250)
    return () => {
      if (searchTimer.current) clearTimeout(searchTimer.current)
    }
  }, [query])

  const qs = useMemo(() => {
    const p = new URLSearchParams()
    if (region !== 'ALL') p.set('region', region)
    if (grade !== 'ALL') p.set('grade', grade)
    if (debouncedQuery.trim()) p.set('q', debouncedQuery.trim())
    p.set('limit', '100')
    return p.toString()
  }, [region, grade, debouncedQuery])

  async function load() {
    setLoading(true)
    setError(null)
    try {
      const [list, totalsRes] = await Promise.all([
        api.get<ListResponse>(`/admin/stocks?${qs}`),
        api.get<TotalsResponse>('/admin/stocks/totals'),
      ])
      setStocks(list.stocks ?? [])
      setTotals(totalsRes)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : t('stocks.error.load'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [qs])

  const headerSub = totals
    ? t('stocks.subtitle', {
        total: fmtNum(totals.total),
        compliant: fmtNum(totals.compliant),
        nonCompliant: fmtNum(totals.nonCompliant),
      })
    : t('stocks.subtitle.loading')

  return (
    <div className="space-y-6">
      <div className="flex items-start justify-between flex-wrap gap-3">
        <div>
          <h1 className="text-2xl sm:text-3xl font-extrabold tracking-tight text-white">
            {t('stocks.title')}
          </h1>
          <p className="text-slate-400 text-sm mt-1">{headerSub}</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <button
            onClick={load}
            disabled={loading}
            className="btn-secondary disabled:opacity-50"
          >
            <RefreshCw
              className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`}
            />
            <span className="hidden sm:inline">{t('common.refresh')}</span>
          </button>
        </div>
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

      {/* Grade summary cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
        <GradeCard
          grade="A"
          count={totals?.byGrade['A'] ?? 0}
          label={t('stocks.grade.aDesc')}
          icon={ShieldCheck}
          color="emerald"
        />
        <GradeCard
          grade="B"
          count={totals?.byGrade['B'] ?? 0}
          label={t('stocks.grade.bDesc')}
          icon={ShieldCheck}
          color="cyan"
        />
        <GradeCard
          grade="C"
          count={totals?.byGrade['C'] ?? 0}
          label={t('stocks.grade.cDesc')}
          icon={ShieldQuestion}
          color="gold"
        />
        <GradeCard
          grade="F"
          count={totals?.byGrade['F'] ?? 0}
          label={t('stocks.grade.fDesc')}
          icon={ShieldX}
          color="rose"
        />
      </div>

      {/* Filter bar */}
      <div className="card overflow-hidden">
        <div className="px-3 sm:px-5 py-3 sm:py-4 border-b border-white/5 flex items-center gap-2 flex-wrap">
          <div className="flex items-center gap-1.5 bg-white/[0.03] rounded-lg px-2 py-1.5 ring-1 ring-white/10 flex-1 min-w-[180px] max-w-xs">
            <Search className="w-3.5 h-3.5 text-slate-500 shrink-0" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder={t('stocks.search.placeholder')}
              className="bg-transparent text-sm text-slate-200 placeholder:text-slate-500 outline-none w-full"
            />
          </div>
          <span className="text-xs text-slate-500 ms-1">{t('stocks.filter.region')}</span>
          {REGIONS.map((r) => (
            <button
              key={r}
              onClick={() => setRegion(r)}
              className={`shrink-0 px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                region === r
                  ? 'bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/20'
                  : 'text-slate-400 hover:bg-white/5'
              }`}
            >
              {r}
            </button>
          ))}
          <span className="text-xs text-slate-500 ms-3">{t('stocks.filter.grade')}</span>
          {(['ALL', ...GRADE_OPTIONS] as const).map((g) => (
            <button
              key={g}
              onClick={() => setGrade(g)}
              className={`shrink-0 px-2.5 py-1 rounded-md text-xs font-medium transition-colors ${
                grade === g
                  ? 'bg-cyan-500/15 text-cyan-300 ring-1 ring-cyan-500/20'
                  : 'text-slate-400 hover:bg-white/5'
              }`}
            >
              {g}
            </button>
          ))}
        </div>

        {/* Table */}
        {loading && stocks.length === 0 ? (
          <div className="p-8 flex items-center justify-center text-slate-500 text-sm">
            <Loader2 className="w-5 h-5 animate-spin me-2" /> {t('stocks.loading')}
          </div>
        ) : stocks.length === 0 ? (
          <div className="p-8 text-center text-sm text-slate-500">
            {t('stocks.empty')}
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-white/[0.02]">
                <tr className="text-start text-[11px] text-slate-500 uppercase tracking-wider">
                  <th className="px-3 sm:px-5 py-3 font-medium">{t('stocks.col.ticker')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium">{t('stocks.col.company')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden md:table-cell">
                    {t('stocks.col.region')}
                  </th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden sm:table-cell">
                    {t('stocks.col.status')}
                  </th>
                  <th className="px-3 sm:px-5 py-3 font-medium">{t('stocks.col.grade')}</th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden lg:table-cell">
                    {t('stocks.col.debt')}
                  </th>
                  <th className="px-3 sm:px-5 py-3 font-medium hidden lg:table-cell">
                    {t('stocks.col.haramIncome')}
                  </th>
                  <th className="px-3 sm:px-5 py-3 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {stocks.map((s) => (
                  <tr
                    key={s.id}
                    className="border-t border-white/5 hover:bg-white/[0.02]"
                  >
                    <td className="px-3 sm:px-5 py-3 font-mono font-bold text-cyan-400 whitespace-nowrap">
                      {s.ticker}
                    </td>
                    <td className="px-3 sm:px-5 py-3 font-semibold text-white">
                      <div className="min-w-0">
                        <p className="truncate max-w-[12rem] sm:max-w-none">
                          {s.name}
                        </p>
                        <p className="sm:hidden text-[11px] font-normal text-slate-500 mt-0.5">
                          {s.region}
                        </p>
                      </div>
                    </td>
                    <td className="px-3 sm:px-5 py-3 text-slate-400 hidden md:table-cell">
                      {s.region || '—'}
                    </td>
                    <td className="px-3 sm:px-5 py-3 hidden sm:table-cell">
                      <span
                        className={`chip ${STATUS_STYLES[s.status] ?? STATUS_STYLES.UNKNOWN}`}
                      >
                        {STATUS_LABEL_KEY[s.status]
                          ? t(STATUS_LABEL_KEY[s.status] as never)
                          : s.status}
                      </span>
                    </td>
                    <td className="px-3 sm:px-5 py-3">
                      {s.grade ? (
                        <span
                          className={`w-7 h-7 inline-flex items-center justify-center rounded-md font-bold text-sm ring-1 ${GRADE_STYLES[s.grade] ?? ''}`}
                        >
                          {s.grade}
                        </span>
                      ) : (
                        <span className="text-slate-500">—</span>
                      )}
                    </td>
                    <td className="px-3 sm:px-5 py-3 text-slate-300 hidden lg:table-cell">
                      {formatRatio(s.debtRatio)}
                    </td>
                    <td className="px-3 sm:px-5 py-3 text-slate-300 hidden lg:table-cell">
                      {formatRatio(s.haramIncome)}
                    </td>
                    <td className="px-3 sm:px-5 py-3">
                      <button
                        onClick={() => setEditing(s)}
                        className="p-1.5 rounded-md hover:bg-white/5 text-slate-500 hover:text-white"
                        title={t('stocks.override.tooltip')}
                      >
                        <Edit className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {editing && (
        <OverrideEditor
          stock={editing}
          onCancel={() => setEditing(null)}
          onSaved={(updated) => {
            setStocks((prev) =>
              prev.map((s) =>
                s.id === updated.id
                  ? { ...s, status: updated.status, grade: updated.grade }
                  : s,
              ),
            )
            setEditing(null)
            setToast(t('stocks.override.toast', { ticker: updated.ticker }))
            // Re-pull totals so the grade cards reflect the change.
            api
              .get<TotalsResponse>('/admin/stocks/totals')
              .then(setTotals)
              .catch(() => {})
          }}
        />
      )}
    </div>
  )
}

// ─── grade summary card (unchanged from the mock) ───────────────────────

function GradeCard({
  grade,
  count,
  label,
  icon: Icon,
  color,
}: {
  grade: string
  count: number
  label: string
  icon: React.ElementType
  color: 'emerald' | 'cyan' | 'gold' | 'rose'
}) {
  const { t } = useI18n()
  const colors = {
    emerald: 'bg-emerald-500/10 text-emerald-400 ring-emerald-500/20',
    cyan: 'bg-cyan-500/10 text-cyan-400 ring-cyan-500/20',
    gold: 'bg-gold-500/10 text-gold-400 ring-gold-500/20',
    rose: 'bg-rose-500/10 text-rose-400 ring-rose-500/20',
  }
  return (
    <div className="card p-4">
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span
              className={`w-7 h-7 inline-flex items-center justify-center rounded-md font-bold text-sm ring-1 ${colors[color]}`}
            >
              {grade}
            </span>
            <p className="text-[11px] uppercase tracking-wider text-slate-500">
              {t('stocks.grade.label', { grade })}
            </p>
          </div>
          <p className="text-2xl font-bold text-white mt-2">
            {fmtNum(count)}
          </p>
          <p className="text-xs text-slate-400 mt-0.5">{label}</p>
        </div>
        <Icon className={`w-8 h-8 ${colors[color].split(' ')[1]}`} />
      </div>
    </div>
  )
}

// ─── shariah override modal ─────────────────────────────────────────────

function OverrideEditor({
  stock,
  onCancel,
  onSaved,
}: {
  stock: Stock
  onCancel: () => void
  onSaved: (updated: {
    id: number
    ticker: string
    status: string
    grade: string
  }) => void
}) {
  const { t } = useI18n()
  const [status, setStatus] = useState(stock.status || 'UNKNOWN')
  const [grade, setGrade] = useState(stock.grade || '')
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  async function save() {
    setSaving(true)
    setErr(null)
    try {
      const res = await api.post<{
        id: number
        ticker: string
        status: string
        grade: string
      }>(`/admin/stocks/${stock.id}/shariah-override`, {
        status,
        grade,
        reason,
      })
      onSaved(res)
    } catch (e) {
      setErr(e instanceof ApiError ? e.message : t('stocks.override.saveFailed'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div className="card w-full max-w-md p-5 sm:p-6 max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-4">
          <h3 className="font-semibold text-white">{t('stocks.override.title')}</h3>
          <button onClick={onCancel} className="text-slate-400 hover:text-white">
            <X className="w-4 h-4" />
          </button>
        </div>

        <p className="text-xs text-slate-400 mb-4">
          {t('stocks.override.intro')}{' '}
          <span className="font-mono text-cyan-300">{stock.ticker}</span> (
          {stock.name}). {t('stocks.override.introSuffix')}
        </p>

        <div className="space-y-3">
          <Field label={t('stocks.override.field.status')}>
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              className="input"
            >
              {STATUS_OPTIONS.map((s) => (
                <option key={s} value={s}>
                  {s}
                </option>
              ))}
            </select>
          </Field>

          <Field label={t('stocks.override.field.grade')}>
            <select
              value={grade}
              onChange={(e) => setGrade(e.target.value)}
              className="input"
            >
              <option value="">{t('stocks.override.field.gradeNone')}</option>
              {GRADE_OPTIONS.map((g) => (
                <option key={g} value={g}>
                  {g}
                </option>
              ))}
            </select>
          </Field>

          <Field label={t('stocks.override.field.reason')}>
            <textarea
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              rows={3}
              maxLength={2000}
              className="input resize-none"
              placeholder={t('stocks.override.field.reasonPlaceholder')}
            />
          </Field>

          {err && (
            <div className="text-rose-300 text-xs bg-rose-500/10 ring-1 ring-rose-500/30 rounded p-2">
              {err}
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
              disabled={saving || !reason.trim()}
              className="flex-1 btn-primary justify-center disabled:opacity-50"
            >
              {saving ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                t('stocks.override.save')
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
  children,
}: {
  label: string
  children: React.ReactNode
}) {
  return (
    <div>
      <label className="block text-[10px] uppercase tracking-wider text-slate-500 mb-1.5">
        {label}
      </label>
      {children}
    </div>
  )
}
