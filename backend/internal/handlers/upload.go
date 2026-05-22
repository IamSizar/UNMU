package handlers

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"halalstocks/internal/services"
)

// UploadHandler accepts multipart file uploads from authenticated users.
// Files land under <root>/videos/ and <root>/images/, and the handler
// returns the URL the client should put on a post (mediaUrl / coverUrl).
//
// When S3 is non-nil the bytes are streamed straight to S3 instead of
// disk, and the returned URL is a pre-signed GET that the existing
// Flutter clients can play back without code changes. With S3 unset the
// handler falls back to the original on-disk behavior so dev machines
// without AWS keys keep working.
type UploadHandler struct {
	// Root is the on-disk root for uploads, e.g. "uploads".
	// In S3 mode it's still used for the chunked-upload staging area
	// (.tmp/) since stitching big files in memory would blow the heap.
	Root string
	// PublicBase is what the URL prefix should be, e.g. "/uploads".
	// Only used in disk-fallback mode.
	PublicBase string
	// S3 is the optional storage backend. When nil → disk mode.
	S3 *services.S3Storage
}

// NewUploadHandler creates the directories on the fly so a fresh checkout
// works without manual mkdir steps. Pass s3 = nil to keep the original
// local-disk behavior; pass a built S3Storage to push uploads to S3.
func NewUploadHandler(root, publicBase string, s3 *services.S3Storage) *UploadHandler {
	_ = os.MkdirAll(filepath.Join(root, "videos"), 0o755)
	_ = os.MkdirAll(filepath.Join(root, "images"), 0o755)
	_ = os.MkdirAll(filepath.Join(root, "documents"), 0o755)
	// Chunk staging area for resumable / chunked video uploads. Lives
	// alongside videos/ and images/ but is hidden from the public mount
	// (router serves /uploads/videos/ and /uploads/images/, not /tmp/).
	// Used in BOTH disk and S3 modes — S3 mode stitches chunks here
	// before doing one streaming upload to the bucket.
	_ = os.MkdirAll(filepath.Join(root, ".tmp"), 0o755)
	return &UploadHandler{Root: root, PublicBase: publicBase, S3: s3}
}

// storeAndURL persists the uploaded bytes — either to S3 (preferred when
// configured) or to local disk (fallback) — and returns the URL the
// client should put on a post. The S3 path uses the transfer manager so
// 100 MB reels get multipart-uploaded automatically; the disk path is
// the original `io.Copy(file, src)` flow.
//
// `subdir` is "videos" / "images" / "documents" and feeds both the on-
// disk path and the S3 key prefix. `name` is the final filename including
// extension. `src` is the request body reader.
func (h *UploadHandler) storeAndURL(
	ctx context.Context,
	subdir, name string,
	src io.Reader,
) (string, error) {
	if h.S3 != nil {
		key := subdir + "/" + name
		contentType := mime.TypeByExtension(filepath.Ext(name))
		if contentType == "" {
			contentType = "application/octet-stream"
		}
		if err := h.S3.Upload(ctx, key, contentType, src); err != nil {
			return "", err
		}
		return h.S3.PresignGet(ctx, key)
	}

	dstPath := filepath.Join(h.Root, subdir, name)
	dst, err := os.Create(dstPath)
	if err != nil {
		return "", fmt.Errorf("create %s: %w", dstPath, err)
	}
	defer dst.Close()
	if _, err := io.Copy(dst, src); err != nil {
		_ = os.Remove(dstPath)
		return "", fmt.Errorf("write %s: %w", dstPath, err)
	}
	return h.PublicBase + "/" + subdir + "/" + name, nil
}

// Limits in bytes. Reels max out at ~60s so a 100 MB ceiling on video is
// generous (1080p reels usually under 50 MB). Images cap at 8 MB.
// Documents (resumes / credentials) cap at 10 MB — most tasteful resume
// PDFs are under 2 MB; 10 MB lets people get away with image-heavy ones.
const (
	maxVideoBytes    = 100 * 1024 * 1024
	maxImageBytes    = 8 * 1024 * 1024
	maxDocumentBytes = 10 * 1024 * 1024
)

