-- =============================================================================
-- 0014 — Community messages (real chat) + align mock community ids
-- with real DB rows.
--
-- Two changes that go together:
--
--   1. Seed `c1`–`c5` as real rows in `communities`, with owners +
--      members mirroring `lib/screens/social/mock_social_data.dart`'s
--      `mockMembersFor()` helper. Without this, the mobile app's
--      community ids (c1, c2, …) don't exist in the backend and
--      every chat fetch / send 404s.
--
--   2. Create `community_messages` — the real chat table. FK on
--      community_id cascades on community delete, FK on author_id
--      cascades on user delete. Composite index lets the chat list
--      query scan only the "tail" of the table for the active
--      community.
--
-- Idempotent — re-running is safe (`ON CONFLICT DO NOTHING` everywhere
-- and `IF NOT EXISTS` on the table + index).
-- =============================================================================

BEGIN;

-- ── 1. Seed mock community rows ─────────────────────────────────────
-- owner_id values match what's in MockSocialData.communities (the
-- mock model's ownerId field). If you change one in the mock data,
-- update it here too.
INSERT INTO communities (id, name, tagline, region_code, owner_id)
VALUES
  ('c1', 'GCC Markets',                 'Saudi · UAE · Qatar — daily flow',  'GCC',    1003),
  ('c2', 'US Halal Tech',               'Shariah-friendly tech megacaps',    'US',     1002),
  ('c3', 'MENA Energy & Industrials',   'Petrochems, utilities, logistics',  'MENA',   2027),
  ('c4', 'Asia Shariah Movers',         'Malaysia · Indonesia · Pakistan',   'ASIA',   2025),
  ('c5', 'Sukuk & Islamic Finance',     'Fixed income · global sukuk',       'GLOBAL', 2029)
ON CONFLICT (id) DO NOTHING;

-- ── 2. Membership rows mirroring mockMembersFor() ───────────────────
-- Listed exactly the same as the mobile app shows in the Members tab.
-- Owner rows are included so the gate "is this user in
-- community_members" is true for the owner too.
INSERT INTO community_members (user_id, community_id)
VALUES
  -- c1 (GCC Markets) — Ahmad owner
  (1003, 'c1'), (2027, 'c1'), (1001, 'c1'), (2030, 'c1'), (2029, 'c1'),
  -- c2 (US Halal Tech) — Sarah owner
  (1002, 'c2'), (2025, 'c2'), (1004, 'c2'), (2031, 'c2'), (2032, 'c2'),
  -- c3 (MENA Energy) — Fatima owner
  (2027, 'c3'), (1003, 'c3'), (2029, 'c3'), (2030, 'c3'),
  -- c4 (Asia Shariah) — Aisha owner
  (2025, 'c4'), (1002, 'c4'), (1004, 'c4'), (2032, 'c4'),
  -- c5 (Sukuk & Islamic Finance) — Sheikh Abdullah owner
  (2029, 'c5'), (2028, 'c5'), (2026, 'c5'), (1001, 'c5'), (2031, 'c5')
ON CONFLICT DO NOTHING;

-- ── 3. The actual messages table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_messages (
  id           BIGSERIAL   PRIMARY KEY,
  community_id TEXT        NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  author_id    BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body         TEXT        NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Composite index — the list query always filters by community_id +
-- orders by created_at DESC, so this lets Postgres index-scan only
-- the tail of one community without touching others.
CREATE INDEX IF NOT EXISTS idx_community_messages_recent
  ON community_messages (community_id, created_at DESC);

COMMIT;
