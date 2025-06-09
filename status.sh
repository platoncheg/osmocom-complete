#!/bin/bash

# Complete Osmocom Mobile Network Status Script

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${CYAN}📊 Osmocom Mobile Network Status Report${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"

# Function to get container status with color
get_container_status() {
    local container=$1
    local status=$(docker-compose -f docker-compose-complete.yml ps | grep "$container" | awk '{print $4}')
    
    case $status in
        "Up")
            echo -e "${GREEN}●${NC} Running"
            ;;
        "Exit"*)
            echo -e "${RED}●${NC} Stopped"
            ;;
        "")
            echo -e "${YELLOW}●${NC} Not Found"
            ;;
        *)
            echo -e "${YELLOW}●${NC} $status"
            ;;
    esac
}

# Function to test port connectivity
test_port() {
    local port=$1
    local timeout=${2:-3}
    
    if timeout $timeout bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
        echo -e "${GREEN}✅${NC}"
    else
        echo -e "${RED}❌${NC}"
    fi
}

# Function to get uptime
get_uptime() {
    local container=$1
    local uptime=$(docker-compose -f docker-compose-complete.yml ps | grep "$container" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i}')
    echo "$uptime" | sed 's/^[ \t]*//' | sed 's/[ \t]*$//'
}

# Check if docker-compose file exists
if [ ! -f "docker-compose-complete.yml" ]; then
    echo -e "${RED}❌ docker-compose-complete.yml not found!${NC}"
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running${NC}"
    exit 1
fi

# Container Status Overview
echo -e "\n${BLUE}📦 Container Status${NC}"
echo "┌─────────────────┬──────────┬──────────┬─────────────────────────┐"
echo "│ Service         │ Status   │ VTY Port │ Uptime                  │"
echo "├─────────────────┼──────────┼──────────┼─────────────────────────┤"

services=(
    "osmo-stp:4239"
    "osmo-hlr:4258"
    "osmo-msc:4254"
    "osmo-smsc:4259"
    "osmo-bsc:4242"
    "osmo-bts:4241"
    "osmo-sgsn:4246"
    "osmo-ggsn:4260"
    "vty-proxy:5000"
    "web-dashboard:-"
    "sms-simulator:-"
    "mobile-simulator:-"
    "network-monitor:-"
)

