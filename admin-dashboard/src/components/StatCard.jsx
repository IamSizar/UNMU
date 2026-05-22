import { ArrowUpRight, ArrowDownRight, Minus } from 'lucide-react'
import { HoverLift, NumberTicker, LivePulseDot } from '../ui/motion'
import { useI18n } from '../i18n/I18nContext'

/**
 * StatCard — the single most-used card on the dashboard.
 *
 * Redesign (May 2026):
 *   - Token-driven (`bg-surface`, hairline border, no glow).
 *   - The value renders through <NumberTicker> so live updates from
 *     the realtime stream animate smoothly to the new figure instead
 *     of snapping.
 *   - Optional <LivePulseDot> in the upper-right when `live=true` —
 *     telegraphs "this number is driven by WebSocket events".
 *   - Hover lifts the card 2px via the <HoverLift> motion primitive,
 *     matching every other interactive surface in the v2 system.
 *
 * Backwards-compat: existing call sites pass `value` as a number or a
 * pre-formatted string. When it's a number, we use the ticker; when
 * it's a string (e.g. "$1.2M"), we just render it as text.
 */
export default function StatCard({
  label,
  value,
  sub,
  change,
  icon: Icon,
  tone = 'cyan',
  live = false,
  // Optional formatter for the number ticker — only used when `value`
  // is a number. Defaults to `n.toLocaleString()`.
  format,
}) {
  const { t: translate } = useI18n()
  const tones = {
    cyan: {
      bg: 'bg-brand-cyan/12',
      text: 'text-brand-cyan',
      ring: 'ring-brand-cyan/24',
    },
    gold: {
      bg: 'bg-brand-gold/12',
      text: 'text-brand-gold',
      ring: 'ring-brand-gold/24',
    },
    ok: {
      bg: 'bg-ok/12',
      text: 'text-ok',
      ring: 'ring-ok/24',
    },
    err: {
      bg: 'bg-err/12',
      text: 'text-err',
      ring: 'ring-err/24',
    },
    info: {
      bg: 'bg-info/12',
      text: 'text-info',
      ring: 'ring-info/24',
    },
    // Legacy aliases — kept so existing tone="emerald|rose|violet" still works.
    emerald: { bg: 'bg-ok/12', text: 'text-ok', ring: 'ring-ok/24' },
    rose: { bg: 'bg-err/12', text: 'text-err', ring: 'ring-err/24' },
    violet: {
      bg: 'bg-info/12',
      text: 'text-info',
      ring: 'ring-info/24',
    },
  }
  const t = tones[tone] ?? tones.cyan

  const positive = change === undefined ? null : change >= 0
  const flat = change === 0
  const ChangeIcon = flat ? Minus : positive ? ArrowUpRight : ArrowDownRight
  const changeColor = flat
    ? 'text-fg-subtle'
    : positive
    ? 'text-ok'
    : 'text-err'

  return (
    <HoverLift className="cursor-default">
      <div className="card-v2 card-v2-hover p-5 h-full">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            {/* Eyebrow + optional live dot. */}
            <div className="flex items-center gap-1.5">
              <p className="eyebrow-v2 truncate">{label}</p>
              {live && <LivePulseDot color="cyan" size={6} />}
            </div>

            {/* Value — number ticker when numeric, plain otherwise. */}
            <p className="num-v2 text-[28px] font-extrabold mt-2 text-fg leading-none">
              {typeof value === 'number' ? (
                <NumberTicker value={value} format={format} />
              ) : (
                value
              )}
            </p>

            {sub && (
              <p className="text-xs text-fg-muted mt-1.5 line-clamp-2">{sub}</p>
            )}
          </div>

          <div
            className={`w-9 h-9 rounded-lg flex items-center justify-center ring-1 ring-inset shrink-0 ${t.bg} ${t.text} ${t.ring}`}
          >
            <Icon className="w-[18px] h-[18px]" />
          </div>
        </div>

        {positive !== null && (
          <div className="mt-4 flex items-center gap-1.5">
            <span
              className={`inline-flex items-center gap-0.5 text-xs font-bold tabular-nums ${changeColor}`}
            >
              <ChangeIcon className="w-3.5 h-3.5" />
              {Math.abs(change)}%
            </span>
            <span className="text-[11px] text-fg-subtle">{translate('statCard.vsLastMonth')}</span>
          </div>
        )}
      </div>
    </HoverLift>
  )
}
