import { useEffect, useState } from 'react'
import {
  Users as UsersIcon,
  GraduationCap,
  Crown,
  TrendingUp,
  FileText,
  Video,
  DollarSign,
  ShieldCheck,
  Download,
  ArrowRight,
} from 'lucide-react'
import {
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from 'recharts'
import StatCard from '../components/StatCard'
import { useAuth } from '../auth/AuthContext'
import { api, ApiError } from '../api/client'
import { FadeIn, HoverLift, StaggerItem, StaggerList } from '../ui/motion'
import { useI18n } from '../i18n/I18nContext'
import { fmtNum } from '../i18n/datefmt'

// ────────────────────────────────────────────────────────────────────
// Wire shape from GET /api/admin/metrics (Phase 4.1).
// ────────────────────────────────────────────────────────────────────
type MetricsResponse = {
  users: {
    total: number
    thisWeek: number
    premium: number
    experts: number
  }
  subscriptions: {
    monthlyActive: number
    yearlyActive: number
    mrrCents: number
    arrCents: number
    pendingApplications: number
  }
  content: {
    articles: number
    articlesThisWeek: number
    videos: number
    videosThisWeek: number
  }
  stocks: {
    total: number
    compliant: number
    byGrade: { grade: string; count: number }[]
  }
  trends: {
    subsByMonth: { month: string; monthly: number; yearly: number }[]
    contentByDay: { day: string; articles: number; videos: number }[]
  }
  topExperts: {
    expertId: string
    name: string
    specialty: string
    followers: number
    articles: number
    videos: number
    avatarUrl: string
  }[]
}

// Pretty-money helper used for MRR / ARR. Server sends USD cents.
function moneyShort(cents: number): string {
  if (!cents) return '$0'
  const dollars = cents / 100
  if (dollars >= 1_000_000) return `$${(dollars / 1_000_000).toFixed(1)}M`
  if (dollars >= 1_000) return `$${(dollars / 1_000).toFixed(1)}K`
  return `$${dollars.toFixed(0)}`
}

function countShort(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`
  return `${n}`
}

// Grade → fill colour. Mirrors the shariah palette the rest of the
// admin dashboard uses.
const GRADE_FILL: Record<string, string> = {
  A: '#34D399',
  B: '#22D3EE',
  C: '#FBBF24',
  F: '#F87171',
}

// Day-of-week label used by the content chart. Server sends
// YYYY-MM-DD; we shorten to Mon/Tue/... for the X axis.
function dayLabel(iso: string): string {
  try {
    const d = new Date(iso)
    return d.toLocaleDateString(undefined, { weekday: 'short' })
  } catch {
    return iso
  }
}

/**
 * Dashboard (home) — the redesign showcase.
 *
 * The data wiring stays static for now (this matches the pre-redesign
 * file; real numbers will flow in via the metrics rollup we ship later).
 * The visual + motion layer is the v2 system:
 *   - PageHeader uses the editorial-minimal pattern: large left-aligned
 *     headline + lowercase support line + right-aligned actions.
 *   - All cards are `card-v2` (hairline border, no glow, hover lift).
 *   - StatCards animate in with a 40ms stagger (StaggerList).
 *   - Recent activity rows fade in individually after the cards.
 *   - The "ARR / MRR" stats use the LivePulseDot to telegraph realtime.
 */

// Recent activity is now sourced live from the audit log
// (GET /admin/audit-logs). Each event's severity maps to a dot colour.
type AuditEvent = {
  id: number
  type: string
  severity: 'info' | 'success' | 'warning' | 'error'
  actorEmail?: string
  summary: string
  createdAt: string
}

// audit severity → dot colour class.
const severityDotClass: Record<string, string> = {
  info: 'bg-info',
  success: 'bg-ok',
  warning: 'bg-brand-gold',
  error: 'bg-err',
}

// "x ago" relative time for the activity feed. Falls back to the raw
// string if the date can't be parsed.
function timeAgo(iso: string): string {
  try {
    const then = new Date(iso).getTime()
    const secs = Math.max(0, Math.floor((Date.now() - then) / 1000))
    if (secs < 60) return `${secs}s ago`
    const mins = Math.floor(secs / 60)
    if (mins < 60) return `${mins}m ago`
    const hrs = Math.floor(mins / 60)
    if (hrs < 24) return `${hrs}h ago`
    const days = Math.floor(hrs / 24)
    return `${days}d ago`
  } catch {
    return iso
  }
}

// Token-driven Recharts theme — pulls colors from the CSS variables
// set in src/index.css. Recharts takes inline style objects rather
// than className strings, so we need the resolved colour values at
// render time. The hook below reads the variables off the document
// root and re-runs whenever the theme class flips.
function useChartTheme() {
  const [theme, setTheme] = useState(() => readChartTheme())
  useEffect(() => {
    function recompute() {
      setTheme(readChartTheme())
    }
    // Re-read when the .dark class flips on <html>.
    const obs = new MutationObserver(recompute)
    obs.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class'],
    })
    return () => obs.disconnect()
  }, [])
  return theme
}

function readChartTheme() {
  const style = getComputedStyle(document.documentElement)
  return {
    grid: style.getPropertyValue('--chart-grid').trim() || 'rgba(255,255,255,0.05)',
    axis: style.getPropertyValue('--chart-axis').trim() || '#64748B',
    axisFont: 12,
    tooltipStyle: {
      background:
        style.getPropertyValue('--chart-tooltip-bg').trim() || '#161A21',
      border:
        '1px solid ' +
        (style.getPropertyValue('--chart-tooltip-border').trim() ||
          'rgba(255,255,255,0.10)'),
      borderRadius: 8,
      fontSize: 12,
      fontFamily: 'Inter, system-ui, sans-serif',
      color:
        style.getPropertyValue('--chart-tooltip-text').trim() || '#F1F5F9',
      boxShadow:
        style.getPropertyValue('--chart-tooltip-shadow').trim() ||
        '0 12px 32px rgba(0,0,0,0.60)',
    },
    // Brand colours stay constant across both themes — they were chosen
    // to read well on either surface.
    cyan: '#22D3EE',
    gold: '#FBBF24',
  }
}

export default function Dashboard() {
  const { t } = useI18n()
  const { user } = useAuth()
  const greeting = user?.name?.split(' ')[0] ?? 'Admin'
  // chartTheme reads CSS variables; recomputes when `.dark` flips on
  // <html> via the MutationObserver in useChartTheme. Light + dark
  // both look correct without any other code change.
  const chartTheme = useChartTheme()

  // Phase 4.1 — single rollup endpoint feeds every card + chart on this
  // screen. We show em-dashes / skeletons while it loads so the
  // visual layout doesn't shift on resolution.
  const [metrics, setMetrics] = useState<MetricsResponse | null>(null)
  const [metricsError, setMetricsError] = useState<string | null>(null)
  // Recent activity — live from the audit log.
  const [activity, setActivity] = useState<AuditEvent[] | null>(null)

  useEffect(() => {
    let cancelled = false
    api
      .get<MetricsResponse>('/admin/metrics')
      .then((m) => {
        if (!cancelled) setMetrics(m)
      })
      .catch((err) => {
        if (!cancelled) {
          setMetricsError(
            err instanceof ApiError ? err.message : t('overview.metricsError'),
          )
        }
      })
    api
      .get<{ events: AuditEvent[] }>('/admin/audit-logs?limit=6')
      .then((res) => {
        if (!cancelled) setActivity(res.events ?? [])
      })
      .catch(() => {
        if (!cancelled) setActivity([])
      })
    return () => {
      cancelled = true
    }
  }, [])

  const subsTrend = metrics?.trends.subsByMonth ?? []
  const shariahGrades = (metrics?.stocks.byGrade ?? []).map((g) => ({
    grade: g.grade,
    count: g.count,
    fill: GRADE_FILL[g.grade] ?? '#64748B',
  }))
  const contentWeek = (metrics?.trends.contentByDay ?? []).map((d) => ({
    day: dayLabel(d.day),
    articles: d.articles,
    videos: d.videos,
  }))
  const topExperts = metrics?.topExperts ?? []

  // Conversion rate — premium ÷ total users. Defensive against div-by-0
  // so first-launch dashboards don't render "NaN%".
  const conversionPct =
    metrics && metrics.users.total > 0
      ? ((metrics.users.premium / metrics.users.total) * 100).toFixed(2)
      : '—'

  return (
    <div className="space-y-8 max-w-[1400px] mx-auto">
      {/* ── Page header ─────────────────────────────────────────────── */}
      <FadeIn>
        <div className="flex items-end justify-between flex-wrap gap-4">
          <div>
            <h1 className="h1-v2">{t('overview.welcome', { name: greeting })}</h1>
            <p className="text-fg-muted text-sm mt-1">
              {t('overview.subtitle')}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <select className="input-v2 w-auto pe-8">
              <option>{t('overview.range30')}</option>
              <option>{t('overview.range90')}</option>
              <option>{t('overview.rangeYear')}</option>
            </select>
            <button className="btn-v2-primary">
              <Download className="w-4 h-4" />
              <span className="hidden sm:inline">{t('overview.export')}</span>
            </button>
          </div>
        </div>
      </FadeIn>

      {metricsError && (
        <div className="rounded-lg p-3 text-sm bg-rose-500/10 ring-1 ring-rose-500/30 text-rose-300">
          {metricsError}
        </div>
      )}

      {/* ── Top stats grid (4) ───────────────────────────────────────── */}
      <StaggerList delayChildren={0.04}>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <StaggerItem>
            <StatCard
              label={t('overview.totalUsers')}
              value={metrics ? metrics.users.total : '—'}
              sub={
                metrics
                  ? t('overview.thisWeek', { count: metrics.users.thisWeek })
                  : t('overview.loading')
              }
              icon={UsersIcon}
              tone="cyan"
              live
            />
          </StaggerItem>
          <StaggerItem>
            <StatCard
              label={t('overview.premiumSubscribers')}
              value={
                metrics
                  ? metrics.subscriptions.monthlyActive +
                    metrics.subscriptions.yearlyActive
                  : '—'
              }
              sub={
                metrics
                  ? t('overview.premiumSub', {
                      monthly: metrics.subscriptions.monthlyActive,
                      yearly: metrics.subscriptions.yearlyActive,
                    })
                  : t('overview.loading')
              }
              icon={Crown}
              tone="gold"
            />
          </StaggerItem>
          <StaggerItem>
            <StatCard
              label={t('overview.verifiedExperts')}
              value={metrics ? metrics.users.experts : '—'}
              sub={
                metrics
                  ? t('overview.pendingApplications', {
                      count: metrics.subscriptions.pendingApplications,
                    })
                  : t('overview.loading')
              }
              icon={GraduationCap}
              tone="info"
            />
          </StaggerItem>
          <StaggerItem>
            <StatCard
              label={t('overview.mrr')}
              value={metrics ? moneyShort(metrics.subscriptions.mrrCents) : '—'}
              sub={
                metrics
                  ? t('overview.arrSub', {
                      amount: moneyShort(metrics.subscriptions.arrCents),
                    })
                  : t('overview.loading')
              }
              icon={DollarSign}
              tone="ok"
              live
            />
          </StaggerItem>
        </div>
      </StaggerList>

      {/* ── Secondary stats grid (4) ─────────────────────────────────── */}
      <StaggerList delayChildren={0.12}>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          <StaggerItem>
            <StatCard
              label={t('overview.articlesPublished')}
              value={metrics ? metrics.content.articles : '—'}
              sub={
                metrics
                  ? t('overview.thisWeek', { count: metrics.content.articlesThisWeek })
                  : t('overview.loading')
              }
              icon={FileText}
              tone="cyan"
            />
          </StaggerItem>
          <StaggerItem>
            <StatCard
              label={t('overview.shortVideos')}
              value={metrics ? metrics.content.videos : '—'}
              sub={
                metrics
                  ? t('overview.thisWeek', { count: metrics.content.videosThisWeek })
                  : t('overview.loading')
              }
              icon={Video}
              tone="gold"
            />
          </StaggerItem>
          <StaggerItem>
            <StatCard
              label={t('overview.stocksScreened')}
              value={metrics ? metrics.stocks.total : '—'}
              sub={
                metrics
                  ? t('overview.compliant', { count: fmtNum(metrics.stocks.compliant) })
                  : t('overview.loading')
              }
              icon={ShieldCheck}
              tone="ok"
            />
          </StaggerItem>
          <StaggerItem>
            <StatCard
              label={t('overview.conversionRate')}
              value={metrics ? `${conversionPct}%` : '—'}
              sub={t('overview.conversionSub')}
              icon={TrendingUp}
              tone="info"
            />
          </StaggerItem>
        </div>
      </StaggerList>

      {/* ── Trends row ───────────────────────────────────────────────── */}
      <FadeIn delay={0.15}>
        <div className="grid grid-cols-1 gap-4">
          {/* Subscriptions trend — area chart. New subs created per month
              across the last 8 months. The donut chart that used to live
              next to this card depended on per-user region data the
              backend doesn't track yet — temporarily removed. */}
          <ChartCard
            title={t('overview.subsGrowthTitle')}
            subtitle={t('overview.subsGrowthSubtitle')}
            legend={
              <>
                <LegendDot color={chartTheme.cyan} label={t('overview.legendMonthly')} />
                <LegendDot color={chartTheme.gold} label={t('overview.legendAnnual')} />
              </>
            }
          >
            <ResponsiveContainer width="100%" height={280}>
              <AreaChart data={subsTrend} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
                <defs>
                  <linearGradient id="monGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor={chartTheme.cyan} stopOpacity={0.45} />
                    <stop offset="100%" stopColor={chartTheme.cyan} stopOpacity={0} />
                  </linearGradient>
                  <linearGradient id="annGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor={chartTheme.gold} stopOpacity={0.45} />
                    <stop offset="100%" stopColor={chartTheme.gold} stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid stroke={chartTheme.grid} vertical={false} />
                <XAxis
                  dataKey="month"
                  stroke={chartTheme.axis}
                  fontSize={chartTheme.axisFont}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  stroke={chartTheme.axis}
                  fontSize={chartTheme.axisFont}
                  axisLine={false}
                  tickLine={false}
                />
                <Tooltip contentStyle={chartTheme.tooltipStyle} />
                <Area
                  type="monotone"
                  dataKey="monthly"
                  stroke={chartTheme.cyan}
                  strokeWidth={2}
                  fill="url(#monGrad)"
                />
                <Area
                  type="monotone"
                  dataKey="yearly"
                  stroke={chartTheme.gold}
                  strokeWidth={2}
                  fill="url(#annGrad)"
                />
              </AreaChart>
            </ResponsiveContainer>
          </ChartCard>
        </div>
      </FadeIn>

      {/* ── Shariah grades + Content week + Recent activity ─────────── */}
      <FadeIn delay={0.2}>
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <ChartCard
            title={t('overview.shariahGradesTitle')}
            subtitle={t('overview.shariahGradesSubtitle')}
          >
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={shariahGrades} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
                <CartesianGrid stroke={chartTheme.grid} vertical={false} />
                <XAxis
                  dataKey="grade"
                  stroke={chartTheme.axis}
                  fontSize={chartTheme.axisFont}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  stroke={chartTheme.axis}
                  fontSize={chartTheme.axisFont}
                  axisLine={false}
                  tickLine={false}
                />
                <Tooltip contentStyle={chartTheme.tooltipStyle} />
                <Bar dataKey="count" radius={[6, 6, 0, 0]}>
                  {shariahGrades.map((g, i) => (
                    <Cell key={i} fill={g.fill} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>

          <ChartCard title={t('overview.contentWeekTitle')} subtitle={t('overview.contentWeekSubtitle')}>
            <ResponsiveContainer width="100%" height={240}>
              <BarChart data={contentWeek} margin={{ top: 8, right: 8, left: -16, bottom: 0 }}>
                <CartesianGrid stroke={chartTheme.grid} vertical={false} />
                <XAxis
                  dataKey="day"
                  stroke={chartTheme.axis}
                  fontSize={chartTheme.axisFont}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  stroke={chartTheme.axis}
                  fontSize={chartTheme.axisFont}
                  axisLine={false}
                  tickLine={false}
                />
                <Tooltip contentStyle={chartTheme.tooltipStyle} />
                <Bar dataKey="articles" fill={chartTheme.cyan} radius={[4, 4, 0, 0]} />
                <Bar dataKey="videos" fill={chartTheme.gold} radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </ChartCard>

          {/* Recent activity feed */}
          <div className="card-v2 p-5">
            <div className="flex items-center justify-between mb-4">
              <div>
                <h3 className="h3-v2">{t('overview.recentActivityTitle')}</h3>
                <p className="text-xs text-fg-subtle mt-0.5">{t('overview.recentActivitySubtitle')}</p>
              </div>
              <button className="btn-v2-ghost text-xs">
                {t('overview.viewAll')}
                <ArrowRight className="w-3.5 h-3.5 rtl:-scale-x-100" />
              </button>
            </div>
            <StaggerList delayChildren={0.25}>
              <ul className="space-y-3">
                {activity && activity.length === 0 && (
                  <li className="text-sm text-fg-subtle py-1">
                    {t('overview.noActivity')}
                  </li>
                )}
                {(activity ?? []).map((a) => (
                  <StaggerItem key={a.id}>
                    <li className="flex items-start gap-3 py-1">
                      <span
                        className={`w-1.5 h-1.5 rounded-full mt-1.5 shrink-0 ${
                          severityDotClass[a.severity] ?? 'bg-info'
                        }`}
                      />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm text-fg leading-snug">{a.summary}</p>
                        <p className="text-[11px] text-fg-subtle mt-0.5 font-mono">
                          {timeAgo(a.createdAt)}
                        </p>
                      </div>
                    </li>
                  </StaggerItem>
                ))}
              </ul>
            </StaggerList>
          </div>
        </div>
      </FadeIn>

      {/* ── Top experts ──────────────────────────────────────────────── */}
      <FadeIn delay={0.25}>
        <div className="card-v2 p-5">
          <div className="flex items-center justify-between mb-5 flex-wrap gap-3">
            <div>
              <h3 className="h2-v2">{t('overview.topExpertsTitle')}</h3>
              <p className="text-xs text-fg-subtle mt-0.5">
                {t('overview.topExpertsSubtitle')}
              </p>
            </div>
            <button className="btn-v2-ghost">
              {t('overview.viewAll')}
              <ArrowRight className="w-4 h-4 rtl:-scale-x-100" />
            </button>
          </div>
          <StaggerList delayChildren={0.28}>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
              {topExperts.length === 0 && metrics && (
                <p className="text-sm text-fg-subtle col-span-full">
                  {t('overview.noExperts')}
                </p>
              )}
              {topExperts.map((e) => {
                const initials = e.name
                  .split(/\s+/)
                  .filter(Boolean)
                  .slice(0, 2)
                  .map((p) => p[0])
                  .join('')
                  .toUpperCase()
                return (
                  <StaggerItem key={e.expertId || e.name}>
                    <HoverLift className="cursor-pointer">
                      <div className="rounded-lg bg-canvas border border-white/[0.06] hover:border-white/[0.12] hover:shadow-hover p-4 transition-all duration-micro ease-out-expo">
                        <div className="flex items-center gap-3 mb-3">
                          <div className="relative shrink-0">
                            {e.avatarUrl ? (
                              <img
                                src={e.avatarUrl}
                                className="w-11 h-11 rounded-full ring-1 ring-white/[0.10] object-cover"
                                alt=""
                              />
                            ) : (
                              <div className="w-11 h-11 rounded-full ring-1 ring-white/[0.10] bg-gradient-to-br from-cyan-500/30 to-cyan-700/30 flex items-center justify-center text-cyan-200 text-xs font-bold">
                                {initials || '?'}
                              </div>
                            )}
                            <span className="absolute -bottom-0.5 -end-0.5 w-4 h-4 rounded-full bg-brand-cyan ring-2 ring-surface flex items-center justify-center">
                              <ShieldCheck className="w-2.5 h-2.5 text-canvas" strokeWidth={3} />
                            </span>
                          </div>
                          <div className="min-w-0">
                            <p className="text-sm font-semibold text-fg truncate">
                              {e.name}
                            </p>
                            <p className="text-[11px] text-brand-cyan truncate">
                              {e.specialty || '—'}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center justify-between text-xs">
                          <span className="text-fg-muted">
                            <span className="num-v2 text-fg font-semibold">
                              {countShort(e.followers)}
                            </span>{' '}
                            {t('overview.followers')}
                          </span>
                          <span className="num-v2 text-fg-subtle">
                            {e.articles} · {e.videos}
                          </span>
                        </div>
                      </div>
                    </HoverLift>
                  </StaggerItem>
                )
              })}
            </div>
          </StaggerList>
        </div>
      </FadeIn>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Reusable chart card — header (title + subtitle + optional legend
// chips) over a sized chart body. Used for the 5 charts on this page.
// ────────────────────────────────────────────────────────────────────
function ChartCard({
  title,
  subtitle,
  legend,
  className,
  children,
}: {
  title: string
  subtitle?: string
  legend?: React.ReactNode
  className?: string
  children: React.ReactNode
}) {
  return (
    <div className={`card-v2 p-5 ${className ?? ''}`}>
      <div className="flex items-start justify-between mb-4 gap-3 flex-wrap">
        <div className="min-w-0">
          <h3 className="h3-v2">{title}</h3>
          {subtitle && (
            <p className="text-xs text-fg-subtle mt-0.5">{subtitle}</p>
          )}
        </div>
        {legend && <div className="flex items-center gap-3 text-xs">{legend}</div>}
      </div>
      {children}
    </div>
  )
}

function LegendDot({ color, label }: { color: string; label: string }) {
  return (
    <span className="flex items-center gap-1.5 text-fg-muted">
      <span
        className="w-2 h-2 rounded-full"
        style={{ background: color }}
      />
      {label}
    </span>
  )
}
