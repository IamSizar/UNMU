/**
 * Sidebar — primary navigation for the UNMU admin dashboard.
 *
 * Redesign notes (May 2026):
 *   - Visual layer rebuilt against the v2 design system: `bg-canvas`,
 *     `border-white/[0.06]` hairlines, brand-cyan active state with an
 *     animated indicator bar instead of a tinted background pill.
 *   - Section labels lean into uppercase + tracking (Linear-style).
 *   - Realtime indicator uses the new <LivePulseDot> primitive.
 *   - The drawer slide-in on mobile is now driven by framer-motion so
 *     the spring matches every other panel in the app.
 *
 * Public API (props, exports) is unchanged so DashboardLayout doesn't
 * need to know about the redesign.
 */

import { NavLink, useLocation, useNavigate } from 'react-router-dom'
import { useEffect, useState } from 'react'
import { motion } from 'framer-motion'
import {
  LayoutDashboard,
  Users as UsersIcon,
  GraduationCap,
  UserCheck,
  TrendingUp,
  CreditCard,
  TicketPercent,
  Megaphone,
  Bell,
  Settings as SettingsIcon,
  LogOut,
  Activity,
  Flag,
  Wallet,
  Upload,
  Stethoscope,
  Newspaper,
  Users2,
  Lightbulb,
  BarChart3,
  LifeBuoy,
  Network as NetworkIcon,
  X,
} from 'lucide-react'
import { useAuth } from '../auth/AuthContext'
import { api } from '../api/client'
import { useRealtime, useRealtimeStatus } from '../api/realtime'
import { useI18n } from '../i18n/I18nContext'
import type { TranslationKey } from '../i18n/translations'
import { DUR, EASE, LivePulseDot } from '../ui/motion'

type NavItem = {
  to: string
  label: TranslationKey
  icon: React.ComponentType<{ className?: string }>
  badge?: string | number
}

type SidebarProps = {
  open: boolean
  onClose: () => void
}

// ── Section definitions ────────────────────────────────────────────
// Static arrays for sections that never grow a badge; functions for
// sections that need to bind a live pending-count number.

// "primary" — top of the sidebar, no section heading. Overview + the
// live platform Network map. Network sits right under Overview so the
// admin can flip between "the numbers" (Dashboard) and "the relationships"
// (Network) without scrolling.
const primary: NavItem[] = [
  { to: '/dashboard', label: 'nav.overview', icon: LayoutDashboard },
  { to: '/network', label: 'nav.network', icon: NetworkIcon },
]

function communityItems(
  pendingCount: number | null,
  pendingProposalsCount: number | null,
): NavItem[] {
  return [
    { to: '/users', label: 'nav.users', icon: UsersIcon },
    { to: '/experts', label: 'nav.experts', icon: GraduationCap },
    {
      to: '/applications',
      label: 'nav.applications',
      icon: UserCheck,
      badge: pendingCount && pendingCount > 0 ? pendingCount : undefined,
    },
    { to: '/communities', label: 'nav.communities', icon: Users2 },
    {
      to: '/community-proposals',
      label: 'nav.communityProposals',
      icon: Lightbulb,
      badge:
        pendingProposalsCount && pendingProposalsCount > 0
          ? pendingProposalsCount
          : undefined,
    },
    { to: '/polls', label: 'nav.polls', icon: BarChart3 },
  ]
}

const content: NavItem[] = [
  { to: '/posts', label: 'nav.posts', icon: Newspaper },
]

function supportItems(pendingSupportCount: number | null): NavItem[] {
  return [
    {
      to: '/support',
      label: 'nav.support',
      icon: LifeBuoy,
      badge:
        pendingSupportCount && pendingSupportCount > 0
          ? pendingSupportCount
          : undefined,
    },
  ]
}

const market: NavItem[] = [
  { to: '/stocks', label: 'nav.stocks', icon: TrendingUp },
]