// Whitelisted extensions. We don't trust the multipart Content-Type (easy
// to spoof) — extensions are checked instead. The video player + Image
// widget will reject anything that's not actually playable / decodable
// downstream anyway.
var (
	videoExts = map[string]bool{
		".mp4": true, ".m4v": true, ".mov": true,
		".webm": true, ".mkv": true,
	}
	imageExts = map[string]bool{
		".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".gif": true,
	}
	// Resume / credentials uploads. Keep tight — admin reviewers should
	// see PDFs that any browser can render inline, not arbitrary blobs.
	documentExts = map[string]bool{
		".pdf": true,
	}
)

// POST /api/me/uploads/video
// Multipart field name: "file"
// Response: { "url": "/uploads/videos/<random>.mp4" }
func (h *UploadHandler) UploadVideo(c *gin.Context) {
	h.uploadFile(c, "videos", videoExts, maxVideoBytes)
}

// POST /api/me/uploads/image
// Multipart field name: "file"
// Response: { "url": "/uploads/images/<random>.jpg" }
func (h *UploadHandler) UploadImage(c *gin.Context) {
	h.uploadFile(c, "images", imageExts, maxImageBytes)
}

// POST /api/me/uploads/document
// Multipart field name: "file"
// Response: { "url": "/uploads/documents/<random>.pdf" }
//
// Used by the expert-application form for resume / credentials uploads.
// Strict to PDF only so reviewers don't have to install random viewers.
func (h *UploadHandler) UploadDocument(c *gin.Context) {
	h.uploadFile(c, "documents", documentExts, maxDocumentBytes)
}

func (h *UploadHandler) uploadFile(
	c *gin.Context,
	subdir string,
	allowed map[string]bool,
	maxBytes int64,
) {
	// Auth check. The middleware sets user_id; if it's missing the JWT
	// middleware would have already responded 401, but be defensive.
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}

	// Cap the request body so a malicious client can't exhaust disk.
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxBytes+1024)

	fileHeader, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "expected multipart field 'file'",
		})
		return
	}
	if fileHeader.Size > maxBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"error": fmt.Sprintf("file is too large (max %d MB)", maxBytes/1024/1024),
		})
		return
	}
	ext := strings.ToLower(filepath.Ext(fileHeader.Filename))
	if !allowed[ext] {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "unsupported file type: " + ext,
		})
		return
	}

	// Random opaque filename — original name leaks user info and can
	// collide. 16 bytes hex = ~3.4 × 10^38 namespace.
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "rand failed"})
		return
	}
	name := hex.EncodeToString(buf) + ext

	src, err := fileHeader.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read upload"})
		return
	}
	defer src.Close()

	url, err := h.storeAndURL(c.Request.Context(), subdir, name, src)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "store failed: " + err.Error()})
		return
	}
	// `key` is the S3 object key (subdir/name) or disk path fragment —
	// stable across URL refreshes, safe to persist on the post row when
	// we move to sign-on-read.
	c.JSON(http.StatusOK, gin.H{
		"url": url,
		"key": subdir + "/" + name,
	})
}

// =============================================================================
// Chunked video upload — three-step protocol
//
// init   POST /api/me/uploads/video/init
//        body: { "filename": "reel.mp4", "totalChunks": 12, "totalSize": 23456789 }
//        resp: { "uploadId": "<hex>", "chunkSize": 2097152 }
//
// chunk  POST /api/me/uploads/video/chunk
//        multipart form:
//          uploadId    text  the id from /init
//          chunkIndex  text  0-based integer
//          data        file  the chunk bytes
//        resp: { "ok": true }
//
// stitch POST /api/me/uploads/video/complete
//        body: { "uploadId": "<hex>", "filename": "reel.mp4" }
//        resp: { "url": "/uploads/videos/<random>.mp4" }
//
// Why we ship this instead of the single-shot UploadVideo for reels:
//   * Cellular drops only lose one chunk → client retries that chunk
//     instead of restarting the whole upload.
//   * Real progress (chunksUploaded / totalChunks) → users see a moving
//     progress bar instead of a forever-spinner.
//   * Sidesteps proxy / nginx body-size limits that bite single-request
//     >50 MB uploads in production.
//
// Restart-on-fail by default — no chunk-status endpoint yet, so killing
// the app mid-upload loses progress. A future "GET .../status" can opt
// into true resumable. The `.tmp/<uploadId>/` directory is the only
// state.
// =============================================================================

