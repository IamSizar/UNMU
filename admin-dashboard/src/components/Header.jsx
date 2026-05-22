import { useEffect, useRef, useState } from 'react'
import { Menu, Search, Bell, Globe, Sun, Moon, Volume2, VolumeX, X, Command } from 'lucide-react'
import { isMuted, setMuted, play } from '../api/sounds'
import { useTheme } from '../theme/ThemeContext'
import { useI18n } from '../i18n/I18nContext'
import { LOCALES } from '../i18n/translations'
import { useAuth } from '../auth/AuthContext'

/**
 * Top app bar — sticky, hairline border, glass blur backdrop.
 *
 * Redesign (May 2026): everything from the brand-cyan focus rings down
 * to the icon-button hover states now uses the v2 design tokens. The
 * search field shows a `⌘K` hint to telegraph the keyboard shortcut
 * (Linear-style discoverability).
 */
export default function Header({ onOpenSidebar }) {
  const [muted, setMutedState] = useState(false)
  const [searchOpen, setSearchOpen] = useState(false)
  const { theme, toggle: toggleTheme } = useTheme()
  const { locale, setLocale, t } = useI18n()
  const { user } = useAuth()
  const [langOpen, setLangOpen] = useState(false)
  const langWrapRef = useRef(null)
  useEffect(() => {
    if (!langOpen) return
    function onDoc(e) {
      if (langWrapRef.current && !langWrapRef.current.contains(e.target)) {
        setLangOpen(false)
      }
    }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [langOpen])

  useEffect(() => { setMutedState(isMuted()) }, [])

  function toggleMuted() {
    const next = !muted
    setMuted(next)
    setMutedState(next)
    if (!next) play('info')
  }

  const userName = user?.name ?? user?.email?.split('@')[0] ?? 'Admin'
  const userRole = user?.role ?? 'ADMIN'

  return (
    <header className="h-14 bg-canvas/80 backdrop-blur-xl border-b border-white/[0.06] sticky top-0 z-30">
      <div className="h-full flex items-center gap-2 px-3 sm:px-4 lg:px-6">
        {/* Hamburger — mobile only */}
        <button
          onClick={onOpenSidebar}
          className="lg:hidden p-2 -ms-1 rounded-md hover:bg-white/[0.04] text-fg-muted hover:text-fg transition-colors duration-micro ease-out-expo"
          aria-label={t('header.openMenu')}
        >
          <Menu className="w-[18px] h-[18px]" />
        </button>

        {/* Desktop / tablet search — pill with leading icon + ⌘K hint */}
        <div className="relative flex-1 max-w-[520px] hidden md:block">
          <Search className="w-4 h-4 text-fg-subtle absolute start-3 top-1/2 -translate-y-1/2 pointer-events-none" />
          <input
            type="text"
            placeholder={t('header.search')}
            className="w-full h-9 ps-9 pe-12 rounded-md bg-white/[0.03] ring-1 ring-inset ring-white/[0.06]
                       text-fg placeholder:text-fg-subtle text-sm
                       focus:outline-none focus:ring-brand-cyan/40 focus:ring-2 focus:bg-white/[0.05]
                       transition-shadow duration-micro ease-out-expo"
          />
          {/* Keyboard hint — Linear-style. Decorative; not bound yet. */}
          <kbd className="absolute end-2 top-1/2 -translate-y-1/2 hidden lg:flex items-center gap-0.5 px-1.5 h-5 rounded-sm bg-white/[0.04] ring-1 ring-inset ring-white/[0.08] text-fg-subtle text-[10px] font-mono">
            <Command className="w-3 h-3" />K
          </kbd>
        </div>

        {/* Spacer so icons hug the right on phones */}
        <div className="flex-1 md:hidden" />

        <div className="flex items-center gap-0.5">
          <IconButton
            icon={Search}
            onClick={() => setSearchOpen(true)}
            title={t('common.search')}
            className="md:hidden"
          />
          {/* Language picker */}
          <div ref={langWrapRef} className="relative hidden sm:block">
            <button
              onClick={() => setLangOpen((v) => !v)}
              className="h-9 px-2.5 rounded-md hover:bg-white/[0.04] text-fg-muted hover:text-fg flex items-center gap-1.5 transition-colors duration-micro ease-out-expo"
              title={t('header.language')}
            >
              <Globe className="w-4 h-4" />
              <span className="text-xs font-bold uppercase tracking-[0.05em] font-mono">{locale}</span>
            </button>
            {langOpen && (
              <div className="absolute end-0 top-full mt-1.5 min-w-[180px] rounded-lg bg-elevated ring-1 ring-white/[0.10] shadow-lg z-50 p-1">
                {LOCALES.map((l) => (
                  <button
                    key={l.code}
                    onClick={() => {
                      setLocale(l.code)
                      setLangOpen(false)
                    }}
                    className={`w-full text-start px-3 py-2 rounded-md text-sm flex items-center justify-between gap-3 transition-colors duration-micro ease-out-expo ${
                      locale === l.code
                        ? 'bg-brand-cyan/15 text-brand-cyan'
                        : 'text-fg-muted hover:bg-white/[0.04] hover:text-fg'
                    }`}
                  >
                    <span>{l.native}</span>
                    <span className="text-[10px] font-mono uppercase text-fg-subtle">
                      {l.code}
                    </span>
                  </button>
                ))}
              </div>
            )}
          </div>
          <IconButton
            icon={theme === 'dark' ? Sun : Moon}
            onClick={toggleTheme}
            title={theme === 'dark' ? t('header.switchToLight') : t('header.switchToDark')}
          />
          <IconButton
            icon={muted ? VolumeX : Volume2}
            onClick={toggleMuted}
            title={muted ? t('header.unmuteNotifications') : t('header.muteNotifications')}
            tone={muted ? 'err' : undefined}
          />
          <IconButton icon={Bell} badge={7} />
          <div className="w-px h-5 bg-white/[0.08] mx-2 hidden sm:block" />
          {/* User chip — real auth, not placeholder. */}
          <div className="flex items-center gap-2.5 ps-1 sm:pe-1">
            <div className="w-8 h-8 rounded-full bg-brand-cyan/15 ring-1 ring-brand-cyan/30 flex items-center justify-center text-brand-cyan text-xs font-bold shrink-0">
              {userName.charAt(0).toUpperCase()}
            </div>
            <div className="leading-tight hidden lg:block">
              <p className="text-sm font-semibold text-fg truncate max-w-[140px]">{userName}</p>
              <p className="text-[10px] font-bold tracking-[0.05em] uppercase text-brand-cyan">
                {userRole}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Mobile search overlay */}
      {searchOpen && (
        <div className="absolute inset-x-0 top-0 h-14 bg-canvas flex items-center gap-2 px-3 md:hidden border-b border-white/[0.06]">
          <Search className="w-4 h-4 text-fg-subtle absolute start-6 top-1/2 -translate-y-1/2 pointer-events-none" />
          <input
            autoFocus
            type="text"
            placeholder={t('header.search')}
            className="flex-1 h-9 ps-9 pe-3 rounded-md bg-white/[0.03] ring-1 ring-inset ring-white/[0.06] text-fg placeholder:text-fg-subtle text-sm focus:outline-none focus:ring-brand-cyan/40 focus:ring-2"
          />
          <button
            onClick={() => setSearchOpen(false)}
            className="p-2 rounded-md hover:bg-white/[0.04] text-fg-muted hover:text-fg"
            aria-label={t('header.closeSearch')}
          >
            <X className="w-[18px] h-[18px]" />
          </button>
        </div>
      )}
    </header>
  )
}

// ────────────────────────────────────────────────────────────────────
// Small icon button used across the header row.
// `tone="err"` flips the icon to red (used for mute state).
// `badge` shows a small dot with a count (the Bell uses it).
// ────────────────────────────────────────────────────────────────────
function IconButton({ icon: Icon, badge, label, onClick, title, tone, className = '' }) {
  const toneCls = tone === 'err'
    ? 'text-err hover:text-err'
    : 'text-fg-muted hover:text-fg'
  return (
    <button
      onClick={onClick}
      title={title}
      className={`relative h-9 px-2 rounded-md hover:bg-white/[0.04] transition-colors duration-micro ease-out-expo flex items-center gap-1.5 ${toneCls} ${className}`}
    >
      <Icon className="w-[18px] h-[18px]" />
      {label && <span className="text-xs font-semibold">{label}</span>}
      {badge && (
        <span className="absolute top-1.5 end-1 min-w-[16px] h-4 px-1 rounded-sm bg-brand-cyan text-canvas text-[10px] font-mono font-bold tabular-nums flex items-center justify-center ring-2 ring-canvas">
          {badge}
        </span>
      )}
    </button>
  )
}
