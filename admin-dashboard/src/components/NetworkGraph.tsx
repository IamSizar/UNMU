/**
 * NetworkGraph — force-directed 2D canvas visualization of the
 * UNMU platform's social fabric.
 *
 * Three node types (expert / user / community) and three edge types
 * (subscription / community_member / owns) painted with brand colors.
 * Tabular legend lives in the parent <Network> page.
 *
 * The graph itself is `react-force-graph-2d`, which gives us:
 *   - native canvas rendering (smooth at 1000+ nodes)
 *   - built-in zoom/pan/drag
 *   - per-node click/hover handlers
 *   - custom `nodeCanvasObject` for full control over how each node
 *     is drawn — that's where the brand colors + halos live.
 *
 * Behaviour:
 *   - Hover: spotlight mode — non-neighbor nodes dim to ~30% alpha.
 *   - Click: focus mode — only the node's direct subgraph stays.
 *     Click background or press Escape to release.
 *   - Pending expert nodes get a slow-pulse gold halo.
 *   - "Spawn" animation: when realtime adds a new edge, we briefly
 *     pulse the new edge in cyan over 800ms before settling.
 */

import { useEffect, useMemo, useRef, useState } from 'react'
import ForceGraph2D, { type ForceGraphMethods } from 'react-force-graph-2d'

// ── Public types ─────────────────────────────────────────────────────
export type GraphNode = {
  id: string
  // Internal kind — drives color, shape, sizing.
  kind: 'expert' | 'user' | 'community'
  name: string
  // Used by the renderer for sizing (subscribers / members).
  weight: number
  // Pending experts get a pulsing halo.
  pending?: boolean
  // Set by the parent when a row in the right panel is hovered.
  spotlight?: boolean
}

export type GraphLink = {
  source: string
  target: string
  type: 'subscription' | 'community_member' | 'owns'
  status?: string
  plan?: string
  // True while the spawn-pulse animation runs.
  fresh?: boolean
}

type Props = {
  nodes: GraphNode[]
  links: GraphLink[]
  // Called when the user clicks a node — parent shows it in the
  // bottom detail drawer.
  onNodeClick?: (n: GraphNode | null) => void
  // ID of the node currently focused via the right-panel hover.
  focusNodeId?: string | null
}

// ── Color palette ───────────────────────────────────────────────────
// Stays constant across themes — brand colors read on both surfaces.
const COLORS = {
  expert: '#FBBF24', // gold
  expertGlow: 'rgba(251, 191, 36, 0.45)',
  user: '#22D3EE', // cyan
  userGlow: 'rgba(34, 211, 238, 0.40)',
  community: '#A78BFA', // violet
  communityGlow: 'rgba(167, 139, 250, 0.40)',
  pending: '#FBBF24',
  edge: {
    subscription: 'rgba(34, 211, 238, 0.45)',
    community_member: 'rgba(167, 139, 250, 0.45)',
    owns: 'rgba(241, 245, 249, 0.30)',
  },
  edgeFresh: 'rgba(34, 211, 238, 1.0)',
  text: 'rgba(241, 245, 249, 0.85)',
}

