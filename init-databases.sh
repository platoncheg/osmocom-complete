#!/bin/bash
echo "🗄️ Initializing databases..."

# Wait for containers to be ready
sleep 10

# Initialize HLR with test subscribers
docker-compose exec osmo-hlr osmo-hlr-db-tool --db-file /var/lib/osmocom/hlr.db create || true

# Add test subscribers
docker-compose exec osmo-hlr osmo-hlr-db-tool --db-file /var/lib/osmocom/hlr.db \
    import-subscriber-csv - << 'CSV'
imsi,msisdn,ki,opc,is_provisioned,vlr_name,sgsn_name
001010000000001,+1234567890,465B5CE8B199B49FAA5F0A2EE238A6BC,000102030405060708090a0b0c0d0e0f,1,,
001010000000002,+1234567891,465B5CE8B199B49FAA5F0A2EE238A6BD,000102030405060708090a0b0c0d0e0f,1,,
001010000000003,+1234567892,465B5CE8B199B49FAA5F0A2EE238A6BE,000102030405060708090a0b0c0d0e0f,1,,
CSV

echo "✅ Test subscribers added to HLR"
