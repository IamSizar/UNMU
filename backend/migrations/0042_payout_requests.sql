-- Payout requests — experts cash out their earned subscription revenue.
--
-- Flow:
--   1. Expert opens Earnings → "Request payout" → fills amount + method.
--   2. POST /me/expert/payouts/request inserts a 'pending' row.
--   3. Admin reviews via /admin/payouts, transfers funds out-of-band
--      (bank wire / FIB / etc.), then POST /admin/payouts/:id/mark-paid
--      flips the row to 'paid' and stamps processed_at.
--   4. Available balance is computed as
--      lifetime_revenue − sum(paid + pending) so an expert can't
--      double-spend their earnings.
--
-- We do NOT hold money — UNMU is the platform-of-record but funds
-- flow directly via admin-initiated bank transfers. No Stripe Connect
-- yet (separate phase). The `payment_details` JSONB carries whatever
-- the expert needs the admin to know: bank IBAN, mobile-wallet phone
-- number, PayPal email — totally free-form.
CREATE TABLE IF NOT EXISTS payout_requests (
    id              BIGSERIAL PRIMARY KEY,

    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- expert_id snapshotted at request time so the row survives a
    -- demote-from-expert without breaking the FK. Just a label, not a
    -- FK constraint.
    expert_id       TEXT NOT NULL,

    amount_cents    INTEGER NOT NULL CHECK (amount_cents > 0),
    currency        VARCHAR(8) NOT NULL DEFAULT 'usd',

    -- bank | fib | paypal | other — the operator-readable label of how
    -- this payout should be sent. Free-form because every region has
    -- its own preferred method.
    method          VARCHAR(32) NOT NULL,
    payment_details JSONB NOT NULL DEFAULT '{}'::jsonb,

    status          VARCHAR(16) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'paid', 'rejected', 'cancelled')),
    admin_note      TEXT,
    processed_at    TIMESTAMPTZ,
    processed_by    BIGINT REFERENCES users(id) ON DELETE SET NULL,

    requested_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Admin queue → "pending first, newest first"
CREATE INDEX IF NOT EXISTS idx_payout_requests_status_requested_at
    ON payout_requests (status, requested_at DESC);

-- Expert dashboard reads their own history newest-first.
CREATE INDEX IF NOT EXISTS idx_payout_requests_user_id_requested_at
    ON payout_requests (user_id, requested_at DESC);
