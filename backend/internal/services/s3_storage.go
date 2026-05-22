package services

import (
	"context"
	"fmt"
	"io"
	"net/url"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// S3Storage wraps the AWS S3 client used by the upload handler.
//
// The bucket lives in me-central-1 (UAE) with Block Public Access ON, so
// objects are never directly fetchable — every read goes through a
// pre-signed GET URL minted by [PresignGet]. Uploads use the transfer
// manager which transparently splits files above 5 MB into multipart
// uploads, giving reels (50–100 MB mp4s) reliable transport even on
// flaky cellular connections.
//
// The "fallback to local disk when AWSS3Bucket is empty" decision lives
// in the upload handler — this struct only exists when S3 is wired.
type S3Storage struct {
	Bucket          string
	Region          string
	PresignGetTTL   time.Duration
	client          *s3.Client
	presigner       *s3.PresignClient
	uploader        *manager.Uploader
}

// NewS3Storage builds the S3 client from explicit credentials and region.
//
// The handler decides whether to call this at all — the constructor
// returns an error only when AWS rejects the credentials at config time
// (rare; usually surfaces on the first API call instead). Callers should
// treat a non-nil error as a misconfiguration and abort startup, since
// running without S3 after the env says S3 is wanted would silently
// drop uploads to disk.
func NewS3Storage(
	ctx context.Context,
	region, bucket, accessKeyID, secretAccessKey string,
	presignTTL time.Duration,
) (*S3Storage, error) {
	if region == "" || bucket == "" {
		return nil, fmt.Errorf("s3: region and bucket are required")
	}

	// Explicit static credentials beat the default chain here — the
	// chain would also probe IMDS / ~/.aws/credentials, which on a dev
	// machine could surprise-pick the wrong account. The env-based
	// values in .env are the only source of truth for this service.
	creds := credentials.NewStaticCredentialsProvider(accessKeyID, secretAccessKey, "")
	cfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion(region),
		awsconfig.WithCredentialsProvider(creds),
	)
	if err != nil {
		return nil, fmt.Errorf("s3: load aws config: %w", err)
	}

	client := s3.NewFromConfig(cfg)
	return &S3Storage{
		Bucket:        bucket,
		Region:        region,
		PresignGetTTL: presignTTL,
		client:        client,
		presigner:     s3.NewPresignClient(client),
		uploader:      manager.NewUploader(client),
	}, nil
}

// Upload streams body bytes into S3 at the given key.
//
// contentType is forwarded so video_player + Image widgets get the right
// MIME on download (S3 otherwise hands back application/octet-stream,
// which blocks inline playback in some clients).
//
// Multipart upload kicks in automatically for bodies above the default
// 5 MB part size, so reel mp4s don't need any caller-side chunking.
func (s *S3Storage) Upload(
	ctx context.Context,
	key, contentType string,
	body io.Reader,
) error {
	if s == nil {
		return fmt.Errorf("s3: nil storage")
	}
	_, err := s.uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(s.Bucket),
		Key:         aws.String(key),
		Body:        body,
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return fmt.Errorf("s3: put %s: %w", key, err)
	}
	return nil
}

// MediaURL takes a raw DB column value (`media_url`, `cover_url`,
// `attachment_url`, `avatar_url`) and returns a URL the client should
// hit right now. The transformation enables "sign on read" — every time
// the feed/post/message endpoints return data, the URL is signed fresh
// so old posts never expire even though pre-signed S3 URLs are capped at
// a 7-day TTL.
//
// Inputs handled:
//
//   - empty           → empty
//   - "/uploads/..."  → pass-through (disk-mode legacy + dev fallback)
//   - our bucket URL  → extract the key from the path, re-sign with
//                       a fresh signature
//   - other http(s)   → pass-through (CDN, external embeds, etc.)
//   - bare key path   → sign it directly (the format we want new code
//                       to write going forward)
//
// Errors silently fall back to returning the input value so a transient
// signing failure can't blank out an existing post's media reference.
// Callers that need strict behavior should use PresignGet directly.
func (s *S3Storage) MediaURL(value string) string {
	if s == nil || value == "" {
		return value
	}
	// Legacy on-disk pathing — Gin's static handler still serves these.
	if strings.HasPrefix(value, "/uploads/") {
		return value
	}
	// Either form of our bucket URL: virtual-host or path-style.
	bucketHost := s.Bucket + ".s3." + s.Region + ".amazonaws.com"
	pathStyle := "s3." + s.Region + ".amazonaws.com/" + s.Bucket + "/"
	if strings.Contains(value, bucketHost) || strings.Contains(value, pathStyle) {
		u, err := url.Parse(value)
		if err != nil {
			return value
		}
		// Virtual-host style: /key
		// Path style:         /<bucket>/key
		key := strings.TrimPrefix(u.Path, "/")
		key = strings.TrimPrefix(key, s.Bucket+"/")
		if key == "" {
			return value
		}
		signed, err := s.PresignGet(context.Background(), key)
		if err != nil {
			return value
		}
		return signed
	}
	// Any other absolute URL — pass through. Future CDN URLs land here.
	if strings.HasPrefix(value, "http://") || strings.HasPrefix(value, "https://") {
		return value
	}
	// Anything else: treat as a raw S3 key (the post-write canonical
	// form once we stop storing URLs in the DB).
	signed, err := s.PresignGet(context.Background(), value)
	if err != nil {
		return value
	}
	return signed
}

