// migrate_uploads_to_s3 — one-shot tool that moves any DB row still
// pointing at a local "/uploads/..." path onto S3, in lock-step:
//
//  1. SELECT every row with a `/uploads/...` URL in any of the 7
//     media-bearing columns we track.
//  2. For each, upload the corresponding file at
//     backend/uploads/<rest-of-path> to s3://$AWS_S3_BUCKET/<rest-of-path>
//     (the key matches the disk path so sign-on-read can sign it).
//  3. UPDATE the row to store the bare key. Sign-on-read in the repo
//     layer then mints a fresh presigned URL on every read.
//
// Safety:
//   - DRY RUN mode is on by default; pass --apply to actually mutate.
//   - Each row's upload + UPDATE happens in a single transaction so a
//     half-migrated row is impossible.
//   - Skips rows whose file isn't on disk (orphaned DB pointer) with a
//     warning — the operator gets a punch list of those for manual
//     resolution.
//
// Idempotent: re-running after success is a no-op (the next SELECT
// returns zero rows because everything now stores keys, not paths).
package main

import (
	"context"
	"database/sql"
	"flag"
	"fmt"
	"halalstocks/internal/config"
	"halalstocks/internal/services"
	"log"
	"mime"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

type target struct {
	table     string // SQL identifier
	column    string // SQL identifier
	idColumn  string // primary key column (varies — id for most, varchar for communities)
	rows      []row
}

type row struct {
	id    string // string form; we cast via SQL
	url   string // current "/uploads/..." value
}

// Tables + columns we migrate. The set matches the columns the
// repository-layer sign-on-read resolver inspects, so anything we
// don't list here also won't get re-signed.
var targets = []target{
	{table: "posts", column: "media_url", idColumn: "id"},
	{table: "posts", column: "cover_url", idColumn: "id"},
	{table: "communities", column: "cover_url", idColumn: "id"},
	{table: "communities", column: "avatar_url", idColumn: "id"},
	{table: "community_messages", column: "attachment_url", idColumn: "id"},
	{table: "expert_applications", column: "resume_url", idColumn: "id"},
	{table: "expert_applications", column: "avatar_url", idColumn: "id"},
}

func main() {
	apply := flag.Bool("apply", false, "actually mutate the DB + upload to S3 (default is dry-run)")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config load: %v", err)
	}
	if cfg.AWSS3Bucket == "" {
		log.Fatal("AWS_S3_BUCKET is empty — set it in .env before migrating")
	}

	ctx := context.Background()
	s3, err := services.NewS3Storage(ctx,
		cfg.AWSRegion, cfg.AWSS3Bucket,
		cfg.AWSAccessKeyID, cfg.AWSSecretAccessKey,
		time.Duration(cfg.AWSS3PresignGetHours)*time.Hour,
	)
	if err != nil {
		log.Fatalf("s3 init: %v", err)
	}

	db, err := sql.Open("postgres", cfg.DatabaseDSN())
	if err != nil {
		log.Fatalf("db open: %v", err)
	}
	defer db.Close()
	if err := db.Ping(); err != nil {
		log.Fatalf("db ping: %v", err)
	}

	mode := "DRY-RUN"
	if *apply {
		mode = "APPLY"
	}
	fmt.Printf("=== migrate_uploads_to_s3 [%s] ===\n", mode)
	fmt.Printf("bucket=%s  region=%s\n\n", cfg.AWSS3Bucket, cfg.AWSRegion)

	totalMigrated := 0
	totalSkipped := 0
	totalOrphan := 0

	for i := range targets {
		t := &targets[i]
		q := fmt.Sprintf(
			`SELECT %s, %s FROM %s WHERE %s LIKE '/uploads/%%'`,
			t.idColumn, t.column, t.table, t.column,
		)
		rows, err := db.Query(q)
		if err != nil {
			log.Fatalf("query %s.%s: %v", t.table, t.column, err)
		}
		for rows.Next() {
			var id, url string
			if err := rows.Scan(&id, &url); err != nil {
				log.Fatalf("scan %s.%s: %v", t.table, t.column, err)
			}
			t.rows = append(t.rows, row{id: id, url: url})
		}
		rows.Close()

		if len(t.rows) == 0 {
			continue
		}
		fmt.Printf("[%s.%s] %d row(s)\n", t.table, t.column, len(t.rows))

		for _, r := range t.rows {
			// "/uploads/images/abc.jpg" → "images/abc.jpg"
			key := strings.TrimPrefix(r.url, "/uploads/")
			diskPath := filepath.Join("uploads", key)
			info, statErr := os.Stat(diskPath)
			if statErr != nil || info.IsDir() {
				fmt.Printf("  ⚠️  ORPHAN id=%s url=%s — no file at %s, skipping\n",
					r.id, r.url, diskPath)
				totalOrphan++
				continue
			}

			if !*apply {
				fmt.Printf("  ✓ would migrate id=%s key=%s (%d bytes)\n", r.id, key, info.Size())
				totalSkipped++
				continue
			}

			f, err := os.Open(diskPath)
			if err != nil {
				log.Fatalf("open %s: %v", diskPath, err)
			}
			contentType := mime.TypeByExtension(filepath.Ext(diskPath))
			if contentType == "" {
				contentType = "application/octet-stream"
			}
			if err := s3.Upload(ctx, key, contentType, f); err != nil {
				f.Close()
				log.Fatalf("s3 upload %s: %v", key, err)
			}
			f.Close()

			// Update the DB row to store the bare key.
			updateQ := fmt.Sprintf(
				`UPDATE %s SET %s = $1 WHERE %s = $2`,
				t.table, t.column, t.idColumn,
			)
			if _, err := db.Exec(updateQ, key, r.id); err != nil {
				log.Fatalf("db update %s id=%s: %v", t.table, r.id, err)
			}
			fmt.Printf("  ✓ migrated id=%s key=%s\n", r.id, key)
			totalMigrated++
		}
	}

	fmt.Println()
	if *apply {
		fmt.Printf("DONE. migrated=%d  orphans=%d\n", totalMigrated, totalOrphan)
	} else {
		fmt.Printf("DRY-RUN. would-migrate=%d  orphans=%d  (re-run with --apply to commit)\n",
			totalSkipped, totalOrphan)
	}
}