// Default per-chunk size advertised back to the client. 2 MB hits the
// sweet spot — small enough that retries are cheap on bad networks, big
// enough that a 100 MB reel only takes ~50 chunks.
const defaultChunkBytes = 2 * 1024 * 1024

// staleChunkTTL — chunk dirs older than this on /init are swept. The
// catch-all is per-init not per-cron because we want zero infra; a busy
// app calls init often enough that nothing rots.
const staleChunkTTL = 24 * time.Hour

// initVideoChunkBody — request shape for /video/init.
type initVideoChunkBody struct {
	Filename    string `json:"filename"`
	TotalChunks int    `json:"totalChunks"`
	TotalSize   int64  `json:"totalSize"`
}

// completeVideoChunkBody — request shape for /video/complete.
type completeVideoChunkBody struct {
	UploadID string `json:"uploadId"`
	Filename string `json:"filename"`
}

// InitVideoChunkUpload — POST /api/me/uploads/video/init
//
// Validates the upload's stated size + extension, mints an uploadId,
// creates the staging directory, and returns the chunk size the client
// should slice with. Also opportunistically sweeps stale staging dirs.
func (h *UploadHandler) InitVideoChunkUpload(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	var body initVideoChunkBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.TotalChunks <= 0 || body.TotalChunks > 10000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "totalChunks out of range"})
		return
	}
	if body.TotalSize <= 0 || body.TotalSize > maxVideoBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"error": fmt.Sprintf("file is too large (max %d MB)", maxVideoBytes/1024/1024),
		})
		return
	}
	ext := strings.ToLower(filepath.Ext(body.Filename))
	if !videoExts[ext] {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "unsupported file type: " + ext,
		})
		return
	}

	// Sweep stale staging dirs from previous failed uploads. Cheap walk —
	// only touches `.tmp/`, never recurses into chunk files.
	h.sweepStaleChunks()

	// Mint a 16-byte hex uploadId. Same namespace size as final filenames.
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "rand failed"})
		return
	}
	uploadID := hex.EncodeToString(buf)
	if err := os.MkdirAll(h.chunkDir(uploadID), 0o755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create staging dir"})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"uploadId":  uploadID,
		"chunkSize": defaultChunkBytes,
	})
}

