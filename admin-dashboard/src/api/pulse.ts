// UNMU Pulse (نبض أنمو) — typed calls to the CMS API (/api/pulse-admin/*).
//
// The shapes mirror backend/internal/models/pulse_admin.go. Keep them in sync:
// a field renamed there must be renamed here.

import { api } from './client'

export type PulseSlot = 'global' | 'gulf' | 'sharia' | 'opportunity'
export type PulseClassification = 'confirmed' | 'analysis'
export type PulseStatus =
  | 'draft'
  | 'in_review'
  | 'approved'
  | 'scheduled'
  | 'published'
  | 'archived'
export type PulseRole = 'editor' | 'reviewer' | 'approver'

export const PULSE_SLOTS: PulseSlot[] = ['global', 'gulf', 'sharia', 'opportunity']
export const PULSE_STATUSES: PulseStatus[] = [
  'draft',
  'in_review',
  'approved',
  'scheduled',
  'published',
  'archived',
]

export interface PulseStock {
  id: number
  ticker: string
  exchange: string
  name: string
}

/** What an editor sends to create or change an item. */
export interface PulseItemInput {
  pulseDate: string // YYYY-MM-DD
  slot: PulseSlot
  classification: PulseClassification
  isSensitive: boolean
  titleAr: string
  titleEn: string
  summaryAr: string
  summaryEn: string
  detailsAr: string
  detailsEn: string
  evidenceAr: string
  evidenceEn: string
  sourceName: string
  sourceUrl: string
  verifiedAt: string | null // ISO timestamp
  stockId: number | null
}

/** A stored item, in any status. */
export interface PulseItem extends Omit<PulseItemInput, 'stockId'> {
  id: number
  status: PulseStatus
  stock: PulseStock | null
  version: number
  changeKind: 'updated' | 'corrected' | null
  lastChangedAt: string | null
  publishAt: string | null
  publishedAt: string | null
  createdBy: number | null
  reviewedBy: number | null
  reviewedAt: string | null
  approvedBy: number | null
  approvedAt: string | null
  createdAt: string
  updatedAt: string
}

export interface PulseMe {
  userId: number
  isAdmin: boolean
  roles: PulseRole[]
}

/** A correction proposed for a live item, waiting for a different approver. */
export interface PulsePendingCorrection {
  id: number
  itemId: number
  proposedBy: number | null
  kind: 'updated' | 'corrected'
  note: string
  input: PulseItemInput
  createdAt: string
}

export interface PulseChangeLogEntry {
  id: number
  action: string
  actorId: number | null
  actorEmail: string
  fromStatus: string
  toStatus: string
  note: string
  createdAt: string
}

export interface PulseVersion {
  version: number
  reason: string
  snapshot: PulseItem
  createdBy: number | null
  createdAt: string
}

export interface PulseStaffMember {
  id: number
  userId: number
  email: string
  role: PulseRole
  createdAt: string
}

export interface PulseItemStats {
  itemId: number
  date: string
  slot: PulseSlot
  title: string
  opens: number
  reads: number
  saves: number
  shares: number
}

export interface PulseAnalytics {
  from: string
  to: string
  dayViews: number
  itemOpens: number
  uniqueReaders: number
  readCompletion: number
  saves: number
  shares: number
  returnRate: number
  items: PulseItemStats[]
}

/** Workflow actions that go through POST /items/:id/<action>. */
export type PulseAction =
  | 'submit'
  | 'review'
  | 'reject'
  | 'approve'
  | 'schedule'
  | 'unschedule'
  | 'publish'
  | 'archive'

export interface PulseListParams {
  status?: PulseStatus | ''
  slot?: PulseSlot | ''
  date?: string
  limit?: number
  offset?: number
}

function query(params: Record<string, string | number | undefined>): string {
  const q = new URLSearchParams()
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== '') q.set(k, String(v))
  }
  const s = q.toString()
  return s ? `?${s}` : ''
}

const BASE = '/pulse-admin'

export const pulseApi = {
  me: () => api.get<PulseMe>(`${BASE}/me`),

  list: (p: PulseListParams) =>
    api.get<{ items: PulseItem[]; hasMore: boolean }>(`${BASE}/items${query({ ...p })}`),
  get: (id: number) => api.get<PulseItem>(`${BASE}/items/${id}`),
  create: (input: PulseItemInput) => api.post<PulseItem>(`${BASE}/items`, input),
  update: (id: number, input: PulseItemInput) =>
    api.put<PulseItem>(`${BASE}/items/${id}`, input),
  remove: (id: number) => api.delete<{ deleted: boolean }>(`${BASE}/items/${id}`),

  action: (id: number, action: PulseAction, body: { note?: string; publishAt?: string } = {}) =>
    api.post<PulseItem>(`${BASE}/items/${id}/${action}`, body),
  /** Proposes a correction. The live item changes only after a different approver applies it. */
  correct: (
    id: number,
    body: { kind: 'updated' | 'corrected'; note: string; item: PulseItemInput },
  ) => api.post<{ pending: PulsePendingCorrection }>(`${BASE}/items/${id}/correct`, body),
  getCorrection: (id: number) =>
    api.get<{ pending: PulsePendingCorrection | null }>(`${BASE}/items/${id}/correction`),
  resolveCorrection: (id: number, approve: boolean, note: string) =>
    api.post<PulseItem>(`${BASE}/items/${id}/correction/${approve ? 'approve' : 'reject'}`, { note }),

  versions: (id: number) =>
    api.get<{ versions: PulseVersion[] }>(`${BASE}/items/${id}/versions`),
  events: (id: number) =>
    api.get<{ events: PulseChangeLogEntry[] }>(`${BASE}/items/${id}/events`),

  staff: () => api.get<{ staff: PulseStaffMember[] }>(`${BASE}/staff`),
  addStaff: (email: string, role: PulseRole) =>
    api.post<{ ok: boolean }>(`${BASE}/staff`, { email, role }),
  removeStaff: (id: number) => api.delete<{ ok: boolean }>(`${BASE}/staff/${id}`),

  analytics: (from?: string, to?: string) =>
    api.get<PulseAnalytics>(`${BASE}/analytics${query({ from, to })}`),

  stocks: (q: string) =>
    api.get<{ stocks: PulseStock[] }>(`${BASE}/stocks${query({ q })}`),
}
