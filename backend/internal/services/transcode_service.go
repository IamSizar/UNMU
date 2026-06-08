package services

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path"
	"strconv"
	"strings"
	"time"

	"halalstocks/internal/repositories"
)

// transcodeRungs are the quality ladders we generate, highest first. A
// rung is only produced when it's STRICTLY below the source height (no
// upscaling) — the original is always available as "Auto", so for a 1080p
// upload we emit 720p + 480p, for a 4K upload 1080p + 720p + 480p, etc.
var transcodeRungs = []int{1080, 720, 480}

const (
	transcodeSweepEvery = 30 * time.Second
	transcodeProbeTTL   = 60 * time.Second
	transcodeEncodeTTL  = 30 * time.Minute
	transcodeFetchTTL   = 20 * time.Minute
	// A variant whose duration is more than this much shorter than the
	// source is treated as a truncated (failed) encode. The old worker fed
	// ffmpeg the S3 URL directly; a dropped HTTP read mid-encode produced a
	// short file that still exited 0, so 6-second "720p" copies of 59-second
	// videos were silently accepted. We now download first and verify length.
	transcodeDurationSlackSec = 2.0
)

// Transcoder is the background worker behind the in-app video quality
// gear. On a timer it sweeps for video/reel posts that still lack quality
// variants, then transcodes each into the lower MP4 rungs (via the local
// ffmpeg binary) and uploads them to S3 next to the original.
//
// It is intentionally best-effort: if ffmpeg/ffprobe aren't installed, or
// S3 isn't configured, the worker simply never starts and every video
// keeps playing from its single original file — exactly today's behavior.
type Transcoder struct {
	repo    *repositories.TranscodeRepository
	s3      *S3Storage
	ffmpeg  string
	ffprobe string
}

func NewTranscoder(repo *repositories.TranscodeRepository, s3 *S3Storage) *Transcoder {
	ffmpeg, _ := exec.LookPath("ffmpeg")
	ffprobe, _ := exec.LookPath("ffprobe")
	return &Transcoder{repo: repo, s3: s3, ffmpeg: ffmpeg, ffprobe: ffprobe}
}

// Available reports whether all prerequisites are present.
func (t *Transcoder) Available() bool {
	return t != nil && t.s3 != nil && t.ffmpeg != "" && t.ffprobe != ""
}

// Start kicks off the sweep loop in a goroutine. No-op (with a log line)
// when prerequisites are missing, so the rest of the app is unaffected.
func (t *Transcoder) Start(ctx context.Context) {
	if !t.Available() {
		log.Printf("[transcode] disabled (s3=%v ffmpeg=%q ffprobe=%q) — videos play single-quality",
			t.s3 != nil, t.ffmpeg, t.ffprobe)
		return
	}
	log.Printf("[transcode] worker started (ffmpeg=%s)", t.ffmpeg)
	go t.loop(ctx)
}

