#!/bin/bash

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Osmocom Complete Stack Deployment${NC}"
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

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}





# Main deployment function
main() {
    print_info "Checking dependencies..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    print_success "All dependencies are available"
    
    print_info "Checking for port conflicts..."
    # Check if required ports are available
    for port in 4239 2905 14001 8888 9999 5000; do
        if netstat -tuln 2>/dev/null | grep -q ":$port " || lsof -i :$port 2>/dev/null | grep -q LISTEN; then
            print_warning "Port $port is already in use. This may cause conflicts."
        fi
    done
    print_success "Port check completed"
    
    print_info "Creating required directories..."
    mkdir -p logs web/assets
    print_success "Directory structure ready"
    
    print_info "Setting up management scripts..."
    # Make other scripts executable if they exist
    for script in startup.sh shutdown.sh status.sh logs.sh; do
        if [ -f "$script" ]; then
            chmod +x "$script"
            print_info "Made $script executable"
        fi
    done
    print_success "Scripts ready"
    
    print_info "Cleaning up any existing deployment..."
    docker-compose down -v 2>/dev/null || true
    docker system prune -f 2>/dev/null || true
    print_success "Cleanup completed"
    
    print_info "Building Docker images..."
    print_info "This may take several minutes on first run..."
    
    if docker-compose build --no-cache; then
        print_success "All images built successfully"
    else
        print_error "Failed to build some images. Check the logs above."
        exit 1
    fi
    
    print_info "Deploying Osmocom Complete Stack..."
    print_info "Starting core network services..."
    
    if docker-compose up -d; then
        print_success "Deployment completed successfully!"
        
        echo ""
        echo "🎉 Your Osmocom SS7 testing environment is now running!"
        echo ""
        echo "Access your services:"
        echo "  📊 Real-time Dashboard: http://localhost:8888"
        echo "  📱 SMS Simulator: http://localhost:9999"
        echo "  🔌 VTY Proxy API: http://localhost:5000"
        echo "  💻 VTY Direct: telnet localhost 4239"
        echo ""
        echo "Useful commands:"
        echo "  🔍 Check status: docker-compose ps"
        echo "  📋 View logs: docker-compose logs -f"
        echo "  🛑 Stop services: docker-compose down"
        echo ""
        
        # Wait a moment for services to start
        sleep 5
        
        print_info "Service status:"
        docker-compose ps
        
    else
        print_error "Failed to start services. Check logs with: docker-compose logs"
        exit 1
    fi
}

# Run the main deployment
main "$@"