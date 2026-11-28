-- 0056_pulse.sql
--
-- UNMU Pulse (نبض أنمو) Phase 1 — daily curated briefing.
-- Spec: "UNMU Pulse MVP" PDF; plan: docs/pulse/PLAN.md.
--
-- Tables
--   pulse_staff           who may edit / review / approve (ADMIN users are the
--                         system admins and are NOT listed here)
--   pulse_items           one row per Pulse item (4 slots per day)
--   pulse_item_versions   full JSON snapshot on every edit / correction
--   pulse_item_events     append-only change log (who did what, when)
--   pulse_saves           a user's saved Pulse items
--   pulse_events          read / save / share events for the basic analytics
--   user_notification_prefs  + 5 Pulse columns
--
-- IMPORTANT: start-railway.sh does NOT run migrations (schema is managed out
-- of band). Apply this file by hand to every database BEFORE deploying the
-- backend that uses it:   psql "$DATABASE_URL" -f 0056_pulse.sql
-- Reverse with 0056_pulse.down.sql. Safe to run twice (IF NOT EXISTS).
--
-- Rules enforced here, as the last line of defence (the Go service enforces
-- the same rules first and gives friendly errors):
--   * both languages + a source + a verification time are required before an
--     item can leave 'draft';
--   * an item cannot be approved / scheduled / published without an approver;
--   * the Sharia slot is always "sensitive", and a sensitive item also needs a
--     reviewer before it can be approved (spec §6-7: nothing sensitive is
--     published before review AND approval);
--   * at most ONE published item per (day, slot).
-- "Author may not approve their own item" is enforced in the service layer,
-- not here, so that the audit trail can still record who acted.

BEGIN;

-- Keeps updated_at honest without every query having to remember it.
CREATE OR REPLACE FUNCTION pulse_touch_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ─── Staff ────────────────────────────────────────────────────────────────
-- A user may hold several Pulse roles. users.role = 'ADMIN' already means
-- system admin, so users_role_check (USER/EXPERT/ADMIN) is left untouched.
CREATE TABLE IF NOT EXISTS pulse_staff (
    id          BIGSERIAL   PRIMARY KEY,
    user_id     BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pulse_role  TEXT        NOT NULL
                CHECK (pulse_role IN ('editor', 'reviewer', 'approver')),
    created_by  BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, pulse_role)
);
CREATE INDEX IF NOT EXISTS idx_pulse_staff_created_by ON pulse_staff (created_by);

-- ─── Items ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pulse_items (
    id              BIGSERIAL   PRIMARY KEY,
    pulse_date      DATE        NOT NULL,
    -- The four daily slots from spec §2.
    slot            TEXT        NOT NULL
                    CHECK (slot IN ('global', 'gulf', 'sharia', 'opportunity')),
    -- Spec §4: confirmed information vs analysis & interpretation.
    classification  TEXT        NOT NULL
                    CHECK (classification IN ('confirmed', 'analysis')),
    status          TEXT        NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'in_review', 'approved',
                                      'scheduled', 'published', 'archived')),
    -- Sensitive / Sharia content needs a reviewer AND an approver.
    is_sensitive    BOOLEAN     NOT NULL DEFAULT FALSE,

    title_ar        TEXT        NOT NULL DEFAULT '',
    title_en        TEXT        NOT NULL DEFAULT '',
    summary_ar      TEXT        NOT NULL DEFAULT '',
    summary_en      TEXT        NOT NULL DEFAULT '',
    details_ar      TEXT        NOT NULL DEFAULT '',
    details_en      TEXT        NOT NULL DEFAULT '',
    evidence_ar     TEXT        NOT NULL DEFAULT '',
    evidence_en     TEXT        NOT NULL DEFAULT '',

    source_name     TEXT        NOT NULL DEFAULT '',
    source_url      TEXT        NOT NULL DEFAULT '',
    verified_at     TIMESTAMPTZ,

    -- Optional link to a stock/company/asset already in the app.
    stock_id        INTEGER     REFERENCES stocks(id) ON DELETE SET NULL,

    -- Bumped on every edit after creation; the matching snapshot lives in
    -- pulse_item_versions.
    version         INTEGER     NOT NULL DEFAULT 1 CHECK (version >= 1),
    -- Marker shown to users once a published item is changed (spec §14).
    change_kind     TEXT        CHECK (change_kind IN ('updated', 'corrected')),
    last_changed_at TIMESTAMPTZ,

    publish_at      TIMESTAMPTZ,
    published_at    TIMESTAMPTZ,

    created_by      BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    reviewed_by     BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at     TIMESTAMPTZ,
    approved_by     BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    approved_at     TIMESTAMPTZ,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- The Sharia slot is always sensitive (spec §7).
    CONSTRAINT pulse_items_sharia_sensitive
        CHECK (slot <> 'sharia' OR is_sensitive),

    -- Both languages + source + verification time before leaving draft
    -- (spec §19 bilingual; §5 source and verification time on every item).
    CONSTRAINT pulse_items_complete_before_review
        CHECK (status = 'draft' OR (
            title_ar <> '' AND title_en <> '' AND
            summary_ar <> '' AND summary_en <> '' AND
            source_name <> '' AND verified_at IS NOT NULL)),

    -- No approved / scheduled / published item without an approver.
    CONSTRAINT pulse_items_approver_required
        CHECK (status IN ('draft', 'in_review') OR approved_by IS NOT NULL),

    -- Sensitive items also need a reviewer on record.
    CONSTRAINT pulse_items_sensitive_needs_reviewer
        CHECK (NOT is_sensitive OR status IN ('draft', 'in_review')
               OR reviewed_by IS NOT NULL),

    -- Scheduled items must say when; published items must carry the time.
    CONSTRAINT pulse_items_schedule_fields
        CHECK ((status <> 'scheduled' OR publish_at IS NOT NULL)
           AND (status <> 'published' OR published_at IS NOT NULL))
);

