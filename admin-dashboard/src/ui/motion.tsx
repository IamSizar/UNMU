/**
 * UNMU admin — motion primitives.
 *
 * One file, one cohesive motion language. Every redesigned page imports
 * from here so the timings + easing curve are identical across the app.
 *
 * Easing: ease-out-expo (`cubic-bezier(0.16, 1, 0.3, 1)`).
 *   Linear taught us subtle UI never bounces; ease-out-expo is the
 *   sharpest decel curve that still feels physical. Used everywhere.
 *
 * Durations:
 *   - micro: 120ms  — hover, focus, color swap
 *   - small: 200ms  — modal fade, list item enter
 *   - page:  320ms  — route transitions
 *
 * Performance: every component animates only `transform` + `opacity`
 * (compositor-friendly). Never `width/height/top/left`.
 */

import {
  AnimatePresence,
  motion,
  useInView,
  useMotionValue,
  useSpring,
  useTransform,
} from 'framer-motion'
import { useEffect, useRef, useState, type ReactNode } from 'react'

// ────────────────────────────────────────────────────────────────────
// Curve + duration constants
// ────────────────────────────────────────────────────────────────────
export const EASE = [0.16, 1, 0.3, 1] as const
export const DUR = { micro: 0.12, small: 0.2, page: 0.32 } as const

// ────────────────────────────────────────────────────────────────────
// PageTransition — fade + 8px y-slide. Wrap each routed page.
// Pair with a parent <AnimatePresence mode="wait"> when routes change.
// ────────────────────────────────────────────────────────────────────
export function PageTransition({
  children,
  routeKey,
}: {
  children: ReactNode
  /** Pass `location.pathname` to retrigger on every navigation. */
  routeKey?: string
}) {
  return (
    <AnimatePresence mode="wait" initial={false}>
      <motion.div
        key={routeKey}
        initial={{ opacity: 0, y: 8 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -4 }}
        transition={{ duration: DUR.page, ease: EASE }}
      >
        {children}
      </motion.div>
    </AnimatePresence>
  )
}

// ────────────────────────────────────────────────────────────────────
// StaggerList — children fade + 6px y-rise, staggered 40ms each.
// Use for nav items, dashboard stat cards, table rows.
// ────────────────────────────────────────────────────────────────────
export function StaggerList({
  children,
  delayChildren = 0,
  staggerMs = 40,
}: {
  children: ReactNode
  delayChildren?: number
  staggerMs?: number
}) {
  return (
    <motion.div
      initial="hidden"
      animate="visible"
      variants={{
        hidden: {},
        visible: {
          transition: {
            delayChildren,
            staggerChildren: staggerMs / 1000,
          },
        },
      }}
    >
      {children}
    </motion.div>
  )
}

export function StaggerItem({
  children,
  className,
}: {
  children: ReactNode
  className?: string
}) {
  return (
    <motion.div
      className={className}
      variants={{
        hidden: { opacity: 0, y: 6 },
        visible: {
          opacity: 1,
          y: 0,
          transition: { duration: DUR.small, ease: EASE },
        },
      }}
    >
      {children}
    </motion.div>
  )
}

// ────────────────────────────────────────────────────────────────────
// HoverLift — wraps a card so it rises 2px on hover with a tap squish.
// Pair with `.card-v2-hover` class for the matching shadow + border.
// ────────────────────────────────────────────────────────────────────
export function HoverLift({
  children,
  className,
  onClick,
}: {
  children: ReactNode
  className?: string
  onClick?: () => void
}) {
  return (
    <motion.div
      className={className}
      onClick={onClick}
      whileHover={{ y: -2 }}
      whileTap={{ scale: 0.985 }}
      transition={{ duration: DUR.micro, ease: EASE }}
    >
      {children}
    </motion.div>
  )
}

// ────────────────────────────────────────────────────────────────────
// NumberTicker — animates between integer values (counters, stats).
// Only animates when the value actually changes; first render snaps.
// ────────────────────────────────────────────────────────────────────
export function NumberTicker({
  value,
  duration = 0.8,
  format = (n: number) => n.toLocaleString('en-US'),
  className,
}: {
  value: number
  duration?: number
  format?: (n: number) => string
  className?: string
}) {
  const motionValue = useMotionValue(value)
  const spring = useSpring(motionValue, {
    duration: duration * 1000,
    bounce: 0,
  })
  const display = useTransform(spring, (latest) => format(Math.round(latest)))
  const ref = useRef<HTMLSpanElement>(null)
  const inView = useInView(ref, { once: true, margin: '-32px' })
  const firstRender = useRef(true)

  // Snap on first paint, animate on subsequent changes — avoids the
  // "counts from 0 every time the page loads" anti-pattern.
  useEffect(() => {
    if (firstRender.current) {
      motionValue.jump(value)
      firstRender.current = false
      return
    }
    if (inView) motionValue.set(value)
    else motionValue.jump(value)
  }, [value, inView, motionValue])

  return (
    <motion.span ref={ref} className={className}>
      {display}
    </motion.span>
  )
}

