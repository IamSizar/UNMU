-- =============================================================================
-- Step-5 follow-up — richer test posts for Sarah Chen (e2).
--
-- Goal: give the subscribe flow a meaningful demo. Without enough subscriber-
-- only posts, a new subscriber accepts payment and barely notices anything
-- new. With this seed, the difference between "before subscribing" (lots of
-- locked teasers) and "after subscribing" (full content unlocks) is obvious.
--
-- Mix shipped here:
--   * 3 PUBLIC posts                — visible to everyone (the "teaser" feed)
--   * 6 SUBSCRIBERS_ONLY posts      — locked to non-subscribers
--                                     (mix of articles / videos / reels)
--
-- Idempotent — uses unique titles + INSERT ... WHERE NOT EXISTS so re-running
-- the migration is safe.
-- =============================================================================

BEGIN;

-- The seeded "test" Sarah account has author_id = 1002 (set in migration 0001).
-- Falls back to a SELECT in case that id ever shifts.
DO $$
DECLARE
    sarah_id BIGINT;
BEGIN
    SELECT id INTO sarah_id
      FROM users
     WHERE expert_id = 'e2'
     LIMIT 1;

    IF sarah_id IS NULL THEN
        RAISE NOTICE 'Skipping seed: no user has expert_id=e2 yet.';
        RETURN;
    END IF;

    -- Helper: insert a post only if no row with the same expert+title exists.
    -- We use title as the dedupe key because all titles below are unique
    -- enough for this seed.

    -- ── PUBLIC POSTS ───────────────────────────────────────────────────────
    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'article',
           'Why I''m watching MSFT this week',
           'Microsoft has a Shariah grade of B and a clean debt-to-asset ratio. I''ll be watching the AI segment commentary in next week''s earnings — that''s where the multiple expansion lives.',
           NULL,
           'https://images.unsplash.com/photo-1633419461186-7d40a38105ec?w=1200',
           NULL,
           'public',
           '["MSFT"]'::jsonb,
           NOW() - INTERVAL '2 hours'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='Why I''m watching MSFT this week'
    );

    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'reel',
           'Halal screener checklist in 60s',
           'My quick checklist before I open a position — debt ratio, impure income, sector compliance.',
           'https://www.w3schools.com/html/mov_bbb.mp4',
           'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=600&h=1067&fit=crop',
           58,
           'public',
           '[]'::jsonb,
           NOW() - INTERVAL '1 day'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='Halal screener checklist in 60s'
    );

    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'article',
           'Three sectors I''m avoiding in Q2',
           'Conventional banks, alcohol-adjacent consumer staples, and most insurance plays. The Shariah math just doesn''t work and the risk/reward isn''t there.',
           NULL,
           'https://images.unsplash.com/photo-1553729459-efe14ef6055d?w=1200',
           NULL,
           'public',
           '[]'::jsonb,
           NOW() - INTERVAL '3 days'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='Three sectors I''m avoiding in Q2'
    );

    -- ── SUBSCRIBERS-ONLY POSTS ─────────────────────────────────────────────
    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'article',
           'Full thesis: scaling into NVDA on the dip',
           'My subscriber-only deep dive. Entry levels at $810/$795, position sizing at 4% of portfolio max, exit thesis if data-center revenue growth drops below 25% YoY for two consecutive quarters. Includes my exact bracket orders.',
           NULL,
           'https://images.unsplash.com/photo-1639762681485-074b7f938ba0?w=1200',
           NULL,
           'subscribers_only',
           '["NVDA"]'::jsonb,
           NOW() - INTERVAL '5 hours'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='Full thesis: scaling into NVDA on the dip'
    );

    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'video',
           'Q1 portfolio review — what worked, what didn''t',
           'Walking through every position I closed in Q1 and why. The ones that hurt and the ones that paid off — including the AAPL trim that I called wrong.',
           'https://www.w3schools.com/html/mov_bbb.mp4',
           'https://images.unsplash.com/photo-1551836022-deb4988cc6c0?w=1200',
           1480,
           'subscribers_only',
           '["AAPL","MSFT","NVDA","GOOGL"]'::jsonb,
           NOW() - INTERVAL '4 days'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='Q1 portfolio review — what worked, what didn''t'
    );

    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'article',
           'GOOGL: my entry plan ahead of earnings',
           'Subscriber-only setup. Three-tiered entry plan with risk-defined stops. I''ll post live updates if the trade triggers.',
           NULL,
           'https://images.unsplash.com/photo-1573804633927-bfcbcd909acd?w=1200',
           NULL,
           'subscribers_only',
           '["GOOGL"]'::jsonb,
           NOW() - INTERVAL '6 days'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='GOOGL: my entry plan ahead of earnings'
    );

    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'reel',
           'Live trade: how I sized my MSFT add',
           'Quick walkthrough of the bracket order I just placed. Subscribers see this in real-time.',
           'https://www.w3schools.com/html/mov_bbb.mp4',
           'https://images.unsplash.com/photo-1620266757065-5814239881fd?w=600&h=1067&fit=crop',
           62,
           'subscribers_only',
           '["MSFT"]'::jsonb,
           NOW() - INTERVAL '8 days'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='Live trade: how I sized my MSFT add'
    );

    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'article',
           'My personal watchlist for next week',
           'The 8 names I''m tracking, with the levels I care about and why. Full notes, not just tickers.',
           NULL,
           'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200',
           NULL,
           'subscribers_only',
           '["MSFT","NVDA","AAPL","GOOGL","AMD","META","TSM","AVGO"]'::jsonb,
           NOW() - INTERVAL '10 days'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='My personal watchlist for next week'
    );

    INSERT INTO posts (
        target_type, expert_id, author_id, author_name,
        post_type, title, body, media_url, cover_url, duration_seconds,
        visibility, tickers, created_at
    )
    SELECT 'expert', 'e2', sarah_id, 'Sarah Chen',
           'video',
           'Position sizing masterclass — my full system',
           '22 minutes on exactly how I size every trade, why fixed-fractional doesn''t work for halal screened portfolios, and the spreadsheet I use.',
           'https://www.w3schools.com/html/mov_bbb.mp4',
           'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=1200',
           1320,
           'subscribers_only',
           '[]'::jsonb,
           NOW() - INTERVAL '14 days'
    WHERE NOT EXISTS (
        SELECT 1 FROM posts WHERE expert_id='e2' AND title='Position sizing masterclass — my full system'
    );

    -- Optional cleanup: nuke the obvious test garbage so the demo is clean.
    DELETE FROM posts WHERE expert_id='e2' AND (title='saasd' OR (title IS NULL AND body IS NULL));
END $$;

COMMIT;
