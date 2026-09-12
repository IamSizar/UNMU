package repositories

import (
	"database/sql"
	"strconv"
	"sync"
)

// AppSettingsRepository is a tiny key/value store for global feature flags
// and, since the screening-thresholds addition, numeric settings too — both
// fronted by an in-memory cache so the request-path gate (CommunityGate) and
// the screening ladder (see internal/shariah) have zero DB cost per lookup.
// The cache is loaded at startup and refreshed on every Set.
type AppSettingsRepository struct {
	db        *sql.DB
	mu        sync.RWMutex
	cache     map[string]bool
	raw       map[string]string
}

func NewAppSettingsRepository(db *sql.DB) *AppSettingsRepository {
	r := &AppSettingsRepository{db: db, cache: map[string]bool{}, raw: map[string]string{}}
	r.reload()
	return r
}

func (r *AppSettingsRepository) reload() {
	rows, err := r.db.Query(`SELECT key, value FROM app_settings`)
	if err != nil {
		return // leave cache as-is; getBool/getFloat fall back to defaults
	}
	defer rows.Close()
	m := map[string]bool{}
	raw := map[string]string{}
	for rows.Next() {
		var k, v string
		if rows.Scan(&k, &v) == nil {
			m[k] = v == "true"
			raw[k] = v
		}
	}
	r.mu.Lock()
	r.cache = m
	r.raw = raw
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

func (r *AppSettingsRepository) getFloat(key string, def float64) float64 {
	r.mu.RLock()
	v, ok := r.raw[key]
	r.mu.RUnlock()
	if !ok {
		return def
	}
	f, err := strconv.ParseFloat(v, 64)
	if err != nil {
		return def
	}
	return f
}

// SetFloat upserts one numeric setting and refreshes the cache.
func (r *AppSettingsRepository) SetFloat(key string, val float64) error {
	_, err := r.db.Exec(`
		INSERT INTO app_settings (key, value, updated_at) VALUES ($1, $2, now())
		ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
		key, strconv.FormatFloat(val, 'f', 4, 64))
	if err == nil {
		r.reload()
	}
	return err
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

// ── Shariah screening thresholds ──
// Keys map 1:1 onto shariah.Thresholds fields; defaults match
// shariah.DefaultThresholds exactly, so an un-configured install behaves
// exactly as it did before this became editable.
func (r *AppSettingsRepository) ScreeningDebtFail() float64  { return r.getFloat("screening_debt_fail", 33) }
func (r *AppSettingsRepository) ScreeningDebtWarn() float64  { return r.getFloat("screening_debt_warn", 30) }
func (r *AppSettingsRepository) ScreeningDebtPass() float64  { return r.getFloat("screening_debt_pass", 20) }
func (r *AppSettingsRepository) ScreeningDebtGood() float64  { return r.getFloat("screening_debt_good", 10) }
func (r *AppSettingsRepository) ScreeningHaramFail() float64 { return r.getFloat("screening_haram_fail", 10) }
func (r *AppSettingsRepository) ScreeningHaramWarn() float64 { return r.getFloat("screening_haram_warn", 5) }
func (r *AppSettingsRepository) ScreeningHaramPass() float64 { return r.getFloat("screening_haram_pass", 3) }
func (r *AppSettingsRepository) ScreeningHaramGood() float64 { return r.getFloat("screening_haram_good", 1) }

// ScreeningThresholdKeys lists every key the admin endpoint may read/write —
// used to validate incoming PUT payloads against a fixed allowlist rather
// than accepting an arbitrary key name into app_settings.
var ScreeningThresholdKeys = []string{
	"screening_debt_fail", "screening_debt_warn", "screening_debt_pass", "screening_debt_good",
	"screening_haram_fail", "screening_haram_warn", "screening_haram_pass", "screening_haram_good",
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
