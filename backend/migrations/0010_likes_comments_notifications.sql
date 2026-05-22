-- =============================================================================
-- Step-6 — Likes, comments, and a user_notifications inbox.
--
-- Three new tables:
--   * post_likes      — (post_id, user_id) PK; one like per (user, post)
--   * post_comments   — flat thread per post; soft-delete not used (hard
--                       delete + count trigger keeps things simple)
--   * user_notifications   — recipient inbox; one row per like / comment /
--                       subscription event aimed at a single user
--
-- Triggers:
--   * Sync `posts.likes` and `posts.comments_count` whenever post_likes /
--     post_comments rows are added or removed.
--   * Insert a notification row on each new like / comment whose recipient
--     is the post's author (skipped when actor == recipient — Sarah doesn't
--     get notified about her own actions).
--   * NOTIFY on three new Postgres channels:
--       - post_like_events       { type, postId, expertId, userId, likes }
--       - post_comment_events    { type, postId, expertId, commentId, userId, body, count }
--       - notification_events    { userId, notificationId, type }
--
-- The Go listener (internal/realtime/listener.go) is taught about these
-- channels in the next commit. Existing channels keep working untouched.
--
-- Idempotent — safe to re-run.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. post_likes
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS post_likes (
    post_id    BIGINT      NOT NULL REFERENCES posts(id)   ON DELETE CASCADE,
    user_id    BIGINT      NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS post_likes_user_idx
    ON post_likes(user_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- 2. post_comments
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS post_comments (
    id          BIGSERIAL PRIMARY KEY,
    post_id     BIGINT      NOT NULL REFERENCES posts(id)  ON DELETE CASCADE,
    author_id   BIGINT      NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    author_name TEXT        NOT NULL,
    body        TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS post_comments_post_idx
    ON post_comments(post_id, created_at);

-- -----------------------------------------------------------------------------
-- 3. user_notifications
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_notifications (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_id      BIGINT      REFERENCES users(id)          ON DELETE SET NULL,
    actor_name    TEXT,
    type          TEXT        NOT NULL,
    post_id       BIGINT      REFERENCES posts(id)          ON DELETE CASCADE,
    comment_id    BIGINT      REFERENCES post_comments(id)  ON DELETE CASCADE,
    body_snippet  TEXT,
    read_at       TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_notifications_user_idx
    ON user_notifications(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS user_notifications_user_unread_idx
    ON user_notifications(user_id, created_at DESC)
    WHERE read_at IS NULL;

-- -----------------------------------------------------------------------------
-- 4. Helpers — keep posts.likes / posts.comments_count in sync.
-- -----------------------------------------------------------------------------

-- Like sync — increments / decrements posts.likes on insert / delete and
-- also fires a NOTIFY so connected clients update their counts in realtime.
CREATE OR REPLACE FUNCTION post_like_count_sync() RETURNS TRIGGER AS $$
DECLARE
    p_record RECORD;
    new_count INT;
    actor_name TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE posts SET likes = likes + 1 WHERE id = NEW.post_id
            RETURNING expert_id, author_id, title, post_type, likes INTO p_record;
        new_count := COALESCE(p_record.likes, 0);

        SELECT COALESCE(NULLIF(name, ''), email) INTO actor_name
            FROM users WHERE id = NEW.user_id;

        -- Notify the post author (skip self-likes) so Sarah's bell lights up.
        IF p_record.author_id IS NOT NULL AND p_record.author_id <> NEW.user_id THEN
            INSERT INTO user_notifications (
                user_id, actor_id, actor_name, type, post_id, body_snippet
            ) VALUES (
                p_record.author_id, NEW.user_id, actor_name,
                'post_liked', NEW.post_id, p_record.title
            );
        END IF;

        PERFORM pg_notify('post_like_events', json_build_object(
            'type',     'liked',
            'postId',   NEW.post_id,
            'expertId', p_record.expert_id,
            'userId',   NEW.user_id,
            'likes',    new_count
        )::text);
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        UPDATE posts SET likes = GREATEST(likes - 1, 0) WHERE id = OLD.post_id
            RETURNING expert_id, likes INTO p_record;
        new_count := COALESCE(p_record.likes, 0);

        PERFORM pg_notify('post_like_events', json_build_object(
            'type',     'unliked',
            'postId',   OLD.post_id,
            'expertId', p_record.expert_id,
            'userId',   OLD.user_id,
            'likes',    new_count
        )::text);
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS post_likes_count_sync ON post_likes;
CREATE TRIGGER post_likes_count_sync
    AFTER INSERT OR DELETE ON post_likes
    FOR EACH ROW EXECUTE FUNCTION post_like_count_sync();

-- Comment sync — same idea for posts.comments_count.
CREATE OR REPLACE FUNCTION post_comment_count_sync() RETURNS TRIGGER AS $$
DECLARE
    p_record RECORD;
    new_count INT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id
            RETURNING expert_id, author_id, title, comments_count INTO p_record;
        new_count := COALESCE(p_record.comments_count, 0);

        -- Notify post author (skip self-comments).
        IF p_record.author_id IS NOT NULL AND p_record.author_id <> NEW.author_id THEN
            INSERT INTO user_notifications (
                user_id, actor_id, actor_name, type, post_id, comment_id, body_snippet
            ) VALUES (
                p_record.author_id, NEW.author_id, NEW.author_name,
                'post_commented', NEW.post_id, NEW.id,
                LEFT(NEW.body, 140)
            );
        END IF;

        PERFORM pg_notify('post_comment_events', json_build_object(
            'type',      'created',
            'postId',    NEW.post_id,
            'expertId',  p_record.expert_id,
            'commentId', NEW.id,
            'userId',    NEW.author_id,
            'count',     new_count,
            'body',      LEFT(NEW.body, 140)
        )::text);
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        UPDATE posts SET comments_count = GREATEST(comments_count - 1, 0)
            WHERE id = OLD.post_id
            RETURNING expert_id, comments_count INTO p_record;
        new_count := COALESCE(p_record.comments_count, 0);

        PERFORM pg_notify('post_comment_events', json_build_object(
            'type',      'deleted',
            'postId',    OLD.post_id,
            'expertId',  p_record.expert_id,
            'commentId', OLD.id,
            'userId',    OLD.author_id,
            'count',     new_count
        )::text);
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS post_comments_count_sync ON post_comments;
CREATE TRIGGER post_comments_count_sync
    AFTER INSERT OR DELETE ON post_comments
    FOR EACH ROW EXECUTE FUNCTION post_comment_count_sync();

-- -----------------------------------------------------------------------------
-- 5. Notification NOTIFY — emit when a user_notifications row is inserted so the
--    recipient's WS client lights up the bell instantly.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notification_created_emit() RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('notification_events', json_build_object(
        'userId',         NEW.user_id,
        'notificationId', NEW.id,
        'type',           NEW.type,
        'actorName',      NEW.actor_name,
        'postId',         NEW.post_id,
        'commentId',      NEW.comment_id,
        'bodySnippet',    NEW.body_snippet
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_notifications_emit ON user_notifications;
CREATE TRIGGER user_notifications_emit
    AFTER INSERT ON user_notifications
    FOR EACH ROW EXECUTE FUNCTION notification_created_emit();

COMMIT;
