#!/bin/bash

#
# Osmocom Complete Stack - Status Script
# Comprehensive status monitoring and health checks
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
COMPOSE_FILE="docker-compose.yml"
PROJECT_NAME="osmocom-complete"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo "📊 Osmocom Complete Stack - Status Monitor"
    echo "==========================================="
    echo ""
}

print_section() {
    echo ""
    echo -e "${CYAN}=== $1 ===${NC}"
    echo ""
}

get_container_status() {
    local container=$1
    
    if docker-compose ps $container 2>/dev/null | grep -q "Up"; then
        if docker-compose ps $container | grep -q "healthy"; then
            echo "healthy"
        else
            echo "running"
        fi
    elif docker-compose ps $container 2>/dev/null | grep -q "Exit"; then
        echo "stopped"
    else
        echo "missing"
    fi
}

check_port_connectivity() {
    local host=${1:-localhost}
    local port=$2
    
    if nc -z $host $port 2>/dev/null; then
        echo "open"
    else
        echo "closed"
    fi
}

get_uptime() {
    local container=$1
    local created_at
    
    created_at=$(docker inspect --format='{{.Created}}' "${PROJECT_NAME}_${container}_1" 2>/dev/null || echo "")
    
    if [ -n "$created_at" ]; then
        # Convert to epoch time and calculate difference
        local created_epoch
        created_epoch=$(date -d "$created_at" +%s 2>/dev/null || echo "0")
        local current_epoch
        current_epoch=$(date +%s)
        local diff=$((current_epoch - created_epoch))
        
        if [ $diff -gt 3600 ]; then
            echo "$((diff / 3600))h $((diff % 3600 / 60))m"
        elif [ $diff -gt 60 ]; then
            echo "$((diff / 60))m $((diff % 60))s"
        else
            echo "${diff}s"
        fi
    else
        echo "unknown"
    fi
}

show_service_status() {
    print_section "Service Status"
    
    # Service definitions: container:port:name:description
    local services=(
        "osmo-stp:4239:OsmoSTP:SS7 Signaling Transfer Point"
        "osmo-hlr:4258:OsmoHLR:Home Location Register"
        "osmo-mgw:2427:OsmoMGW:Media Gateway"
        "osmo-msc:4254:OsmoMSC:Mobile Switching Center + SMSC"
        "osmo-bsc:4242:OsmoBSC:Base Station Controller"
        "vty-proxy:5000:VTY Proxy:HTTP-VTY Bridge"
        "web-dashboard:8888:Web Dashboard:Monitoring Interface"
        "sms-simulator:9999:SMS Simulator:Testing Interface"
    )
    
    printf "%-15s %-12s %-8s %-8s %-10s %s\n" "SERVICE" "STATUS" "PORT" "HEALTH" "UPTIME" "DESCRIPTION"
    printf "%-15s %-12s %-8s %-8s %-10s %s\n" "-------" "------" "----" "------" "------" "-----------"
    
    local healthy_count=0
    local total_count=${#services[@]}
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r container port name description <<< "$service_info"
        
        local status
        status=$(get_container_status $container)
        
        local port_status
        port_status=$(check_port_connectivity localhost $port)
        
        local uptime
        uptime=$(get_uptime $container)
        
        # Determine overall health
        local health="unknown"
        local status_color=$YELLOW
        
        case $status in
            "healthy")
                if [ "$port_status" = "open" ]; then
                    health="healthy"
                    status_color=$GREEN
                    ((healthy_count++))
                else
                    health="degraded"
                    status_color=$YELLOW
                fi
                ;;
            "running")
                if [ "$port_status" = "open" ]; then
                    health="running"
                    status_color=$BLUE
                    ((healthy_count++))
                else
                    health="degraded"
                    status_color=$YELLOW
                fi
                ;;
            "stopped")
                health="stopped"
                status_color=$RED
                ;;
            "missing")
                health="missing"
                status_color=$RED
                ;;
        esac
        
        printf "${status_color}%-15s %-12s %-8s %-8s %-10s %s${NC}\n" \
            "$name" "$status" "$port" "$port_status" "$uptime" "$description"
    done
    
    echo ""
    echo "Overall Health: $healthy_count/$total_count services operational"
    
    if [ $healthy_count -eq $total_count ]; then
        echo -e "${GREEN}✓ All services are healthy${NC}"
    elif [ $healthy_count -gt $((total_count / 2)) ]; then
        echo -e "${YELLOW}⚠ Some services need attention${NC}"
    else
        echo -e "${RED}✗ Multiple services are down${NC}"
    fi
}

