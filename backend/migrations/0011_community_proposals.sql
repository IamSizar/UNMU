-- =============================================================================
-- 0011 — community_proposals + communities.owner_id
--
-- Two changes that together enable the "expert proposes a community,
-- admin approves, expert becomes owner" flow:
--
--   1. communities.owner_id — nullable BIGINT FK to users(id). The
--      proposing expert lands here on approval. Existing seeded
--      communities can have their owner_id back-filled by 0012.
--
--   2. community_proposals — same shape conventions as
--      expert_applications: pending/approved/rejected status, soft
--      review trail (reviewed_at, reviewed_by, rejection_reason), and
--      a one-pending-per-user partial unique index that mirrors the
--      expert-application constraint exactly. Once a proposal is
--      approved we backfill `approved_community_id` for forensics.
--
-- Idempotent — `IF NOT EXISTS` everywhere so re-running is a no-op.
-- =============================================================================

BEGIN;

ALTER TABLE communities
  ADD COLUMN IF NOT EXISTS owner_id BIGINT REFERENCES users(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS community_proposals (
  id                    BIGSERIAL PRIMARY KEY,
  user_id               BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name                  TEXT        NOT NULL,
  region_code           TEXT,
  description           TEXT        NOT NULL,
  status                TEXT        NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason      TEXT,
  submitted_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at           TIMESTAMPTZ,
  reviewed_by           BIGINT      REFERENCES users(id) ON DELETE SET NULL,
  approved_community_id TEXT        REFERENCES communities(id) ON DELETE SET NULL
);

-- One pending proposal per user — same constraint as expert_applications.
-- Doesn't block a user who's been rejected from re-submitting (only the
-- pending row is unique).
CREATE UNIQUE INDEX IF NOT EXISTS community_proposals_one_pending_per_user
  ON community_proposals (user_id) WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS community_proposals_status_idx
  ON community_proposals (status, submitted_at DESC);

CREATE INDEX IF NOT EXISTS community_proposals_user_idx
  ON community_proposals (user_id, submitted_at DESC);

COMMIT;
