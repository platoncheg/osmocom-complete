#!/bin/bash

#
# Osmocom Complete Stack - Shutdown Script
# Gracefully stop all services in reverse dependency order
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
    echo "🛑 Osmocom Complete Stack - Shutdown"
    echo "====================================="
    echo ""
}

check_running_services() {
    log_info "Checking running services..."
    
    local running_services
    running_services=$(docker-compose ps --services --filter "status=running" 2>/dev/null || echo "")
    
    if [ -z "$running_services" ]; then
        log_warning "No services are currently running"
        return 1
    fi
    
    echo "Running services:"
    echo "$running_services" | while read -r service; do
        echo "  - $service"
    done
    echo ""
    
    return 0
}

wait_for_service_stop() {
    local service=$1
    local timeout=${2:-30}
    
    log_info "Waiting for $service to stop..."
    
    local counter=0
    while [ $counter -lt $timeout ]; do
        if ! docker-compose ps $service | grep -q "Up"; then
            log_success "$service stopped"
            return 0
        fi
        
        sleep 1
        counter=$((counter + 1))
        
        # Show progress every 5 seconds
        if [ $((counter % 5)) -eq 0 ]; then
            log_info "Still waiting for $service to stop... (${counter}s/${timeout}s)"
        fi
    done
    
    log_warning "$service did not stop gracefully within ${timeout}s"
    return 1
}

stop_web_services() {
    log_info "Stopping web and management services..."
    
    # Stop web interfaces first (least critical)
    services=("sms-simulator" "web-dashboard" "vty-proxy")
    
    for service in "${services[@]}"; do
        if docker-compose ps $service | grep -q "Up"; then
            log_info "Stopping $service..."
            docker-compose stop $service
            wait_for_service_stop $service 15
        fi
    done
    
    log_success "Web services stopped"
}

stop_radio_services() {
    log_info "Stopping radio access network services..."
    
    # Stop mobile emulator first (depends on BTS)
    if docker-compose ps osmocom-bb | grep -q "Up"; then
        log_info "Stopping OsmocomBB (Mobile Station Emulator)..."
        docker-compose stop osmocom-bb
        wait_for_service_stop osmocom-bb 15
    fi
    
    # Then stop BTS (depends on BSC)
    if docker-compose ps osmo-bts | grep -q "Up"; then
        log_info "Stopping BTS (Base Transceiver Station)..."
        docker-compose stop osmo-bts
        wait_for_service_stop osmo-bts 20
    fi
    
    log_success "Radio access network services stopped"
}

stop_telecom_services() {
    log_info "Stopping telecom services..."
    
    # Stop BSC (depends on MSC)
    if docker-compose ps osmo-bsc | grep -q "Up"; then
        log_info "Stopping BSC (Base Station Controller)..."
        docker-compose stop osmo-bsc
        wait_for_service_stop osmo-bsc 20
    fi
    
    # Then stop MSC
    if docker-compose ps osmo-msc | grep -q "Up"; then
        log_info "Stopping MSC (Mobile Switching Center with SMSC)..."
        docker-compose stop osmo-msc
        wait_for_service_stop osmo-msc 25
    fi
    
    log_success "Telecom services stopped"
}

stop_core_services() {
    log_info "Stopping core network services..."
    
    # Stop core services in reverse dependency order
    services=("osmo-mgw" "osmo-hlr" "osmo-stp")
    
    for service in "${services[@]}"; do
        if docker-compose ps $service | grep -q "Up"; then
            case $service in
                "osmo-mgw")
                    log_info "Stopping MGW (Media Gateway)..."
                    ;;
                "osmo-hlr")
                    log_info "Stopping HLR (Home Location Register)..."
                    ;;
                "osmo-stp")
                    log_info "Stopping STP (SS7 Signaling Transfer Point)..."
                    ;;
            esac
            
            docker-compose stop $service
            wait_for_service_stop $service 20
        fi
    done
    
    log_success "Core services stopped"
}

force_stop_all() {
    log_warning "Force stopping all containers..."
    
    docker-compose kill
    docker-compose down
    
    log_success "All containers force stopped"
}

cleanup_containers() {
    log_info "Cleaning up stopped containers..."
    
    # Remove stopped containers
    docker-compose down --remove-orphans
    
    log_success "Container cleanup completed"
}

cleanup_networks() {
    log_info "Cleaning up Docker networks..."
    
    # Remove project networks
    docker network ls --filter "name=${PROJECT_NAME}" --format "{{.Name}}" | while read -r network; do
        if [ -n "$network" ]; then
            log_info "Removing network: $network"
            docker network rm "$network" 2>/dev/null || log_warning "Could not remove network: $network"
        fi
    done
    
    # Prune unused networks
    docker network prune -f >/dev/null 2>&1
    
    log_success "Network cleanup completed"
}

