#!/bin/bash

# Complete Osmocom Mobile Network Restart Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🔄 Restarting Complete Osmocom Mobile Network...${NC}"

# Function to restart a specific service
restart_service() {
    local service=$1
    local wait_time=${2:-10}
    
    echo -e "${BLUE}🔄 Restarting $service...${NC}"
    
    # Stop the service
    docker-compose -f docker-compose-complete.yml stop $service 2>/dev/null || {
        echo -e "${YELLOW}⚠️  $service was not running${NC}"
    }
    
    # Start the service
    docker-compose -f docker-compose-complete.yml up -d $service
    
    # Wait for service to stabilize
    echo -e "${CYAN}   ⏳ Waiting ${wait_time}s for $service to stabilize...${NC}"
    sleep $wait_time
    
    # Verify service is running
    if docker-compose -f docker-compose-complete.yml ps | grep -q "$service.*Up"; then
        echo -e "${GREEN}   ✅ $service restarted successfully${NC}"
        return 0
    else
        echo -e "${RED}   ❌ $service failed to restart${NC}"
        return 1
    fi
}

# Function to test service connectivity
test_service() {
    local service=$1
    local port=$2
    local name=$3
    
    if timeout 5 bash -c "</dev/tcp/localhost/$port" 2>/dev/null; then
        echo -e "${GREEN}   ✅ $name responding on port $port${NC}"
        return 0
    else
        echo -e "${RED}   ❌ $name not responding on port $port${NC}"
        return 1
    fi
}