// UploadVideoChunk — POST /api/me/uploads/video/chunk
//
// Stores one chunk under `.tmp/<uploadId>/<index>.bin`. Idempotent on
// the chunk index — the same chunk can be retried after a network error
// without leaving phantom data. Returns 400 if the uploadId doesn't
// exist (probably already completed or swept).
func (h *UploadHandler) UploadVideoChunk(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	// Hard cap — one chunk should never exceed the negotiated chunk
	// size + a small slack for multipart framing. 4 MB is more than
	// enough at our 2 MB defaultChunkBytes.
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, 4*1024*1024)

	uploadID := strings.TrimSpace(c.PostForm("uploadId"))
	indexStr := strings.TrimSpace(c.PostForm("chunkIndex"))
	if uploadID == "" || indexStr == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "uploadId and chunkIndex required"})
		return
	}
	if !isHexID(uploadID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid uploadId"})
		return
	}
	index, err := strconv.Atoi(indexStr)
	if err != nil || index < 0 || index > 10000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid chunkIndex"})
		return
	}
	dir := h.chunkDir(uploadID)
	if st, err := os.Stat(dir); err != nil || !st.IsDir() {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unknown uploadId"})
		return
	}

	fileHeader, err := c.FormFile("data")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "expected multipart field 'data'"})
		return
	}
	src, err := fileHeader.Open()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not read chunk"})
		return
	}
	defer src.Close()

	// Atomic rename pattern — write to <index>.bin.part, then rename.
	// If the request dies mid-write, the .part file is left behind and
	// gets swept on the next /init. The chunk file proper either
	// exists fully or doesn't exist.
	tmpPath := filepath.Join(dir, fmt.Sprintf("%d.bin.part", index))
	finalPath := filepath.Join(dir, fmt.Sprintf("%d.bin", index))

	dst, err := os.Create(tmpPath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not write chunk"})
		return
	}
	if _, err := io.Copy(dst, src); err != nil {
		dst.Close()
		_ = os.Remove(tmpPath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "write failed: " + err.Error()})
		return
	}
	if err := dst.Close(); err != nil {
		_ = os.Remove(tmpPath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "close failed: " + err.Error()})
		return
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "rename failed: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// CompleteVideoChunkUpload — POST /api/me/uploads/video/complete
//
// Stitches every chunk under `.tmp/<uploadId>/` in index order into a
// single file at `<root>/videos/<random>.<ext>` and returns the public
// URL. Deletes the staging dir on success. Validates that chunks are
// contiguous starting from 0 — gaps mean an upload that's not actually
// finished.
func (h *UploadHandler) CompleteVideoChunkUpload(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	var body completeVideoChunkBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if !isHexID(body.UploadID) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid uploadId"})
		return
	}
	ext := strings.ToLower(filepath.Ext(body.Filename))
	if !videoExts[ext] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported file type: " + ext})
		return
	}

	dir := h.chunkDir(body.UploadID)
	entries, err := os.ReadDir(dir)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unknown uploadId"})
		return
	}

	// Collect <int>.bin entries, sort by index, sanity-check contiguity.
	indexes := make([]int, 0, len(entries))
	for _, e := range entries {
		n := e.Name()
		if !strings.HasSuffix(n, ".bin") {
			continue
		}
		idx, err := strconv.Atoi(strings.TrimSuffix(n, ".bin"))
		if err != nil {
			continue
		}
		indexes = append(indexes, idx)
	}
	sort.Ints(indexes)
	for i, idx := range indexes {
		if idx != i {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": fmt.Sprintf("missing chunk %d (gap before idx=%d)", i, idx),
			})
			return
		}
	}
	if len(indexes) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no chunks uploaded"})
		return
	}

	// Mint the final filename. Same scheme as single-shot uploads so
	// downstream code (resolveUrl, video_player) doesn't care which path
	// produced the file.
	buf := make([]byte, 16)
	if _, err := rand.Read(buf); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "rand failed"})
		return
	}
	name := hex.EncodeToString(buf) + ext
	dstPath := filepath.Join(h.Root, "videos", name)
	dst, err := os.Create(dstPath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "could not create output"})
		return
	}
	for _, idx := range indexes {
		chunkPath := filepath.Join(dir, fmt.Sprintf("%d.bin", idx))
		src, err := os.Open(chunkPath)
		if err != nil {
			dst.Close()
			_ = os.Remove(dstPath)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": fmt.Sprintf("open chunk %d failed: %s", idx, err.Error()),
			})
			return
		}
		if _, err := io.Copy(dst, src); err != nil {
			src.Close()
			dst.Close()
			_ = os.Remove(dstPath)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": fmt.Sprintf("stitch chunk %d failed: %s", idx, err.Error()),
			})
			return
		}
		src.Close()
	}
	if err := dst.Close(); err != nil {
		_ = os.Remove(dstPath)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "close failed: " + err.Error()})
		return
	}

	// Best-effort staging cleanup. A leftover dir would only waste disk;
	// the next /init's sweep would catch it eventually.
	_ = os.RemoveAll(dir)

	// Disk-mode happy path — file is already at its final location and
	// the static mount will serve it.
	if h.S3 == nil {
		c.JSON(http.StatusOK, gin.H{
			"url": h.PublicBase + "/videos/" + name,
			"key": "videos/" + name,
		})
		return
	}

	// S3 mode — push the stitched file up, then delete the local copy
	// (we keep the same `.../videos/<random>.mp4` naming so the key in
	// S3 matches what disk-mode would have produced, and the post-row
	// key column doesn't need to know which path produced the file).
	stitched, err := os.Open(dstPath)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "reopen stitched: " + err.Error()})
		return
	}
	defer stitched.Close()
	key := "videos/" + name
	contentType := mime.TypeByExtension(ext)
	if contentType == "" {
		contentType = "video/mp4"
	}
	if err := h.S3.Upload(c.Request.Context(), key, contentType, stitched); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "s3 upload: " + err.Error()})
		return
	}
	stitched.Close()
	// Local stitched file is redundant once it's in S3.
	_ = os.Remove(dstPath)
	url, err := h.S3.PresignGet(c.Request.Context(), key)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "presign: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url, "key": key})
}

// chunkDir returns the staging path for a given uploadId.
func (h *UploadHandler) chunkDir(uploadID string) string {
	return filepath.Join(h.Root, ".tmp", uploadID)
}

