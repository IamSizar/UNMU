-- =============================================================================
-- Step 2 — Posts get media + types + visibility.
--
-- Extends the `posts` table so experts can publish three kinds of content:
--   * article  — long-form text (title + body)
--   * video    — long video with cover + media url
--   * reel     — short 9:16 vertical video
--
-- Each post also gets an explicit visibility:
--   * public            — anyone can read it (acts as a teaser)
--   * subscribers_only  — gated; only the expert's subscribers can read
--
-- Run with:
--   psql "$DATABASE_URL" -f backend/migrations/0003_post_media_and_visibility.sql
--
-- Idempotent. Safe to re-run.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. New columns. All optional / nullable so existing rows keep working.
-- -----------------------------------------------------------------------------
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS post_type        TEXT NOT NULL DEFAULT 'article',
    ADD COLUMN IF NOT EXISTS media_url        TEXT,
    ADD COLUMN IF NOT EXISTS cover_url        TEXT,
    ADD COLUMN IF NOT EXISTS duration_seconds INTEGER,
    ADD COLUMN IF NOT EXISTS visibility       TEXT NOT NULL DEFAULT 'subscribers_only';

-- Constrain valid values.
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_post_type_check;
ALTER TABLE posts ADD  CONSTRAINT posts_post_type_check
    CHECK (post_type IN ('article','video','reel'));

ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_visibility_check;
ALTER TABLE posts ADD  CONSTRAINT posts_visibility_check
    CHECK (visibility IN ('public','subscribers_only'));

-- Helpful indexes for the studio + reels-feed queries.
CREATE INDEX IF NOT EXISTS posts_expert_type_idx
    ON posts(expert_id, post_type, created_at DESC)
    WHERE target_type = 'expert';

CREATE INDEX IF NOT EXISTS posts_visibility_idx
    ON posts(visibility, created_at DESC);

-- -----------------------------------------------------------------------------
-- 2. Seed sample expert posts so the studio + admin dashboard show data
--    immediately. Only inserts when there are fewer than 4 posts for e2 — the
--    Sarah Chen test expert — so re-running doesn't pile up duplicates.
-- -----------------------------------------------------------------------------
INSERT INTO posts (
    target_type, expert_id, author_id, author_name,
    post_type, title, body,
    media_url, cover_url, duration_seconds,
    visibility, tickers, created_at
)
SELECT * FROM (VALUES
    ('expert','e2', 1002::bigint, 'Sarah Chen',
        'article',
        'My take on NVDA after the Q4 print',
        'NVDA crushed Q4 expectations on data-center revenue. The Shariah grade stays B — debt ratio held flat at 12% and impure income is still well under the 5% threshold. I''m adding on any pullback to $810.',
        NULL,
        'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200',
        NULL,
        'public',
        '["NVDA"]'::jsonb,
        NOW() - INTERVAL '6 hours'),
    ('expert','e2', 1002::bigint, 'Sarah Chen',
        'video',
        'Halal portfolio rebalance — March 2025',
        'Walking through how I rebalanced my US-tech sleeve this month and why I trimmed AAPL.',
        'https://www.w3schools.com/html/mov_bbb.mp4',
        'https://images.unsplash.com/photo-1642790551116-18e150f248e3?w=1200',
        612,
        'subscribers_only',
        '["AAPL","NVDA","MSFT"]'::jsonb,
        NOW() - INTERVAL '1 day'),
    ('expert','e2', 1002::bigint, 'Sarah Chen',
        'reel',
        'Why I avoid most banking stocks',
        '60-second take on why conventional banks fail Shariah debt ratios.',
        'https://www.w3schools.com/html/mov_bbb.mp4',
        'https://images.unsplash.com/photo-1611224923853-80b023f02d71?w=600&h=1067&fit=crop',
        58,
        'public',
        '[]'::jsonb,
        NOW() - INTERVAL '2 days'),
    ('expert','e2', 1002::bigint, 'Sarah Chen',
        'reel',
        'Quick AAPL update',
        'iPhone services revenue is the moat. Sticking with the position.',
        'https://www.w3schools.com/html/mov_bbb.mp4',
        'https://images.unsplash.com/photo-1640340434855-6084b1f4901c?w=600&h=1067&fit=crop',
        47,
        'subscribers_only',
        '["AAPL"]'::jsonb,
        NOW() - INTERVAL '3 days')
) AS seed
WHERE (SELECT COUNT(*) FROM posts WHERE target_type='expert' AND expert_id='e2') < 4;

COMMIT;