func (t *Transcoder) loop(ctx context.Context) {
	tick := time.NewTicker(transcodeSweepEvery)
	defer tick.Stop()
	for {
		t.sweep(ctx)
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}

// sweep enqueues any missing posts, then drains the queue one job at a
// time (sequential on purpose — transcoding is CPU-heavy and we don't want
// to peg every core on a shared box).
func (t *Transcoder) sweep(ctx context.Context) {
	if err := t.repo.EnqueueMissing(); err != nil {
		log.Printf("[transcode] enqueue: %v", err)
		return
	}
	for {
		if ctx.Err() != nil {
			return
		}
		job, err := t.repo.ClaimNext()
		if err != nil {
			log.Printf("[transcode] claim: %v", err)
			return
		}
		if job == nil {
			return // queue drained
		}
		if err := t.process(ctx, job); err != nil {
			log.Printf("[transcode] post %d failed (attempt %d): %v",
				job.PostID, job.Attempts, err)
			_ = t.repo.MarkFailed(job.PostID, err.Error())
		}
	}
}

// process transcodes one post's source into every applicable rung and
// records the resulting S3 keys on the post.
func (t *Transcoder) process(ctx context.Context, job *repositories.TranscodeJob) error {
	key := t.s3.KeyFromValue(job.SourceURL)
	if key == "" {
		return fmt.Errorf("could not derive s3 key from %q", job.SourceURL)
	}
	srcURL, err := t.s3.PresignGet(ctx, key)
	if err != nil {
		return fmt.Errorf("presign source: %w", err)
	}

	// Derive sibling keys, e.g. videos/<rand>.mp4 -> videos/<rand>_720p.mp4
	dir := path.Dir(key)
	base := strings.TrimSuffix(path.Base(key), path.Ext(key))

	tmp, err := os.MkdirTemp("", "unmu-transcode-*")
	if err != nil {
		return fmt.Errorf("tempdir: %w", err)
	}
	defer os.RemoveAll(tmp)

	// Download the source to local disk FIRST, then transcode from the file.
	// Streaming the S3 URL straight into ffmpeg meant a dropped HTTP read
	// mid-encode produced a silently-truncated output (ffmpeg treats early
	// EOF as end-of-stream and exits 0). A local file can't truncate
	// mid-read, and download() verifies the full byte count.
	srcPath := path.Join(tmp, "source"+path.Ext(key))
	if err := t.download(ctx, srcURL, srcPath); err != nil {
		return fmt.Errorf("download source: %w", err)
	}

	height, err := t.probeHeight(ctx, srcPath)
	if err != nil {
		return fmt.Errorf("probe height: %w", err)
	}
	srcDur, err := t.probeDuration(ctx, srcPath)
	if err != nil {
		return fmt.Errorf("probe duration: %w", err)
	}

	variants := map[string]string{}
	for _, h := range transcodeRungs {
		if h >= height {
			continue // no upscaling; "Auto" (the original) already covers it
		}
		outPath := path.Join(tmp, fmt.Sprintf("%dp.mp4", h))
		if err := t.encode(ctx, srcPath, outPath, h); err != nil {
			return fmt.Errorf("encode %dp: %w", h, err)
		}
		// Reject a truncated encode before it can be recorded. Returning an
		// error marks the job failed so it retries, instead of shipping a
		// broken variant the client would have to detect and skip.
		outDur, err := t.probeDuration(ctx, outPath)
		if err != nil {
			return fmt.Errorf("probe %dp output: %w", h, err)
		}
		if srcDur > 0 && outDur < srcDur-transcodeDurationSlackSec {
			return fmt.Errorf("%dp encode truncated: %.1fs of %.1fs source",
				h, outDur, srcDur)
		}
		variantKey := dir + "/" + base + "_" + strconv.Itoa(h) + "p.mp4"
		f, err := os.Open(outPath)
		if err != nil {
			return fmt.Errorf("open %dp output: %w", h, err)
		}
		upErr := t.s3.Upload(ctx, variantKey, "video/mp4", f)
		_ = f.Close()
		if upErr != nil {
			return fmt.Errorf("upload %dp: %w", h, upErr)
		}
		variants[strconv.Itoa(h)+"p"] = variantKey
	}

	// Empty map (source too small for any lower rung) is still recorded so
	// the post leaves the enqueue set and we don't retry it forever.
	if err := t.repo.MarkDone(job.PostID, variants); err != nil {
		return fmt.Errorf("mark done: %w", err)
	}
	log.Printf("[transcode] post %d done: %d variant(s)", job.PostID, len(variants))
	return nil
}

// probeHeight returns the source video's pixel height via ffprobe.
func (t *Transcoder) probeHeight(ctx context.Context, url string) (int, error) {
	c, cancel := context.WithTimeout(ctx, transcodeProbeTTL)
	defer cancel()
	out, err := exec.CommandContext(c, t.ffprobe,
		"-v", "error",
		"-select_streams", "v:0",
		"-show_entries", "stream=height",
		"-of", "csv=p=0",
		url,
	).Output()
	if err != nil {
		return 0, err
	}
	s := strings.TrimSpace(string(out))
	if i := strings.IndexAny(s, "\r\n,"); i >= 0 {
		s = s[:i]
	}
	h, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil {
		return 0, fmt.Errorf("unexpected ffprobe output %q", string(out))
	}
	return h, nil
}

// encode runs ffmpeg to produce one H.264/AAC MP4 scaled to `height`
// (width auto, kept even via scale=-2) from a LOCAL source file. +faststart
// moves the moov atom to the front so the file starts playing before it's
// fully downloaded.
func (t *Transcoder) encode(ctx context.Context, srcPath, outPath string, height int) error {
	c, cancel := context.WithTimeout(ctx, transcodeEncodeTTL)
	defer cancel()
	cmd := exec.CommandContext(c, t.ffmpeg,
		"-y",
		"-i", srcPath,
		"-vf", fmt.Sprintf("scale=-2:%d", height),
		"-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
		"-c:a", "aac", "-b:a", "128k",
		"-movflags", "+faststart",
		outPath,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("%v: %s", err, truncate(string(out), 400))
	}
	return nil
}

// download fetches `url` to local `dest`, failing on a short read — the exact
// failure mode (a partial source) that the old direct-to-ffmpeg path silently
// tolerated. A complete local copy is the precondition for a non-truncated
// encode.
func (t *Transcoder) download(ctx context.Context, url, dest string) error {
	c, cancel := context.WithTimeout(ctx, transcodeFetchTTL)
	defer cancel()
	req, err := http.NewRequestWithContext(c, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("source GET %d", resp.StatusCode)
	}
	f, err := os.Create(dest)
	if err != nil {
		return err
	}
	n, copyErr := io.Copy(f, resp.Body)
	closeErr := f.Close()
	if copyErr != nil {
		return fmt.Errorf("copy: %w", copyErr)
	}
	if closeErr != nil {
		return closeErr
	}
	if resp.ContentLength > 0 && n != resp.ContentLength {
		return fmt.Errorf("short download: %d of %d bytes", n, resp.ContentLength)
	}
	return nil
}

// probeDuration returns the media's duration in seconds via ffprobe.
func (t *Transcoder) probeDuration(ctx context.Context, pathOrURL string) (float64, error) {
	c, cancel := context.WithTimeout(ctx, transcodeProbeTTL)
	defer cancel()
	out, err := exec.CommandContext(c, t.ffprobe,
		"-v", "error",
		"-show_entries", "format=duration",
		"-of", "csv=p=0",
		pathOrURL,
	).Output()
	if err != nil {
		return 0, err
	}
	s := strings.TrimSpace(string(out))
	d, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, fmt.Errorf("unexpected ffprobe duration %q", string(out))
	}
	return d, nil
}

func truncate(s string, n int) string {
	s = strings.TrimSpace(s)
	if len(s) <= n {
		return s
	}
	return s[len(s)-n:] // tail — ffmpeg's actual error is at the end
}
