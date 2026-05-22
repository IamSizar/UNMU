-- Apple In-App-Purchase transactions. One row per Apple transaction we've
-- successfully verified via Apple's verifyReceipt endpoint. We persist
-- here so we can (a) reject replay attempts (UNIQUE on transaction_id)
-- and (b) audit what subscription state a user has paid for.
--
-- The corresponding expert_subscription row (when product_id maps to an
-- expert sub) references this transaction via the existing payment_ref
-- column (which already stores arbitrary opaque strings).
CREATE TABLE IF NOT EXISTS apple_iap_transactions (
    id                       BIGSERIAL PRIMARY KEY,
    user_id                  BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Apple identifiers. transaction_id is unique per purchase event;
    -- original_transaction_id stays the same across renewals of a sub.
    transaction_id           TEXT NOT NULL UNIQUE,
    original_transaction_id  TEXT NOT NULL,
    product_id               TEXT NOT NULL,

    -- Whether this verification was against Apple's production endpoint
    -- (https://buy.itunes.apple.com/verifyReceipt) or sandbox
    -- (https://sandbox.itunes.apple.com/verifyReceipt). Sandbox receipts
    -- show up during App Store review and from sandbox testers; the
    -- verifier auto-detects and records which one matched.
    environment              TEXT NOT NULL CHECK (environment IN ('Production', 'Sandbox')),

    -- The lifecycle dates Apple reports. expires_date is null for non-
    -- subscription products (one-time purchases / consumables).
    purchase_date            TIMESTAMPTZ NOT NULL,
    expires_date             TIMESTAMPTZ,

    -- Audit blob — the parsed receipt JSON Apple returned for THIS
    -- transaction (not the full receipt; just this transaction's slice).
    -- Useful when reconciling with Apple's records later.
    raw_payload              JSONB NOT NULL,

    created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_apple_iap_user_id
    ON apple_iap_transactions (user_id);

CREATE INDEX IF NOT EXISTS idx_apple_iap_original_txn
    ON apple_iap_transactions (original_transaction_id);

CREATE INDEX IF NOT EXISTS idx_apple_iap_product_id
    ON apple_iap_transactions (product_id);
