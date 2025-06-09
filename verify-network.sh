#!/bin/bash

# Complete Network Verification Script
echo "🔍 Verifying Complete Osmocom Mobile Network..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0

# Helper function for test status
test_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASS${NC}: $2"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}❌ FAIL${NC}: $2"
        ((TESTS_FAILED++))
    fi
}

echo "📊 Testing Network Component Status..."

# Test 1: Check if all containers are running
echo -e "\n${BLUE}Test 1: Container Status${NC}"
CONTAINERS=("osmo-stp" "osmo-hlr" "osmo-msc" "osmo-smsc" "osmo-bsc" "osmo-bts" "osmo-sgsn" "osmo-ggsn")

for container in "${CONTAINERS[@]}"; do
    if docker-compose -f docker-compose-complete.yml ps | grep -q "$container.*Up"; then
        test_status 0 "$container container running"
    else
        test_status 1 "$container container not running"
    fi
done

# Test 2: VTY Interface Connectivity
echo -e "\n${BLUE}Test 2: VTY Interface Connectivity${NC}"
VTY_PORTS=("4239:STP" "4258:HLR" "4254:MSC" "4259:SMSC" "4242:BSC" "4241:BTS" "4246:SGSN" "4260:GGSN")

for port_info in "${VTY_PORTS[@]}"; do
    port=$(echo $port_info | cut -d: -f1)
    name=$(echo $port_info | cut -d: -f2)
    
    if timeout 3 bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
        test_status 0 "$name VTY port $port accessible"
    else
        test_status 1 "$name VTY port $port not accessible"
    fi
done

# Test 3: SS7 Stack Connectivity
echo -e "\n${BLUE}Test 3: SS7 Stack Connectivity${NC}"

# Test STP status
STP_STATUS=$(echo "show cs7 instance 0" | timeout 5 nc localhost 4239 2>/dev/null | grep -c "Point Code")
test_status $([[ $STP_STATUS -gt 0 ]] && echo 0 || echo 1) "STP CS7 instance responding"

# Test HLR database
HLR_STATUS=$(echo "show subscriber summary" | timeout 5 nc localhost 4258 2>/dev/null | grep -c "subscribers")
test_status $([[ $HLR_STATUS -gt 0 ]] && echo 0 || echo 1) "HLR subscriber database accessible"

# Test MSC connectivity  
MSC_STATUS=$(echo "show network" | timeout 5 nc localhost 4254 2>/dev/null | grep -c "Network")
test_status $([[ $MSC_STATUS -gt 0 ]] && echo 0 || echo 1) "MSC network configuration active"

# Test 4: SMPP Interface
echo -e "\n${BLUE}Test 4: SMPP Interface${NC}"

# Test SMPP port accessibility
if timeout 3 bash -c "</dev/tcp/localhost/2775" 2>/dev/null; then
    test_status 0 "SMPP port 2775 accessible"
    
    # Test SMPP bind (requires python smpplib)
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import socket
import time
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(('localhost', 2775))
    s.close()
    print('SMPP_CONNECT_OK')
except:
    print('SMPP_CONNECT_FAIL')
" > /tmp/smpp_test 2>&1
        
        if grep -q "SMPP_CONNECT_OK" /tmp/smpp_test; then
            test_status 0 "SMPP socket connection successful"
        else
            test_status 1 "SMPP socket connection failed"
        fi
    else
        test_status 1 "Python3 not available for SMPP testing"
    fi
else
    test_status 1 "SMPP port 2775 not accessible"
fi

# Test 5: Database Integrity
echo -e "\n${BLUE}Test 5: Database Integrity${NC}"

# Test HLR database
if docker-compose -f docker-compose-complete.yml exec -T osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "SELECT COUNT(*) FROM subscriber;" 2>/dev/null | grep -q "[0-9]"; then
    SUBSCRIBER_COUNT=$(docker-compose -f docker-compose-complete.yml exec -T osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "SELECT COUNT(*) FROM subscriber;" 2>/dev/null | tr -d '\r')
    test_status 0 "HLR database accessible ($SUBSCRIBER_COUNT subscribers)"
else
    test_status 1 "HLR database not accessible"
fi

# Test SMSC database
if docker-compose -f docker-compose-complete.yml exec -T osmo-smsc sqlite3 /var/lib/osmocom/smsc.db "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null | grep -q "sms"; then
    test_status 0 "SMSC database accessible"
else
    test_status 1 "SMSC database not accessible"
fi

# Test 6: Protocol Stack Communication
echo -e "\n${BLUE}Test 6: Protocol Stack Communication${NC}"

# Test M3UA associations
M3UA_ASPS=$(echo "show cs7 instance 0 asp" | timeout 5 nc localhost 4239 2>/dev/null | grep -c "ASP")
test_status $([[ $M3UA_ASPS -gt 0 ]] && echo 0 || echo 1) "M3UA ASP associations ($M3UA_ASPS found)"

# Test SCCP connections
SCCP_CONNS=$(echo "show cs7 instance 0 sccp users" | timeout 5 nc localhost 4239 2>/dev/null | wc -l)
test_status $([[ $SCCP_CONNS -gt 1 ]] && echo 0 || echo 1) "SCCP subsystem users responding"

# Test 7: Mobile Network Registration
echo -e "\n${BLUE}Test 7: Mobile Network Registration Simulation${NC}"

