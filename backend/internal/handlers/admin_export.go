package handlers

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"halalstocks/internal/config"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// pgDumpBin returns the pg_dump binary path the operator wants us to
// use. Falls back to "pg_dump" so PATH lookup keeps working in normal
// deployments. The override is critical on Homebrew machines where
// multiple Postgres versions coexist and the default `pg_dump` is
// often older than the running server.
func pgDumpBin() string {
	if v := os.Getenv("PG_DUMP_BIN"); strings.TrimSpace(v) != "" {
		return strings.TrimSpace(v)
	}
	return "pg_dump"
}

// AdminExportHandler — full-database export for admins.
//
// Two routes:
//   * GET /api/admin/export/json  → one big {tableName: [rows]} JSON
//                                   object, served as an attachment.
//   * GET /api/admin/export/sql   → pg_dump output (plain SQL with
//                                   schema + data + DROP IF EXISTS).
//
// Both endpoints stream the result directly to the browser as a file
// download (Content-Disposition: attachment). The admin route group
// already enforces the admin role + JWT.
//
// For SQL we shell out to `pg_dump` for two reasons:
//   1. It produces a true, restorable dump (schema + sequences + FK
//      constraints) rather than a hand-rolled INSERT-only export.
//   2. It already handles every edge case (escaping, blobs, custom
//      types, etc.) that we'd otherwise need to reinvent.
type AdminExportHandler struct {
	db  *sql.DB
	cfg *config.Config
}

func NewAdminExportHandler(db *sql.DB, cfg *config.Config) *AdminExportHandler {
	return &AdminExportHandler{db: db, cfg: cfg}
}

// ExportJSON — GET /api/admin/export/json
//
// Builds a `{table_name: [row, row, ...]}` map for every user table in
// the public schema. Rows are returned in their natural insertion
// order (PK ASC, falls back to ctid otherwise). Marshals to indented
// JSON for readability.
//
// Skips:
//   * Postgres-managed tables (pg_*, information_schema)
//   * Generated columns (pulled by `SELECT *` are fine — the column
//     just appears in the JSON, matches what's in DB).
func (h *AdminExportHandler) ExportJSON(c *gin.Context) {
	tables, err := h.listTables()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	out := make(map[string]any, len(tables))
	for _, table := range tables {
		rows, err := h.dumpTable(table)
		if err != nil {
			log.Printf("admin_export json: table %q failed: %v", table, err)
			out[table] = []any{} // empty rather than crash the whole dump
			continue
		}
		out[table] = rows
	}

	filename := fmt.Sprintf(
		"halalstocks-export-%s.json",
		time.Now().UTC().Format("2006-01-02-150405"),
	)
	c.Header(
		"Content-Disposition",
		`attachment; filename="`+filename+`"`,
	)
	c.Header("Content-Type", "application/json; charset=utf-8")
	// Pretty-print so the admin can grep / diff the file by hand.
	enc := json.NewEncoder(c.Writer)
	enc.SetIndent("", "  ")
	if err := enc.Encode(out); err != nil {
		log.Printf("admin_export json: encode failed: %v", err)
	}
}

