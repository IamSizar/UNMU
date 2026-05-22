/**
 * NodeDetail — bottom drawer that appears when the admin clicks any
 * node in the network graph.
 *
 * Renders type-specific information:
 *   - Expert: subscribers count, communities owned, "Open profile" link
 *   - User: subscriptions + community memberships count
 *   - Community: members count, owner, "Open community" link
 *
 * Slides in from below using framer-motion (`<AnimatePresence>` +
 * `y: 60 → 0`). Closes when the parent passes `node={null}` (clicking
 * background on the graph triggers that).
 */

import { motion, AnimatePresence } from 'framer-motion'
import {
  ArrowUpRight,
  Crown,
  Users as UsersIcon,
  Users2,
  ShieldCheck,
  X,
} from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { DUR, EASE } from '../ui/motion'
import { useI18n } from '../i18n/I18nContext'
import type { GraphNode } from './NetworkGraph'

type Props = {
  node: GraphNode | null
  // Resolved counts/details from the graph payload — passed in by the
  // parent so this component stays presentation-only.
  details?: {
    subscriberCount?: number
    subscriptionCount?: number
    membershipCount?: number
    communityCount?: number
    memberCount?: number
    email?: string
    expertise?: string
    ownerName?: string
    pending?: boolean
  }
  onClose: () => void
}

export default function NodeDetail({ node, details, onClose }: Props) {
  const { t } = useI18n()
  const navigate = useNavigate()

  return (
    <AnimatePresence>
      {node && (
        <motion.div
          initial={{ opacity: 0, y: 60 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 60 }}
          transition={{ duration: DUR.small, ease: EASE }}
          className="absolute start-4 end-4 bottom-4 z-20"
        >
          <div className="card-v2 shadow-lg p-4 sm:p-5">
            <div className="flex items-start gap-4">
              <NodeIcon kind={node.kind} pending={details?.pending} />

              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <p className="text-[10px] font-bold tracking-[0.08em] uppercase text-fg-subtle">
                    {kindLabel(node.kind, t)}
                  </p>
                  {details?.pending && (
                    <span className="px-1.5 h-[18px] inline-flex items-center rounded-sm bg-brand-gold/15 text-brand-gold text-[10px] font-mono font-bold ring-1 ring-inset ring-brand-gold/30">
                      {t('nodeDetail.pending')}
                    </span>
                  )}
                </div>
                <h3 className="text-lg font-extrabold tracking-tight text-fg mt-0.5 truncate">
                  {node.name}
                </h3>
                {(details?.expertise || details?.email) && (
                  <p className="text-xs text-fg-muted truncate">
                    {details.expertise || details.email}
                  </p>
                )}

                {/* Stats strip — adapts to node kind. */}
                <div className="flex items-center gap-5 mt-3 flex-wrap">
                  {node.kind === 'expert' && (
                    <>
                      <Stat
                        label={t('nodeDetail.subscribers')}
                        value={details?.subscriberCount ?? 0}
                      />
                      <Stat
                        label={t('nodeDetail.communities')}
                        value={details?.communityCount ?? 0}
                      />
                    </>
                  )}
                  {node.kind === 'user' && (
                    <>
                      <Stat
                        label={t('nodeDetail.subscriptions')}
                        value={details?.subscriptionCount ?? 0}
                      />
                      <Stat
                        label={t('nodeDetail.memberships')}
                        value={details?.membershipCount ?? 0}
                      />
                    </>
                  )}
                  {node.kind === 'community' && (
                    <>
                      <Stat
                        label={t('nodeDetail.members')}
                        value={details?.memberCount ?? 0}
                      />
                      {details?.ownerName && (
                        <Stat label={t('nodeDetail.owner')} value={details.ownerName} mono={false} />
                      )}
                    </>
                  )}
                </div>
              </div>

              {/* Actions + close */}
              <div className="flex items-center gap-2 shrink-0">
                {node.kind === 'expert' && (
                  <button
                    onClick={() => navigate(`/experts`)}
                    className="btn-v2-secondary text-xs"
                  >
                    {t('nodeDetail.openProfile')}
                    <ArrowUpRight className="w-3.5 h-3.5 rtl:-scale-x-100" />
                  </button>
                )}
                {node.kind === 'user' && (
                  <button
                    onClick={() =>
                      navigate(`/users/${node.id.replace('u_', '')}`)
                    }
                    className="btn-v2-secondary text-xs"
                  >
                    {t('nodeDetail.openUser')}
                    <ArrowUpRight className="w-3.5 h-3.5 rtl:-scale-x-100" />
                  </button>
                )}
                {node.kind === 'community' && (
                  <button
                    onClick={() =>
                      navigate(
                        `/communities/${node.id.replace('c_', '')}`,
                      )
                    }
                    className="btn-v2-secondary text-xs"
                  >
                    {t('nodeDetail.openCommunity')}
                    <ArrowUpRight className="w-3.5 h-3.5 rtl:-scale-x-100" />
                  </button>
                )}
                <button
                  onClick={onClose}
                  className="p-1.5 rounded-md hover:bg-hairline text-fg-subtle hover:text-fg"
                  aria-label={t('nodeDetail.close')}
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
            </div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  )
}

function NodeIcon({
  kind,
  pending,
}: {
  kind: GraphNode['kind']
  pending?: boolean
}) {
  const baseClass = 'w-11 h-11 rounded-lg flex items-center justify-center ring-1 ring-inset shrink-0'
  if (kind === 'expert') {
    return (
      <div
        className={`${baseClass} bg-brand-gold/15 text-brand-gold ring-brand-gold/30 ${
          pending ? 'animate-livepulse' : ''
        }`}
      >
        <Crown className="w-5 h-5" />
      </div>
    )
  }
  if (kind === 'community') {
    return (
      <div
        className={`${baseClass} bg-info/15 text-info ring-info/30`}
      >
        <Users2 className="w-5 h-5" />
      </div>
    )
  }
  return (
    <div className={`${baseClass} bg-brand-cyan/15 text-brand-cyan ring-brand-cyan/30`}>
      <UsersIcon className="w-5 h-5" />
    </div>
  )
}

function Stat({
  label,
  value,
  mono = true,
}: {
  label: string
  value: number | string
  mono?: boolean
}) {
  return (
    <div className="flex flex-col">
      <span className="text-[10px] font-bold tracking-[0.05em] uppercase text-fg-subtle">
        {label}
      </span>
      <span
        className={`text-base font-bold text-fg leading-none mt-0.5 ${
          mono ? 'font-mono tabular-nums' : ''
        }`}
      >
        {value}
      </span>
    </div>
  )
}

function kindLabel(
  kind: GraphNode['kind'],
  t: (key: any, vars?: Record<string, unknown>) => string,
): string {
  if (kind === 'expert') return t('nodeDetail.kindExpert')
  if (kind === 'community') return t('nodeDetail.kindCommunity')
  return t('nodeDetail.kindUser')
}

// Suppress unused-icon warning — ShieldCheck is here for future
// "verified" badge usage on the expert avatar.
void ShieldCheck
