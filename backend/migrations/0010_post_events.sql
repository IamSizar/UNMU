-- =============================================================================
-- 0010 — post_events: track share / deep-link / reel-load-failed events.
--
-- We've shipped sharing (share_plus), deep links (`unmu.app/p/:id`), and
-- chunked reel uploads with retry — but admin has no visibility into any
-- of those flows: which posts get shared, how often deep links resolve,
-- which reels fail to load on real devices.
--
-- This table is the single home for those engagement / reliability
-- events. Wide-ish so we don't need separate tables per event type;
-- indexed on (post_id, occurred_at) so admin time-window queries stay
-- fast even at 1M+ rows.
--
-- Idempotent — `IF NOT EXISTS` everywhere so re-running this migration
-- against an already-migrated DB is a no-op.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS post_events (
  id              BIGSERIAL PRIMARY KEY,
  post_id         BIGINT      NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  -- 'share_tapped'         user tapped Share on a post (reel rail or article card)
  -- 'deep_link_opened'     server resolved a /api/posts/:id GET (someone tapped a shared URL)
  -- 'reel_load_failed'     mobile client gave up initialising the reel video
  event_type      TEXT        NOT NULL,
  -- Optional — null when an unauthenticated client triggers the event
  -- (e.g. a deep-link tap before the user signs in).
  user_id         BIGINT      REFERENCES users(id) ON DELETE SET NULL,
  -- Free-form JSON for whatever the client wants to attach. Keeps the
  -- schema stable while we figure out what we actually want to slice on.
  -- Examples: { "platform": "ios" }, { "errorKind": "timeout" }
  meta            JSONB       NOT NULL DEFAULT '{}'::jsonb,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Admin time-window aggregates ("how many shares in the last 24h?")
-- always filter by occurred_at first, then group by event_type. The
-- composite index lets Postgres index-scan the recent slice without
-- touching older rows.
CREATE INDEX IF NOT EXISTS idx_post_events_recent
  ON post_events (occurred_at DESC, event_type);

-- Per-post counters ("how many times has post X been shared?") use this.
CREATE INDEX IF NOT EXISTS idx_post_events_post
  ON post_events (post_id, event_type);

COMMIT;