// sweepStaleChunks removes any `.tmp/<uploadId>/` whose mtime is older
// than [staleChunkTTL]. Best-effort — errors are swallowed because a
// failed sweep just delays cleanup, never breaks an upload.
func (h *UploadHandler) sweepStaleChunks() {
	root := filepath.Join(h.Root, ".tmp")
	entries, err := os.ReadDir(root)
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-staleChunkTTL)
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(cutoff) {
			_ = os.RemoveAll(filepath.Join(root, e.Name()))
		}
	}
}

// isHexID validates that a string is non-empty hex of plausible length —
// guards against `..`, slashes, etc. so caller-supplied uploadIds can be
// joined into a path safely.
func isHexID(s string) bool {
	if s == "" || len(s) > 64 {
		return false
	}
	for _, r := range s {
		if !(r >= '0' && r <= '9') && !(r >= 'a' && r <= 'f') && !(r >= 'A' && r <= 'F') {
			return false
		}
	}
	return true
}

// =============================================================================
// Direct-to-S3 multipart upload — Phase A
//
// The client uploads bytes directly to S3 (not through this backend), with
// the backend acting only as the auth + orchestration layer. The flow:
//
//   POST .../multipart/init
//        body  { filename, totalSize }
//        resp  { uploadId, key, partSize, parts: [{partNumber, url}, ...] }
//   PUT  <each presigned URL> — direct to S3, with the part's bytes
//        →  S3 responds with an ETag header per part (client captures it)
//   POST .../multipart/complete
//        body  { uploadId, key, parts: [{partNumber, etag}, ...] }
//        resp  { url, key }
//   POST .../multipart/abort  (on cancel)
//        body  { uploadId, key }
//
// S3 minimum part size is 5 MiB except the last part; the client SHOULD
// upload parts in order but [CompleteMultipartUpload] sorts by partNumber
// so order tolerance is built in.
//
// Disabled gracefully when S3 isn't configured — returns 503 instead of
// trying to fall back to disk, because the disk fallback only makes
// sense for the bytes-through-backend flow.
// =============================================================================

// S3 multipart constraints we honor:
const (
	// 10 MiB part size — sweet spot for the 1 GB–5 GB range. 5 MiB
	// (S3's minimum) produces too many parts for a 30-minute reel
	// (~500+ round trips); 25 MiB leaves too little parallelism on
	// smaller files. 10 MiB / 5 GiB file ≈ 500 parts, well under the
	// 10 000-part ceiling.
	multipartPartSize int64 = 10 * 1024 * 1024
	multipartMaxParts       = 10_000        // S3 hard limit
	multipartPresignTTL     = 6 * time.Hour // outlasts a 5 GB cellular upload

	// 5 GiB cap on the *direct-to-S3* flow. Plenty for a 30-minute
	// phone video (1080p HDR averages ~2 GB, even iPhone 4K @ 60fps
	// rarely tops 11 GB and gets compressed before upload in practice).
	//
	// CRITICAL: this cap is for the multipart endpoints ONLY — the
	// single-shot and chunked endpoints stream bytes through the
	// backend and stay capped at [maxVideoBytes] (100 MB) so a
	// Railway / similar host can't be OOM'd by a 5 GB POST.
	multipartMaxFileBytes int64 = 5 * 1024 * 1024 * 1024
)

// initMultipartBody — request shape for /multipart/init.
type initMultipartBody struct {
	Filename  string `json:"filename"`
	TotalSize int64  `json:"totalSize"`
}

// initMultipartPart — one entry in the response `parts` array.
type initMultipartPart struct {
	PartNumber int    `json:"partNumber"`
	URL        string `json:"url"`
}

// completeMultipartBody — request shape for /multipart/complete.
// `Parts` must contain one entry per uploaded part with the ETag the
// client captured from each S3 PUT's response headers.
type completeMultipartBody struct {
	UploadID string                   `json:"uploadId"`
	Key      string                   `json:"key"`
	Parts    []services.CompletedPart `json:"parts"`
}

// abortMultipartBody — request shape for /multipart/abort.
type abortMultipartBody struct {
	UploadID string `json:"uploadId"`
	Key      string `json:"key"`
}

