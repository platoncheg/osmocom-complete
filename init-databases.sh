#!/bin/bash
set -e

echo "🗄️ Initializing HLR database..."

# Database path
DB_PATH="/var/lib/osmocom/hlr.db"
DATA_DIR="/var/lib/osmocom"

# Ensure data directory exists with proper permissions
mkdir -p "$DATA_DIR"
chown -R osmocom:osmocom "$DATA_DIR" 2>/dev/null || true

# Check if database already exists
if [ -f "$DB_PATH" ]; then
    echo "✅ HLR database already exists at $DB_PATH - skipping initialization"
    exit 0
fi

echo "📋 Creating new HLR database..."

# Create the database
osmo-hlr-db-tool --database "$DB_PATH" create

# Verify database was created
if [ ! -f "$DB_PATH" ]; then
    echo "❌ Failed to create HLR database"
    exit 1
fi

echo "👥 Adding test subscribers..."

# Create SQL file and execute it
cat > /tmp/subscribers.sql << 'SQL'
INSERT INTO subscriber (imsi, msisdn, nam_cs, nam_ps) VALUES 
    ('001010000000001', '+1234567890', 1, 1),
    ('001010000000002', '+1234567891', 1, 1), 
    ('001010000000003', '+1234567892', 1, 1);

INSERT INTO auc_3g (subscriber_id, algo_id_3g, k, opc, sqn) VALUES
    (1, 4, X'465B5CE8B199B49FAA5F0A2EE238A6BC', X'000102030405060708090a0b0c0d0e0f', 0),
    (2, 4, X'465B5CE8B199B49FAA5F0A2EE238A6BD', X'000102030405060708090a0b0c0d0e0f', 0),
    (3, 4, X'465B5CE8B199B49FAA5F0A2EE238A6BE', X'000102030405060708090a0b0c0d0e0f', 0);
SQL

# Execute SQL using sqlite3
sqlite3 "$DB_PATH" < /tmp/subscribers.sql

# Clean up
rm -f /tmp/subscribers.sql

# Set proper ownership
chown osmocom:osmocom "$DB_PATH" 2>/dev/null || true
chmod 644 "$DB_PATH"

echo "✅ HLR database initialized successfully with test subscribers"
echo "📍 Database location: $DB_PATH"