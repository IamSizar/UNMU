-- =============================================================================
-- 0019 — Community metadata + discovery
--
-- Items 2.13 → 2.18 from the audit. One migration, six features:
--
--   2.13 Edit community description       — uses existing communities.tagline
--                                           + the new `description` (long form).
--   2.14 Edit community rules             — new `rules` text column.
--   2.15 Search / discovery by interest    — full-text `search_tsv` + GIN index
--                                           over name + tagline + description.
--   2.16 Tags / categories                 — single optional `category` column
--                                           + many-to-many `community_tags`.
--   2.17 Cover image                       — `cover_url` text column. Files
--                                           land via the existing UploadHandler
--                                           under uploads/images/.
--   2.18 Public vs private                 — `is_public` boolean. Default FALSE
--                                           preserves the privacy model we
--                                           shipped (members-only). Owner can
--                                           flip to TRUE to expose the
--                                           community to read-only visitors.
--
-- Idempotent — every column / table / index uses IF NOT EXISTS so re-running
-- this migration is safe on a partially-applied database.
-- =============================================================================

ALTER TABLE communities
    ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS rules       TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS cover_url   TEXT,
    ADD COLUMN IF NOT EXISTS is_public   BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS category    TEXT;

-- Generated full-text search column. Stored so the GIN index can sit on it
-- directly. We use 'simple' (no stemming) because community names are often
-- proper nouns ("US Halal Tech") that English stemming would mangle.
ALTER TABLE communities
    ADD COLUMN IF NOT EXISTS search_tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector(
            'simple',
            COALESCE(name, '')        || ' ' ||
            COALESCE(tagline, '')     || ' ' ||
            COALESCE(description, '') || ' ' ||
            COALESCE(category, '')
        )
    ) STORED;

CREATE INDEX IF NOT EXISTS idx_communities_search_tsv
    ON communities USING GIN (search_tsv);

CREATE INDEX IF NOT EXISTS idx_communities_category
    ON communities (category);

CREATE INDEX IF NOT EXISTS idx_communities_is_public
    ON communities (is_public);

-- Many-to-many tag join. Free-form strings (lowercase normalized in the
-- handler) so users can tag with niche topics. Predefined categories live
-- on `communities.category` for the chip strip; tags are for fine-grained
-- search ranking.
CREATE TABLE IF NOT EXISTS community_tags (
    community_id TEXT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    tag          TEXT NOT NULL,
    PRIMARY KEY (community_id, tag)
);

CREATE INDEX IF NOT EXISTS idx_community_tags_tag
    ON community_tags (tag);