for service_info in "${services[@]}"; do
    service=$(echo $service_info | cut -d: -f1)
    port=$(echo $service_info | cut -d: -f2)
    
    status=$(get_container_status "$service")
    uptime=$(get_uptime "$service")
    
    # Truncate long uptimes
    if [ ${#uptime} -gt 23 ]; then
        uptime="${uptime:0:20}..."
    fi
    
    printf "│ %-15s │ %-8s │ %-8s │ %-23s │\n" "$service" "$status" "$port" "$uptime"
done

echo "└─────────────────┴──────────┴──────────┴─────────────────────────┘"

# Port Connectivity Tests
echo -e "\n${BLUE}🔌 Port Connectivity${NC}"
echo "┌─────────────────┬──────────┬────────────┬──────────┐"
echo "│ Service         │ Port     │ Protocol   │ Status   │"
echo "├─────────────────┼──────────┼────────────┼──────────┤"

port_tests=(
    "STP VTY:4239:TCP"
    "HLR VTY:4258:TCP"
    "MSC VTY:4254:TCP"
    "SMSC VTY:4259:TCP"
    "BSC VTY:4242:TCP"
    "BTS VTY:4241:TCP"
    "SGSN VTY:4246:TCP"
    "GGSN VTY:4260:TCP"
    "VTY Proxy:5000:HTTP"
    "Dashboard:8888:HTTP"
    "SMS Simulator:9999:HTTP"
    "Mobile Sim:7777:HTTP"
    "Monitor:6666:HTTP"
    "SMPP:2775:TCP"
    "M3UA:2905:SCTP"
    "SCCP:14001:TCP"
)

for port_info in "${port_tests[@]}"; do
    service=$(echo $port_info | cut -d: -f1)
    port=$(echo $port_info | cut -d: -f2)
    protocol=$(echo $port_info | cut -d: -f3)
    
    status=$(test_port "$port")
    
    printf "│ %-15s │ %-8s │ %-10s │ %-8s │\n" "$service" "$port" "$protocol" "$status"
done

echo "└─────────────────┴──────────┴────────────┴──────────┘"

# SS7 Stack Status
echo -e "\n${BLUE}🌐 SS7 Stack Status${NC}"

# Test STP
echo -e "${CYAN}📡 Signaling Transfer Point (STP):${NC}"
stp_response=$(echo "show cs7 instance 0" | timeout 5 nc localhost 4239 2>/dev/null)
if echo "$stp_response" | grep -q "Point Code"; then
    pc=$(echo "$stp_response" | grep "Point Code" | awk '{print $3}')
    echo -e "   Status: ${GREEN}Active${NC} | Point Code: $pc"
else
    echo -e "   Status: ${RED}Inactive${NC}"
fi

# Test ASP connections
asp_count=$(echo "show cs7 instance 0 asp" | timeout 5 nc localhost 4239 2>/dev/null | grep -c "ASP" || echo "0")
echo -e "   ASP Connections: $asp_count"

# Test HLR
echo -e "\n${CYAN}🏠 Home Location Register (HLR):${NC}"
if docker-compose -f docker-compose-complete.yml exec -T osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "SELECT COUNT(*) FROM subscriber;" 2>/dev/null | grep -q "[0-9]"; then
    subscriber_count=$(docker-compose -f docker-compose-complete.yml exec -T osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "SELECT COUNT(*) FROM subscriber;" 2>/dev/null | tr -d '\r')
    echo -e "   Status: ${GREEN}Active${NC} | Subscribers: $subscriber_count"
    
    # Show sample subscribers
    if [ "$subscriber_count" -gt 0 ]; then
        echo "   Sample Subscribers:"
        docker-compose -f docker-compose-complete.yml exec -T osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "SELECT imsi, msisdn FROM subscriber LIMIT 3;" 2>/dev/null | while read line; do
            echo "     - $line"
        done
    fi
else
    echo -e "   Status: ${RED}Database Error${NC}"
fi

# Test MSC
echo -e "\n${CYAN}📞 Mobile Switching Center (MSC):${NC}"
msc_response=$(echo "show network" | timeout 5 nc localhost 4254 2>/dev/null)
if echo "$msc_response" | grep -q "Network"; then
    echo -e "   Status: ${GREEN}Active${NC}"
    # Extract network info
    if echo "$msc_response" | grep -q "country code"; then
        mcc=$(echo "$msc_response" | grep "country code" | awk '{print $4}')
        mnc=$(echo "$msc_response" | grep "mobile network code" | awk '{print $5}')
        echo -e "   Network: MCC=$mcc, MNC=$mnc"
    fi
else
    echo -e "   Status: ${RED}Inactive${NC}"
fi

# Test SMSC
echo -e "\n${CYAN}📱 SMS Center (SMSC):${NC}"
if docker-compose -f docker-compose-complete.yml exec -T osmo-smsc sqlite3 /var/lib/osmocom/smsc.db "SELECT COUNT(*) FROM sms;" 2>/dev/null | grep -q "[0-9]"; then
    sms_count=$(docker-compose -f docker-compose-complete.yml exec -T osmo-smsc sqlite3 /var/lib/osmocom/smsc.db "SELECT COUNT(*) FROM sms;" 2>/dev/null | tr -d '\r')
    echo -e "   Status: ${GREEN}Active${NC} | Messages in queue: $sms_count"
    
    # Show SMPP connections
    smpp_response=$(echo "show smpp esme" | timeout 5 nc localhost 4259 2>/dev/null)
    if echo "$smpp_response" | grep -q "ESME"; then
        esme_count=$(echo "$smpp_response" | grep -c "ESME" || echo "0")
        echo -e "   SMPP Connections: $esme_count"
    fi
else
    echo -e "   Status: ${RED}Database Error${NC}"
fi

# Resource Usage
echo -e "\n${BLUE}💻 Resource Usage${NC}"
if command -v docker >/dev/null 2>&1; then
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null | head -10 | while read line; do
        if [[ "$line" == *"NAME"* ]]; then
            echo -e "${CYAN}$line${NC}"
        else
            echo "$line"
        fi
    done
fi

# Network Statistics
echo -e "\n${BLUE}📊 Network Statistics${NC}"

# Calculate total processed messages
total_sms=0
if docker-compose -f docker-compose-complete.yml exec -T osmo-smsc sqlite3 /var/lib/osmocom/smsc.db "SELECT COUNT(*) FROM sms;" 2>/dev/null | grep -q "[0-9]"; then
    total_sms=$(docker-compose -f docker-compose-complete.yml exec -T osmo-smsc sqlite3 /var/lib/osmocom/smsc.db "SELECT COUNT(*) FROM sms;" 2>/dev/null | tr -d '\r')
fi

# Get uptime of main service
stp_uptime=$(docker-compose -f docker-compose-complete.yml ps | grep "osmo-stp" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i}' | sed 's/^[ \t]*//' | sed 's/[ \t]*$//')

echo "┌─────────────────────────┬─────────────────┐"
echo "│ Metric                  │ Value           │"
echo "├─────────────────────────┼─────────────────┤"
printf "│ %-23s │ %-15s │\n" "Network Uptime" "${stp_uptime:-Unknown}"
printf "│ %-23s │ %-15s │\n" "Total Subscribers" "${subscriber_count:-0}"
printf "│ %-23s │ %-15s │\n" "SMS Messages Processed" "${total_sms:-0}"
printf "│ %-23s │ %-15s │\n" "Active ASP Connections" "${asp_count:-0}"

# Count running services
running_services=$(docker-compose -f docker-compose-complete.yml ps | grep -c "Up" || echo "0")
total_services=$(echo "${services[@]}" | wc -w)
printf "│ %-23s │ %-15s │\n" "Services Running" "$running_services/$total_services"
echo "└─────────────────────────┴─────────────────┘"

# Recent Activity
echo -e "\n${BLUE}📝 Recent Activity (Last 10 log entries)${NC}"
echo -e "${CYAN}Recent STP Activity:${NC}"
docker-compose -f docker-compose-complete.yml logs --tail=3 osmo-stp 2>/dev/null | sed 's/^/   /' || echo "   No logs available"

echo -e "${CYAN}Recent HLR Activity:${NC}"
docker-compose -f docker-compose-complete.yml logs --tail=3 osmo-hlr 2>/dev/null | sed 's/^/   /' || echo "   No logs available"

echo -e "${CYAN}Recent SMSC Activity:${NC}"
docker-compose -f docker-compose-complete.yml logs --tail=3 osmo-smsc 2>/dev/null | sed 's/^/   /' || echo "   No logs available"

# Health Summary
echo -e "\n${BLUE}🏥 Health Summary${NC}"

# Count healthy services
healthy_vty=0
total_vty_services=8

vty_ports=("4239" "4258" "4254" "4259" "4242" "4241" "4246" "4260")
for port in "${vty_ports[@]}"; do
    if timeout 3 bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
        ((healthy_vty++))
    fi
done

healthy_web=0
total_web_services=5
web_ports=("8888" "9999" "5000" "7777" "6666")
for port in "${web_ports[@]}"; do
    if timeout 3 bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
        ((healthy_web++))
    fi
done

# Calculate overall health
overall_health=$((($running_services + $healthy_vty + $healthy_web) * 100 / ($total_services + $total_vty_services + $total_web_services)))

echo "┌─────────────────────────┬─────────────────┬──────────┐"
echo "│ Component               │ Status          │ Health   │"
echo "├─────────────────────────┼─────────────────┼──────────┤"
printf "│ %-23s │ %-15s │ " "Container Services" "$running_services/$total_services"
if [ $running_services -eq $total_services ]; then
    echo -e "${GREEN}100%${NC}     │"
else
    pct=$((running_services * 100 / total_services))
    echo -e "${YELLOW}$pct%${NC}      │"
fi

printf "│ %-23s │ %-15s │ " "VTY Interfaces" "$healthy_vty/$total_vty_services"
if [ $healthy_vty -eq $total_vty_services ]; then
    echo -e "${GREEN}100%${NC}     │"
else
    pct=$((healthy_vty * 100 / total_vty_services))
    echo -e "${YELLOW}$pct%${NC}      │"
fi

printf "│ %-23s │ %-15s │ " "Web Interfaces" "$healthy_web/$total_web_services"
if [ $healthy_web -eq $total_web_services ]; then
    echo -e "${GREEN}100%${NC}     │"
else
    pct=$((healthy_web * 100 / total_web_services))
    echo -e "${YELLOW}$pct%${NC}      │"
fi

echo "├─────────────────────────┼─────────────────┼──────────┤"
printf "│ %-23s │ %-15s │ " "Overall Network" "Composite"
if [ $overall_health -ge 90 ]; then
    echo -e "${GREEN}$overall_health%${NC}     │"
elif [ $overall_health -ge 70 ]; then
    echo -e "${YELLOW}$overall_health%${NC}     │"
else
    echo -e "${RED}$overall_health%${NC}     │"
fi
echo "└─────────────────────────┴─────────────────┴──────────┘"

# Quick Actions
echo -e "\n${BLUE}🚀 Quick Actions${NC}"
echo "   📊 Full verification:    ./verify-network.sh"
echo "   🔄 Restart network:      ./restart.sh"
echo "   🛑 Shutdown network:     ./shutdown.sh"
echo "   📱 Test SMS:             python3 test-sms.py --from=+1234567890 --to=+1234567891"
echo "   📝 View logs:            docker-compose -f docker-compose-complete.yml logs -f"
echo "   🌐 Web dashboard:        http://localhost:8888"
echo "   📨 SMS simulator:        http://localhost:9999"

# Status Summary
echo -e "\n${CYAN}════════════════════════════════════════${NC}"
if [ $overall_health -ge 90 ]; then
    echo -e "${GREEN}✅ Network Status: HEALTHY${NC}"
    echo -e "   All systems operational. Ready for SMS testing."
elif [ $overall_health -ge 70 ]; then
    echo -e "${YELLOW}⚠️  Network Status: DEGRADED${NC}"
    echo -e "   Some components need attention. Check failed services above."
else
    echo -e "${RED}❌ Network Status: CRITICAL${NC}"
    echo -e "   Multiple system failures. Run ./restart.sh or check logs."
fi

echo -e "   Overall Health: $overall_health%"
echo -e "${CYAN}════════════════════════════════════════${NC}"