// InitMultipartUpload — POST /api/me/uploads/video/multipart/init
//
// Validates the desired upload, creates the S3 multipart upload, and
// returns a list of pre-signed PUT URLs the client should hit (one per
// part). The backend never sees the actual bytes.
func (h *UploadHandler) InitMultipartUpload(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if h.S3 == nil {
		// Direct-to-S3 makes no sense without S3 configured. Surface a
		// clean 503 so the client can fall back to the chunked flow.
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "s3 not configured"})
		return
	}

	var body initMultipartBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.TotalSize <= 0 || body.TotalSize > multipartMaxFileBytes {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{
			"error": fmt.Sprintf("file is too large (max %d MB)", multipartMaxFileBytes/1024/1024),
		})
		return
	}
	ext := strings.ToLower(filepath.Ext(body.Filename))
	if !videoExts[ext] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "unsupported file type: " + ext})
		return
	}

	// Sanity-check the resulting part count fits S3's 10k limit.
	numParts := int((body.TotalSize + multipartPartSize - 1) / multipartPartSize)
	if numParts < 1 {
		numParts = 1
	}
	if numParts > multipartMaxParts {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": fmt.Sprintf("file would require %d parts (max %d)", numParts, multipartMaxParts),
		})
		return
	}

	// Mint the final S3 key now so the client can be told what it'll be
	// — saves a round-trip on /complete and lets the client store the
	// key alongside its local upload-state for resume in Phase C.
	randBytes := make([]byte, 16)
	if _, err := rand.Read(randBytes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "rand failed"})
		return
	}
	key := "videos/" + hex.EncodeToString(randBytes) + ext

	contentType := mime.TypeByExtension(ext)
	if contentType == "" {
		contentType = "video/mp4"
	}
	ctx := c.Request.Context()
	uploadID, err := h.S3.CreateMultipart(ctx, key, contentType)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "s3 create multipart: " + err.Error()})
		return
	}

	parts := make([]initMultipartPart, 0, numParts)
	for i := 1; i <= numParts; i++ {
		url, err := h.S3.PresignUploadPart(ctx, key, uploadID, int32(i), multipartPresignTTL)
		if err != nil {
			// Best-effort abort so the partial upload doesn't sit around
			// racking up storage (S3 charges for parts even before
			// /complete is called).
			_ = h.S3.AbortMultipart(ctx, key, uploadID)
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": fmt.Sprintf("presign part %d: %s", i, err.Error()),
			})
			return
		}
		parts = append(parts, initMultipartPart{PartNumber: i, URL: url})
	}

	c.JSON(http.StatusOK, gin.H{
		"uploadId": uploadID,
		"key":      key,
		"partSize": multipartPartSize,
		"parts":    parts,
	})
}

// CompleteMultipartUpload — POST /api/me/uploads/video/multipart/complete
//
// Tells S3 to assemble the uploaded parts into the final object. The
// client must include every part's ETag (as returned in each S3 PUT's
// response headers). Returns the same { url, key } shape the existing
// upload endpoints return so the post-create code stays unchanged.
func (h *UploadHandler) CompleteMultipartUpload(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if h.S3 == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "s3 not configured"})
		return
	}

	var body completeMultipartBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.UploadID == "" || body.Key == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "uploadId and key required"})
		return
	}
	if len(body.Parts) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "parts required"})
		return
	}
	// Keys are server-minted in /init and only ever match `videos/<hex>.<ext>`.
	// Reject anything outside that namespace so a misbehaving client
	// can't trick us into completing arbitrary keys.
	if !strings.HasPrefix(body.Key, "videos/") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "key must live under videos/"})
		return
	}

	ctx := c.Request.Context()
	if err := h.S3.CompleteMultipart(ctx, body.Key, body.UploadID, body.Parts); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "s3 complete: " + err.Error()})
		return
	}
	url, err := h.S3.PresignGet(ctx, body.Key)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "presign: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"url": url, "key": body.Key})
}

// AbortMultipartUpload — POST /api/me/uploads/video/multipart/abort
//
// Releases the already-uploaded parts so S3 stops charging for them.
// Idempotent on S3's side — calling abort twice doesn't error.
func (h *UploadHandler) AbortMultipartUpload(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if h.S3 == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "s3 not configured"})
		return
	}
	var body abortMultipartBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.UploadID == "" || body.Key == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "uploadId and key required"})
		return
	}
	if !strings.HasPrefix(body.Key, "videos/") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "key must live under videos/"})
		return
	}
	if err := h.S3.AbortMultipart(c.Request.Context(), body.Key, body.UploadID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "s3 abort: " + err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{})
}
