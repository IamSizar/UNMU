-- 0055_referrals.sql
-- Referral program, built on top of the existing promo_codes table rather
-- than inventing new billing logic: redeeming a referral mints a one-time
-- promo code for both the referrer and the new user, and the existing
-- (already tested) promo-redemption path handles applying it.
--
-- SHARIAH-REVIEW: not fiqh-sensitive (no financial-instrument judgment
-- involved), but IS a monetization/fraud-surface change — the reward
-- percentage below is a placeholder pending product sign-off, and nothing
-- here rate-limits or fraud-checks referral redemption beyond "one
-- referred-by row per new user, and you can't refer yourself".
CREATE TABLE IF NOT EXISTS referrals (
    id                 BIGSERIAL PRIMARY KEY,
    referrer_user_id   BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    referred_user_id   BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    referral_code      TEXT NOT NULL,
    referrer_promo_id  BIGINT REFERENCES promo_codes(id) ON DELETE SET NULL,
    referred_promo_id  BIGINT REFERENCES promo_codes(id) ON DELETE SET NULL,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- A user can only ever be the REFERRED party once — otherwise the same
    -- new account could redeem multiple referral codes and mint unlimited
    -- rewards for different referrers.
    UNIQUE (referred_user_id)
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_user_id);

-- Each user's personal referral code — generated lazily on first request
-- (see ReferralRepository.GetOrCreateCode) rather than backfilled here.
CREATE TABLE IF NOT EXISTS user_referral_codes (
    user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    code    TEXT NOT NULL UNIQUE
);