-- At most one live item per day and slot.
CREATE UNIQUE INDEX IF NOT EXISTS pulse_items_one_published_per_slot
    ON pulse_items (pulse_date, slot) WHERE status = 'published';
-- "Today's Pulse" and the archive read by day.
CREATE INDEX IF NOT EXISTS idx_pulse_items_date_slot ON pulse_items (pulse_date, slot);
-- The scheduler scans only due scheduled rows (same idea as idx_posts_scheduled).
CREATE INDEX IF NOT EXISTS idx_pulse_items_due
    ON pulse_items (publish_at) WHERE status = 'scheduled';
-- Admin list filters by status, newest first.
CREATE INDEX IF NOT EXISTS idx_pulse_items_status ON pulse_items (status, pulse_date DESC);
CREATE INDEX IF NOT EXISTS idx_pulse_items_stock ON pulse_items (stock_id);
CREATE INDEX IF NOT EXISTS idx_pulse_items_created_by ON pulse_items (created_by);
CREATE INDEX IF NOT EXISTS idx_pulse_items_reviewed_by ON pulse_items (reviewed_by);
CREATE INDEX IF NOT EXISTS idx_pulse_items_approved_by ON pulse_items (approved_by);

DROP TRIGGER IF EXISTS pulse_items_touch ON pulse_items;
CREATE TRIGGER pulse_items_touch BEFORE UPDATE ON pulse_items
    FOR EACH ROW EXECUTE FUNCTION pulse_touch_updated_at();

-- ─── Versions (spec §14: previous version is kept) ───────────────────────
CREATE TABLE IF NOT EXISTS pulse_item_versions (
    id          BIGSERIAL   PRIMARY KEY,
    item_id     BIGINT      NOT NULL REFERENCES pulse_items(id) ON DELETE CASCADE,
    version     INTEGER     NOT NULL CHECK (version >= 1),
    snapshot    JSONB       NOT NULL,
    reason      TEXT        NOT NULL
                CHECK (reason IN ('create', 'edit', 'update', 'correction')),
    created_by  BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (item_id, version)
);
CREATE INDEX IF NOT EXISTS idx_pulse_item_versions_created_by
    ON pulse_item_versions (created_by);

-- ─── Change log (spec §15) ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pulse_item_events (
    id           BIGSERIAL   PRIMARY KEY,
    item_id      BIGINT      NOT NULL REFERENCES pulse_items(id) ON DELETE CASCADE,
    action       TEXT        NOT NULL
                 CHECK (action IN ('created', 'edited', 'submitted', 'reviewed',
                                   'rejected', 'approved', 'scheduled',
                                   'published', 'updated', 'corrected', 'unscheduled',
                                   'archived')),
    actor_id     BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    from_status  TEXT,
    to_status    TEXT,
    note         TEXT        NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pulse_item_events_item
    ON pulse_item_events (item_id, created_at);
CREATE INDEX IF NOT EXISTS idx_pulse_item_events_actor ON pulse_item_events (actor_id);

-- The log is append-only: rows may be inserted but never rewritten.
CREATE OR REPLACE FUNCTION pulse_item_events_no_update() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'pulse_item_events is append-only';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS pulse_item_events_immutable ON pulse_item_events;
CREATE TRIGGER pulse_item_events_immutable BEFORE UPDATE ON pulse_item_events
    FOR EACH ROW EXECUTE FUNCTION pulse_item_events_no_update();

-- ─── Saves (spec §11) ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pulse_saves (
    id          BIGSERIAL   PRIMARY KEY,
    user_id     BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    item_id     BIGINT      NOT NULL REFERENCES pulse_items(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, item_id)
);
-- "My saved Pulse", newest save first.
CREATE INDEX IF NOT EXISTS idx_pulse_saves_user ON pulse_saves (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_pulse_saves_item ON pulse_saves (item_id);

-- ─── Analytics events (spec §18) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pulse_events (
    id          BIGSERIAL   PRIMARY KEY,
    -- NULL for day-level events (view_day).
    item_id     BIGINT      REFERENCES pulse_items(id) ON DELETE CASCADE,
    user_id     BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    event       TEXT        NOT NULL
                CHECK (event IN ('view_day', 'open_item', 'read_complete',
                                 'save', 'unsave', 'share', 'open_source',
                                 'open_stock')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pulse_events_item ON pulse_events (item_id, event, created_at);
CREATE INDEX IF NOT EXISTS idx_pulse_events_user ON pulse_events (user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_pulse_events_day ON pulse_events (event, created_at);

-- ─── Notification preferences (spec §17) ─────────────────────────────────
-- pulse_enabled is the master switch; the other four mirror the four events
-- a user can be told about. All default ON.
ALTER TABLE user_notification_prefs
    ADD COLUMN IF NOT EXISTS pulse_enabled             BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS pulse_new_enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS pulse_updates_enabled     BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS pulse_corrections_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS pulse_saved_enabled       BOOLEAN NOT NULL DEFAULT TRUE;

COMMIT;