show_network_status() {
    print_section "Network Status"
    
    # Check Docker network
    local network_name="${PROJECT_NAME}_osmocom-network"
    if docker network inspect $network_name >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Docker network '$network_name' exists"
        
        # Show network details
        local subnet
        subnet=$(docker network inspect $network_name --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "unknown")
        echo "  Subnet: $subnet"
        
        # Show connected containers
        local connected_containers
        connected_containers=$(docker network inspect $network_name --format '{{range $k, $v := .Containers}}{{$v.Name}} {{end}}' 2>/dev/null || echo "")
        if [ -n "$connected_containers" ]; then
            echo "  Connected containers: $connected_containers"
        fi
    else
        echo -e "${RED}✗${NC} Docker network '$network_name' not found"
    fi
    
    # Check port accessibility from external
    echo ""
    echo "External Port Accessibility:"
    
    local external_ports=(
        "4239:OsmoSTP VTY"
        "4254:OsmoMSC VTY"
        "4242:OsmoBSC VTY"
        "4258:OsmoHLR VTY"
        "2427:OsmoMGW VTY"
        "5000:VTY Proxy API"
        "8888:Web Dashboard"
        "9999:SMS Simulator"
        "2905:M3UA/SCTP"
        "2728:MGCP"
    )
    
    for port_info in "${external_ports[@]}"; do
        IFS=':' read -r port service <<< "$port_info"
        
        if nc -z localhost $port 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Port $port ($service) - accessible"
        else
            echo -e "  ${RED}✗${NC} Port $port ($service) - not accessible"
        fi
    done
}

show_resource_usage() {
    print_section "Resource Usage"
    
    # Check if any containers are running
    local running_containers
    running_containers=$(docker-compose ps --services --filter "status=running" 2>/dev/null || echo "")
    
    if [ -z "$running_containers" ]; then
        echo "No containers are currently running"
        return
    fi
    
    echo "Container Resource Usage:"
    echo ""
    
    # Get docker stats for project containers
    local stats_output
    stats_output=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null | grep "$PROJECT_NAME" || echo "")
    
    if [ -n "$stats_output" ]; then
        echo "$stats_output"
    else
        echo "Unable to retrieve container statistics"
    fi
    
    echo ""
    
    # System resources
    echo "System Resources:"
    
    # Available memory
    if command -v free >/dev/null 2>&1; then
        local mem_info
        mem_info=$(free -h | grep "Mem:")
        echo "  Memory: $mem_info"
    fi
    
    # Available disk space
    if command -v df >/dev/null 2>&1; then
        local disk_info
        disk_info=$(df -h / | tail -1 | awk '{print $4 " available of " $2 " total (" $5 " used)"}')
        echo "  Disk: $disk_info"
    fi
    
    # Docker disk usage
    if command -v docker >/dev/null 2>&1; then
        echo ""
        echo "Docker Disk Usage:"
        docker system df 2>/dev/null || echo "  Unable to get Docker disk usage"
    fi
}

show_vty_connectivity() {
    print_section "VTY Connectivity Test"
    
    local vty_services=(
        "localhost:4239:OsmoSTP"
        "localhost:4254:OsmoMSC"
        "localhost:4242:OsmoBSC"
        "localhost:4258:OsmoHLR"
        "localhost:2427:OsmoMGW"
    )
    
    for service_info in "${vty_services[@]}"; do
        IFS=':' read -r host port service <<< "$service_info"
        
        echo -n "Testing $service VTY ($host:$port)... "
        
        # Test VTY connection with timeout
        if timeout 5 bash -c "echo 'quit' | nc $host $port" >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    done
}