function monetizationItems(
  pendingSubsCount: number | null,
  pendingCommunitySubsCount: number | null,
  pendingPayoutsCount: number | null,
): NavItem[] {
  return [
    {
      to: '/subscriptions',
      label: 'nav.subscriptions',
      icon: CreditCard,
      badge:
        pendingSubsCount && pendingSubsCount > 0 ? pendingSubsCount : undefined,
    },
    {
      to: '/community-subscriptions',
      label: 'nav.communitySubscriptions',
      icon: Users2,
      badge:
        pendingCommunitySubsCount && pendingCommunitySubsCount > 0
          ? pendingCommunitySubsCount
          : undefined,
    },
    {
      to: '/payouts',
      label: 'nav.payouts',
      icon: Wallet,
      badge:
        pendingPayoutsCount && pendingPayoutsCount > 0
          ? pendingPayoutsCount
          : undefined,
    },
    { to: '/promos', label: 'nav.promos', icon: TicketPercent },
    { to: '/ads', label: 'nav.ads', icon: Megaphone },
  ]
}

function systemItems(pendingReportsCount: number | null): NavItem[] {
  return [
    { to: '/notifications', label: 'nav.notifications', icon: Bell },
    {
      to: '/reports',
      label: 'nav.reports',
      icon: Flag,
      badge:
        pendingReportsCount && pendingReportsCount > 0
          ? pendingReportsCount
          : undefined,
    },
    { to: '/audit-log', label: 'nav.auditLog', icon: Activity },
    { to: '/uploads', label: 'nav.uploads', icon: Upload },
    { to: '/diagnostics', label: 'nav.diagnostics', icon: Stethoscope },
    { to: '/settings', label: 'nav.settings', icon: SettingsIcon },
  ]
}