# Main restart function
main() {
    # Parse command line arguments
    RESTART_TYPE="full"
    SERVICE_NAME=""
    SKIP_TESTS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service|-s)
                RESTART_TYPE="service"
                SERVICE_NAME="$2"
                shift 2
                ;;
            --core-only)
                RESTART_TYPE="core"
                shift
                ;;
            --interfaces-only)
                RESTART_TYPE="interfaces"
                shift
                ;;
            --skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -s, --service NAME   Restart specific service only"
                echo "  --core-only          Restart only core network services"
                echo "  --interfaces-only    Restart only management interfaces"
                echo "  --skip-tests         Skip connectivity tests after restart"
                echo "  -h, --help           Show this help message"
                echo ""
                echo "Available services:"
                echo "  osmo-stp, osmo-hlr, osmo-msc, osmo-smsc"
                echo "  osmo-bsc, osmo-bts, osmo-sgsn, osmo-ggsn"
                echo "  vty-proxy, web-dashboard, sms-simulator"
                echo ""
                echo "Examples:"
                echo "  $0                           # Full network restart"
                echo "  $0 --service osmo-msc        # Restart MSC only"
                echo "  $0 --core-only              # Restart core services only"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Check if docker-compose file exists
    if [ ! -f "docker-compose-complete.yml" ]; then
        echo -e "${RED}❌ docker-compose-complete.yml not found!${NC}"
        echo "Please run this script from the osmocom-complete directory"
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}❌ Docker is not running${NC}"
        exit 1
    fi
    
    # Show current status
    echo -e "${BLUE}📋 Current network status:${NC}"
    docker-compose -f docker-compose-complete.yml ps 2>/dev/null || true
    echo ""
    
    # Execute restart based on type
    case $RESTART_TYPE in
        "service")
            if [ -z "$SERVICE_NAME" ]; then
                echo -e "${RED}❌ Service name required with --service option${NC}"
                exit 1
            fi
            
            echo -e "${BLUE}🔄 Restarting single service: $SERVICE_NAME${NC}"
            
            if restart_service "$SERVICE_NAME" 15; then
                echo -e "${GREEN}✅ Service $SERVICE_NAME restarted successfully${NC}"
            else
                echo -e "${RED}❌ Failed to restart $SERVICE_NAME${NC}"
                echo "Check logs: docker-compose -f docker-compose-complete.yml logs $SERVICE_NAME"
                exit 1
            fi
            ;;
            
        "core")
            echo -e "${BLUE}🔄 Restarting core network services only${NC}"
            
            # Restart core services in dependency order
            restart_service "osmo-stp" 15
            restart_service "osmo-hlr" 15
            restart_service "osmo-msc" 15
            restart_service "osmo-smsc" 15
            restart_service "osmo-bsc" 10
            restart_service "osmo-bts" 10
            restart_service "osmo-sgsn" 10
            restart_service "osmo-ggsn" 10
            ;;
            
        "interfaces")
            echo -e "${BLUE}🔄 Restarting management interfaces only${NC}"
            
            restart_service "vty-proxy" 10
            restart_service "web-dashboard" 10
            restart_service "sms-simulator" 10
            restart_service "mobile-simulator" 10
            restart_service "network-monitor" 10
            ;;
            
        "full")
            echo -e "${BLUE}🔄 Full network restart${NC}"
            
            # Option 1: Complete restart (faster but less controlled)
            echo -e "${CYAN}Method: Complete restart with dependency ordering${NC}"
            
            # Stop all services
            echo -e "${YELLOW}📴 Stopping all services...${NC}"
            docker-compose -f docker-compose-complete.yml down --remove-orphans
            
            # Start services in dependency order
            echo -e "${YELLOW}🚀 Starting services in dependency order...${NC}"
            
            echo -e "${CYAN}Phase 1: Core SS7 signaling${NC}"
            docker-compose -f docker-compose-complete.yml up -d osmo-stp
            sleep 10
            
            echo -e "${CYAN}Phase 2: Subscriber database${NC}"
            docker-compose -f docker-compose-complete.yml up -d osmo-hlr
            sleep 10
            
            echo -e "${CYAN}Phase 3: Switching and SMS${NC}"
            docker-compose -f docker-compose-complete.yml up -d osmo-msc osmo-smsc
            sleep 15
            
            echo -e "${CYAN}Phase 4: Access network${NC}"
            docker-compose -f docker-compose-complete.yml up -d osmo-bsc osmo-bts
            sleep 10
            
            echo -e "${CYAN}Phase 5: Packet core${NC}"
            docker-compose -f docker-compose-complete.yml up -d osmo-sgsn osmo-ggsn
            sleep 10
            
            echo -e "${CYAN}Phase 6: Management interfaces${NC}"
            docker-compose -f docker-compose-complete.yml up -d vty-proxy web-dashboard sms-simulator mobile-simulator network-monitor
            sleep 15
            ;;
    esac
    
    # Run connectivity tests
    if [ "$SKIP_TESTS" = false ]; then
        echo -e "\n${BLUE}🔍 Testing service connectivity...${NC}"
        
        # Test VTY interfaces
        echo -e "${CYAN}Testing VTY interfaces:${NC}"
        test_service "osmo-stp" 4239 "STP"
        test_service "osmo-hlr" 4258 "HLR"
        test_service "osmo-msc" 4254 "MSC"
        test_service "osmo-smsc" 4259 "SMSC"
        test_service "osmo-bsc" 4242 "BSC"
        test_service "osmo-bts" 4241 "BTS"
        test_service "osmo-sgsn" 4246 "SGSN"
        test_service "osmo-ggsn" 4260 "GGSN"
        
        # Test web interfaces
        echo -e "${CYAN}Testing web interfaces:${NC}"
        test_service "web-dashboard" 8888 "Dashboard"
        test_service "sms-simulator" 9999 "SMS Simulator"
        test_service "vty-proxy" 5000 "VTY Proxy"
        test_service "mobile-simulator" 7777 "Mobile Simulator"
        test_service "network-monitor" 6666 "Network Monitor"
        
        # Test SMPP interface
        echo -e "${CYAN}Testing SMPP interface:${NC}"
        test_service "osmo-smsc" 2775 "SMPP"
        
        # Test basic functionality
        echo -e "\n${CYAN}Testing basic functionality:${NC}"
        
        # Test STP CS7 instance
        if echo "show cs7 instance 0" | timeout 5 nc localhost 4239 2>/dev/null | grep -q "Point Code"; then
            echo -e "${GREEN}   ✅ STP CS7 instance responding${NC}"
        else
            echo -e "${RED}   ❌ STP CS7 instance not responding${NC}"
        fi
        
        # Test HLR database
        if docker-compose -f docker-compose-complete.yml exec -T osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "SELECT COUNT(*) FROM subscriber;" 2>/dev/null | grep -q "[0-9]"; then
            SUBSCRIBER_COUNT=$(docker-compose -f docker-compose-complete.yml exec -T osmo-hlr sqlite3 /var/lib/osmocom/hlr.db "SELECT COUNT(*) FROM subscriber;" 2>/dev/null | tr -d '\r')
            echo -e "${GREEN}   ✅ HLR database accessible ($SUBSCRIBER_COUNT subscribers)${NC}"
        else
            echo -e "${RED}   ❌ HLR database not accessible${NC}"
        fi
        
        # Test SMSC database
        if docker-compose -f docker-compose-complete.yml exec -T osmo-smsc sqlite3 /var/lib/osmocom/smsc.db "SELECT name FROM sqlite_master WHERE type='table';" 2>/dev/null | grep -q "sms"; then
            echo -e "${GREEN}   ✅ SMSC database accessible${NC}"
        else
            echo -e "${RED}   ❌ SMSC database not accessible${NC}"
        fi
    fi
    
    # Final status
    echo -e "\n${GREEN}🎉 Network restart completed!${NC}"
    echo ""
    echo -e "${BLUE}📊 Final service status:${NC}"
    docker-compose -f docker-compose-complete.yml ps
    echo ""
    echo -e "${BLUE}🌐 Access points:${NC}"
    echo "   - Main Dashboard:      http://localhost:8888"
    echo "   - SMS Simulator:       http://localhost:9999"
    echo "   - VTY Proxy API:       http://localhost:5000"
    echo "   - Mobile Simulator:    http://localhost:7777"
    echo "   - Network Monitor:     http://localhost:6666"
    echo ""
    echo -e "${BLUE}📱 Quick tests:${NC}"
    echo "   - Test SMS: python3 test-sms.py --from=+1234567890 --to=+1234567891 --text='Restart test'"
    echo "   - Verify network: ./verify-network.sh"
    echo "   - View logs: docker-compose -f docker-compose-complete.yml logs -f"
}

# Handle interruption
trap 'echo -e "\n${RED}🛑 Restart interrupted!${NC}"; exit 130' INT TERM

# Run main function
main "$@"