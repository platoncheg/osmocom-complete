#!/bin/bash

# Complete Osmocom Mobile Network Shutdown Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}🛑 Shutting down Complete Osmocom Mobile Network...${NC}"

# Function to gracefully stop a service
graceful_stop() {
    local service=$1
    local timeout=${2:-30}
    
    echo -e "${BLUE}📴 Stopping $service...${NC}"
    
    if docker-compose -f docker-compose-complete.yml ps | grep -q "$service.*Up"; then
        # Send graceful shutdown signal
        docker-compose -f docker-compose-complete.yml stop -t $timeout $service
        
        # Check if stopped successfully
        if docker-compose -f docker-compose-complete.yml ps | grep -q "$service.*Up"; then
            echo -e "${YELLOW}⚠️  $service did not stop gracefully, forcing shutdown...${NC}"
            docker-compose -f docker-compose-complete.yml kill $service
        else
            echo -e "${GREEN}✅ $service stopped successfully${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  $service was not running${NC}"
    fi
}

# Function to save service data
backup_data() {
    echo -e "${BLUE}💾 Backing up service data...${NC}"
    
    # Create backup directory with timestamp
    BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup HLR database
    if docker-compose -f docker-compose-complete.yml ps | grep -q "osmo-hlr.*Up"; then
        echo -e "${CYAN}   📋 Backing up HLR subscriber database...${NC}"
        docker-compose -f docker-compose-complete.yml exec -T osmo-hlr \
            sqlite3 /var/lib/osmocom/hlr.db .dump > "$BACKUP_DIR/hlr_backup.sql" 2>/dev/null || \
            echo -e "${YELLOW}   ⚠️  Could not backup HLR database${NC}"
    fi
    
    # Backup SMSC database
    if docker-compose -f docker-compose-complete.yml ps | grep -q "osmo-smsc.*Up"; then
        echo -e "${CYAN}   📨 Backing up SMSC message database...${NC}"
        docker-compose -f docker-compose-complete.yml exec -T osmo-smsc \
            sqlite3 /var/lib/osmocom/smsc.db .dump > "$BACKUP_DIR/smsc_backup.sql" 2>/dev/null || \
            echo -e "${YELLOW}   ⚠️  Could not backup SMSC database${NC}"
    fi
    
    # Backup configuration files
    echo -e "${CYAN}   ⚙️  Backing up configuration files...${NC}"
    cp -r configs/ "$BACKUP_DIR/" 2>/dev/null || echo -e "${YELLOW}   ⚠️  Could not backup configs${NC}"
    
    # Backup logs
    echo -e "${CYAN}   📝 Backing up log files...${NC}"
    cp -r logs/ "$BACKUP_DIR/" 2>/dev/null || echo -e "${YELLOW}   ⚠️  Could not backup logs${NC}"
    
    echo -e "${GREEN}✅ Data backed up to: $BACKUP_DIR${NC}"
}

# Function to collect network statistics
collect_stats() {
    echo -e "${BLUE}📊 Collecting final network statistics...${NC}"
    
    STATS_FILE="network_stats_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "=== OSMOCOM MOBILE NETWORK SHUTDOWN REPORT ==="
        echo "Shutdown Time: $(date)"
        echo "Duration: Network was running since last deployment"
        echo ""
        
        echo "=== CONTAINER STATUS ==="
        docker-compose -f docker-compose-complete.yml ps || true
        echo ""
        
        echo "=== FINAL VTY STATUS ==="
        echo "--- STP Status ---"
        echo "show cs7 instance 0" | timeout 5 nc localhost 4239 2>/dev/null || echo "STP not responding"
        echo ""
        
        echo "--- HLR Subscriber Count ---"
        docker-compose -f docker-compose-complete.yml exec -T osmo-hlr \
            sqlite3 /var/lib/osmocom/hlr.db "SELECT COUNT(*) FROM subscriber;" 2>/dev/null || echo "HLR not accessible"
        echo ""
        
        echo "--- SMSC Message Count ---"
        docker-compose -f docker-compose-complete.yml exec -T osmo-smsc \
            sqlite3 /var/lib/osmocom/smsc.db "SELECT COUNT(*) FROM sms;" 2>/dev/null || echo "SMSC not accessible"
        echo ""
        
        echo "=== RESOURCE USAGE ==="
        docker stats --no-stream 2>/dev/null || echo "Could not collect resource stats"
        echo ""
        
        echo "=== LOG SUMMARY ==="
        echo "Recent log entries from each service:"
        for service in osmo-stp osmo-hlr osmo-msc osmo-smsc; do
            echo "--- $service (last 5 lines) ---"
            docker-compose -f docker-compose-complete.yml logs --tail=5 $service 2>/dev/null || echo "$service logs not available"
            echo ""
        done
        
    } > "$STATS_FILE"
    
    echo -e "${GREEN}✅ Network statistics saved to: $STATS_FILE${NC}"
}

