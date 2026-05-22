#!/bin/bash

# Stop the Halal Stocks API server

cd "$(dirname "$0")"

# Find and kill process on port 8080
if lsof -ti:8080 > /dev/null 2>&1; then
    PID=$(lsof -ti:8080)
    echo "🛑 Stopping server (PID: $PID)..."
    kill -9 $PID 2>/dev/null
    sleep 1
    echo "✅ Server stopped"
else
    echo "ℹ️  No server running on port 8080"
fi