// =============================================================================
// Multipart upload — Phase A direct-to-S3 flow.
//
// The pipeline replaces the old "phone → backend → S3" pattern with one
// where the backend only orchestrates and the bytes go straight from the
// phone to S3:
//
//   1. CreateMultipart           — backend creates the upload, gets an uploadId
//   2. PresignUploadPart × N     — backend mints N pre-signed PUT URLs (one per
//                                  part) and hands them to the client
//   3. Client PUTs each part directly to S3 (no backend involvement at all)
//   4. CompleteMultipart         — backend tells S3 to assemble the parts using
//                                  the ETags the client collected
//
// AbortMultipart cleans up if the client gives up halfway — no orphan parts
// linger in the bucket. S3 also charges for those parts until they're
// either committed (via Complete) or abandoned (via Abort or a bucket
// lifecycle rule), so the client SHOULD call Abort on any cancel path.
// =============================================================================

// CompletedPart mirrors the (partNumber, etag) pair S3 needs to finalize
// a multipart upload. Flutter collects these as it PUTs each part and
// sends them back on /complete.
type CompletedPart struct {
	PartNumber int    `json:"partNumber"`
	ETag       string `json:"etag"`
}

// CreateMultipart kicks off the S3-side upload and returns the uploadId
// the client + every subsequent call must thread through.
func (s *S3Storage) CreateMultipart(
	ctx context.Context, key, contentType string,
) (string, error) {
	if s == nil {
		return "", fmt.Errorf("s3: nil storage")
	}
	out, err := s.client.CreateMultipartUpload(ctx, &s3.CreateMultipartUploadInput{
		Bucket:      aws.String(s.Bucket),
		Key:         aws.String(key),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", fmt.Errorf("s3: create multipart %s: %w", key, err)
	}
	if out.UploadId == nil {
		return "", fmt.Errorf("s3: create multipart %s: no uploadId returned", key)
	}
	return *out.UploadId, nil
}

// PresignUploadPart returns a pre-signed PUT URL for one part. The
// client uploads the part directly to this URL; S3 responds with an
// ETag header that the client must capture and forward to
// [CompleteMultipart].
//
// `ttl` should be long enough to outlast the entire upload — 6 hours is
// safe for a 100 MB video on any cellular network.
func (s *S3Storage) PresignUploadPart(
	ctx context.Context, key, uploadID string, partNumber int32, ttl time.Duration,
) (string, error) {
	if s == nil {
		return "", fmt.Errorf("s3: nil storage")
	}
	req, err := s.presigner.PresignUploadPart(ctx, &s3.UploadPartInput{
		Bucket:     aws.String(s.Bucket),
		Key:        aws.String(key),
		UploadId:   aws.String(uploadID),
		PartNumber: aws.Int32(partNumber),
	}, s3.WithPresignExpires(ttl))
	if err != nil {
		return "", fmt.Errorf("s3: presign part %d for %s: %w", partNumber, key, err)
	}
	return req.URL, nil
}

// CompleteMultipart tells S3 to stitch the uploaded parts into the
// final object. Parts must arrive in [CompletedPart] form (the same
// pair S3 returned in each part's ETag header).
//
// S3 validates the order + etags itself; we return whatever error it
// raises so the handler can surface "part 7 missing" etc. directly.
func (s *S3Storage) CompleteMultipart(
	ctx context.Context, key, uploadID string, parts []CompletedPart,
) error {
	if s == nil {
		return fmt.Errorf("s3: nil storage")
	}
	if len(parts) == 0 {
		return fmt.Errorf("s3: complete multipart %s: no parts", key)
	}
	awsParts := make([]types.CompletedPart, 0, len(parts))
	for _, p := range parts {
		awsParts = append(awsParts, types.CompletedPart{
			PartNumber: aws.Int32(int32(p.PartNumber)),
			ETag:       aws.String(p.ETag),
		})
	}
	_, err := s.client.CompleteMultipartUpload(ctx, &s3.CompleteMultipartUploadInput{
		Bucket:   aws.String(s.Bucket),
		Key:      aws.String(key),
		UploadId: aws.String(uploadID),
		MultipartUpload: &types.CompletedMultipartUpload{
			Parts: awsParts,
		},
	})
	if err != nil {
		return fmt.Errorf("s3: complete multipart %s: %w", key, err)
	}
	return nil
}

// AbortMultipart cancels an in-flight multipart upload and releases any
// parts that were already uploaded. Call this on user-initiated cancel
// paths so orphan parts don't sit in the bucket racking up storage.
func (s *S3Storage) AbortMultipart(
	ctx context.Context, key, uploadID string,
) error {
	if s == nil {
		return fmt.Errorf("s3: nil storage")
	}
	_, err := s.client.AbortMultipartUpload(ctx, &s3.AbortMultipartUploadInput{
		Bucket:   aws.String(s.Bucket),
		Key:      aws.String(key),
		UploadId: aws.String(uploadID),
	})
	if err != nil {
		return fmt.Errorf("s3: abort multipart %s: %w", key, err)
	}
	return nil
}

// PresignGet returns a time-limited GET URL for the object at key.
//
// The bucket is private (Block Public Access ON), so direct
// `https://bucket.s3.region.amazonaws.com/key` URLs return 403. Every
// playback URL the API hands to the client must be pre-signed instead.
//
// The TTL here is whatever the caller passed in at construction time —
// for the upload-response URL we use a long TTL (close to the SigV4 7-day
// max) so the URL stored alongside the post stays valid through a normal
// review/publish cycle. For per-request views (feed/post fetch) a shorter
// TTL is better; a second presigner with a shorter window can be added if
// we move signing onto the read path.
func (s *S3Storage) PresignGet(ctx context.Context, key string) (string, error) {
	if s == nil {
		return "", fmt.Errorf("s3: nil storage")
	}
	req, err := s.presigner.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.Bucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(s.PresignGetTTL))
	if err != nil {
		return "", fmt.Errorf("s3: presign get %s: %w", key, err)
	}
	return req.URL, nil
}