export default function NetworkGraph({
  nodes,
  links,
  onNodeClick,
  focusNodeId,
}: Props) {
  const fgRef = useRef<ForceGraphMethods | undefined>(undefined)
  const containerRef = useRef<HTMLDivElement>(null)
  const [size, setSize] = useState({ w: 800, h: 600 })
  const [hoverNode, setHoverNode] = useState<GraphNode | null>(null)
  const [focusedId, setFocusedId] = useState<string | null>(null)

  // Track t for pending-node pulse animation. Re-render every ~60fps.
  const [tick, setTick] = useState(0)
  useEffect(() => {
    const id = setInterval(() => setTick((x) => x + 1), 60)
    return () => clearInterval(id)
  }, [])

  // ResizeObserver — keep the canvas pinned to its container.
  useEffect(() => {
    if (!containerRef.current) return
    const el = containerRef.current
    const ro = new ResizeObserver(() => {
      const rect = el.getBoundingClientRect()
      setSize({ w: rect.width, h: rect.height })
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  // Sync external focus (e.g. user hovered a pending event).
  useEffect(() => {
    if (focusNodeId === undefined) return
    setFocusedId(focusNodeId)
  }, [focusNodeId])

  // Neighbor lookup so spotlight + focus are O(1) per node.
  const neighbors = useMemo(() => {
    const map = new Map<string, Set<string>>()
    for (const n of nodes) map.set(n.id, new Set())
    for (const l of links) {
      map.get(l.source)?.add(l.target)
      map.get(l.target)?.add(l.source)
    }
    return map
  }, [nodes, links])

  const activeId = focusedId ?? hoverNode?.id ?? null
  const isHighlighted = (id: string) => {
    if (!activeId) return true
    if (id === activeId) return true
    return neighbors.get(activeId)?.has(id) ?? false
  }
  const isEdgeHighlighted = (l: GraphLink) => {
    if (!activeId) return true
    return l.source === activeId || l.target === activeId
  }

  // Escape releases focus.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        setFocusedId(null)
        onNodeClick?.(null)
      }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onNodeClick])

  // ── Custom node painter ────────────────────────────────────────────
  // Called by react-force-graph for every visible node every frame.
  // We draw a filled circle + a hairline ring + a subtle halo for
  // pending experts and an inner dot for non-experts.
  function paintNode(
    node: GraphNode,
    ctx: CanvasRenderingContext2D,
    globalScale: number,
  ) {
    // Node size: experts scale with subscriber count, users tiny, communities medium.
    const baseR = node.kind === 'expert' ? 8 : node.kind === 'community' ? 7 : 4
    const weightR =
      node.kind === 'expert'
        ? Math.min(baseR + Math.sqrt(node.weight) * 0.6, 22)
        : node.kind === 'community'
        ? Math.min(baseR + Math.sqrt(node.weight) * 0.4, 16)
        : baseR
    const r = weightR

    const highlighted = isHighlighted(node.id)
    const alpha = highlighted ? 1 : 0.18

    // Pending halo — pulse 0.4 → 1 → 0.4 over 1.5s.
    if (node.pending) {
      const phase = (Date.now() % 1500) / 1500
      const pulseAlpha = (0.4 + 0.6 * Math.sin(phase * Math.PI * 2)) * 0.5
      ctx.beginPath()
      ctx.arc(node.x as number, node.y as number, r + 6, 0, 2 * Math.PI)
      ctx.fillStyle = `rgba(251, 191, 36, ${pulseAlpha * (highlighted ? 1 : 0.3)})`
      ctx.fill()
    }

    // Spotlight outline (hover/focus)
    if (node.id === activeId) {
      ctx.beginPath()
      ctx.arc(node.x as number, node.y as number, r + 3, 0, 2 * Math.PI)
      ctx.strokeStyle = `rgba(34, 211, 238, ${alpha})`
      ctx.lineWidth = 1.5 / globalScale
      ctx.stroke()
    }

    // Main fill
    ctx.beginPath()
    if (node.kind === 'community') {
      // Diamond for communities.
      const x = node.x as number
      const y = node.y as number
      ctx.moveTo(x, y - r)
      ctx.lineTo(x + r, y)
      ctx.lineTo(x, y + r)
      ctx.lineTo(x - r, y)
      ctx.closePath()
    } else {
      ctx.arc(node.x as number, node.y as number, r, 0, 2 * Math.PI)
    }
    const baseColor =
      node.kind === 'expert'
        ? COLORS.expert
        : node.kind === 'user'
        ? COLORS.user
        : COLORS.community
    ctx.fillStyle =
      `rgba(${hexToRgb(baseColor)}, ${alpha})`
    ctx.fill()

    // Hairline ring
    ctx.strokeStyle = `rgba(8, 9, 12, ${alpha})`
    ctx.lineWidth = 1 / globalScale
    ctx.stroke()

    // Label — only render when zoomed in OR node is highlighted.
    if (globalScale > 1.2 || node.id === activeId) {
      const label = node.name
      const fontSize = Math.max(10 / globalScale, 2)
      ctx.font = `${fontSize}px Inter, system-ui, sans-serif`
      ctx.textAlign = 'center'
      ctx.textBaseline = 'top'
      ctx.fillStyle = `rgba(241, 245, 249, ${alpha})`
      ctx.fillText(label, node.x as number, (node.y as number) + r + 4)
    }
  }

  // ── Edge painter — gradient on type, brighter when fresh ─────────
  function paintLink(
    link: GraphLink & { source: GraphNode; target: GraphNode },
    ctx: CanvasRenderingContext2D,
  ) {
    const highlighted = isEdgeHighlighted({
      ...link,
      source: link.source.id,
      target: link.target.id,
    })
    const baseColor = link.fresh ? COLORS.edgeFresh : COLORS.edge[link.type]
    const finalAlpha = highlighted ? 1 : 0.12
    ctx.strokeStyle = baseColor.replace(/[\d.]+\)$/, `${finalAlpha})`)
    ctx.lineWidth = link.fresh ? 2 : 1
    ctx.beginPath()
    ctx.moveTo(link.source.x as number, link.source.y as number)
    ctx.lineTo(link.target.x as number, link.target.y as number)
    ctx.stroke()
  }

  // Convert the public types to react-force-graph's expected shape.
  // The library mutates node positions; cloning protects React state.
  const fgData = useMemo(
    () => ({
      nodes: nodes.map((n) => ({ ...n })),
      links: links.map((l) => ({ ...l })),
    }),
    [nodes, links],
  )

  // Reference tick so the canvas repaints on the interval.
  void tick

  return (
    <div ref={containerRef} className="absolute inset-0 overflow-hidden">
      <ForceGraph2D
        ref={fgRef}
        graphData={fgData}
        width={size.w}
        height={size.h}
        backgroundColor="rgba(0,0,0,0)"
        nodeRelSize={1}
        nodeCanvasObject={paintNode as any}
        nodePointerAreaPaint={(node: any, color, ctx) => {
          const r = node.kind === 'expert' ? 12 : 8
          ctx.fillStyle = color
          ctx.beginPath()
          ctx.arc(node.x, node.y, r, 0, 2 * Math.PI)
          ctx.fill()
        }}
        linkCanvasObject={paintLink as any}
        linkCanvasObjectMode={() => 'replace'}
        cooldownTicks={120}
        d3VelocityDecay={0.3}
        onNodeHover={(n) => setHoverNode((n as GraphNode) ?? null)}
        onNodeClick={(n) => {
          const node = n as GraphNode
          setFocusedId(node.id)
          onNodeClick?.(node)
        }}
        onBackgroundClick={() => {
          setFocusedId(null)
          onNodeClick?.(null)
        }}
      />
    </div>
  )
}

// ── Helpers ──────────────────────────────────────────────────────────
function hexToRgb(hex: string): string {
  const h = hex.replace('#', '')
  const r = parseInt(h.substring(0, 2), 16)
  const g = parseInt(h.substring(2, 4), 16)
  const b = parseInt(h.substring(4, 6), 16)
  return `${r}, ${g}, ${b}`
}
