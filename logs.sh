#!/bin/bash

#
# Osmocom Complete Stack - Logs Management Script
# View, filter, and manage container logs
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
    echo "📋 Osmocom Complete Stack - Logs Manager"
    echo "========================================="
    echo ""
}

show_help() {
    echo "Osmocom Complete Stack - Logs Management Script"
    echo ""
    echo "Usage: $0 [SERVICE] [OPTIONS]"
    echo ""
    echo "Services:"
    echo "  stp, osmo-stp          OsmoSTP (SS7 Signaling Transfer Point)"
    echo "  msc, osmo-msc          OsmoMSC (Mobile Switching Center + SMSC)"
    echo "  bsc, osmo-bsc          OsmoBSC (Base Station Controller)"
    echo "  hlr, osmo-hlr          OsmoHLR (Home Location Register)"
    echo "  mgw, osmo-mgw          OsmoMGW (Media Gateway)"
    echo "  proxy, vty-proxy       VTY Proxy (HTTP-VTY Bridge)"
    echo "  dashboard, web         Web Dashboard"
    echo "  sms, simulator         SMS Simulator"
    echo "  all                    All services"
    echo ""
    echo "Options:"
    echo "  --help, -h             Show this help message"
    echo "  --follow, -f           Follow log output (live mode)"
    echo "  --tail N               Show last N lines (default: 50)"
    echo "  --since TIME           Show logs since timestamp (e.g., '1h', '30m', '2024-01-01')"
    echo "  --grep PATTERN         Filter logs by pattern"
    echo "  --errors               Show only error messages"
    echo "  --warnings             Show only warnings and errors"
    echo "  --no-color             Disable colored output"
    echo "  --timestamps           Show timestamps"
    echo "  --export FILE          Export logs to file"
    echo ""
    echo "Examples:"
    echo "  $0 msc                 # Show MSC logs"
    echo "  $0 all --follow        # Follow all service logs"
    echo "  $0 stp --tail 100      # Show last 100 lines from STP"
    echo "  $0 all --since 1h      # Show logs from last hour"
    echo "  $0 msc --grep SMS      # Filter MSC logs for SMS messages"
    echo "  $0 all --errors        # Show only error messages from all services"
    echo "  $0 msc --export msc.log # Export MSC logs to file"
    echo ""
}

get_service_name() {
    local service=$1
    
    case $service in
        "stp"|"osmo-stp")
            echo "osmo-stp"
            ;;
        "msc"|"osmo-msc")
            echo "osmo-msc"
            ;;
        "bsc"|"osmo-bsc")
            echo "osmo-bsc"
            ;;
        "hlr"|"osmo-hlr")
            echo "osmo-hlr"
            ;;
        "mgw"|"osmo-mgw")
            echo "osmo-mgw"
            ;;
        "proxy"|"vty-proxy")
            echo "vty-proxy"
            ;;
        "dashboard"|"web"|"web-dashboard")
            echo "web-dashboard"
            ;;
        "sms"|"simulator"|"sms-simulator")
            echo "sms-simulator"
            ;;
        "all")
            echo "all"
            ;;
        *)
            echo ""
            ;;
    esac
}

