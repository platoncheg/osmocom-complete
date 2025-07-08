#!/bin/bash
set -e

echo "🚀 Starting OsmoHLR container..."

# Ensure directories exist with proper permissions
mkdir -p /var/lib/osmocom /opt/osmocom/logs

# Database path
DB_PATH="${OSMO_HLR_DB_PATH:-/var/lib/osmocom/hlr.db}"
CONFIG_FILE="${OSMO_HLR_CONFIG_FILE:-/data/osmo-hlr.cfg}"

echo "📋 Database path: $DB_PATH"
echo "⚙️ Config file: $CONFIG_FILE"

# Initialize database if it doesn't exist
if [ ! -f "$DB_PATH" ]; then
    echo "🗄️ Database not found, initializing..."
    /usr/local/bin/init-databases.sh
else
    echo "✅ Database already exists, skipping initialization"
fi

# Wait a moment for any initialization to complete
sleep 2

# Verify config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found at $CONFIG_FILE"
    echo "Please ensure the config file is mounted correctly"
    exit 1
fi

echo "🎯 Starting OsmoHLR with config: $CONFIG_FILE"
echo "📊 Database: $DB_PATH"

# Execute the command passed to the container
exec "$@"