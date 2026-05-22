#!/bin/bash

# Start the Halal Stocks API server

cd "$(dirname "$0")"

# Check if port 8080 is already in use
if lsof -ti:8080 > /dev/null 2>&1; then
    echo "⚠️  Port 8080 is already in use. Killing existing process..."
    lsof -ti:8080 | xargs kill -9 2>/dev/null
    sleep 1
fi

# Start the server
echo "🚀 Starting Halal Stocks API server on port 8080..."
go run cmd/api/main.go

