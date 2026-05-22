-- Pending email-change requests. Two-step flow:
--   1. User submits the new email + current password →
--      INSERT row here, email a 6-digit code to the new address.
--   2. User clicks the code in their inbox →
--      consume the row and flip users.email.
--
-- Hashed codes at rest (SHA-256). The plaintext code is short (6 digits)
-- so brute-force is technically feasible; combined with a 60-second
-- rate-limit on /request and a short TTL on /confirm we keep that risk
-- bounded.
CREATE TABLE IF NOT EXISTS email_change_requests (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    new_email   TEXT NOT NULL,
    code_hash   TEXT NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_email_change_requests_user_id
    ON email_change_requests (user_id);

CREATE INDEX IF NOT EXISTS idx_email_change_requests_expires_at
    ON email_change_requests (expires_at);