cleanup_volumes() {
    log_info "Cleaning up Docker volumes..."
    
    # List project volumes
    local volumes
    volumes=$(docker volume ls --filter "name=${PROJECT_NAME}" --format "{{.Name}}" 2>/dev/null || echo "")
    
    if [ -n "$volumes" ]; then
        echo "Project volumes found:"
        echo "$volumes" | while read -r volume; do
            echo "  - $volume"
        done
        echo ""
        
        read -p "Remove project volumes? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "$volumes" | while read -r volume; do
                log_info "Removing volume: $volume"
                docker volume rm "$volume" 2>/dev/null || log_warning "Could not remove volume: $volume"
            done
            log_success "Volume cleanup completed"
        else
            log_info "Volume cleanup skipped"
        fi
    else
        log_info "No project volumes found"
    fi
}

show_final_status() {
    log_info "Final status check..."
    
    local running_containers
    running_containers=$(docker-compose ps --services --filter "status=running" 2>/dev/null || echo "")
    
    if [ -z "$running_containers" ]; then
        echo ""
        echo "🎉 Shutdown completed successfully!"
        echo ""
        echo "All Osmocom services have been stopped."
        echo ""
        echo "To start the stack again:"
        echo "  ./startup.sh"
        echo ""
        echo "To deploy from scratch:"
        echo "  ./deploy.sh"
        echo ""
    else
        echo ""
        echo "⚠️  Some containers are still running:"
        echo "$running_containers"
        echo ""
        echo "You may need to force stop them:"
        echo "  ./shutdown.sh --force"
        echo ""
    fi
}

# Main shutdown function
main() {
    print_header
    
    if ! check_running_services; then
        echo "Nothing to shutdown."
        exit 0
    fi
    
    # Ask for confirmation unless forced
    if [ "${1:-}" != "--force" ] && [ "${1:-}" != "--yes" ]; then
        read -p "Are you sure you want to shutdown all Osmocom services? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Shutdown cancelled"
            exit 0
        fi
    fi
    
    # Graceful shutdown in proper reverse dependency order
    stop_web_services
    stop_radio_services
    stop_telecom_services
    stop_core_services
    
    # Final cleanup
    cleanup_containers
    
    show_final_status
}

# Script options
case "${1:-}" in
    --help|-h)
        echo "Osmocom Complete Stack - Shutdown Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h       Show this help message"
        echo "  --force          Force immediate shutdown (no graceful stop)"
        echo "  --yes            Skip confirmation prompt"
        echo "  --clean          Also remove volumes and networks"
        echo "  --web-only       Stop only web services (dashboard, simulator)"
        echo "  --radio-only     Stop only radio services (BTS, mobile emulator)"
        echo "  --core-only      Stop only core services (keep web running)"
        echo ""
        echo "Examples:"
        echo "  $0               # Graceful shutdown with confirmation"
        echo "  $0 --yes         # Graceful shutdown without confirmation"
        echo "  $0 --force       # Immediate force shutdown"
        echo "  $0 --clean       # Shutdown and clean up volumes"
        echo "  $0 --radio-only  # Stop mobile and BTS only"
        echo ""
        exit 0
        ;;
    --force)
        print_header
        log_warning "Force shutdown initiated"
        force_stop_all
        cleanup_containers
        show_final_status
        ;;
    --yes)
        main --yes
        ;;
    --clean)
        print_header
        log_info "Shutdown with cleanup initiated"
        
        if check_running_services; then
            main --yes
        fi
        
        cleanup_networks
        cleanup_volumes
        
        log_success "Complete cleanup finished"
        ;;
    --web-only)
        print_header
        log_info "Stopping web services only..."
        stop_web_services
        echo ""
        echo "Web services stopped. Core network services are still running."
        echo "Access via VTY: telnet localhost 4239/4254/4242/4241/4247/4258/2427"
        ;;
    --radio-only)
        print_header
        log_info "Stopping radio access network services only..."
        stop_radio_services
        echo ""
        echo "Radio services stopped. Core network and web services are still running."
        echo "Mobile emulator and BTS are now offline."
        echo ""
        echo "To restart radio services:"
        echo "  docker-compose up -d osmo-bts osmocom-bb"
        ;;
    --core-only)
        print_header
        log_info "Stopping core services only..."
        
        read -p "This will stop core services but may leave web and radio services in error state. Continue? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            stop_core_services
            echo ""
            echo "Core services stopped. Web and radio services may show errors."
        else
            log_info "Operation cancelled"
        fi
        ;;
    "")
        # Default behavior - graceful shutdown with confirmation
        main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac