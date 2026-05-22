-- =============================================================================
-- 0012 — Demo data for the community + creator-economy story.
--
-- What this migration seeds (idempotent — safe to re-run):
--
--   1. Resets every test account's password to `test1234`. JWT sessions
--      issued before this migration stay valid until natural expiry,
--      so any browser tab you have open is unaffected.
--
--   2. Creates 5 NEW expert/scholar accounts (Sheikh Abdullah, Fatima,
--      Dr. Yusuf, Aisha, Mufti Bilal) with role+expert_id set, plus an
--      approved expert_application row each so the audit trail looks
--      organic.
--
--   3. Creates 3 NEW subscriber accounts (Khaled, Layla, Omar) with
--      active 1-year subscriptions seeded directly. Every existing
--      expert ends up with at least one paying subscriber so the
--      demo's monetization layer renders something.
--
--   4. Backfills owner_id on the 4 legacy communities (Sarah, Ahmad,
--      Fatima, Aisha) — every community must have an owner now.
--
--   5. Adds community memberships across all 12 accounts so every
--      community feed has 4–6 members.
--
--   6. Seeds 2–4 demo posts per new expert (mix of articles + reels)
--      so their profiles aren't empty when subscribers tap through.
-- =============================================================================

BEGIN;

-- ── 1. Password reset on every test account ──────────────────────────
-- bcrypt hash of `test1234` (cost 10). Generated externally so this
-- migration doesn't depend on a Postgres pgcrypto extension.
UPDATE users
   SET password_hash = '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
       updated_at = NOW()
 WHERE email IN (
   'admin@test.com', 'user@test.com', 'expert@test.com',
   'scholar@test.com', 'you@test.com'
 );

-- ── 2. Five new EXPERT/SCHOLAR accounts ─────────────────────────────
-- Inserts are guarded by NOT EXISTS so re-running is a no-op.
INSERT INTO users (email, password_hash, name, role, expert_id, bio)
SELECT v.email, v.password_hash, v.name, v.role, v.expert_id, v.bio
  FROM (VALUES
    ('sheikh.abdullah@test.com',
     '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
     'Sheikh Abdullah Al-Mansoori', 'SCHOLAR', 'e3',
     'Senior Shariah scholar with 20+ years auditing halal-compliant funds. AAOIFI advisor.'),
    ('fatima@test.com',
     '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
     'Fatima Al-Zahrani', 'EXPERT', 'e4',
     'CFA, focused on GCC large-caps and Saudi tech. Daily flow + weekly outlook.'),
    ('dr.yusuf@test.com',
     '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
     'Dr. Yusuf Rahman', 'SCHOLAR', 'e5',
     'PhD Islamic Economics. Issues fatwas on modern financial instruments.'),
    ('aisha@test.com',
     '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
     'Aisha Khalil', 'EXPERT', 'e6',
     'Wealth manager — long-term halal portfolio strategy and US tech exposure.'),
    ('mufti.bilal@test.com',
     '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
     'Mufti Bilal Khan', 'SCHOLAR', 'e7',
     'Dar al-Ifta scholar covering retirement, sukuk, and digital assets.')
  ) AS v(email, password_hash, name, role, expert_id, bio)
 WHERE NOT EXISTS (SELECT 1 FROM users WHERE users.email = v.email);

-- Cache new expert IDs in temp variables for downstream inserts.
-- Using a CTE-then-merge pattern keeps the migration self-contained.

-- ── 3. Three new subscriber accounts ─────────────────────────────────
INSERT INTO users (email, password_hash, name, role, bio)
SELECT v.email, v.password_hash, v.name, v.role, v.bio
  FROM (VALUES
    ('khaled@test.com',
     '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
     'Khaled Mansour', 'USER', 'GCC retail investor, 7yr halal portfolio.'),
    ('layla@test.com',
     '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
     'Layla Hassan', 'USER', 'New to investing, learning sukuk + REITs.'),
    ('omar@test.com',
     '$2a$10$89nXbr1bXGprsh2J9lyn7O4ozSSChx/IAeNasEGEPzeN3516GTWsq',
     'Omar Khalil', 'USER', 'US tech bull, focused on Shariah-screened megacaps.')
  ) AS v(email, password_hash, name, role, bio)
 WHERE NOT EXISTS (SELECT 1 FROM users WHERE users.email = v.email);

-- ── 3.5. Expert profile rows (FK target for posts + subscriptions) ──
-- The `experts` table is separate from `users` — every user with a
-- non-null users.expert_id must also have a row here. Without this,
-- post_expert_id_fkey + expert_subscriptions_expert_id_fkey both fail.
INSERT INTO experts (id, name, expertise, bio, tier, subscriber_count)
SELECT u.expert_id,
       u.name,
       CASE u.email
         WHEN 'sheikh.abdullah@test.com' THEN 'Islamic Finance · Halal Funds'
         WHEN 'fatima@test.com'           THEN 'GCC Stocks · Saudi Tech'
         WHEN 'dr.yusuf@test.com'         THEN 'Shariah Compliance · Fatwa'
         WHEN 'aisha@test.com'            THEN 'US Tech · Portfolio Strategy'
         WHEN 'mufti.bilal@test.com'      THEN 'Sukuk · Retirement · Digital Assets'
       END,
       u.bio,
       LOWER(u.role),  -- 'expert' or 'scholar' — passes the check constraint
       0
  FROM users u
 WHERE u.email IN (
   'sheikh.abdullah@test.com', 'fatima@test.com',
   'dr.yusuf@test.com', 'aisha@test.com', 'mufti.bilal@test.com'
 )
   AND NOT EXISTS (SELECT 1 FROM experts WHERE experts.id = u.expert_id);

-- ── 4. Approved expert applications for the new experts ─────────────
-- Gives each new expert a forensic paper-trail in the dashboard.
-- Reviewed by admin (id 1000), reviewed 60 days ago for plausibility.
INSERT INTO expert_applications (
  user_id, full_name, expertise, bio, credentials, country,
  status, submitted_at, reviewed_at, reviewed_by
)
SELECT u.id,
       u.name,
       CASE u.email
         WHEN 'sheikh.abdullah@test.com' THEN 'Islamic Finance'
         WHEN 'fatima@test.com'           THEN 'GCC Stock Analysis'
         WHEN 'dr.yusuf@test.com'         THEN 'Shariah Compliance'
         WHEN 'aisha@test.com'            THEN 'Portfolio Strategy'
         WHEN 'mufti.bilal@test.com'      THEN 'Fatwa & Rulings'
       END,
       u.bio,
       '["AAOIFI", "CFA / equivalent"]'::jsonb,
       CASE u.email
         WHEN 'sheikh.abdullah@test.com' THEN 'UAE'
         WHEN 'fatima@test.com'           THEN 'Saudi Arabia'
         WHEN 'dr.yusuf@test.com'         THEN 'UK'
         WHEN 'aisha@test.com'            THEN 'USA'
         WHEN 'mufti.bilal@test.com'      THEN 'Pakistan'
       END,
       'approved',
       NOW() - INTERVAL '62 days',
       NOW() - INTERVAL '60 days',
       1000
  FROM users u
 WHERE u.email IN (
   'sheikh.abdullah@test.com', 'fatima@test.com',
   'dr.yusuf@test.com', 'aisha@test.com', 'mufti.bilal@test.com'
 )
   AND NOT EXISTS (
     SELECT 1 FROM expert_applications a
      WHERE a.user_id = u.id AND a.status = 'approved'
   );

-- ── 5. Active subscriptions ─────────────────────────────────────────
-- Pattern matches the existing accepted-state shape:
--   status=active, accepted_at=now-1d, expires_at=now+364d, accepted_by=admin
INSERT INTO expert_subscriptions (
  user_id, expert_id, status, accepted_by,
  plan, price_cents, currency, payment_method,
  created_at, accepted_at, expires_at
)
SELECT sub.user_id, sub.expert_id, 'active', 1000,
       'monthly', 1500, 'USD', 'cash',
       NOW() - INTERVAL '2 days',
       NOW() - INTERVAL '1 day',
       NOW() + INTERVAL '364 days'
  FROM (VALUES
    -- Khaled → Sarah (e2) + Sheikh Abdullah (e3)
    ((SELECT id FROM users WHERE email = 'khaled@test.com'), 'e2'),
    ((SELECT id FROM users WHERE email = 'khaled@test.com'), 'e3'),
    -- Layla → Fatima (e4) + Dr. Yusuf (e5)
    ((SELECT id FROM users WHERE email = 'layla@test.com'),  'e4'),
    ((SELECT id FROM users WHERE email = 'layla@test.com'),  'e5'),
    -- Omar → Sarah (e2) + Aisha (e6) + Mufti Bilal (e7)
    ((SELECT id FROM users WHERE email = 'omar@test.com'),   'e2'),
    ((SELECT id FROM users WHERE email = 'omar@test.com'),   'e6'),
    ((SELECT id FROM users WHERE email = 'omar@test.com'),   'e7')
  ) AS sub(user_id, expert_id)
 WHERE sub.user_id IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM expert_subscriptions s
      WHERE s.user_id = sub.user_id AND s.expert_id = sub.expert_id
        AND s.status = 'active'
   );

-- ── 6. Owner backfill on legacy communities ─────────────────────────
-- Every community must have an owner. Pairs are aligned to expertise:
--   c_glob (Global Halal)   → Sarah (e2, US tech, broadest brand)
--   c_sa   (Saudi Markets)  → Ahmad (e1, GCC analyst)
--   c_ae   (UAE Investors)  → Fatima (e4, GCC stocks)
--   c_us   (US Halal Tech)  → Aisha (e6, US tech portfolio strategy)
UPDATE communities SET owner_id = (
  SELECT id FROM users WHERE expert_id = 'e2'
) WHERE id = 'c_glob' AND owner_id IS NULL;

UPDATE communities SET owner_id = (
  SELECT id FROM users WHERE expert_id = 'e1'
) WHERE id = 'c_sa' AND owner_id IS NULL;

UPDATE communities SET owner_id = (
  SELECT id FROM users WHERE expert_id = 'e4'
) WHERE id = 'c_ae' AND owner_id IS NULL;

UPDATE communities SET owner_id = (
  SELECT id FROM users WHERE expert_id = 'e6'
) WHERE id = 'c_us' AND owner_id IS NULL;

-- ── 7. Community memberships ────────────────────────────────────────
-- Spread members so every community has 4–6 people. Owners are
-- auto-members of the community they own — added explicitly here so
-- the rows exist in community_members regardless of how the membership
-- query is shaped downstream.
INSERT INTO community_members (user_id, community_id)
SELECT u.id, m.community_id
  FROM (VALUES
    -- Each tuple: (email, community_id)
    ('admin@test.com',           'c_glob'),
    ('expert@test.com',          'c_glob'),
    ('expert@test.com',          'c_us'),
    ('scholar@test.com',         'c_glob'),
    ('scholar@test.com',         'c_sa'),
    ('scholar@test.com',         'c_ae'),
    ('user@test.com',            'c_glob'),
    ('user@test.com',            'c_sa'),
    ('you@test.com',             'c_glob'),
    ('you@test.com',             'c_us'),
    ('sheikh.abdullah@test.com', 'c_glob'),
    ('sheikh.abdullah@test.com', 'c_ae'),
    ('fatima@test.com',          'c_ae'),
    ('fatima@test.com',          'c_sa'),
    ('dr.yusuf@test.com',        'c_glob'),
    ('aisha@test.com',           'c_us'),
    ('aisha@test.com',           'c_glob'),
    ('mufti.bilal@test.com',     'c_glob'),
    ('khaled@test.com',          'c_sa'),
    ('khaled@test.com',          'c_ae'),
    ('khaled@test.com',          'c_glob'),
    ('layla@test.com',           'c_glob'),
    ('layla@test.com',           'c_us'),
    ('omar@test.com',            'c_us'),
    ('omar@test.com',            'c_glob')
  ) AS m(email, community_id)
  JOIN users u ON u.email = m.email
 WHERE NOT EXISTS (
   SELECT 1 FROM community_members cm
    WHERE cm.user_id = u.id AND cm.community_id = m.community_id
 );

-- ── 8. Seed posts for the new experts ───────────────────────────────
-- Cover URLs are stable Unsplash images so the look is consistent
-- across machines (no broken thumbnails on a fresh checkout).
INSERT INTO posts (
  target_type, expert_id, author_id, author_name,
  title, body, tickers, post_type, cover_url,
  visibility, created_at
)
SELECT 'expert', p.expert_id,
       (SELECT id FROM users WHERE expert_id = p.expert_id),
       (SELECT name FROM users WHERE expert_id = p.expert_id),
       p.title, p.body, p.tickers::jsonb, p.post_type, p.cover_url,
       p.visibility, NOW() - (p.age_hours || ' hours')::interval
  FROM (VALUES
    -- Sheikh Abdullah Al-Mansoori (e3) — 4 posts (mix article + reel)
    ('e3', 'AAOIFI Standard 31 — what changed in the 2024 revision',
     'The AAOIFI Standard 31 revision tightens the screening of revenue-source ratios for hybrid products. Three practical implications for halal-compliant fund managers...',
     '["RAJHIB", "ALINMA"]', 'article',
     'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=800',
     'public', 18),
    ('e3', 'Why "interest-free" alone isn''t enough',
     'A short explainer on impurities ratio and why a screen of "no riba income" can still mask non-compliance through opaque holdings...',
     '[]', 'article',
     'https://images.unsplash.com/photo-1607968565043-36af90dde238?w=800',
     'subscribers_only', 30),
    ('e3', 'Sukuk vs Eurobond — tax-equivalent yield comparison',
     'Worked example comparing a 5y sukuk against a comparable Eurobond. Net of zakat and gross-up, the structural difference flips the apparent yield gap...',
     '["GCCB"]', 'article',
     'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=800',
     'subscribers_only', 50),
    ('e3', '90 seconds: AAOIFI 59 — fixed deposits',
     'Quick walkthrough of why traditional fixed deposits fail screen 59 and how mudarabah-based alternatives compare.',
     '[]', 'reel',
     'https://images.unsplash.com/photo-1554224155-1696413565d3?w=800',
     'public', 72),

    -- Fatima Al-Zahrani (e4) — 3 posts
    ('e4', 'GCC large-cap flow — week of May 6',
     'ARAMCO led the week on dividend revision. STC saw mid-week selling on a downgrade. Three names worth watching into next week...',
     '["ARAMCO", "STC", "SABIC"]', 'article',
     'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=800',
     'public', 6),
    ('e4', 'Saudi Arabia Vision 2030 — equity exposure check',
     'Mapping the largest 12 Vision 2030 beneficiaries to Tadawul tickers, halal grade, and 2025 estimates...',
     '["MAADEN", "ELM", "STC"]', 'article',
     'https://images.unsplash.com/photo-1554224154-26032ffc0d07?w=800',
     'subscribers_only', 26),
    ('e4', 'Reel: ARAMCO dividend math, fast',
     'Why the trailing yield is misleading when payout policy resets quarterly.',
     '["ARAMCO"]', 'reel',
     'https://images.unsplash.com/photo-1591696205602-2f950c417cb9?w=800',
     'public', 12),

    -- Dr. Yusuf Rahman (e5) — 3 posts (articles only)
    ('e5', 'Fatwa: Bitcoin staking yield — analysis',
     'Detailed analysis of staking returns under different schools, from a hadith and ijma perspective. The risk-yield separation matters more than people think...',
     '[]', 'article',
     'https://images.unsplash.com/photo-1518544866330-95a2bec01d72?w=800',
     'public', 4),
    ('e5', 'Margin trading and qard hasan',
     'Modern broker margin facilities — when do they cross the line? A scholar''s framework for screening.',
     '[]', 'article',
     'https://images.unsplash.com/photo-1535320903710-d993d3d77d29?w=800',
     'subscribers_only', 28),
    ('e5', 'Zakat on capital gains — 2025 framework',
     'New worked examples for hybrid portfolios mixing equity, sukuk, and digital assets...',
     '[]', 'article',
     'https://images.unsplash.com/photo-1554224154-22dec7ec8818?w=800',
     'subscribers_only', 96),

    -- Aisha Khalil (e6) — 4 posts (mix all 3 types)
    ('e6', 'US tech megacaps — Q2 reset',
     'NVDA + MSFT + GOOGL all hit screen-grade questions this quarter. Here''s the rebalance I''m running for clients...',
     '["NVDA", "MSFT", "GOOGL"]', 'article',
     'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=800',
     'subscribers_only', 14),
    ('e6', 'Reel: NVDA earnings recap in 60s',
     'Quick take on tonight''s NVDA print and what it means for halal tech allocation.',
     '["NVDA"]', 'reel',
     'https://images.unsplash.com/photo-1639762681485-074b7f938ba0?w=800',
     'public', 36),
    ('e6', 'Halal portfolio model — 2025 update',
     'My current 60/30/10 allocation across halal equity, sukuk, and cash equivalents. Annualised return + zakat-adjusted...',
     '[]', 'article',
     'https://images.unsplash.com/photo-1559526324-4b87b5e36e44?w=800',
     'subscribers_only', 60),
    ('e6', 'Video: Building your first halal portfolio',
     '12-minute walkthrough for new investors on what to screen for and where to start.',
     '[]', 'video',
     'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=800',
     'public', 110),

    -- Mufti Bilal Khan (e7) — 2 posts
    ('e7', 'Retirement accounts and riba — practical guidance',
     'Most US 401(k) target-date funds have screen-failing constituents. Three workarounds and what to ask your plan administrator...',
     '[]', 'article',
     'https://images.unsplash.com/photo-1554224155-1696413565d3?w=800',
     'public', 8),
    ('e7', 'Sukuk laddering for retail investors',
     'A simple 5-rung sukuk ladder example with rebalance triggers...',
     '[]', 'article',
     'https://images.unsplash.com/photo-1605792657660-596af9009e82?w=800',
     'subscribers_only', 44)
  ) AS p(expert_id, title, body, tickers, post_type, cover_url, visibility, age_hours)
 WHERE NOT EXISTS (
   SELECT 1 FROM posts
    WHERE expert_id = p.expert_id
      AND title = p.title
 );

COMMIT;