# Check if test subscribers exist
TEST_IMSI="001010000000001"
SUBSCRIBER_EXISTS=$(echo "subscriber imsi $TEST_IMSI show" | timeout 5 nc localhost 4258 2>/dev/null | grep -c "$TEST_IMSI")
test_status $([[ $SUBSCRIBER_EXISTS -gt 0 ]] && echo 0 || echo 1) "Test subscriber $TEST_IMSI exists in HLR"

# Test 8: SMS Flow Simulation
echo -e "\n${BLUE}Test 8: SMS Flow Simulation${NC}"

# Test SMS routing info request (simulate HLR query)
if command -v python3 >/dev/null 2>&1 && [ -f "test-sms.py" ]; then
    echo "Testing SMS through complete stack..."
    timeout 10 python3 test-sms.py --from="+1234567890" --to="+1234567891" --text="Network verification test" --test-hlr 2>/dev/null > /tmp/sms_test
    
    if grep -q "Connected to SMSC" /tmp/sms_test; then
        test_status 0 "SMS submission to SMSC successful"
    else
        test_status 1 "SMS submission to SMSC failed"
    fi
    
    if grep -q "found in HLR" /tmp/sms_test; then
        test_status 0 "HLR subscriber lookup successful"
    else
        test_status 1 "HLR subscriber lookup failed"
    fi
else
    test_status 1 "SMS testing script not available"
fi

# Test 9: Web Interface Accessibility  
echo -e "\n${BLUE}Test 9: Web Interface Accessibility${NC}"

WEB_INTERFACES=("8888:Dashboard" "9999:SMS_Simulator" "5000:VTY_Proxy" "7777:Mobile_Simulator" "6666:Network_Monitor")

for interface_info in "${WEB_INTERFACES[@]}"; do
    port=$(echo $interface_info | cut -d: -f1)
    name=$(echo $interface_info | cut -d: -f2)
    
    if timeout 3 curl -s http://localhost:$port/ >/dev/null 2>&1; then
        test_status 0 "$name web interface (port $port) accessible"
    else
        test_status 1 "$name web interface (port $port) not accessible"
    fi
done

# Test 10: Network Performance
echo -e "\n${BLUE}Test 10: Network Performance${NC}"

# Test VTY response time
VTY_START=$(date +%s%N)
echo "show cs7 instance 0" | timeout 5 nc localhost 4239 >/dev/null 2>&1
VTY_END=$(date +%s%N)
VTY_TIME=$((($VTY_END - $VTY_START) / 1000000)) # Convert to milliseconds

test_status $([[ $VTY_TIME -lt 1000 ]] && echo 0 || echo 1) "VTY response time acceptable (${VTY_TIME}ms)"

# Test HLR response time
HLR_START=$(date +%s%N)
echo "show subscriber summary" | timeout 5 nc localhost 4258 >/dev/null 2>&1
HLR_END=$(date +%s%N)
HLR_TIME=$((($HLR_END - $HLR_START) / 1000000))

test_status $([[ $HLR_TIME -lt 2000 ]] && echo 0 || echo 1) "HLR response time acceptable (${HLR_TIME}ms)"

# Summary
echo -e "\n${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}           VERIFICATION SUMMARY${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED))
SUCCESS_RATE=$((TESTS_PASSED * 100 / TOTAL_TESTS))

echo -e "Total Tests: $TOTAL_TESTS"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo -e "Success Rate: $SUCCESS_RATE%"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n🎉 ${GREEN}ALL TESTS PASSED!${NC}"
    echo -e "Your complete Osmocom mobile network is fully operational!"
    echo -e "\n📱 Ready for:"
    echo -e "   ✅ Real SMS over SS7 with TCAP/MAP semantics"
    echo -e "   ✅ Subscriber management via HLR"
    echo -e "   ✅ SMS store-and-forward via SMSC"
    echo -e "   ✅ Complete mobile network simulation"
    echo -e "   ✅ Load testing and protocol validation"
elif [ $SUCCESS_RATE -gt 70 ]; then
    echo -e "\n⚠️ ${YELLOW}MOSTLY OPERATIONAL${NC}"
    echo -e "Network is functional but some components need attention."
    echo -e "Check failed tests above for details."
else
    echo -e "\n❌ ${RED}NETWORK ISSUES DETECTED${NC}"
    echo -e "Multiple components are not working correctly."
    echo -e "Review logs and configuration before proceeding."
fi

echo -e "\n🔧 ${BLUE}Next Steps:${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "   1. Check logs: docker-compose -f docker-compose-complete.yml logs"
    echo -e "   2. Restart failed services: docker-compose -f docker-compose-complete.yml restart <service>"
    echo -e "   3. Verify configurations in configs/ directory"
    echo -e "   4. Ensure sufficient system resources (CPU/RAM)"
fi

echo -e "   5. Test SMS: python3 test-sms.py --from=+1234567890 --to=+1234567891 --text='Hello Network!'"
echo -e "   6. Monitor traffic: docker-compose -f docker-compose-complete.yml logs -f"
echo -e "   7. Access dashboards: http://localhost:8888 (main), http://localhost:9999 (SMS)"

echo -e "\n📚 ${BLUE}Documentation:${NC}"
echo -e "   - Network Architecture: See docker-compose-complete.yml"
echo -e "   - Component configs: configs/ directory"
echo -e "   - Subscriber management: telnet localhost 4258"
echo -e "   - SMS testing: Use test-sms.py script"

# Return appropriate exit code
if [ $TESTS_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi