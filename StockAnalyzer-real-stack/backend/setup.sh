#!/bin/bash

# Setup script for Halal Stocks Backend

echo "Setting up Halal Stocks Backend..."

# Check if PostgreSQL is installed
if ! command -v psql &> /dev/null; then
    echo "PostgreSQL is not installed. Please install it first."
    exit 1
fi

# Check if golang-migrate is installed
if ! command -v migrate &> /dev/null; then
    echo "Installing golang-migrate..."
    go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest
fi

# Create database if it doesn't exist
DB_NAME=${DB_NAME:-halalstocks}
DB_USER=${DB_USER:-$(whoami)}

echo "Creating database $DB_NAME..."
createdb $DB_NAME 2>/dev/null || echo "Database $DB_NAME already exists or creation failed"

# Run migrations
echo "Running database migrations..."
migrate -path migrations -database "postgres://$DB_USER@localhost/$DB_NAME?sslmode=disable" up

echo "Setup complete!"
echo ""
echo "To start the API server:"
echo "  go run cmd/api/main.go"
echo ""
echo "To run data ingestion:"
echo "  go run cmd/ingest/main.go"

