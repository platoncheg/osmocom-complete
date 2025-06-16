#!/bin/bash

#
# Osmocom Complete Stack - Startup Script
# Start all services in proper dependency order
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
    echo "🚀 Osmocom Complete Stack - Startup"
    echo "===================================="
    echo ""
}

check_docker() {
    log_info "Checking Docker availability..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not available"
        exit 1
    fi
    
    log_success "Docker is ready"
}

check_images() {
    log_info "Checking Docker images..."
    
    required_images=(
        "${PROJECT_NAME}_osmo-stp"
        "${PROJECT_NAME}_osmo-hlr"
        "${PROJECT_NAME}_osmo-mgw"
        "${PROJECT_NAME}_osmo-msc"
        "${PROJECT_NAME}_osmo-bsc"
        "${PROJECT_NAME}_vty-proxy"
        "${PROJECT_NAME}_web-dashboard"
        "${PROJECT_NAME}_sms-simulator"
    )
    
    missing_images=()
    
    for image in "${required_images[@]}"; do
        if ! docker images --format "table {{.Repository}}" | grep -q "^${image}$"; then
            missing_images+=("$image")
        fi
    done
    
    if [ ${#missing_images[@]} -gt 0 ]; then
        log_warning "Missing Docker images: ${missing_images[*]}"
        log_info "Building missing images..."
        docker-compose build
        log_success "Images built successfully"
    else
        log_success "All Docker images are available"
    fi
}

wait_for_service() {
    local service=$1
    local port=$2
    local timeout=${3:-60}
    local host=${4:-localhost}
    
    log_info "Waiting for $service to be ready on port $port..."
    
    local counter=0
    while [ $counter -lt $timeout ]; do
        if nc -z $host $port 2>/dev/null; then
            log_success "$service is ready"
            return 0
        fi
        
        sleep 2
        counter=$((counter + 2))
        
        # Show progress every 10 seconds
        if [ $((counter % 10)) -eq 0 ]; then
            log_info "Still waiting for $service... (${counter}s/${timeout}s)"
        fi
    done
    
    log_error "$service failed to start within ${timeout}s"
    return 1
}

start_core_services() {
    log_info "Starting core network services..."
    
    # Start foundational services first
    log_info "Starting STP (SS7 Signaling Transfer Point)..."
    docker-compose up -d osmo-stp
    wait_for_service "OsmoSTP" 4239
    
    log_info "Starting HLR (Home Location Register)..."
    docker-compose up -d osmo-hlr
    wait_for_service "OsmoHLR" 4258
    
    log_info "Starting MGW (Media Gateway)..."
    docker-compose up -d osmo-mgw
    wait_for_service "OsmoMGW" 2427
    
    log_success "Core services started successfully"
}

start_telecom_services() {
    log_info "Starting telecom services..."
    
    # MSC depends on STP, HLR, and MGW
    log_info "Starting MSC (Mobile Switching Center with integrated SMSC)..."
    docker-compose up -d osmo-msc
    wait_for_service "OsmoMSC" 4254
    
    # BSC depends on STP and MSC
    log_info "Starting BSC (Base Station Controller)..."
    docker-compose up -d osmo-bsc
    wait_for_service "OsmoBSC" 4242
    
    log_success "Telecom services started successfully"
}

start_management_services() {
    log_info "Starting management and monitoring services..."
    
    # VTY Proxy depends on all core services
    log_info "Starting VTY Proxy (HTTP-VTY Bridge)..."
    docker-compose up -d vty-proxy
    wait_for_service "VTY Proxy" 5000
    
    # Web services depend on VTY Proxy
    log_info "Starting Web Dashboard..."
    docker-compose up -d web-dashboard
    wait_for_service "Web Dashboard" 8888
    
    log_info "Starting SMS Simulator..."
    docker-compose up -d sms-simulator
    wait_for_service "SMS Simulator" 9999
    
    log_success "Management services started successfully"
}

verify_health() {
    log_info "Performing health checks..."
    
    local services=(
        "osmo-stp:4239:OsmoSTP"
        "osmo-hlr:4258:OsmoHLR"
        "osmo-mgw:2427:OsmoMGW"
        "osmo-msc:4254:OsmoMSC"
        "osmo-bsc:4242:OsmoBSC"
        "vty-proxy:5000:VTY Proxy"
        "web-dashboard:8888:Web Dashboard"
        "sms-simulator:9999:SMS Simulator"
    )
    
    local healthy=0
    local total=${#services[@]}
    
    echo ""
    echo "Service Health Status:"
    echo "====================="
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r container port name <<< "$service_info"
        
        if docker-compose ps $container | grep -q "Up"; then
            if nc -z localhost $port 2>/dev/null; then
                echo -e "${GREEN}✓${NC} $name: Healthy (port $port)"
                ((healthy++))
            else
                echo -e "${YELLOW}⚠${NC} $name: Running but port $port not accessible"
            fi
        else
            echo -e "${RED}✗${NC} $name: Not running"
        fi
    done
    
    echo ""
    echo "Health Summary: $healthy/$total services healthy"
    
    if [ $healthy -eq $total ]; then
        return 0
    else
        return 1
    fi
}

show_access_info() {
    echo ""
    echo "🎉 Osmocom Complete Stack Started Successfully!"
    echo ""
    echo "=== Quick Access ==="
    echo ""
    echo "📊 Web Dashboard:     http://localhost:8888"
    echo "📱 SMS Simulator:     http://localhost:9999"
    echo "🔌 VTY Proxy API:     http://localhost:5000"
    echo ""
    echo "=== Direct VTY Access ==="
    echo ""
    echo "OsmoSTP:  telnet localhost 4239"
    echo "OsmoMSC:  telnet localhost 4254"
    echo "OsmoBSC:  telnet localhost 4242"
    echo "OsmoHLR:  telnet localhost 4258"
    echo "OsmoMGW:  telnet localhost 2427"
    echo ""
    echo "=== Quick Test ==="
    echo ""
    echo "# Send test SMS:"
    echo "curl -X POST http://localhost:5000/api/sms/send \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"from\": \"1001\", \"to\": \"1002\", \"message\": \"Hello!\"}'"
    echo ""
    echo "=== Management ==="
    echo ""
    echo "Status:    ./status.sh"
    echo "Shutdown:  ./shutdown.sh"
    echo "Logs:      docker-compose logs -f"
    echo ""
}

show_startup_failed() {
    echo ""
    echo "⚠️  Startup completed with warnings"
    echo ""
    echo "Some services may not be fully ready. You can:"
    echo ""
    echo "1. Check detailed status:"
    echo "   ./status.sh"
    echo ""
    echo "2. View service logs:"
    echo "   docker-compose logs -f"
    echo ""
    echo "3. Restart specific services:"
    echo "   docker-compose restart <service-name>"
    echo ""
    echo "4. Try full restart:"
    echo "   ./shutdown.sh && ./startup.sh"
    echo ""
}

# Main startup function
main() {
    print_header
    
    # Pre-startup checks
    check_docker
    check_images
    
    # Start services in dependency order
    start_core_services
    start_telecom_services
    start_management_services
    
    # Verify everything is working
    if verify_health; then
        show_access_info
    else
        show_startup_failed
        exit 1
    fi
}

# Script options
case "${1:-}" in
    --help|-h)
        echo "Osmocom Complete Stack - Startup Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --core-only    Start only core services (STP, HLR, MGW)"
        echo "  --no-web       Start without web interfaces"
        echo "  --force        Force startup even if some services fail"
        echo ""
        echo "Examples:"
        echo "  $0              # Start all services"
        echo "  $0 --core-only  # Start only core network services"
        echo "  $0 --no-web     # Start without web dashboard and SMS simulator"
        echo ""
        exit 0
        ;;
    --core-only)
        print_header
        check_docker
        check_images
        start_core_services
        verify_health
        echo ""
        echo "Core services started. Use '$0' to start remaining services."
        ;;
    --no-web)
        print_header
        check_docker
        check_images
        start_core_services
        start_telecom_services
        
        # Start only VTY proxy, skip web interfaces
        log_info "Starting VTY Proxy only..."
        docker-compose up -d vty-proxy
        wait_for_service "VTY Proxy" 5000
        
        verify_health
        echo ""
        echo "Services started without web interfaces."
        echo "VTY Proxy API: http://localhost:5000"
        ;;
    --force)
        print_header
        log_warning "Force mode: Will continue even if some services fail"
        check_docker
        check_images
        
        # Start all services without waiting
        log_info "Starting all services..."
        docker-compose up -d
        
        # Give them time to start
        log_info "Waiting 30 seconds for services to initialize..."
        sleep 30
        
        verify_health
        show_access_info
        ;;
    "")
        # Default behavior - full startup
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac