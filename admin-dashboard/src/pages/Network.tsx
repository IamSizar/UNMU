/**
 * Network — the live platform map.
 *
 * Reads /api/admin/network/graph once on mount, renders it as a
 * force-directed visualisation (NetworkGraph) with a right-side feed
 * of pending events (PendingEventsPanel) and a bottom drawer that
 * appears when the admin clicks a node (NodeDetail).
 *
 * Realtime: subscribes to the same WS events the sidebar uses
 * (`application_*`, `subscription_*`, `community_proposal_*`,
 * `community_subscription_*`) — when one fires, we re-fetch the
 * graph payload. Future iteration: surgical patches that animate
 * single-edge insertions rather than full re-fetches.
 */

import { useEffect, useMemo, useState } from 'react'
import { Filter, GraduationCap, Loader2, Users as UsersIcon, Users2 } from 'lucide-react'
import { api } from '../api/client'
import { useI18n } from '../i18n/I18nContext'
import { useRealtime } from '../api/realtime'
import { FadeIn, LivePulseDot, NumberTicker } from '../ui/motion'
import NetworkGraph, {
  type GraphLink,
  type GraphNode,
} from '../components/NetworkGraph'
import PendingEventsPanel, {
  type PendingEvent,
} from '../components/PendingEventsPanel'
import NodeDetail from '../components/NodeDetail'

// ── API response shape (mirrors backend NetworkGraphResponse) ─────
type NetExpert = {
  id: number
  expertId: string
  name: string
  expertise: string
  subscriberCount: number
  communityCount: number
  pending: boolean
}
type NetUser = {
  id: number
  name: string
  email: string
  subscriptionCount: number
  membershipCount: number
}
type NetCommunity = {
  id: string
  name: string
  memberCount: number
  ownerUserId: number
}
type NetRawEdge = {
  type: 'subscription' | 'community_member' | 'owns'
  source: number
  targetUserId?: number
  targetCommunity?: string
  status?: string
  plan?: string
}
type NetGraphResp = {
  experts: NetExpert[]
  users: NetUser[]
  communities: NetCommunity[]
  edges: NetRawEdge[]
  pending: PendingEvent[]
}

// ── Node-id namespacing ────────────────────────────────────────────
// Three node sets share one id space inside react-force-graph, so we
// prefix to avoid collisions: u_, e_, c_.
const uid = (id: number) => `u_${id}`
const eid = (id: number) => `e_${id}`
const cid = (id: string) => `c_${id}`

type Filters = {
  experts: boolean
  users: boolean
  communities: boolean
  pendingOnly: boolean
}

