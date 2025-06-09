#!/bin/bash

# Osmocom SS7 Stack Docker Deployment Script
set -e

echo "🚀 Deploying Osmocom SS7 Stack with Web Dashboard and SMS Simulator..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker Desktop."
    exit 1
fi

# Create project directory
PROJECT_DIR="osmocom-ss7"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Create logs directory
mkdir -p logs

echo "📁 Created project structure in $PROJECT_DIR"

# Check if dashboard.html exists, if not create a placeholder
if [ ! -f "dashboard.html" ]; then
    echo "📄 Creating dashboard.html file..."
    cat > dashboard.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Dashboard Loading...</title></head>
<body><h1>Dashboard is loading...</h1><p>Please copy the dashboard.html content from the artifacts.</p></body></html>
EOF
    echo "⚠️  Please replace dashboard.html with the complete dashboard content from the artifacts!"
fi

# Check if sms_simulator.html exists, if not create a placeholder
if [ ! -f "sms_simulator.html" ]; then
    echo "📄 Creating sms_simulator.html file..."
    cat > sms_simulator.html << 'EOF'
<!DOCTYPE html>
<html><head><title>SMS Simulator Loading...</title></head>
<body><h1>SMS Simulator is loading...</h1><p>Please copy the sms_simulator.html content from the artifacts.</p></body></html>
EOF
    echo "⚠️  Please replace sms_simulator.html with the complete SMS simulator content from the artifacts!"
fi

# Build and start the containers
echo "🔨 Building Docker images..."
docker-compose build

echo "🚀 Starting SS7 stack, web dashboard, and SMS simulator..."
docker-compose up -d

# Wait for services to start
echo "⏳ Waiting for services to start..."
sleep 20

# Check if containers are running
if docker-compose ps | grep -q "Up"; then
    echo "✅ Osmocom SS7 Stack with Web Dashboard and SMS Simulator is running!"
    echo ""
    echo "📊 Service Status:"
    docker-compose ps
    echo ""
    echo "🌐 Web Interfaces:"
    echo "  - Main Dashboard:      http://localhost:8888"
    echo "  - SMS Simulator:       http://localhost:9999"
    echo "  - VTY Interface:       telnet localhost 4239"
    echo ""
    echo "🔧 Management Commands:"
    echo "  - View all logs:       docker-compose logs -f"
    echo "  - View SS7 logs:       docker-compose logs -f osmo-stp"
    echo "  - View dashboard logs: docker-compose logs -f web-dashboard"
    echo "  - View SMS logs:       docker-compose logs -f sms-simulator"
    echo "  - Stop services:       docker-compose down"
    echo "  - Restart services:    docker-compose restart"
    echo ""
    echo "🌐 Exposed Ports:"
    echo "  - Main Dashboard:      localhost:8888"
    echo "  - SMS Simulator:       localhost:9999"
    echo "  - VTY Interface:       localhost:4239"
    echo "  - M3UA:               localhost:2905"
    echo "  - SCCP:               localhost:14001"
    echo ""
    echo "🧪 Test Connections:"
    echo "  - Main Dashboard:     Open http://localhost:8888 in browser"
    echo "  - SMS Simulator:      Open http://localhost:9999 in browser"
    echo "  - VTY:                telnet localhost 4239"
    echo "    Then run: show cs7 instance 0 users"
    echo ""
    echo "📱 SMS Testing Features:"
    echo "  - Send individual SMS messages"
    echo "  - Generate bulk SMS traffic"
    echo "  - Real-time traffic monitoring"
    echo "  - Protocol stack visualization"
    echo "  - Export traffic logs"
    echo ""
    if ([ ! -s "dashboard.html" ] || grep -q "Dashboard is loading" dashboard.html) || ([ ! -s "sms_simulator.html" ] || grep -q "SMS Simulator is loading" sms_simulator.html); then
        echo "⚠️  IMPORTANT: Replace placeholder files with complete content!"
        if grep -q "Dashboard is loading" dashboard.html; then
            echo "   - Replace dashboard.html with the complete dashboard content"
        fi
        if grep -q "SMS Simulator is loading" sms_simulator.html; then
            echo "   - Replace sms_simulator.html with the complete SMS simulator content"
        fi
        echo "   Then restart: docker-compose restart"
    fi
    echo ""
    echo "🎉 Your complete SS7 SMS testing environment is ready!"
    echo "   📊 Monitor at: http://localhost:8888"
    echo "   📱 SMS Testing at: http://localhost:9999"
else
    echo "❌ Failed to start services. Check logs:"
    docker-compose logs
    exit 1
fi