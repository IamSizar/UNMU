#!/bin/bash
set -e

# Railway provides standard Postgres variables when connecting the DB service:
# PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE

echo "Starting deployment on Railway..."

# Check if PG variables exist to run migrations
if [ -n "$PGHOST" ]; then
    echo "PostgreSQL credentials found from Railway. Mapping to backend environment variables."
    export DB_HOST=$PGHOST
    export DB_PORT=$PGPORT
    export DB_USER=$PGUSER
    export DB_PASSWORD=$PGPASSWORD
    export DB_NAME=$PGDATABASE
    
    # Optional DB SSL setting, Railway PG typically requires SSL Disable or Require
    # If there are connection issues with SSL, you may need to set this to 'require'
    export DB_SSLMODE=${DB_SSLMODE:-disable}
    
    # Construct postgres connection string for migrations
    DB_URL="postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}?sslmode=${DB_SSLMODE}"
    
    echo "Running database migrations..."
    # Apply migrations
    migrate -path /app/migrations -database "$DB_URL" up || true
    echo "Migrations check complete."
else
    echo "WARNING: PGHOST is not set. Assuming database is managed externally or connection vars are set manually."
fi

# The SERVER_PORT handles the dynamic $PORT injected by Railway. 
# Go API uses SERVER_PORT variable.
export SERVER_PORT=${PORT:-8080}

echo "Starting Go API server on port $SERVER_PORT..."
exec /app/api