show_api_status() {
    print_section "API Status"
    
    # Test VTY Proxy API
    echo "VTY Proxy API (http://localhost:5000):"
    
    if curl -s --connect-timeout 5 http://localhost:5000/health >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Health endpoint accessible"
        
        # Get detailed health info
        local health_response
        health_response=$(curl -s --connect-timeout 5 http://localhost:5000/health 2>/dev/null || echo "")
        
        if [ -n "$health_response" ]; then
            echo "  Health details:"
            echo "$health_response" | python3 -m json.tool 2>/dev/null | head -20 || echo "$health_response"
        fi
    else
        echo -e "  ${RED}✗${NC} Health endpoint not accessible"
    fi
    
    echo ""
    
    # Test other API endpoints
    local api_endpoints=(
        "/api/services:Services list"
        "/api/status:System status"
    )
    
    for endpoint_info in "${api_endpoints[@]}"; do
        IFS=':' read -r endpoint description <<< "$endpoint_info"
        
        echo -n "Testing $description ($endpoint)... "
        
        if curl -s --connect-timeout 5 http://localhost:5000$endpoint >/dev/null 2>&1; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
        fi
    done
}

show_sms_status() {
    print_section "SMS System Status"
    
    # Check if VTY Proxy is accessible
    if ! curl -s --connect-timeout 5 http://localhost:5000/health >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} Cannot check SMS status - VTY Proxy not accessible"
        return
    fi
    
    echo "Checking SMS queue status via MSC..."
    
    # Try to get SMS queue status
    local queue_response
    queue_response=$(curl -s --connect-timeout 10 -X POST http://localhost:5000/api/command \
        -H "Content-Type: application/json" \
        -d '{"service": "msc", "command": "show sms queue"}' 2>/dev/null || echo "")
    
    if [ -n "$queue_response" ]; then
        echo "SMS Queue Status:"
        echo "$queue_response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    if data.get('result', {}).get('success'):
        print('  ✓ SMS queue accessible')
        output = data['result'].get('output', '')
        if output:
            print('  Queue details:')
            for line in output.split('\n')[:10]:  # First 10 lines
                if line.strip():
                    print(f'    {line}')
    else:
        print('  ✗ SMS queue check failed')
        print(f'    Error: {data.get(\"result\", {}).get(\"error\", \"Unknown error\")}')
except:
    print('  ✗ Could not parse SMS queue response')
" 2>/dev/null || echo "  ✗ Could not check SMS queue"
    else
        echo -e "${RED}✗${NC} Could not retrieve SMS queue status"
    fi
    
    echo ""
    echo "SMS Testing:"
    echo "  Send test SMS: curl -X POST http://localhost:5000/api/sms/send \\"
    echo "                      -H 'Content-Type: application/json' \\"
    echo "                      -d '{\"from\": \"1001\", \"to\": \"1002\", \"message\": \"Test\"}'"
}

show_logs_summary() {
    print_section "Recent Logs Summary"
    
    local services=("osmo-stp" "osmo-hlr" "osmo-mgw" "osmo-msc" "osmo-bsc" "vty-proxy")
    
    for service in "${services[@]}"; do
        if docker-compose ps $service | grep -q "Up"; then
            echo "$service recent logs:"
            docker-compose logs --tail=3 $service 2>/dev/null | tail -3 | sed 's/^/  /'
            echo ""
        fi
    done
    
    echo "For detailed logs: docker-compose logs -f [service-name]"
}

show_quick_actions() {
    print_section "Quick Actions"
    
    echo "Management Commands:"
    echo "  ./startup.sh          - Start all services"
    echo "  ./shutdown.sh         - Stop all services"
    echo "  ./deploy.sh           - Full deployment"
    echo ""
    echo "Monitoring:"
    echo "  ./status.sh --watch   - Continuous monitoring"
    echo "  ./status.sh --health  - Health check only"
    echo "  ./status.sh --logs    - Recent logs only"
    echo ""
    echo "Access Points:"
    echo "  Web Dashboard:        http://localhost:8888"
    echo "  SMS Simulator:        http://localhost:9999"
    echo "  VTY Proxy API:        http://localhost:5000"
    echo ""
    echo "Direct VTY Access:"
    echo "  telnet localhost 4239 # OsmoSTP"
    echo "  telnet localhost 4254 # OsmoMSC"
    echo "  telnet localhost 4242 # OsmoBSC"
    echo "  telnet localhost 4258 # OsmoHLR"
    echo "  telnet localhost 2427 # OsmoMGW"
}

watch_mode() {
    echo "Starting continuous monitoring mode (Ctrl+C to exit)..."
    echo ""
    
    while true; do
        clear
        print_header
        show_service_status
        
        echo ""
        echo -e "${CYAN}Last updated: $(date)${NC}"
        echo "Press Ctrl+C to exit watch mode"
        
        sleep 5
    done
}

# Main status function
main() {
    print_header
    
    show_service_status
    show_network_status
    show_resource_usage
    show_vty_connectivity
    show_api_status
    show_sms_status
    show_logs_summary
    show_quick_actions
}

# Script options
case "${1:-}" in
    --help|-h)
        echo "Osmocom Complete Stack - Status Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h       Show this help message"
        echo "  --watch, -w      Continuous monitoring mode"
        echo "  --health         Show only service health status"
        echo "  --network        Show only network status"
        echo "  --resources      Show only resource usage"
        echo "  --vty            Test VTY connectivity only"
        echo "  --api            Test API endpoints only"
        echo "  --sms            Show SMS system status only"
        echo "  --logs           Show recent logs only"
        echo "  --json           Output status in JSON format"
        echo ""
        echo "Examples:"
        echo "  $0               # Full status report"
        echo "  $0 --watch       # Continuous monitoring"
        echo "  $0 --health      # Quick health check"
        echo "  $0 --json        # JSON output for automation"
        echo ""
        exit 0
        ;;
    --watch|-w)
        trap 'echo ""; echo "Monitoring stopped."; exit 0' INT
        watch_mode
        ;;
    --health)
        print_header
        show_service_status
        ;;
    --network)
        print_header
        show_network_status
        ;;
    --resources)
        print_header
        show_resource_usage
        ;;
    --vty)
        print_header
        show_vty_connectivity
        ;;
    --api)
        print_header
        show_api_status
        ;;
    --sms)
        print_header
        show_sms_status
        ;;
    --logs)
        print_header
        show_logs_summary
        ;;
    --json)
        # Simple JSON output for automation
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"services\": {"
        
        local services=("osmo-stp" "osmo-hlr" "osmo-mgw" "osmo-msc" "osmo-bsc" "vty-proxy" "web-dashboard" "sms-simulator")
        local first=true
        
        for service in "${services[@]}"; do
            if [ "$first" = false ]; then
                echo ","
            fi
            first=false
            
            local status
            status=$(get_container_status $service)
            
            echo -n "    \"$service\": {"
            echo -n "\"status\": \"$status\""
            echo -n "}"
        done
        
        echo ""
        echo "  }"
        echo "}"
        ;;
    "")
        # Default behavior - full status report
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac