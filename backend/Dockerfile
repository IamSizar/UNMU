# Stage 1: Build the Go binary and download golang-migrate
FROM golang:1.21-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates wget tar

WORKDIR /app

# Copy go mod files
COPY backend/go.mod backend/go.sum ./
RUN go mod download

# Copy the source code
COPY backend/ .

# Build the main API binary
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o api cmd/api/main.go

# Download golang-migrate
RUN wget https://github.com/golang-migrate/migrate/releases/download/v4.16.2/migrate.linux-amd64.tar.gz && \
    tar -xzf migrate.linux-amd64.tar.gz && \
    mv migrate /app/migrate

# Stage 2: Create the final lightweight image
FROM alpine:3.18

RUN apk add --no-cache ca-certificates bash postgresql-client

WORKDIR /app

# Copy the binary from builder
COPY --from=builder /app/api .
# Copy the migration tool
COPY --from=builder /app/migrate /usr/local/bin/migrate
# Copy the migration scripts
COPY --from=builder /app/migrations ./migrations

# Copy the custom start script
COPY backend/start-railway.sh .
RUN chmod +x start-railway.sh

# Expose the port (Railway injects PORT automatically, defaults to 8080)
EXPOSE 8080

# Command to run the start script
CMD ["./start-railway.sh"]
