-- 0061_google_play_purchases.sql — verified Google Play subscription purchases.
--
-- One row per purchase token. Google keeps the same token across renewals,
-- so re-verifying updates the row (new expiry / order id). An upgrade,
-- downgrade or re-subscribe issues a new token that points at the old one
-- (linked_purchase_token); ownership follows that chain so another account
-- cannot claim it. Mirrors apple_iap_transactions (mig 0035).
BEGIN;

CREATE TABLE IF NOT EXISTS google_play_purchases (
    id                     BIGSERIAL PRIMARY KEY,
    user_id                BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    purchase_token         TEXT        NOT NULL UNIQUE,
    linked_purchase_token  TEXT,
    order_id               TEXT        NOT NULL DEFAULT '',
    product_id             TEXT        NOT NULL,
    subscription_state     TEXT        NOT NULL,
    is_test                BOOLEAN     NOT NULL DEFAULT FALSE,
    purchase_date          TIMESTAMPTZ NOT NULL,
    expires_date           TIMESTAMPTZ,
    raw_payload            JSONB       NOT NULL,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_google_play_user_id
    ON google_play_purchases (user_id);
CREATE INDEX IF NOT EXISTS idx_google_play_linked_token
    ON google_play_purchases (linked_purchase_token);

COMMIT;
