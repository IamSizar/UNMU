#!/bin/bash

# Script to update .env file for DataJockey API

ENV_FILE=".env"

# Check if .env exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating .env file..."
    touch "$ENV_FILE"
fi

# Update or add DataJockey configuration
if grep -q "STOCK_API_PROVIDER" "$ENV_FILE"; then
    # Replace existing provider
    sed -i '' 's/^STOCK_API_PROVIDER=.*/STOCK_API_PROVIDER=datajockey/' "$ENV_FILE"
else
    echo "STOCK_API_PROVIDER=datajockey" >> "$ENV_FILE"
fi

# Add or update DataJockey API key
if grep -q "DATAJOCKEY_API_KEY" "$ENV_FILE"; then
    sed -i '' 's/^DATAJOCKEY_API_KEY=.*/DATAJOCKEY_API_KEY=f87d23e621e7d523d7b2df3092e66d3f8459271006ab11ee9c59/' "$ENV_FILE"
else
    echo "DATAJOCKEY_API_KEY=f87d23e621e7d523d7b2df3092e66d3f8459271006ab11ee9c59" >> "$ENV_FILE"
fi

echo "✅ Updated .env file for DataJockey API"
echo "   Provider: datajockey"
echo "   API Key: configured"

