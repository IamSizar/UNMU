-- 0045_app_settings.sql
-- Global key/value app settings — drives admin feature flags. First use:
-- the community kill-switch (master + chat + posts sub-toggles) the admin
-- can flip from the dashboard in one click.
CREATE TABLE IF NOT EXISTS app_settings (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO app_settings (key, value) VALUES
    ('community_enabled',       'true'),
    ('community_chat_enabled',  'true'),
    ('community_posts_enabled', 'true')
ON CONFLICT (key) DO NOTHING;