# Main shutdown sequence
main() {
    # Parse command line arguments
    FORCE_SHUTDOWN=false
    SKIP_BACKUP=false
    SKIP_STATS=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                FORCE_SHUTDOWN=true
                shift
                ;;
            --no-backup)
                SKIP_BACKUP=true
                shift
                ;;
            --no-stats)
                SKIP_STATS=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -f, --force      Force immediate shutdown without graceful stop"
                echo "  --no-backup      Skip data backup"
                echo "  --no-stats       Skip statistics collection"
                echo "  -h, --help       Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                    # Normal graceful shutdown with backup"
                echo "  $0 --force           # Force immediate shutdown"
                echo "  $0 --no-backup       # Shutdown without backup"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Unknown option: $1${NC}"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Show current network status
    echo -e "${BLUE}📋 Current network status:${NC}"
    docker-compose -f docker-compose-complete.yml ps 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Could not get container status${NC}"
    }
    echo ""
    
    # Confirm shutdown unless forced
    if [ "$FORCE_SHUTDOWN" = false ]; then
        echo -e "${YELLOW}⚠️  This will shutdown the complete mobile network including:${NC}"
        echo "   - All SS7 signaling (STP)"
        echo "   - Subscriber database (HLR)"
        echo "   - SMS services (SMSC)"
        echo "   - Mobile switching (MSC)"
        echo "   - Base stations (BSC/BTS)"
        echo "   - Packet core (SGSN/GGSN)"
        echo "   - Management interfaces"
        echo ""
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✅ Shutdown cancelled${NC}"
            exit 0
        fi
    fi
    
    # Collect statistics before shutdown
    if [ "$SKIP_STATS" = false ]; then
        collect_stats
    fi
    
    # Backup data before shutdown
    if [ "$SKIP_BACKUP" = false ]; then
        backup_data
    fi
    
    echo -e "\n${BLUE}🛑 Beginning network shutdown sequence...${NC}"
    
    if [ "$FORCE_SHUTDOWN" = true ]; then
        echo -e "${RED}⚡ FORCE MODE: Immediate shutdown${NC}"
        docker-compose -f docker-compose-complete.yml down --timeout 10
    else
        echo -e "${BLUE}🕐 GRACEFUL MODE: Stopping services in dependency order${NC}"
        
        # Shutdown in reverse dependency order
        echo -e "\n${CYAN}Phase 1: Management interfaces${NC}"
        graceful_stop "web-dashboard" 10
        graceful_stop "sms-simulator" 10
        graceful_stop "mobile-simulator" 10
        graceful_stop "network-monitor" 10
        graceful_stop "vty-proxy" 10
        
        echo -e "\n${CYAN}Phase 2: Access network${NC}"
        graceful_stop "osmo-bts" 15
        graceful_stop "osmo-bsc" 15
        
        echo -e "\n${CYAN}Phase 3: Packet core${NC}"
        graceful_stop "osmo-ggsn" 15
        graceful_stop "osmo-sgsn" 15
        
        echo -e "\n${CYAN}Phase 4: Core network services${NC}"
        graceful_stop "osmo-smsc" 20
        graceful_stop "osmo-msc" 20
        
        echo -e "\n${CYAN}Phase 5: Subscriber database${NC}"
        graceful_stop "osmo-hlr" 20
        
        echo -e "\n${CYAN}Phase 6: SS7 signaling${NC}"
        graceful_stop "osmo-stp" 25
        
        # Clean up any remaining containers
        echo -e "\n${BLUE}🧹 Cleaning up remaining containers...${NC}"
        docker-compose -f docker-compose-complete.yml down --remove-orphans
    fi
    
    # Verify shutdown
    echo -e "\n${BLUE}🔍 Verifying shutdown...${NC}"
    REMAINING=$(docker-compose -f docker-compose-complete.yml ps -q 2>/dev/null | wc -l)
    
    if [ "$REMAINING" -eq 0 ]; then
        echo -e "${GREEN}✅ All services stopped successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  $REMAINING containers still running${NC}"
        docker-compose -f docker-compose-complete.yml ps
    fi
    
    # Clean up networks
    echo -e "\n${BLUE}🌐 Cleaning up networks...${NC}"
    docker-compose -f docker-compose-complete.yml down --volumes --remove-orphans 2>/dev/null || true
    
    # Final status
    echo -e "\n${GREEN}🎉 Mobile network shutdown complete!${NC}"
    echo ""
    echo -e "${BLUE}📁 Files preserved:${NC}"
    [ "$SKIP_BACKUP" = false ] && echo "   - Data backup: $(ls -t backup_* 2>/dev/null | head -1 || echo 'No backup created')"
    [ "$SKIP_STATS" = false ] && echo "   - Statistics: $(ls -t network_stats_* 2>/dev/null | head -1 || echo 'No stats collected')"
    echo "   - Configuration: configs/ directory"
    echo "   - Logs: logs/ directory"
    echo "   - Databases: data/ directory"
    echo ""
    echo -e "${BLUE}🚀 To restart the network:${NC}"
    echo "   ./deploy-complete.sh"
    echo ""
    echo -e "${BLUE}📊 To restore from backup:${NC}"
    echo "   # Restore HLR database:"
    echo "   cat backup_*/hlr_backup.sql | docker-compose exec -T osmo-hlr sqlite3 /var/lib/osmocom/hlr.db"
    echo "   # Restore SMSC database:"
    echo "   cat backup_*/smsc_backup.sql | docker-compose exec -T osmo-smsc sqlite3 /var/lib/osmocom/smsc.db"
}

# Handle interruption
trap 'echo -e "\n${RED}🛑 Shutdown interrupted!${NC}"; exit 130' INT TERM

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

# Run main function
main "$@"