check_service_exists() {
    local service=$1
    
    if [ "$service" = "all" ]; then
        return 0
    fi
    
    if docker-compose ps $service >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

build_docker_logs_command() {
    local service=$1
    local follow=$2
    local tail_lines=$3
    local since_time=$4
    local timestamps=$5
    local no_color=$6
    
    local cmd="docker-compose logs"
    
    if [ "$timestamps" = "true" ]; then
        cmd="$cmd --timestamps"
    fi
    
    if [ "$no_color" = "true" ]; then
        cmd="$cmd --no-color"
    fi
    
    if [ "$follow" = "true" ]; then
        cmd="$cmd --follow"
    fi
    
    if [ -n "$tail_lines" ]; then
        cmd="$cmd --tail $tail_lines"
    fi
    
    if [ -n "$since_time" ]; then
        cmd="$cmd --since $since_time"
    fi
    
    if [ "$service" != "all" ]; then
        cmd="$cmd $service"
    fi
    
    echo "$cmd"
}

filter_logs() {
    local grep_pattern=$1
    local errors_only=$2
    local warnings_only=$3
    
    local filter_cmd=""
    
    if [ "$errors_only" = "true" ]; then
        filter_cmd="grep -i 'error\|fatal\|critical'"
    elif [ "$warnings_only" = "true" ]; then
        filter_cmd="grep -i 'error\|fatal\|critical\|warning\|warn'"
    elif [ -n "$grep_pattern" ]; then
        filter_cmd="grep -i '$grep_pattern'"
    else
        filter_cmd="cat"
    fi
    
    echo "$filter_cmd"
}

show_logs() {
    local service=$1
    local follow=${2:-false}
    local tail_lines=${3:-50}
    local since_time=$4
    local grep_pattern=$5
    local errors_only=${6:-false}
    local warnings_only=${7:-false}
    local timestamps=${8:-false}
    local no_color=${9:-false}
    local export_file=$10
    
    # Build Docker logs command
    local logs_cmd
    logs_cmd=$(build_docker_logs_command "$service" "$follow" "$tail_lines" "$since_time" "$timestamps" "$no_color")
    
    # Build filter command
    local filter_cmd
    filter_cmd=$(filter_logs "$grep_pattern" "$errors_only" "$warnings_only")
    
    log_info "Showing logs for: $service"
    
    if [ "$follow" = "true" ]; then
        log_info "Following logs (Ctrl+C to exit)..."
    fi
    
    if [ -n "$export_file" ]; then
        log_info "Exporting logs to: $export_file"
        
        # Export without follow mode
        local export_logs_cmd
        export_logs_cmd=$(build_docker_logs_command "$service" "false" "$tail_lines" "$since_time" "$timestamps" "true")
        
        eval "$export_logs_cmd" | eval "$filter_cmd" > "$export_file"
        log_success "Logs exported to $export_file"
        return
    fi
    
    echo ""
    echo "=== Log Output ==="
    echo ""
    
    # Execute the command with filtering
    eval "$logs_cmd" | eval "$filter_cmd"
}

show_service_list() {
    echo ""
    echo "Available services:"
    echo ""
    
    local services=("osmo-stp" "osmo-hlr" "osmo-mgw" "osmo-msc" "osmo-bsc" "vty-proxy" "web-dashboard" "sms-simulator")
    
    for service in "${services[@]}"; do
        if check_service_exists "$service"; then
            local status
            if docker-compose ps $service | grep -q "Up"; then
                status="${GREEN}running${NC}"
            else
                status="${RED}stopped${NC}"
            fi
            echo -e "  $service - $status"
        else
            echo -e "  $service - ${YELLOW}not found${NC}"
        fi
    done
    
    echo ""
}

interactive_mode() {
    print_header
    
    echo "Interactive Logs Viewer"
    echo ""
    
    while true; do
        echo ""
        echo "Available commands:"
        echo "  1. Show service list"
        echo "  2. View logs for specific service"
        echo "  3. Follow all logs"
        echo "  4. Search logs"
        echo "  5. Export logs"
        echo "  q. Quit"
        echo ""
        
        read -p "Select option: " choice
        
        case $choice in
            1)
                show_service_list
                ;;
            2)
                echo ""
                read -p "Enter service name: " service_name
                local normalized_service
                normalized_service=$(get_service_name "$service_name")
                
                if [ -z "$normalized_service" ]; then
                    log_error "Invalid service name: $service_name"
                    continue
                fi
                
                if ! check_service_exists "$normalized_service"; then
                    log_error "Service not found: $normalized_service"
                    continue
                fi
                
                echo ""
                read -p "Number of lines to show (default 50): " tail_lines
                tail_lines=${tail_lines:-50}
                
                show_logs "$normalized_service" false "$tail_lines"
                ;;
            3)
                echo ""
                log_info "Following all service logs (Ctrl+C to stop)..."
                show_logs "all" true
                ;;
            4)
                echo ""
                read -p "Enter service name (or 'all'): " service_name
                read -p "Enter search pattern: " search_pattern
                
                local normalized_service
                normalized_service=$(get_service_name "$service_name")
                
                if [ -z "$normalized_service" ]; then
                    log_error "Invalid service name: $service_name"
                    continue
                fi
                
                show_logs "$normalized_service" false 100 "" "$search_pattern"
                ;;
            5)
                echo ""
                read -p "Enter service name (or 'all'): " service_name
                read -p "Enter export filename: " export_filename
                
                local normalized_service
                normalized_service=$(get_service_name "$service_name")
                
                if [ -z "$normalized_service" ]; then
                    log_error "Invalid service name: $service_name"
                    continue
                fi
                
                show_logs "$normalized_service" false 1000 "" "" false false false true "$export_filename"
                ;;
            q|Q|quit|exit)
                echo "Goodbye!"
                break
                ;;
            *)
                log_error "Invalid option: $choice"
                ;;
        esac
    done
}

# Main function
main() {
    local service=""
    local follow=false
    local tail_lines=50
    local since_time=""
    local grep_pattern=""
    local errors_only=false
    local warnings_only=false
    local timestamps=false
    local no_color=false
    local export_file=""
    local interactive=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --follow|-f)
                follow=true
                shift
                ;;
            --tail)
                tail_lines="$2"
                shift 2
                ;;
            --since)
                since_time="$2"
                shift 2
                ;;
            --grep)
                grep_pattern="$2"
                shift 2
                ;;
            --errors)
                errors_only=true
                shift
                ;;
            --warnings)
                warnings_only=true
                shift
                ;;
            --timestamps)
                timestamps=true
                shift
                ;;
            --no-color)
                no_color=true
                shift
                ;;
            --export)
                export_file="$2"
                shift 2
                ;;
            --interactive|-i)
                interactive=true
                shift
                ;;
            *)
                if [ -z "$service" ]; then
                    service="$1"
                else
                    log_error "Unknown argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Interactive mode
    if [ "$interactive" = "true" ]; then
        interactive_mode
        exit 0
    fi
    
    # Default to interactive mode if no service specified
    if [ -z "$service" ]; then
        interactive_mode
        exit 0
    fi
    
    # Normalize service name
    local normalized_service
    normalized_service=$(get_service_name "$service")
    
    if [ -z "$normalized_service" ]; then
        log_error "Invalid service name: $service"
        echo ""
        show_help
        exit 1
    fi
    
    # Check if service exists
    if ! check_service_exists "$normalized_service"; then
        log_error "Service not found: $normalized_service"
        show_service_list
        exit 1
    fi
    
    # Show logs
    show_logs "$normalized_service" "$follow" "$tail_lines" "$since_time" "$grep_pattern" \
              "$errors_only" "$warnings_only" "$timestamps" "$no_color" "$export_file"
}

# Run main function with all arguments
main "$@"