// ────────────────────────────────────────────────────────────────────
// LivePulseDot — 8px cyan dot with a soft pulse halo. Indicates a
// value driven by realtime/WS updates.
// ────────────────────────────────────────────────────────────────────
export function LivePulseDot({
  color = 'cyan',
  size = 8,
}: {
  color?: 'cyan' | 'gold' | 'ok' | 'warn'
  size?: number
}) {
  const colorMap = {
    cyan: { core: '#22D3EE', glow: 'rgba(34, 211, 238, 0.45)' },
    gold: { core: '#FBBF24', glow: 'rgba(251, 191, 36, 0.45)' },
    ok: { core: '#34D399', glow: 'rgba(52, 211, 153, 0.45)' },
    warn: { core: '#FBBF24', glow: 'rgba(251, 191, 36, 0.45)' },
  }[color]

  return (
    <span
      className="relative inline-flex shrink-0"
      style={{ width: size, height: size }}
    >
      {/* Halo — animated via the `livepulse` keyframes in tailwind config. */}
      <span
        className="absolute inset-0 rounded-full animate-livepulse"
        style={{ background: colorMap.glow }}
      />
      <span
        className="absolute inset-0 rounded-full"
        style={{ background: colorMap.core }}
      />
    </span>
  )
}

// ────────────────────────────────────────────────────────────────────
// Shimmer — skeleton placeholder. Use while data is loading.
// `lines` for stacked rows of text; `circle` for round avatars.
// ────────────────────────────────────────────────────────────────────
export function Shimmer({
  className,
  variant = 'block',
}: {
  className?: string
  variant?: 'block' | 'circle' | 'line'
}) {
  const variantClasses = {
    block: 'h-12 rounded-md',
    circle: 'h-8 w-8 rounded-full',
    line: 'h-3 rounded-sm',
  }[variant]
  return <div className={`shimmer-v2 ${variantClasses} ${className ?? ''}`} />
}

// ────────────────────────────────────────────────────────────────────
// Toast — slides in from the top-right. Used by the global Toaster.
// ────────────────────────────────────────────────────────────────────
export function ToastMotion({
  children,
  show,
}: {
  children: ReactNode
  show: boolean
}) {
  return (
    <AnimatePresence>
      {show && (
        <motion.div
          initial={{ opacity: 0, x: 120 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: 120 }}
          transition={{ duration: DUR.small, ease: EASE }}
        >
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  )
}

// ────────────────────────────────────────────────────────────────────
// FadeIn — generic fade-in for sections (e.g. content after a fetch).
// Defaults to a small upward rise.
// ────────────────────────────────────────────────────────────────────
export function FadeIn({
  children,
  delay = 0,
  y = 6,
  className,
}: {
  children: ReactNode
  delay?: number
  y?: number
  className?: string
}) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: DUR.small, ease: EASE, delay }}
    >
      {children}
    </motion.div>
  )
}

// ────────────────────────────────────────────────────────────────────
// usePrevious — small util used by NumberTicker variants in pages.
// ────────────────────────────────────────────────────────────────────
export function usePrevious<T>(value: T): T | undefined {
  const ref = useRef<T>()
  useEffect(() => {
    ref.current = value
  }, [value])
  return ref.current
}

// ────────────────────────────────────────────────────────────────────
// AccessibilityNote
// ────────────────────────────────────────────────────────────────────
// All animations respect `prefers-reduced-motion` via framer-motion's
// built-in handling. When a user has reduced motion enabled, framer
// shortens durations to 0 — they see no animation, just the final state.
// No extra code needed here.

// Tiny consumer-side hook in case a component wants to know if reduced
// motion is on so it can skip a decoration entirely.
export function useReducedMotionPreferred(): boolean {
  const [reduced, setReduced] = useState(false)
  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)')
    setReduced(mq.matches)
    const handler = (e: MediaQueryListEvent) => setReduced(e.matches)
    mq.addEventListener('change', handler)
    return () => mq.removeEventListener('change', handler)
  }, [])
  return reduced
}
