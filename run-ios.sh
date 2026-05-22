#!/bin/bash

# Script to run the Halal Stocks app on iOS simulator
# This will start the backend server and then launch the Flutter app

echo "🚀 Starting Halal Stocks on iOS Simulator..."
echo ""

# Check if backend server is running
if ! lsof -i :8080 | grep -q LISTEN; then
    echo "📡 Starting backend server..."
    cd backend
    export $(cat .env | grep -v '^#' | xargs)
    go run cmd/api/main.go > /tmp/halalstocks-backend.log 2>&1 &
    BACKEND_PID=$!
    echo "Backend server started (PID: $BACKEND_PID)"
    echo "Waiting for server to be ready..."
    sleep 3
    
    # Check if server started successfully
    if curl -s http://localhost:8080/api/regions > /dev/null 2>&1; then
        echo "✅ Backend server is running on http://localhost:8080"
    else
        echo "⚠️  Backend server may not be ready yet. Check /tmp/halalstocks-backend.log"
    fi
    cd ..
else
    echo "✅ Backend server is already running"
fi

echo ""
echo "📱 Starting iOS Simulator..."
open -a Simulator
sleep 2

echo ""
echo "🎨 Building and running Flutter app on iOS..."
echo ""

# Run Flutter app on iOS simulator
flutter run -d ios

# Cleanup: Kill backend server when script exits (if we started it)
if [ ! -z "$BACKEND_PID" ]; then
    trap "kill $BACKEND_PID 2>/dev/null" EXIT
fi

