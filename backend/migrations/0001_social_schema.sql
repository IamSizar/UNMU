-- =============================================================================
-- Social schema — adds the role system, communities, experts, posts and
-- subscriptions on top of the existing `users` table.
--
-- Run with:
--   psql "$DATABASE_URL" -f backend/migrations/0001_social_schema.sql
--
-- This file is idempotent: every CREATE / ALTER uses IF NOT EXISTS so it can
-- be re-applied safely. Seed data uses ON CONFLICT DO NOTHING.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Extend `users` with role + expert linkage.
--    role:     'USER' | 'EXPERT' | 'SCHOLAR'   (default 'USER')
--    expert_id: optional FK → experts.id      (only set for EXPERT/SCHOLAR)
-- -----------------------------------------------------------------------------
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS role         TEXT NOT NULL DEFAULT 'USER',
    ADD COLUMN IF NOT EXISTS expert_id    TEXT,
    ADD COLUMN IF NOT EXISTS bio          TEXT,
    ADD COLUMN IF NOT EXISTS avatar_url   TEXT;

ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users
    ADD  CONSTRAINT users_role_check
         CHECK (role IN ('USER','EXPERT','SCHOLAR'));

-- -----------------------------------------------------------------------------
-- 2. experts — public profile rows for verified experts and scholars.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS experts (
    id                TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    expertise         TEXT NOT NULL,
    bio               TEXT NOT NULL DEFAULT '',
    tier              TEXT NOT NULL CHECK (tier IN ('expert','scholar')),
    subscriber_count  INTEGER NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 3. communities — region-scoped discussion forums.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS communities (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    region_code   TEXT NOT NULL,
    tagline       TEXT NOT NULL DEFAULT '',
    member_count  INTEGER NOT NULL DEFAULT 0,
    active_now    INTEGER NOT NULL DEFAULT 0,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- -----------------------------------------------------------------------------
-- 4. community_members — join table for "X is in community Y".
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS community_members (
    user_id       BIGINT NOT NULL REFERENCES users(id)        ON DELETE CASCADE,
    community_id  TEXT   NOT NULL REFERENCES communities(id)  ON DELETE CASCADE,
    joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, community_id)
);

-- -----------------------------------------------------------------------------
-- 5. subscriptions — "user X subscribed to expert Y".
--    Used to gate read access to expert posts (paywall).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subscriptions (
    user_id       BIGINT NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
    expert_id     TEXT   NOT NULL REFERENCES experts(id)  ON DELETE CASCADE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, expert_id)
);

CREATE INDEX IF NOT EXISTS subscriptions_expert_idx ON subscriptions(expert_id);

