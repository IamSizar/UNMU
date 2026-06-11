package repositories

import (
	"database/sql"
	"sync"
)

// AppSettingsRepository is a tiny key/value store for global feature flags,
// fronted by an in-memory cache so the request-path gate (CommunityGate) has
// zero DB cost per request. The cache is loaded at startup and refreshed on
// every Set.
type AppSettingsRepository struct {
	db    *sql.DB
	mu    sync.RWMutex
	cache map[string]bool
}

func NewAppSettingsRepository(db *sql.DB) *AppSettingsRepository {
	r := &AppSettingsRepository{db: db, cache: map[string]bool{}}
	r.reload()
	return r
}

func (r *AppSettingsRepository) reload() {
	rows, err := r.db.Query(`SELECT key, value FROM app_settings`)
	if err != nil {
		return // leave cache as-is; getBool falls back to defaults
	}
	defer rows.Close()
	m := map[string]bool{}
	for rows.Next() {
		var k, v string
		if rows.Scan(&k, &v) == nil {
			m[k] = v == "true"
		}
	}
	r.mu.Lock()
	r.cache = m
	r.mu.Unlock()
}

func (r *AppSettingsRepository) getBool(key string, def bool) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	if v, ok := r.cache[key]; ok {
		return v
	}
	return def // default = enabled, so a missing row never accidentally locks a feature
}

// ── Community feature flags ──
func (r *AppSettingsRepository) CommunityEnabled() bool      { return r.getBool("community_enabled", true) }
func (r *AppSettingsRepository) CommunityChatEnabled() bool  { return r.getBool("community_chat_enabled", true) }
func (r *AppSettingsRepository) CommunityPostsEnabled() bool { return r.getBool("community_posts_enabled", true) }

// TestAccountEnabled — controls whether the login screen shows the
// "Test account" quick-switch button. Default true (current behaviour);
// admins can hide it from the dashboard for production.
func (r *AppSettingsRepository) TestAccountEnabled() bool { return r.getBool("test_account_enabled", true) }

// Flags returns the camelCase shape the dashboard + app expect.
func (r *AppSettingsRepository) Flags() map[string]bool {
	return map[string]bool{
		"communityEnabled":      r.CommunityEnabled(),
		"communityChatEnabled":  r.CommunityChatEnabled(),
		"communityPostsEnabled": r.CommunityPostsEnabled(),
		"testAccountEnabled":    r.TestAccountEnabled(),
	}
}

// Set upserts one flag and refreshes the cache.
func (r *AppSettingsRepository) Set(key string, val bool) error {
	s := "false"
	if val {
		s = "true"
	}
	_, err := r.db.Exec(`
		INSERT INTO app_settings (key, value, updated_at) VALUES ($1, $2, now())
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
		key, s)
	if err == nil {
		r.reload()
	}
	return err
}
