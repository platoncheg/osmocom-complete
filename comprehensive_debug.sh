#!/bin/bash

echo "🔍 Comprehensive subscriber debugging..."

echo "=== 1. Database File Check ==="
echo "Database file exists:"
docker-compose exec osmo-hlr ls -la /var/lib/osmocom/hlr.db

echo ""
echo "=== 2. All Subscribers in Database ==="
docker-compose exec osmo-hlr sqlite3 /var/lib/osmocom/hlr.db << 'SQL'
.headers on
.mode column
SELECT id, imsi, msisdn, nam_cs, nam_ps FROM subscriber ORDER BY id;
SQL

echo ""
echo "=== 3. Authentication Data ==="
docker-compose exec osmo-hlr sqlite3 /var/lib/osmocom/hlr.db << 'SQL'
.headers on 
.mode column
SELECT subscriber_id, algo_id_2g FROM auc_2g;
SELECT subscriber_id, algo_id_3g FROM auc_3g;
SQL

echo ""
echo "=== 4. VTY Interface Check ==="
echo "Checking VTY connection and subscriber lookup:"
timeout 10 docker-compose exec osmo-hlr telnet localhost 4258 << 'VTY' || echo "VTY connection failed"
enable
show subscribers all
show subscriber msisdn 1234
show subscriber msisdn 5678
exit
VTY

echo ""
echo "=== 5. HLR Configuration Check ==="
echo "Checking if HLR is using the correct database:"
docker-compose exec osmo-hlr ps aux | grep osmo-hlr

echo ""
echo "=== 6. HLR Logs ==="
echo "Recent HLR logs:"
docker-compose logs --tail=20 osmo-hlr

echo ""
echo "=== 7. Database Schema Check ==="
docker-compose exec osmo-hlr sqlite3 /var/lib/osmocom/hlr.db ".schema subscriber"

echo ""
echo "=== 8. Manual Database Query ==="
echo "Direct query for MSISDN 5678:"
docker-compose exec osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "SELECT * FROM subscriber WHERE msisdn = '5678';"

echo ""
echo "=== 9. HLR Process Check ==="
echo "Is HLR running and listening?"
docker-compose exec osmo-hlr netstat -tlnp | grep 4258 || echo "Port 4258 not listening"

echo ""
echo "=== 10. Database Integrity ==="
docker-compose exec osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "PRAGMA integrity_check;"