-- -----------------------------------------------------------------------------
-- 6. posts — polymorphic. target_type tells you whether the post lives on a
--    community board or on an expert profile. Exactly one of community_id or
--    expert_id is non-null (enforced by a CHECK constraint).
--
--    target_type:  'community' | 'expert'
--    stance:       'BUY' | 'HOLD' | 'SELL'      (community posts only)
--    tickers:      JSON array of strings        (expert posts allow many)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS posts (
    id             BIGSERIAL PRIMARY KEY,
    target_type    TEXT NOT NULL CHECK (target_type IN ('community','expert')),
    community_id   TEXT REFERENCES communities(id) ON DELETE CASCADE,
    expert_id      TEXT REFERENCES experts(id)     ON DELETE CASCADE,
    author_id      BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    author_name    TEXT NOT NULL,
    title          TEXT,
    body           TEXT NOT NULL,
    ticker         TEXT,
    tickers        JSONB NOT NULL DEFAULT '[]'::jsonb,
    stance         TEXT CHECK (stance IS NULL OR stance IN ('BUY','HOLD','SELL')),
    upvotes        INTEGER NOT NULL DEFAULT 0,
    likes          INTEGER NOT NULL DEFAULT 0,
    comments_count INTEGER NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Exactly one target FK is set, matching target_type.
    CONSTRAINT posts_target_xor CHECK (
        (target_type = 'community' AND community_id IS NOT NULL AND expert_id IS NULL)
     OR (target_type = 'expert'    AND expert_id    IS NOT NULL AND community_id IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS posts_community_idx
    ON posts(community_id, created_at DESC);
CREATE INDEX IF NOT EXISTS posts_expert_idx
    ON posts(expert_id, created_at DESC);

-- =============================================================================
-- Seed data — matches the Flutter mock dataset so the test harness UI works
-- against a real database. Idempotent thanks to ON CONFLICT DO NOTHING.
-- =============================================================================

-- Experts (e1 = scholar Ahmad, e2 = expert Sarah)
INSERT INTO experts (id, name, expertise, bio, tier, subscriber_count) VALUES
    ('e1', 'Ahmad Al-Rashid', 'Shariah Compliance & Islamic Finance',
        'Senior scholar specializing in modern fintech screening rules.',
        'scholar', 12400),
    ('e2', 'Sarah Chen',      'Tech Equities & Growth Investing',
        'Quant-focused trader covering large-cap US tech and emerging plays.',
        'expert',  9100)
ON CONFLICT (id) DO NOTHING;

-- Communities (Saudi, UAE, US, Global)
INSERT INTO communities (id, name, region_code, tagline, member_count, active_now) VALUES
    ('c_sa',  'Saudi Markets',  'SA',  'Tadawul talk · Vision 2030',          4820, 142),
    ('c_ae',  'UAE Investors',  'AE',  'DFM · ADX deep dives',                 2310,  87),
    ('c_us',  'US Halal Tech',  'US',  'Shariah-screened US growth names',     6970, 311),
    ('c_glob','Global Halal',   'GL',  'Cross-border ideas, all regions',     11240, 528)
ON CONFLICT (id) DO NOTHING;

-- Test accounts. Passwords are bcrypt hashes of the literal string 'test'
-- so anyone can log in with email + password 'test' during local testing.
-- Hash: $2a$10$9dJhcPWISOsu2asiIlf9N.7/gdoWl8i136OD2DC53G7Lpt393VTH2
INSERT INTO users (id, email, password_hash, name, role, expert_id, subscription_tier, subscription_status, created_at, updated_at)
VALUES
    (1001,'user@test.com',   '$2a$10$9dJhcPWISOsu2asiIlf9N.7/gdoWl8i136OD2DC53G7Lpt393VTH2','Sizar',           'USER',    NULL, 'FREE',    'ACTIVE', NOW(), NOW()),
    (1002,'expert@test.com', '$2a$10$9dJhcPWISOsu2asiIlf9N.7/gdoWl8i136OD2DC53G7Lpt393VTH2','Sarah Chen',      'EXPERT',  'e2', 'PREMIUM', 'ACTIVE', NOW(), NOW()),
    (1003,'scholar@test.com','$2a$10$9dJhcPWISOsu2asiIlf9N.7/gdoWl8i136OD2DC53G7Lpt393VTH2','Ahmad Al-Rashid', 'SCHOLAR', 'e1', 'PREMIUM', 'ACTIVE', NOW(), NOW()),
    (1004,'you@test.com',    '$2a$10$9dJhcPWISOsu2asiIlf9N.7/gdoWl8i136OD2DC53G7Lpt393VTH2','You',             'USER',    NULL, 'FREE',    'ACTIVE', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

-- Make sure the sequence stays past our hardcoded ids so future signups don't
-- collide with 1001-1004.
SELECT setval(pg_get_serial_sequence('users','id'),
              GREATEST((SELECT MAX(id) FROM users), 2000));

-- Make every test user a member of the global community + their natural region.
INSERT INTO community_members (user_id, community_id) VALUES
    (1001,'c_glob'),(1001,'c_sa'),
    (1002,'c_glob'),(1002,'c_us'),
    (1003,'c_glob'),(1003,'c_sa'),(1003,'c_ae'),
    (1004,'c_glob'),(1004,'c_us')
ON CONFLICT DO NOTHING;

-- Seed expert posts (these are paywalled — non-subscribers see the gate).
INSERT INTO posts (target_type, expert_id, author_id, author_name, body, tickers, created_at) VALUES
    ('expert','e1', 1003, 'Ahmad Al-Rashid',
        'Reviewed the latest Aramco fundamentals — debt-to-asset still inside Shariah threshold. Maintaining HALAL status.',
        '["ARAMCO"]'::jsonb, NOW() - INTERVAL '2 hours'),
    ('expert','e2', 1002, 'Sarah Chen',
        'NVDA closed above the Q3 high on strong volume. Watching $880 as next leg up — Shariah grade B.',
        '["NVDA","AMD"]'::jsonb, NOW() - INTERVAL '5 hours');

-- Seed community posts (visible to anyone — no paywall).
INSERT INTO posts (target_type, community_id, author_id, author_name, title, body, ticker, stance, upvotes, comments_count, created_at) VALUES
    ('community','c_sa',  1001, 'Sizar',
        'Aramco dividend hike — sustainable?',
        'Yield bumped again this quarter. Cash flow looks fine but capex guidance is up too. Curious what others think.',
        'ARAMCO', 'HOLD', 38, 12, NOW() - INTERVAL '3 hours'),
    ('community','c_us',  1002, 'Sarah Chen',
        'NVDA: where I''m adding',
        'Building between $810-$830. Still long-term bullish but trimming if it fades $880.',
        'NVDA',   'BUY',  152, 47, NOW() - INTERVAL '6 hours'),
    ('community','c_glob',1004, 'You',
        'How do you screen new listings?',
        'When a new ticker shows up Halal-graded, do you wait a quarter or jump in?',
        'AAPL',   'HOLD', 14, 6, NOW() - INTERVAL '1 day');

COMMIT;