// ────────────────────────────────────────────────────────────────────
// Section — one labeled group of nav items.
// ────────────────────────────────────────────────────────────────────
function Section({
  title,
  items,
  onNavigate,
  activeKey,
}: {
  title?: TranslationKey
  items: NavItem[]
  onNavigate?: () => void
  /** Shared key across all sections so the active indicator can
   *  animate between rows via framer-motion's layoutId. */
  activeKey: string
}) {
  const { t } = useI18n()
  return (
    <div>
      {title && (
        <p className="px-3 pt-5 pb-2 text-[10px] font-bold uppercase tracking-[0.12em] text-fg-subtle">
          {t(title)}
        </p>
      )}
      <div className="space-y-px">
        {items.map(({ to, label, icon: Icon, badge }) => (
          <NavLink
            key={to}
            to={to}
            onClick={onNavigate}
            className={({ isActive }) =>
              [
                'group relative flex items-center gap-3 px-3 h-9 rounded-md',
                'text-sm font-medium tracking-[-0.005em]',
                'transition-colors duration-micro ease-out-expo',
                isActive
                  ? 'text-fg'
                  : 'text-fg-muted hover:text-fg hover:bg-white/[0.03]',
              ].join(' ')
            }
          >
            {({ isActive }) => (
              <>
                {/* Animated left bar — slides between active items
                    instead of fading. Linear-style. */}
                {isActive && (
                  <motion.span
                    layoutId={activeKey}
                    className="absolute start-0 top-1.5 bottom-1.5 w-[3px] rounded-e-full bg-brand-cyan"
                    transition={{ duration: DUR.small, ease: EASE }}
                  />
                )}
                <Icon
                  className={`w-[18px] h-[18px] shrink-0 ${
                    isActive ? 'text-brand-cyan' : ''
                  }`}
                />
                <span className="flex-1 truncate">{t(label)}</span>
                {badge && (
                  <span
                    className="px-1.5 h-[18px] inline-flex items-center justify-center
                               rounded-sm text-[10px] font-mono font-bold tabular-nums
                               bg-brand-gold/15 text-brand-gold ring-1 ring-inset ring-brand-gold/30"
                  >
                    {badge}
                  </span>
                )}
              </>
            )}
          </NavLink>
        ))}
      </div>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Sidebar
// ────────────────────────────────────────────────────────────────────
export default function Sidebar({ open, onClose }: SidebarProps) {
  const { user, logout } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()
  const { t } = useI18n()
  const [pendingCount, setPendingCount] = useState<number | null>(null)
  const [pendingSubsCount, setPendingSubsCount] = useState<number | null>(null)
  const [pendingProposalsCount, setPendingProposalsCount] =
    useState<number | null>(null)
  const [pendingCommunitySubsCount, setPendingCommunitySubsCount] =
    useState<number | null>(null)
  const [pendingSupportCount, setPendingSupportCount] = useState<number | null>(
    null,
  )
  const [pendingReportsCount, setPendingReportsCount] = useState<number | null>(
    null,
  )
  const [pendingPayoutsCount, setPendingPayoutsCount] = useState<number | null>(
    null,
  )
  const realtimeOnline = useRealtimeStatus()

  // Stable layoutId for the active-row indicator. Shared across every
  // Section so the bar animates smoothly when navigation moves between
  // sections (e.g. Users → Polls).
  const activeKey = 'sidebar-active-' + location.pathname

  async function loadPending() {
    try {
      const res = await api.get<{ count: number }>(
        '/admin/expert-applications/pending-count',
      )
      setPendingCount(res.count ?? 0)
    } catch {
      setPendingCount(0)
    }
  }

  async function loadPendingSubs() {
    try {
      const res = await api.get<{ count: number }>(
        '/admin/subscriptions/pending-count',
      )
      setPendingSubsCount(res.count ?? 0)
    } catch {
      setPendingSubsCount(0)
    }
  }

  async function loadPendingProposals() {
    try {
      const res = await api.get<{ count: number }>(
        '/admin/community-proposals/pending-count',
      )
      setPendingProposalsCount(res.count ?? 0)
    } catch {
      setPendingProposalsCount(0)
    }
  }

  async function loadPendingCommunitySubs() {
    try {
      const res = await api.get<{ count: number }>(
        '/admin/community-subscriptions/pending-count',
      )
      setPendingCommunitySubsCount(res.count ?? 0)
    } catch {
      setPendingCommunitySubsCount(0)
    }
  }

  async function loadPendingSupport() {
    try {
      const res = await api.get<{ count: number }>(
        '/admin/support/pending-count',
      )
      setPendingSupportCount(res.count ?? 0)
    } catch {
      setPendingSupportCount(0)
    }
  }

  async function loadPendingReports() {
    try {
      const res = await api.get<{ count: number }>(
        '/admin/reports/pending-count',
      )
      setPendingReportsCount(res.count ?? 0)
    } catch {
      setPendingReportsCount(0)
    }
  }

  async function loadPendingPayouts() {
    try {
      const res = await api.get<{ count: number }>(
        '/admin/payouts/pending-count',
      )
      setPendingPayoutsCount(res.count ?? 0)
    } catch {
      setPendingPayoutsCount(0)
    }
  }

  useEffect(() => {
    loadPending()
    loadPendingSubs()
    loadPendingProposals()
    loadPendingCommunitySubs()
    loadPendingSupport()
    loadPendingReports()
    loadPendingPayouts()
    const t = setInterval(() => {
      loadPending()
      loadPendingSubs()
      loadPendingProposals()
      loadPendingCommunitySubs()
      loadPendingSupport()
      loadPendingReports()
      loadPendingPayouts()
    }, 60_000)
    return () => clearInterval(t)
  }, [])

  useRealtime(
    [
      'application_submitted',
      'application_resolved',
      'application_approved',
      'application_rejected',
    ],
    loadPending,
  )
  useRealtime(
    [
      'subscription_submitted',
      'subscription_active',
      'subscription_rejected',
      'subscription_cancelled',
      'subscription_expired',
    ],
    loadPendingSubs,
  )
  useRealtime(
    [
      'community_subscription_submitted',
      'community_subscription_active',
      'community_subscription_rejected',
      'community_subscription_expired',
    ],
    loadPendingCommunitySubs,
  )
  useRealtime(
    [
      'community_proposal_submitted',
      'community_proposal_approved',
      'community_proposal_rejected',
    ],
    loadPendingProposals,
  )
  useRealtime(
    ['support_message_sent', 'support_thread_closed'],
    loadPendingSupport,
  )
  // Payouts (Phase 4.9). Backend doesn't fan-out payout events on the
  // realtime channel yet, so the 60s poll is the primary refresh path —
  // we listen here defensively so when the publisher is added the
  // badge starts updating live without another sidebar edit.
  useRealtime(
    ['payout_requested', 'payout_paid', 'payout_rejected', 'payout_cancelled'],
    loadPendingPayouts,
  )

  return (
    <>
      {/* Mobile backdrop — click anywhere outside to dismiss. */}
      <div
        onClick={onClose}
        aria-hidden={!open}
        className={`lg:hidden fixed inset-0 z-40 bg-black/70 backdrop-blur-sm
                    transition-opacity duration-small ease-out-expo ${
                      open
                        ? 'opacity-100 pointer-events-auto'
                        : 'opacity-0 pointer-events-none'
                    }`}
      />

      <aside
        className={[
          'fixed inset-y-0 left-0 z-50 w-72 sm:w-64',
          'bg-canvas border-r border-white/[0.06] flex flex-col',
          'transform transition-transform duration-page ease-out-expo',
          'lg:static lg:translate-x-0 lg:z-0 lg:w-60',
          open ? 'translate-x-0' : '-translate-x-full',
        ].join(' ')}
        aria-label={t('sidebar.primaryNav')}
      >
        {/* Brand header — wordmark + admin label. */}
        <div className="h-14 flex items-center gap-2.5 px-4 border-b border-white/[0.06]">
          <img
            src="/unmu-wordmark.png"
            alt="UNMU"
            className="h-7 w-auto shrink-0"
            draggable={false}
          />
          <span className="text-[9px] font-bold tracking-[0.18em] uppercase text-brand-cyan/80">
            {t('sidebar.adminBadge')}
          </span>
          <div className="flex-1" />
          <button
            onClick={onClose}
            className="lg:hidden p-1.5 rounded-md hover:bg-white/[0.04] text-fg-muted hover:text-fg"
            aria-label={t('sidebar.closeMenu')}
          >
            <X className="w-[18px] h-[18px]" />
          </button>
        </div>

        <nav className="flex-1 px-2 py-3 overflow-y-auto">
          <Section
            items={primary}
            onNavigate={onClose}
            activeKey={activeKey}
          />
          <Section
            title="nav.community"
            items={communityItems(pendingCount, pendingProposalsCount)}
            onNavigate={onClose}
            activeKey={activeKey}
          />
          <Section
            title="nav.content"
            items={content}
            onNavigate={onClose}
            activeKey={activeKey}
          />
          <Section
            title="nav.market"
            items={market}
            onNavigate={onClose}
            activeKey={activeKey}
          />
          <Section
            title="nav.monetization"
            items={monetizationItems(
              pendingSubsCount,
              pendingCommunitySubsCount,
              pendingPayoutsCount,
            )}
            onNavigate={onClose}
            activeKey={activeKey}
          />
          <Section
            title="nav.support"
            items={supportItems(pendingSupportCount)}
            onNavigate={onClose}
            activeKey={activeKey}
          />
          <Section
            title="nav.system"
            items={systemItems(pendingReportsCount)}
            onNavigate={onClose}
            activeKey={activeKey}
          />
        </nav>

        {/* Account footer — avatar + name + role + realtime status. */}
        <div className="p-2 border-t border-white/[0.06]">
          <div className="flex items-center gap-3 p-2 rounded-md hover:bg-white/[0.03] transition-colors duration-micro ease-out-expo">
            <div className="relative shrink-0">
              <div className="w-9 h-9 rounded-full bg-brand-cyan/15 ring-1 ring-brand-cyan/30 flex items-center justify-center text-brand-cyan font-bold">
                {(user?.name ?? user?.email ?? '?').charAt(0).toUpperCase()}
              </div>
              {/* Realtime online indicator — uses LivePulseDot when on. */}
              <span
                title={
                  realtimeOnline ? t('sidebar.realtimeConnected') : t('sidebar.realtimeOffline')
                }
                className="absolute -bottom-0.5 -end-0.5 ring-2 ring-canvas rounded-full"
              >
                {realtimeOnline ? (
                  <LivePulseDot color="ok" size={10} />
                ) : (
                  <span
                    className="block w-2.5 h-2.5 rounded-full bg-err/80"
                  />
                )}
              </span>
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-fg truncate">
                {user?.name ?? user?.email ?? 'Admin'}
              </p>
              <p className="text-[11px] text-fg-subtle truncate">
                {user?.role ?? 'ADMIN'} ·{' '}
                {t(realtimeOnline ? 'header.live' : 'header.offline')}
              </p>
            </div>
            <button
              onClick={() => {
                logout()
                navigate('/login', { replace: true })
              }}
              title={t('header.signOut')}
              className="p-1.5 rounded-md hover:bg-white/[0.04] text-fg-subtle hover:text-fg shrink-0"
            >
              <LogOut className="w-4 h-4" />
            </button>
          </div>
        </div>
      </aside>
    </>
  )
}
