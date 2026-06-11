# ─────────────────────────────────────────────────────────────────────────
# ROOT Dockerfile — builds the Go BACKEND with the build context = repo ROOT.
#
# Use this when a Railway service has Root Directory = "/" (repo root); the
# root railway.toml points here. COPY paths are prefixed with `backend/`
# because the context is the whole repo.
#
# The sibling `backend/Dockerfile` is the SAME build but with context =
# `backend/` (no prefix) — used when a service's Root Directory = "backend".
# Keep the two in sync.
# ─────────────────────────────────────────────────────────────────────────
FROM golang:1.25-alpine AS builder

RUN apk add --no-cache git ca-certificates wget tar

WORKDIR /app

# Copy go mod files (context = repo root → prefix with backend/)
COPY backend/go.mod backend/go.sum ./
RUN go mod download

# Copy the backend source
COPY backend/ .

# Build the main API binary
RUN CGO_ENABLED=0 GOOS=linux go build -o api ./cmd/api

# Download golang-migrate
RUN wget https://github.com/golang-migrate/migrate/releases/download/v4.16.2/migrate.linux-amd64.tar.gz && \
    tar -xzf migrate.linux-amd64.tar.gz && \
    mv migrate /app/migrate

# Stage 2: lightweight runtime image
FROM alpine:3.18

# ffmpeg/ffprobe required by the background video transcode worker.
RUN apk add --no-cache ca-certificates bash postgresql-client ffmpeg

WORKDIR /app

COPY --from=builder /app/api .
COPY --from=builder /app/migrate /usr/local/bin/migrate
COPY --from=builder /app/migrations ./migrations

COPY backend/start-railway.sh .
RUN chmod +x start-railway.sh

EXPOSE 8080

CMD ["./start-railway.sh"]
