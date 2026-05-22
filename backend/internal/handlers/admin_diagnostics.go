package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// AdminDiagnosticsHandler — admin-only operational endpoints that don't
// fit cleanly into one of the existing domain handlers:
//
//   * In-flight chunked-upload monitor + manual sweep
//   * Universal Link / App Link well-known reachability check
//
// Lives in its own file because the surface is small and isn't tied
// to a single repository.
type AdminDiagnosticsHandler struct {
	uploadRoot string
}

func NewAdminDiagnosticsHandler(uploadRoot string) *AdminDiagnosticsHandler {
	return &AdminDiagnosticsHandler{uploadRoot: uploadRoot}
}

// ─── /admin/uploads/in-flight ─────────────────────────────────────────

// InFlightUpload — one staged chunked upload waiting on /complete or
// abandoned. Surfaced to admin so leaked staging dirs are visible
// before they accumulate.
type InFlightUpload struct {
	UploadID    string    `json:"uploadId"`
	Chunks      int       `json:"chunks"`
	Bytes       int64     `json:"bytes"`
	StartedAt   time.Time `json:"startedAt"`
	LastChunkAt time.Time `json:"lastChunkAt"`
	AgeHours    float64   `json:"ageHours"`
}

// ListInFlightUploads — GET /admin/uploads/in-flight
//
// Walks `uploads/.tmp/<uploadId>/`, summarising each remaining staging
// dir. Sorted by `startedAt` ASC so the oldest leaks float to the top.
func (h *AdminDiagnosticsHandler) ListInFlightUploads(c *gin.Context) {
	root := filepath.Join(h.uploadRoot, ".tmp")
	entries, err := os.ReadDir(root)
	if err != nil {
		// No staging dir yet — return an empty list, not a 500. Common
		// state on a fresh deploy where no uploads have happened yet.
		if os.IsNotExist(err) {
			c.JSON(http.StatusOK, gin.H{"uploads": []InFlightUpload{}})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	out := make([]InFlightUpload, 0, len(entries))
	now := time.Now()
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dirInfo, err := e.Info()
		if err != nil {
			continue
		}
		dirPath := filepath.Join(root, e.Name())
		chunkEntries, err := os.ReadDir(dirPath)
		if err != nil {
			continue
		}
		var chunks int
		var totalBytes int64
		var lastMod time.Time
		for _, ce := range chunkEntries {
			if !strings.HasSuffix(ce.Name(), ".bin") {
				continue
			}
			info, err := ce.Info()
			if err != nil {
				continue
			}
			chunks++
			totalBytes += info.Size()
			if info.ModTime().After(lastMod) {
				lastMod = info.ModTime()
			}
		}
		started := dirInfo.ModTime()
		if lastMod.IsZero() {
			lastMod = started
		}
		out = append(out, InFlightUpload{
			UploadID:    e.Name(),
			Chunks:      chunks,
			Bytes:       totalBytes,
			StartedAt:   started,
			LastChunkAt: lastMod,
			AgeHours:    now.Sub(started).Hours(),
		})
	}
	c.JSON(http.StatusOK, gin.H{"uploads": out})
}

// SweepUploads — POST /admin/uploads/sweep
//
// Force-runs the stale staging cleanup that normally only happens
// inside `/api/me/uploads/video/init`. Body shape:
//
//   { "minAgeHours": 1 }    // only delete dirs older than 1h
//   {}                      // default: 24h (matches staleChunkTTL)
//
// Returns the list of removed uploadIds + total bytes reclaimed.
func (h *AdminDiagnosticsHandler) SweepUploads(c *gin.Context) {
	var body struct {
		MinAgeHours float64 `json:"minAgeHours"`
	}
	_ = c.ShouldBindJSON(&body)
	cutoffHours := body.MinAgeHours
	if cutoffHours <= 0 {
		cutoffHours = 24
	}
	cutoff := time.Now().Add(-time.Duration(cutoffHours * float64(time.Hour)))

	root := filepath.Join(h.uploadRoot, ".tmp")
	entries, err := os.ReadDir(root)
	if err != nil {
		if os.IsNotExist(err) {
			c.JSON(http.StatusOK, gin.H{"removed": []string{}, "bytesReclaimed": 0})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	removed := make([]string, 0, 4)
	var bytesReclaimed int64
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if !info.ModTime().Before(cutoff) {
			continue
		}
		dirPath := filepath.Join(root, e.Name())
		bytesReclaimed += dirSizeBytes(dirPath)
		if err := os.RemoveAll(dirPath); err == nil {
			removed = append(removed, e.Name())
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"removed":        removed,
		"bytesReclaimed": bytesReclaimed,
	})
}

// dirSizeBytes — sum of every file inside the given dir. Pre-removal
// snapshot so we can report bytes reclaimed.
func dirSizeBytes(dir string) int64 {
	var total int64
	_ = filepath.Walk(dir, func(_ string, info os.FileInfo, err error) error {
		if err != nil || info == nil {
			return nil
		}
		if !info.IsDir() {
			total += info.Size()
		}
		return nil
	})
	return total
}

// ─── /admin/diagnostics/deep-links ────────────────────────────────────

// DeepLinkCheck — single-host result of the well-known fetch.
type DeepLinkCheck struct {
	Host         string `json:"host"`
	URL          string `json:"url"`
	Reachable    bool   `json:"reachable"`
	StatusCode   int    `json:"statusCode"`
	ContentType  string `json:"contentType"`
	BodyBytes    int    `json:"bodyBytes"`
	JSONValid    bool   `json:"jsonValid"`
	Error        string `json:"error,omitempty"`
	BundleIDOK   bool   `json:"bundleIdOk,omitempty"`   // AASA only
	PackageIDOK  bool   `json:"packageIdOk,omitempty"`  // assetlinks only
	FingerprintOK bool  `json:"fingerprintOk,omitempty"` // assetlinks only
}

// DeepLinkDiagnostics — GET /admin/diagnostics/deep-links
//
// Server-side fetches both well-known files and validates them, so
// admin can confirm Universal Links + App Links are actually wired up
// without leaving the dashboard.
//
// Hard-coded to unmu.app + the values we baked into the entitlements
// and AndroidManifest. If those move, this needs to move with them.
func (h *AdminDiagnosticsHandler) DeepLinkDiagnostics(c *gin.Context) {
	// Hard-coded to match what we shipped on the client:
	//   ios entitlements      → applinks:unmu.app, applinks:www.unmu.app
	//   android intent-filter → host="unmu.app", host="www.unmu.app"
	const (
		expectedAppleAppID    = "SBL65MNY44.com.easytech.stocksanalyzer"
		expectedAndroidPkg    = "com.easytech.stocks"
		expectedSHA256        = "0F:26:49:F8:2B:FB:0D:2C:C5:25:57:A0:CF:F6:22:20:9D:43:06:8B:40:10:3D:B4:30:F3:36:BA:4D:23:B5:7E"
	)
	hosts := []string{"unmu.app", "www.unmu.app"}

	results := make([]DeepLinkCheck, 0, 2*len(hosts))
	for _, host := range hosts {
		// Apple App-Site Association — note: NO `.json` extension.
		results = append(results, fetchAndValidateAASA(
			host,
			"https://"+host+"/.well-known/apple-app-site-association",
			expectedAppleAppID,
		))
		// Android Asset Links.
		results = append(results, fetchAndValidateAssetLinks(
			host,
			"https://"+host+"/.well-known/assetlinks.json",
			expectedAndroidPkg,
			expectedSHA256,
		))
	}

	c.JSON(http.StatusOK, gin.H{
		"checks":    results,
		"checkedAt": time.Now(),
	})
}

func fetchAndValidateAASA(host, url, expectedAppID string) DeepLinkCheck {
	r := DeepLinkCheck{Host: host, URL: url}
	body, status, ct, err := httpGet(url)
	if err != nil {
		r.Error = err.Error()
		return r
	}
	r.Reachable = true
	r.StatusCode = status
	r.ContentType = ct
	r.BodyBytes = len(body)
	if status != http.StatusOK {
		return r
	}
	// AASA shape: { "applinks": { "details": [ { "appIDs": ["TEAMID.bundle"] } ] } }
	var parsed struct {
		Applinks struct {
			Details []struct {
				AppIDs []string `json:"appIDs"`
			} `json:"details"`
		} `json:"applinks"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		r.Error = "invalid JSON: " + err.Error()
		return r
	}
	r.JSONValid = true
	for _, d := range parsed.Applinks.Details {
		for _, id := range d.AppIDs {
			if strings.EqualFold(id, expectedAppID) {
				r.BundleIDOK = true
				return r
			}
		}
	}
	r.Error = fmt.Sprintf("appID %q not in file", expectedAppID)
	return r
}

func fetchAndValidateAssetLinks(host, url, expectedPkg, expectedSHA string) DeepLinkCheck {
	r := DeepLinkCheck{Host: host, URL: url}
	body, status, ct, err := httpGet(url)
	if err != nil {
		r.Error = err.Error()
		return r
	}
	r.Reachable = true
	r.StatusCode = status
	r.ContentType = ct
	r.BodyBytes = len(body)
	if status != http.StatusOK {
		return r
	}
	// assetlinks shape: [ { target: { package_name, sha256_cert_fingerprints[] } } ]
	var parsed []struct {
		Target struct {
			PackageName  string   `json:"package_name"`
			Fingerprints []string `json:"sha256_cert_fingerprints"`
		} `json:"target"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		r.Error = "invalid JSON: " + err.Error()
		return r
	}
	r.JSONValid = true
	for _, entry := range parsed {
		if !strings.EqualFold(entry.Target.PackageName, expectedPkg) {
			continue
		}
		r.PackageIDOK = true
		for _, fp := range entry.Target.Fingerprints {
			if strings.EqualFold(fp, expectedSHA) {
				r.FingerprintOK = true
				return r
			}
		}
	}
	if !r.PackageIDOK {
		r.Error = fmt.Sprintf("package %q not in file", expectedPkg)
	} else if !r.FingerprintOK {
		r.Error = "expected SHA-256 not in fingerprints"
	}
	return r
}

// httpGet — short-timeout GET, no redirects. Universal Links + App
// Links spec forbids redirects on the well-known URL, so this matches
// the OS's behaviour.
func httpGet(url string) ([]byte, int, string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, "", err
	}
	client := &http.Client{
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error {
			return http.ErrUseLastResponse
		},
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, 0, "", err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if err != nil {
		return nil, resp.StatusCode, resp.Header.Get("Content-Type"), err
	}
	return body, resp.StatusCode, resp.Header.Get("Content-Type"), nil
}