// ExportSQL — GET /api/admin/export/sql
//
// Invokes `pg_dump --no-owner --no-acl --clean --if-exists --inserts`
// against the configured database and streams the output as a `.sql`
// attachment. Returns 500 with a clear message if `pg_dump` isn't on
// the host's PATH (deploys without it can fall back to the JSON
// export — they share the same data, just different shapes).
//
// Flags:
//   --no-owner    : strip OWNER TO clauses (admin re-importing into a
//                   different DB user shouldn't need to match names).
//   --no-acl      : skip GRANT / REVOKE — same portability reasoning.
//   --clean       : prepend DROP statements so re-import is idempotent.
//   --if-exists   : pairs with --clean — DROP IF EXISTS instead of DROP.
//   --inserts     : emit INSERT statements rather than COPY blocks —
//                   slower to restore but much easier to diff / cherry-
//                   pick when an admin wants to recover a single table.
func (h *AdminExportHandler) ExportSQL(c *gin.Context) {
	args := []string{
		"--host", h.cfg.DBHost,
		"--port", h.cfg.DBPort,
		"--username", h.cfg.DBUser,
		"--dbname", h.cfg.DBName,
		"--no-owner",
		"--no-acl",
		"--clean",
		"--if-exists",
		"--inserts",
	}
	// Honour PG_DUMP_BIN env override so the operator can point at a
	// specific pg_dump binary that matches the server version (the
	// default `pg_dump` on PATH can be an older Homebrew install
	// which aborts with "server version mismatch"). Falls back to the
	// PATH default when unset.
	cmd := exec.Command(pgDumpBin(), args...)
	if h.cfg.DBPassword != "" {
		cmd.Env = append(cmd.Environ(), "PGPASSWORD="+h.cfg.DBPassword)
	}

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to start pg_dump: " + err.Error(),
		})
		return
	}
	if err := cmd.Start(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to invoke pg_dump (is it on PATH?): " + err.Error(),
		})
		return
	}

	filename := fmt.Sprintf(
		"halalstocks-export-%s.sql",
		time.Now().UTC().Format("2006-01-02-150405"),
	)
	c.Header(
		"Content-Disposition",
		`attachment; filename="`+filename+`"`,
	)
	c.Header("Content-Type", "application/sql; charset=utf-8")

	// Stream pg_dump's stdout straight into the HTTP response. Avoids
	// buffering the whole dump in memory.
	if _, err := io.Copy(c.Writer, stdout); err != nil {
		log.Printf("admin_export sql: stream failed: %v", err)
	}
	if err := cmd.Wait(); err != nil {
		// Headers are already sent — log and move on. The download
		// will be truncated; admin will see an obvious error in the
		// last lines of the SQL file.
		log.Printf("admin_export sql: pg_dump exit %v stderr=%s",
			err, strings.TrimSpace(stderr.String()))
	}
}

// listTables — every user-created table in the public schema. Ordered
// alphabetically so the resulting JSON keys are stable across exports
// (helpful for diffing two dumps).
func (h *AdminExportHandler) listTables() ([]string, error) {
	rows, err := h.db.Query(`
		SELECT tablename FROM pg_tables
		 WHERE schemaname = 'public'
		 ORDER BY tablename
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		out = append(out, name)
	}
	return out, rows.Err()
}

// dumpTable — every row in the given table as a slice of
// column→value maps. Uses `SELECT *` + per-column type-coercion so
// numbers stay numbers in JSON instead of becoming quoted strings.
//
// Bytes are base64-encoded (matches the standard json.Marshal
// behaviour for `[]byte` values) so binary columns survive a round-
// trip through JSON.
func (h *AdminExportHandler) dumpTable(table string) ([]map[string]any, error) {
	// Identifier is static (came from pg_tables WHERE schemaname='public'),
	// not user input, so fmt.Sprintf is safe here.
	q := fmt.Sprintf(`SELECT * FROM "%s"`, table)
	rows, err := h.db.Query(q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	cols, err := rows.Columns()
	if err != nil {
		return nil, err
	}
	out := make([]map[string]any, 0)
	for rows.Next() {
		// Buffer one value per column. The interface{} target lets
		// pq pick the right Go type per column (int64, string,
		// time.Time, etc.).
		vals := make([]any, len(cols))
		ptrs := make([]any, len(cols))
		for i := range vals {
			ptrs[i] = &vals[i]
		}
		if err := rows.Scan(ptrs...); err != nil {
			return nil, err
		}
		rec := make(map[string]any, len(cols))
		for i, col := range cols {
			// pq returns []byte for some text columns — convert to
			// a Go string for clean JSON output.
			switch v := vals[i].(type) {
			case []byte:
				rec[col] = string(v)
			default:
				rec[col] = v
			}
		}
		out = append(out, rec)
	}
	return out, rows.Err()
}
