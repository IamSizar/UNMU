/** @type {import('tailwindcss').Config} */
//
// UNMU admin dashboard — design tokens.
//
// History: this file is consumed by every page; 31 page files already
// reference the existing `midnight-*`, `cyan-*`, `gold-*` scales, so we
// KEEP those intact and ADD the new system on top. Pages migrated to
// the new look use the v2 tokens (`bg-canvas`, `text-fg`, etc.).
//
// The two systems will coexist while the redesign rolls out page by
// page; once every page is migrated, the legacy `midnight-50..900`
// numeric scales can be deleted.
//
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // ── v2 tokens (new design system) ─────────────────────────────
        // CSS-variable-driven so the theme toggle swaps light/dark in
        // a single repaint. Each token resolves to an `rgb(r g b / α)`
        // call so Tailwind's opacity modifier (`bg-canvas/80`) keeps
        // working — the glass-blur sticky header depends on it.
        //
        // Variables come from src/index.css:
        //   :root         → light theme channel values
        //   :root.dark    → dark theme channel values
        canvas: 'rgb(var(--bg-canvas-rgb) / <alpha-value>)',
        surface: 'rgb(var(--bg-surface-rgb) / <alpha-value>)',
        elevated: 'rgb(var(--bg-elevated-rgb) / <alpha-value>)',
        fg: 'rgb(var(--fg-rgb) / <alpha-value>)',
        'fg-muted': 'rgb(var(--fg-muted-rgb) / <alpha-value>)',
        'fg-subtle': 'rgb(var(--fg-subtle-rgb) / <alpha-value>)',
        // Brand accents — adjusted to slightly desaturated values
        // because the legacy #00D9FF and #FFD700 vibrate against pure
        // dark backgrounds.
        brand: {
          cyan: '#22D3EE',      // CTAs, focus, active nav
          'cyan-deep': '#06B6D4',
          gold: '#FBBF24',      // premium / verified only
          'gold-deep': '#F59E0B',
        },
        // Semantic — Tailwind's emerald/amber/red/blue family at the
        // -400 step for AA contrast on dark surfaces.
        ok: '#34D399',
        warn: '#FBBF24',
        err: '#F87171',
        info: '#60A5FA',

        // Theme-aware borders. Use these instead of literal
        // `border-white/[0.06]` — the latter is invisible on white
        // backgrounds in light mode.
        hairline: 'var(--border-hairline)',
        line: 'var(--border-default)',
        'line-strong': 'var(--border-strong)',

        // ── legacy tokens (kept while pages migrate) ─────────────────
        midnight: {
          50: '#1a2942',
          100: '#142339',
          200: '#0f1d31',
          300: '#0d1a2c',
          400: '#0b1828',
          500: '#0A1628',
          600: '#091324',
          700: '#07101e',
          800: '#050c18',
          900: '#040912',
        },
        cyan: {
          50: '#e0fbff',
          100: '#b8f5ff',
          200: '#85eeff',
          300: '#52e6ff',
          400: '#1fdfff',
          500: '#00D9FF',
          600: '#00afcc',
          700: '#008599',
          800: '#005c66',
          900: '#003339',
        },
        gold: {
          50: '#fffbe6',
          100: '#fff5b8',
          200: '#ffec70',
          300: '#ffe340',
          400: '#ffdb1f',
          500: '#FFD700',
          600: '#ccac00',
          700: '#998100',
          800: '#665600',
          900: '#332b00',
        },
      },

      fontFamily: {
        sans: ['Inter var', 'Inter', 'Noto Sans Arabic', 'system-ui', 'sans-serif'],
        // Mono for numbers / IDs / code snippets. Apple uses SF Mono on
        // macOS automatically when JetBrains isn't loaded; on Windows
        // Cascadia Code is the equivalent.
        mono: ['"JetBrains Mono"', 'SF Mono', 'Cascadia Code', 'Menlo', 'monospace'],
      },

      // Strict size scale. Use these and no others — keeps visual
      // rhythm across 31 pages.
      fontSize: {
        xs: ['12px', { lineHeight: '16px', letterSpacing: '0' }],
        sm: ['13px', { lineHeight: '20px', letterSpacing: '0' }],
        base: ['14px', { lineHeight: '20px', letterSpacing: '0' }],
        md: ['16px', { lineHeight: '24px', letterSpacing: '-0.01em' }],
        lg: ['20px', { lineHeight: '28px', letterSpacing: '-0.015em' }],
        xl: ['24px', { lineHeight: '32px', letterSpacing: '-0.02em' }],
        '2xl': ['32px', { lineHeight: '40px', letterSpacing: '-0.02em' }],
        '3xl': ['48px', { lineHeight: '56px', letterSpacing: '-0.025em' }],
      },

      // 4px grid. The non-standard values (5, 7, 9) are intentionally
      // omitted — sticking to the rhythm makes "off by 2px" mistakes
      // obvious in PR review.
      spacing: {
        '0.5': '2px',
        '1': '4px',
        '2': '8px',
        '3': '12px',
        '4': '16px',
        '5': '20px',
        '6': '24px',
        '8': '32px',
        '10': '40px',
        '12': '48px',
        '16': '64px',
        '20': '80px',
        '24': '96px',
        '32': '128px',
      },

      borderRadius: {
        sm: '4px',    // chips, tags, badges
        DEFAULT: '8px', // buttons, inputs
        md: '8px',
        lg: '12px',   // cards
        xl: '16px',   // modals, sheets
        '2xl': '24px',
        full: '9999px',
      },

      boxShadow: {
        // No drop shadows on flat surfaces — depth via hairlines.
        // These are only for elevated layers.
        sm: '0 1px 0 rgba(0,0,0,0.5)',                  // sticky header line
        DEFAULT: '0 4px 12px rgba(0,0,0,0.40)',          // popovers
        md: '0 4px 12px rgba(0,0,0,0.40)',
        lg: '0 12px 32px rgba(0,0,0,0.60)',              // modals
        xl: '0 24px 64px rgba(0,0,0,0.70)',              // sheets
        // Focus ring — 2px cyan glow, not a hard stroke.
        focus: '0 0 0 3px rgba(34, 211, 238, 0.32)',
        // Card hover lift — matches motion.y -2px elsewhere.
        hover: '0 8px 24px rgba(0,0,0,0.50)',
        // Legacy — kept for old `shadow-glow` references.
        glow: '0 0 0 1px rgba(0, 217, 255, 0.15), 0 4px 24px -2px rgba(0, 217, 255, 0.12)',
      },

      // Single easing curve everywhere — ease-out-expo. The default
      // Tailwind `ease-out` is too aggressive for subtle UI motion.
      transitionTimingFunction: {
        'out-expo': 'cubic-bezier(0.16, 1, 0.3, 1)',
      },

      // Pre-canned durations matching the motion language doc.
      transitionDuration: {
        micro: '120ms',
        small: '200ms',
        page: '320ms',
      },

      // Keyframes for primitives that don't need framer-motion.
      keyframes: {
        // Skeleton shimmer — bg gradient slides across.
        shimmer: {
          '0%': { transform: 'translateX(-100%)' },
          '100%': { transform: 'translateX(100%)' },
        },
        // Live status dot — heartbeat for WS-driven counts.
        livepulse: {
          '0%, 100%': { transform: 'scale(1)', opacity: '0.4' },
          '50%': { transform: 'scale(1.08)', opacity: '1' },
        },
      },
      animation: {
        shimmer: 'shimmer 1.6s linear infinite',
        livepulse: 'livepulse 1.5s ease-in-out infinite',
      },
    },
  },
  plugins: [],
}