export default function Network() {
  const { t } = useI18n()
  const [data, setData] = useState<NetGraphResp | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [clicked, setClicked] = useState<GraphNode | null>(null)
  const [focusFromPanel, setFocusFromPanel] = useState<string | null>(null)
  const [filters, setFilters] = useState<Filters>({
    experts: true,
    users: true,
    communities: true,
    pendingOnly: false,
  })

  async function load() {
    try {
      const res = await api.get<NetGraphResp>('/admin/network/graph')
      setData(res)
      setError(null)
    } catch (e: any) {
      setError(e?.message ?? t('network.error.load'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    load()
  }, [])

  // Realtime — re-fetch on the same events the sidebar listens for.
  // (Surgical patches are a v2 enhancement.)
  useRealtime(
    [
      'application_submitted',
      'application_resolved',
      'application_approved',
      'application_rejected',
      'subscription_submitted',
      'subscription_active',
      'subscription_rejected',
      'subscription_cancelled',
      'community_subscription_submitted',
      'community_subscription_active',
      'community_subscription_rejected',
      'community_proposal_submitted',
      'community_proposal_approved',
      'community_proposal_rejected',
    ],
    () => load(),
  )

  // ── Adapt the API payload to react-force-graph's node/link shape ──
  const { nodes, links } = useMemo(() => {
    if (!data) return { nodes: [], links: [] }

    const nodes: GraphNode[] = []
    const links: GraphLink[] = []

    if (filters.experts) {
      for (const e of data.experts) {
        if (filters.pendingOnly && !e.pending) continue
        nodes.push({
          id: uid(e.id),
          kind: 'expert',
          name: e.name,
          weight: e.subscriberCount,
          pending: e.pending,
        })
      }
    }
    if (filters.users) {
      for (const u of data.users) {
        if (filters.pendingOnly) continue
        nodes.push({
          id: uid(u.id),
          kind: 'user',
          name: u.name || u.email.split('@')[0],
          weight: u.subscriptionCount,
        })
      }
    }
    if (filters.communities) {
      for (const c of data.communities) {
        if (filters.pendingOnly) continue
        nodes.push({
          id: cid(c.id),
          kind: 'community',
          name: c.name,
          weight: c.memberCount,
        })
      }
    }

    // Build a quick set of present node IDs so we don't render
    // dangling edges when a filter is off.
    const present = new Set(nodes.map((n) => n.id))

    for (const e of data.edges) {
      if (e.type === 'subscription' && e.targetUserId) {
        const src = uid(e.source)
        const tgt = uid(e.targetUserId)
        if (present.has(src) && present.has(tgt)) {
          links.push({
            source: src,
            target: tgt,
            type: 'subscription',
            status: e.status,
            plan: e.plan,
          })
        }
      } else if (e.type === 'community_member' && e.targetCommunity) {
        const src = uid(e.source)
        const tgt = cid(e.targetCommunity)
        if (present.has(src) && present.has(tgt)) {
          links.push({
            source: src,
            target: tgt,
            type: 'community_member',
          })
        }
      } else if (e.type === 'owns' && e.targetCommunity) {
        const src = uid(e.source)
        const tgt = cid(e.targetCommunity)
        if (present.has(src) && present.has(tgt)) {
          links.push({
            source: src,
            target: tgt,
            type: 'owns',
          })
        }
      }
    }

    return { nodes, links }
  }, [data, filters])

  // Resolve hovered-event actor → graph node id so the panel can
  // dim everything except that node.
  function actorToNodeId(actorUserId: number | null): string | null {
    if (!actorUserId) return null
    return uid(actorUserId)
  }

  // Look up the details to show in the bottom drawer.
  const clickedDetails = useMemo(() => {
    if (!clicked || !data) return undefined
    if (clicked.kind === 'expert') {
      const e = data.experts.find((x) => uid(x.id) === clicked.id)
      return e
        ? {
            subscriberCount: e.subscriberCount,
            communityCount: e.communityCount,
            expertise: e.expertise,
            pending: e.pending,
          }
        : undefined
    }
    if (clicked.kind === 'user') {
      const u = data.users.find((x) => uid(x.id) === clicked.id)
      return u
        ? {
            subscriptionCount: u.subscriptionCount,
            membershipCount: u.membershipCount,
            email: u.email,
          }
        : undefined
    }
    if (clicked.kind === 'community') {
      const c = data.communities.find((x) => cid(x.id) === clicked.id)
      if (!c) return undefined
      const owner = data.experts.find((x) => x.id === c.ownerUserId)
      return {
        memberCount: c.memberCount,
        ownerName: owner?.name,
      }
    }
    return undefined
  }, [clicked, data])

  return (
    <div className="space-y-6 max-w-[1600px] mx-auto">
      <FadeIn>
        <div className="flex items-end justify-between gap-4 flex-wrap">
          <div>
            <h1 className="h1-v2">{t('network.title')}</h1>
            <p className="text-fg-muted text-sm mt-1">
              {t('network.subtitle')}
            </p>
          </div>
          <div className="flex items-center gap-2">
            <FilterChip
              icon={GraduationCap}
              label={t('network.filter.experts')}
              active={filters.experts}
              onClick={() => setFilters((f) => ({ ...f, experts: !f.experts }))}
            />
            <FilterChip
              icon={UsersIcon}
              label={t('network.filter.users')}
              active={filters.users}
              onClick={() => setFilters((f) => ({ ...f, users: !f.users }))}
            />
            <FilterChip
              icon={Users2}
              label={t('network.filter.communities')}
              active={filters.communities}
              onClick={() =>
                setFilters((f) => ({ ...f, communities: !f.communities }))
              }
            />
            <FilterChip
              icon={Filter}
              label={t('network.filter.pendingOnly')}
              active={filters.pendingOnly}
              gold
              onClick={() =>
                setFilters((f) => ({ ...f, pendingOnly: !f.pendingOnly }))
              }
            />
          </div>
        </div>
      </FadeIn>

      {/* Stat strip */}
      <FadeIn delay={0.04}>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <StatStrip
            label={t('network.stat.experts')}
            value={data?.experts.length ?? 0}
            live
          />
          <StatStrip
            label={t('network.stat.subscribers')}
            value={data?.users.length ?? 0}
          />
          <StatStrip
            label={t('network.stat.communities')}
            value={data?.communities.length ?? 0}
          />
          <StatStrip
            label={t('network.stat.pending')}
            value={data?.pending.length ?? 0}
            tone="gold"
            live
          />
        </div>
      </FadeIn>

      {/* Main grid: graph (2/3) + pending panel (1/3) */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 h-[640px]">
        {/* Graph */}
        <div className="lg:col-span-2 relative">
          <div className="card-v2 absolute inset-0 overflow-hidden">
            {loading ? (
              <div className="flex items-center justify-center h-full text-fg-muted">
                <Loader2 className="w-5 h-5 animate-spin me-2" />{' '}
                {t('network.loading')}
              </div>
            ) : error ? (
              <div className="flex items-center justify-center h-full text-err text-sm">
                {error}
              </div>
            ) : nodes.length === 0 ? (
              <EmptyGraph />
            ) : (
              <NetworkGraph
                nodes={nodes}
                links={links}
                onNodeClick={setClicked}
                focusNodeId={focusFromPanel}
              />
            )}

            {/* Legend overlay */}
            {!loading && !error && nodes.length > 0 && (
              <Legend />
            )}
          </div>

          <NodeDetail
            node={clicked}
            details={clickedDetails}
            onClose={() => setClicked(null)}
          />
        </div>

        {/* Pending panel */}
        <div className="lg:col-span-1 min-h-[640px]">
          <PendingEventsPanel
            events={data?.pending ?? []}
            onAction={() => load()}
            onHoverActor={(id) => setFocusFromPanel(actorToNodeId(id))}
          />
        </div>
      </div>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Empty state — shown when the DB has no nodes yet (post-wipe).
// ────────────────────────────────────────────────────────────────────
function EmptyGraph() {
  const { t } = useI18n()
  return (
    <div className="flex flex-col items-center justify-center h-full text-center px-8">
      <div className="w-12 h-12 rounded-full bg-brand-cyan/15 ring-1 ring-brand-cyan/30 flex items-center justify-center mb-4">
        <Users2 className="w-6 h-6 text-brand-cyan" />
      </div>
      <p className="text-base font-bold text-fg">{t('network.empty.title')}</p>
      <p className="text-sm text-fg-muted mt-1 max-w-sm">
        {t('network.empty.help')}
      </p>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Legend overlay — sits on top of the canvas.
// ────────────────────────────────────────────────────────────────────
function Legend() {
  const { t } = useI18n()
  return (
    <div className="absolute start-4 bottom-4 flex flex-col gap-1.5 bg-elevated/90 backdrop-blur ring-1 ring-hairline rounded-md px-3 py-2 text-[11px] z-10">
      <p className="text-[9px] font-bold tracking-[0.1em] uppercase text-fg-subtle">
        {t('network.legend.title')}
      </p>
      <LegendRow color="#FBBF24" label={t('network.legend.expert')} shape="circle" />
      <LegendRow color="#22D3EE" label={t('network.legend.user')} shape="circle" small />
      <LegendRow color="#A78BFA" label={t('network.legend.community')} shape="diamond" />
    </div>
  )
}

function LegendRow({
  color,
  label,
  shape,
  small,
}: {
  color: string
  label: string
  shape: 'circle' | 'diamond'
  small?: boolean
}) {
  const size = small ? 6 : 9
  return (
    <div className="flex items-center gap-2 text-fg-muted">
      <span
        className="inline-block"
        style={{
          width: size,
          height: size,
          background: color,
          borderRadius: shape === 'circle' ? '50%' : '2px',
          transform: shape === 'diamond' ? 'rotate(45deg)' : undefined,
        }}
      />
      {label}
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Top stat strip pill
// ────────────────────────────────────────────────────────────────────
function StatStrip({
  label,
  value,
  tone,
  live,
}: {
  label: string
  value: number
  tone?: 'gold'
  live?: boolean
}) {
  const numberTone = tone === 'gold' ? 'text-brand-gold' : 'text-fg'
  return (
    <div className="card-v2 p-4">
      <div className="flex items-center gap-1.5">
        <p className="eyebrow-v2">{label}</p>
        {live && <LivePulseDot color={tone === 'gold' ? 'gold' : 'cyan'} size={6} />}
      </div>
      <p
        className={`num-v2 text-[28px] font-extrabold mt-1.5 leading-none ${numberTone}`}
      >
        <NumberTicker value={value} />
      </p>
    </div>
  )
}

// ────────────────────────────────────────────────────────────────────
// Filter chip — toggleable
// ────────────────────────────────────────────────────────────────────
function FilterChip({
  icon: Icon,
  label,
  active,
  onClick,
  gold,
}: {
  icon: React.ComponentType<{ className?: string }>
  label: string
  active: boolean
  onClick: () => void
  gold?: boolean
}) {
  const activeClass = gold
    ? 'bg-brand-gold/15 text-brand-gold ring-brand-gold/30'
    : 'bg-brand-cyan/15 text-brand-cyan ring-brand-cyan/30'
  return (
    <button
      onClick={onClick}
      className={`h-8 px-3 rounded-md text-xs font-semibold flex items-center gap-1.5 ring-1 ring-inset transition-colors duration-micro ease-out-expo ${
        active
          ? activeClass
          : 'bg-white/[0.03] text-fg-muted ring-hairline hover:text-fg hover:bg-white/[0.05]'
      }`}
    >
      <Icon className="w-3.5 h-3.5" />
      {label}
    </button>
  )
}
