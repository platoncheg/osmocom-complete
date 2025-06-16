#!/bin/bash

#
# Osmocom Complete Stack Deployment Script
# Deploys complete SS7/GSM testing environment with integrated SMSC
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

check_dependencies() {
    log_info "Checking dependencies..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    log_success "All dependencies are available"
}

check_ports() {
    log_info "Checking for port conflicts..."
    
    ports=(4239 4254 4242 4258 2427 5000 8888 9999 2905 2728 4222 3002 2775)
    conflicts=()
    
    for port in "${ports[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":${port} " || ss -tuln 2>/dev/null | grep -q ":${port} "; then
            conflicts+=($port)
        fi
    done
    
    if [ ${#conflicts[@]} -gt 0 ]; then
        log_warning "Port conflicts detected: ${conflicts[*]}"
        log_warning "These ports are required for the Osmocom stack:"
        echo "  - 4239: OsmoSTP VTY"
        echo "  - 4254: OsmoMSC VTY"
        echo "  - 4242: OsmoBSC VTY"
        echo "  - 4258: OsmoHLR VTY"
        echo "  - 2427: OsmoMGW VTY"
        echo "  - 5000: VTY Proxy HTTP"
        echo "  - 8888: Web Dashboard"
        echo "  - 9999: SMS Simulator"
        echo "  - 2905: M3UA/SCTP"
        echo "  - 2728: MGCP"
        echo "  - 4222: GSUP"
        echo "  - 3002: Abis over IP"
        echo "  - 2775: SMPP (optional)"
        
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "No port conflicts detected"
    fi
}

create_directories() {
    log_info "Creating required directories..."
    
    directories=(
        "docker"
        "config"
        "scripts"
        "web"
        "web/assets"
        "logs"
    )
    
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    # Make management scripts executable
    log_info "Setting up management scripts..."
    management_scripts=("startup.sh" "shutdown.sh" "status.sh" "logs.sh")
    
    for script in "${management_scripts[@]}"; do
        if [ -f "$script" ]; then
            chmod +x "$script"
            log_info "Made $script executable"
        fi
    done
    
    log_success "Directory structure and scripts ready"
}

cleanup_old_deployment() {
    log_info "Cleaning up any existing deployment..."
    
    # Stop and remove containers
    docker-compose -p $PROJECT_NAME down -v 2>/dev/null || true
    
    # Remove orphaned containers
    docker container prune -f &>/dev/null || true
    
    # Remove unused networks
    docker network prune -f &>/dev/null || true
    
    log_success "Cleanup completed"
}

build_images() {
    log_info "Building Docker images..."
    log_info "This may take several minutes on first run..."
    
    # Build images with progress
    if docker-compose build --parallel 2>&1 | while IFS= read -r line; do
        echo "$line"
        if [[ $line == *"Successfully tagged"* ]]; then
            log_success "Image built: $(echo $line | grep -o 'osmocom-complete[^:]*')"
        fi
    done; then
        log_success "All images built successfully"
    else
        log_error "Failed to build images"
        exit 1
    fi
}

deploy_stack() {
    log_info "Deploying Osmocom Complete Stack..."
    
    # Start services in dependency order
    log_info "Starting core network services..."
    docker-compose up -d osmo-stp osmo-hlr osmo-mgw
    
    # Wait for core services
    log_info "Waiting for core services to be ready..."
    sleep 10
    
    # Start MSC and BSC
    log_info "Starting MSC and BSC..."
    docker-compose up -d osmo-msc osmo-bsc
    
    # Wait for telecom services
    log_info "Waiting for telecom services to be ready..."
    sleep 15
    
    # Start management services
    log_info "Starting management services..."
    docker-compose up -d vty-proxy web-dashboard sms-simulator
    
    log_success "Stack deployment completed"
}

wait_for_services() {
    log_info "Waiting for all services to be healthy..."
    
    services=("osmo-stp" "osmo-hlr" "osmo-mgw" "osmo-msc" "osmo-bsc" "vty-proxy" "web-dashboard" "sms-simulator")
    max_attempts=60
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        healthy=0
        total=${#services[@]}
        
        for service in "${services[@]}"; do
            if docker-compose ps $service | grep -q "healthy\|Up"; then
                ((healthy++))
            fi
        done
        
        log_info "Health check: $healthy/$total services ready"
        
        if [ $healthy -eq $total ]; then
            log_success "All services are healthy!"
            return 0
        fi
        
        sleep 5
        ((attempt++))
    done
    
    log_warning "Some services may not be fully ready. Check status manually."
    return 1
}

show_status() {
    log_info "Checking service status..."
    echo ""
    
    docker-compose ps
    echo ""
    
    log_info "Service health status:"
    
    # Check individual services
    services=(
        "osmo-stp:4239:OsmoSTP"
        "osmo-hlr:4258:OsmoHLR" 
        "osmo-mgw:2427:OsmoMGW"
        "osmo-msc:4254:OsmoMSC"
        "osmo-bsc:4242:OsmoBSC"
        "vty-proxy:5000:VTY Proxy"
        "web-dashboard:8888:Dashboard"
        "sms-simulator:9999:SMS Simulator"
    )
    
    for service_info in "${services[@]}"; do
        IFS=':' read -r container port name <<< "$service_info"
        
        if docker-compose ps $container | grep -q "Up"; then
            if nc -z localhost $port 2>/dev/null; then
                echo -e "${GREEN}✓${NC} $name: Running and accessible on port $port"
            else
                echo -e "${YELLOW}⚠${NC} $name: Running but port $port not accessible"
            fi
        else
            echo -e "${RED}✗${NC} $name: Not running"
        fi
    done
    
    echo ""
}

show_access_info() {
    log_success "Osmocom Complete Stack is ready!"
    echo ""
    echo "=== Access Information ==="
    echo ""
    echo "📊 Web Dashboard (Real-time monitoring):"
    echo "   http://localhost:8888"
    echo ""
    echo "📱 SMS Simulator (Traffic testing):"
    echo "   http://localhost:9999"
    echo ""
    echo "🔌 VTY Proxy API (HTTP interface):"
    echo "   http://localhost:5000"
    echo "   Health check: curl http://localhost:5000/health"
    echo ""
    echo "💻 Direct VTY Access:"
    echo "   OsmoSTP:  telnet localhost 4239"
    echo "   OsmoMSC:  telnet localhost 4254"
    echo "   OsmoBSC:  telnet localhost 4242"
    echo "   OsmoHLR:  telnet localhost 4258"
    echo "   OsmoMGW:  telnet localhost 2427"
    echo ""
    echo "=== Key Features ==="
    echo ""
    echo "🔧 Integrated SMSC: Built into OsmoMSC for SMS handling"
    echo "📡 SS7 Network: Complete signaling setup with STP"
    echo "📞 Voice Support: MGW for RTP media handling"
    echo "👥 Subscriber Management: HLR with test subscribers"
    echo "🧪 SMS Testing: Web interface and CLI tools"
    echo "📈 Real-time Monitoring: Live status and statistics"
    echo ""
    echo "=== Test Subscribers ==="
    echo ""
    echo "IMSI: 001010000000001, MSISDN: 1001"
    echo "IMSI: 001010000000002, MSISDN: 1002"
    echo "IMSI: 001010000000003, MSISDN: 1003"
    echo ""
    echo "=== Quick Tests ==="
    echo ""
    echo "1. Check system health:"
    echo "   curl http://localhost:5000/health"
    echo ""
    echo "2. Send test SMS via CLI:"
    echo "   docker-compose exec sms-simulator python3 /app/sms_simulator.py --mode single --from 1001 --to 1002"
    echo ""
    echo "3. Generate SMS traffic:"
    echo "   docker-compose exec sms-simulator python3 /app/sms_simulator.py --mode traffic --tps 10 --duration 60"
    echo ""
    echo "4. Interactive SMS testing:"
    echo "   docker-compose exec sms-simulator python3 /app/sms_simulator.py --mode interactive"
    echo ""
    echo "=== Management Commands ==="
    echo ""
    echo "View logs:         docker-compose logs -f"
    echo "Stop stack:        docker-compose down"
    echo "Restart service:   docker-compose restart <service>"
    echo "Scale testing:     docker-compose up -d --scale sms-simulator=3"
    echo ""
    echo "📚 Documentation: Check README.md for detailed information"
    echo ""
}

show_troubleshooting() {
    echo ""
    echo "=== Troubleshooting ==="
    echo ""
    echo "If services are not starting properly:"
    echo ""
    echo "1. Check Docker resources:"
    echo "   docker system df"
    echo "   docker stats"
    echo ""
    echo "2. View service logs:"
    echo "   docker-compose logs osmo-stp"
    echo "   docker-compose logs osmo-msc"
    echo "   docker-compose logs vty-proxy"
    echo ""
    echo "3. Restart problematic services:"
    echo "   docker-compose restart osmo-msc"
    echo ""
    echo "4. Full cleanup and redeploy:"
    echo "   docker-compose down -v"
    echo "   docker system prune -f"
    echo "   ./deploy.sh"
    echo ""
    echo "5. Check port conflicts:"
    echo "   netstat -tuln | grep -E '(4239|4254|4242|4258|2427|5000|8888|9999)'"
    echo ""
}

# Main deployment function
main() {
    echo ""
    echo "🚀 Osmocom Complete Stack Deployment"
    echo "====================================="
    echo ""
    echo "This will deploy a complete SS7/GSM testing environment with:"
    echo "- OsmoSTP (SS7 Signaling Transfer Point)"
    echo "- OsmoMSC (Mobile Switching Center with integrated SMSC)"
    echo "- OsmoBSC (Base Station Controller)"
    echo "- OsmoMGW (Media Gateway)"
    echo "- OsmoHLR (Home Location Register)"
    echo "- Web Dashboard (Real-time monitoring)"
    echo "- SMS Simulator (Traffic testing)"
    echo "- VTY Proxy (HTTP API)"
    echo ""
    
    # Check if running as root (not recommended)
    if [ "$EUID" -eq 0 ]; then
        log_warning "Running as root is not recommended for Docker operations"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Run deployment steps
    check_dependencies
    check_ports
    create_directories
    cleanup_old_deployment
    build_images
    deploy_stack
    
    # Wait for services and show status
    if wait_for_services; then
        show_status
        show_access_info
    else
        show_status
        show_troubleshooting
        log_warning "Deployment completed with warnings. Some services may need additional time to start."
    fi
}

# Script options
case "${1:-}" in
    --help|-h)
        echo "Osmocom Complete Stack Deployment Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --status       Show current deployment status"
        echo "  --stop         Stop the stack"
        echo "  --restart      Restart the stack"
        echo "  --cleanup      Clean up everything and redeploy"
        echo "  --logs         Show logs from all services"
        echo ""
        exit 0
        ;;
    --status)
        show_status
        exit 0
        ;;
    --stop)
        log_info "Stopping Osmocom Complete Stack..."
        docker-compose down
        log_success "Stack stopped"
        exit 0
        ;;
    --restart)
        log_info "Restarting Osmocom Complete Stack..."
        docker-compose restart
        wait_for_services
        show_status
        exit 0
        ;;
    --cleanup)
        log_info "Performing full cleanup and redeployment..."
        cleanup_old_deployment
        docker system prune -f
        main
        exit 0
        ;;
    --logs)
        log_info "Showing logs from all services..."
        docker-compose logs -f
        exit 0
        ;;
    "")
        # Default behavior - run main deployment
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac