# Osmocom SS7 Stack - Complete Testing Environment

This project provides a comprehensive dockerized SS7 testing environment with real-time monitoring, SMS simulation, and management tools for macOS.

## 🚀 Quick Start

1. **Clone this repository and navigate to the project directory:**
   ```bash
   mkdir osmocom-ss7 && cd osmocom-ss7
   ```

2. **Copy all the provided files into this directory**

3. **Make the deployment script executable:**
   ```bash
   chmod +x deploy.sh
   ```

4. **Deploy the complete stack:**
   ```bash
   ./deploy.sh
   ```

5. **Access your services:**
   - **📊 Real-time Dashboard**: http://localhost:8888
   - **📱 SMS Simulator**: http://localhost:9999
   - **🔌 VTY Proxy API**: http://localhost:5000
   - **💻 VTY Direct**: `telnet localhost 4239`

## 📁 Project Structure

```
osmocom-ss7/
├── Dockerfile                    # Main SS7 stack container
├── Dockerfile.dashboard          # Web dashboard container
├── Dockerfile.sms               # SMS simulator container  
├── Dockerfile.proxy             # VTY proxy server container
├── docker-compose.yml           # Multi-service orchestration
├── osmo-stp.cfg                 # SS7 service configuration
├── deploy.sh                    # Automated deployment script
├── dashboard.html               # Real-time SS7 monitoring dashboard
├── sms_simulator.html           # SMS traffic simulation interface
├── vty_proxy.py                 # Python VTY proxy server
├── ss7_sms_simulator.py         # Python CLI SMS simulator
├── README.md                    # This documentation
└── logs/                        # Log files directory (auto-created)
```

## 🐳 Services Architecture

| Service | Container | Port | Description |
|---------|-----------|------|-------------|
| **osmo-stp** | SS7 Stack | 4239, 2905, 14001 | Main SS7 signaling transfer point |
| **vty-proxy** | Python Flask | 5000 | HTTP bridge to VTY interface |
| **web-dashboard** | nginx + HTML | 8888 | Real-time monitoring dashboard |
| **sms-simulator** | nginx + HTML | 9999 | SMS traffic simulation interface |

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Web Browser   │────│  Web Dashboard  │────│   VTY Proxy     │
│  (localhost:8888)│    │  (nginx:80)     │    │  (python:5000)  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                |                       |
                                └───────────────────────┼───────────┐
                                                        │           │
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐   │
│   SMS Browser   │────│  SMS Simulator  │    │   osmo-stp      │───┘
│  (localhost:9999)│    │  (nginx:80)     │    │  (ubuntu:4239)  │VTY
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                |                       |
                                └───────────────────────┘
                                      Docker Network
                                      (172.20.0.0/16)
```

## 🌟 Key Features

### ✅ **Real-time SS7 Monitoring**
- **Live VTY connection** via proxy server
- **Real-time status updates** that reflect actual service state
- **Interactive command interface** with command history
- **Protocol stack visualization** with live data
- **Connection health monitoring** with auto-reconnect

### ✅ **SMS Traffic Simulation**
- **Individual SMS sending** with full parameter control
- **Bulk traffic generation** with customizable patterns
- **Traffic templates** for different message types
- **Real-time statistics** and performance monitoring
- **Export capabilities** for analysis

### ✅ **Production-Ready Infrastructure**
- **Docker containerization** for consistent deployment
- **Service orchestration** with Docker Compose
- **Health monitoring** and auto-restart policies
- **Persistent logging** with volume mounts
- **Network isolation** with custom bridge network

## 📊 Dashboard Features

### **System Status Monitoring**
- **Service health** indicators (connected/disconnected states)
- **CS7 instance** status and configuration
- **ASP/AS status** with real-time updates
- **SCCP users** and routing information

### **Interactive VTY Interface**
- **Direct command execution** via web interface
- **Quick command buttons** for common operations
- **Real-time output** with proper formatting
- **Command history** and auto-completion

### **Quick Commands Available**
- `show cs7 instance 0 users` - Display CS7 users
- `show cs7 instance 0 asp` - Show ASP status
- `show cs7 instance 0 as all` - Display all Application Servers
- `show cs7 instance 0 sccp users` - Show SCCP users
- `show cs7 instance 0 route` - Display routing table
- `show running-config` - Show current configuration
- `show stats` - Display system statistics

## 📱 SMS Simulator Features

### **Message Composition**
- **Flexible sender/recipient** number configuration
- **Message type selection** (SMS-SUBMIT, SMS-DELIVER, STATUS-REPORT)
- **Priority levels** and encoding options
- **SMSC configuration** for routing

### **Traffic Generation**
- **Configurable TPS** (Transactions Per Second) rates
- **Duration-based** traffic generation
- **Pattern-based** message generation
- **Error rate simulation** for realistic testing

### **Message Templates**
- **Welcome messages** for subscriber onboarding
- **OTP verification** with random code generation
- **Promotional messages** with marketing content
- **System alerts** for notifications
- **Balance inquiries** with account information
- **Unicode testing** for international messaging

### **Statistics and Monitoring**
- **Real-time counters** for sent/received/failed messages
- **Success rate** calculation and trending
- **TPS monitoring** with live updates
- **Traffic log** with detailed message information
- **Export functionality** for analysis

## 🛠️ Management Commands

### **Docker Operations**
```bash
# Deploy entire stack
./deploy.sh

# View all services status
docker-compose ps

# View logs from all services
docker-compose logs -f

# View specific service logs
docker-compose logs -f osmo-stp
docker-compose logs -f vty-proxy
docker-compose logs -f web-dashboard
docker-compose logs -f sms-simulator

# Restart specific service
docker-compose restart osmo-stp

# Stop all services
docker-compose down

# Rebuild and restart
docker-compose build --no-cache
docker-compose up -d
```

### **VTY Access**
```bash
# Direct VTY access
telnet localhost 4239

# Common VTY commands
show cs7 instance 0 users
show cs7 instance 0 asp
show cs7 instance 0 as all
show running-config
```

### **SMS Testing**
```bash
# CLI SMS simulator
python3 ss7_sms_simulator.py --help

# Send bulk SMS
python3 ss7_sms_simulator.py --mode bulk --count 100

# Generate traffic
python3 ss7_sms_simulator.py --mode traffic --tps 10 --duration 300

# Interactive mode
python3 ss7_sms_simulator.py --mode interactive
```

## 🔧 Configuration

### **SS7 Stack Configuration (`osmo-stp.cfg`)**
- **Point Code**: 0.23.1 (ITU format)
- **M3UA Port**: 2905 (SCTP/TCP)
- **VTY Port**: 4239 (Management interface)
- **SCCP Port**: 14001 (Connection control)
- **ASP Configuration**: Dynamic connections permitted
- **Routing**: Dynamic key allocation enabled

### **Network Configuration**
- **Docker Network**: ss7-network (172.20.0.0/16)
- **Service Discovery**: Container name resolution
- **Port Mapping**: Host to container port forwarding
- **Volume Mounts**: Persistent log storage

## 🚨 Troubleshooting

### **Service Startup Issues**
```bash
# Check if all containers are running
docker-compose ps

# View startup logs
docker-compose logs osmo-stp

# Check container health
docker-compose exec osmo-stp ps aux
```

### **Dashboard Connection Issues**
```bash
# Test VTY proxy connectivity
curl http://localhost:5000/health

# Check proxy logs
docker-compose logs vty-proxy

# Test direct VTY connection
telnet localhost 4239
```

### **Port Conflicts**
If ports are already in use, modify `docker-compose.yml`:
```yaml
ports:
  - "18888:80"   # Changed dashboard port
  - "19999:80"   # Changed SMS simulator port
  - "15000:5000" # Changed VTY proxy port
```

### **Build Failures**
```bash
# Clean rebuild
docker-compose down -v
docker system prune -f
docker-compose build --no-cache
docker-compose up -d
```

### **VTY Connection Problems**
```bash
# Check osmo-stp is accepting connections
docker-compose exec osmo-stp netstat -tlnp | grep 4239

# Test internal connectivity
docker-compose exec vty-proxy telnet osmo-stp 4239

# Check firewall rules
sudo ufw status
```

## 🔒 Security Considerations

### **Development vs Production**
- **Current setup**: Development/testing environment
- **VTY interface**: No authentication (bind 0.0.0.0)
- **Web interfaces**: HTTP only (no HTTPS)
- **Docker network**: Isolated but not hardened

### **Production Recommendations**
- **Enable VTY authentication**: Configure passwords
- **Use HTTPS**: Add SSL certificates
- **Restrict binding**: Change from 0.0.0.0 to specific IPs
- **Firewall rules**: Limit access to management ports
- **Log monitoring**: Implement centralized logging
- **Regular updates**: Keep containers and dependencies updated

## 📈 Performance Tuning

### **SMS Traffic Optimization**
- **Adjust TPS rates**: Based on system capabilities
- **Monitor resource usage**: `docker stats`
- **Tune error rates**: For realistic simulation
- **Batch operations**: Use bulk SMS for high volume

### **System Resource Management**
```bash
# Monitor container resources
docker stats

# Adjust container limits in docker-compose.yml
services:
  osmo-stp:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
```

### **Log Management**
```bash
# Rotate logs to prevent disk space issues
docker-compose logs --tail=1000 > logs/archive.log

# Clean old containers and images
docker system prune -f
```

## 🧪 Testing Scenarios

### **Basic Functionality Test**
1. Deploy stack with `./deploy.sh`
2. Verify all services are running
3. Access dashboard at http://localhost:8888
4. Check VTY connection status
5. Send test SMS via simulator

### **Load Testing**
1. Configure SMS simulator for high TPS
2. Monitor system resources during load
3. Verify SS7 stack handles traffic correctly
4. Check for memory leaks or crashes

### **Failover Testing**
1. Stop osmo-stp container: `docker stop osmo-stp`
2. Verify dashboard shows disconnected status
3. Restart container: `docker start osmo-stp`
4. Confirm dashboard reconnects automatically

## 📚 Additional Resources

### **Osmocom Documentation**
- [Osmocom Wiki](https://osmocom.org/projects/cellular-infrastructure/wiki)
- [SS7/SIGTRAN Documentation](https://osmocom.org/projects/libosmo-sccp/wiki)
- [VTY Command Reference](https://osmocom.org/projects/osmo-stp/wiki)

### **SS7 Protocol References**
- ITU-T Q.700 series recommendations
- RFC 4666 (M3UA specification)
- RFC 3868 (SUA specification)

### **Docker Resources**
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Docker Networking](https://docs.docker.com/network/)
- [Container Health Checks](https://docs.docker.com/engine/reference/builder/#healthcheck)

## 🤝 Contributing

### **Development Setup**
1. Fork the repository
2. Create feature branch
3. Make changes and test thoroughly
4. Submit pull request with detailed description

### **Reporting Issues**
- Include full error logs
- Describe reproduction steps
- Specify environment details (macOS version, Docker version)
- Attach relevant configuration files

## 📄 License

This project is provided as-is for educational and testing purposes. Please ensure compliance with local regulations when using SS7 testing tools.

## 🏆 Acknowledgments

- **Osmocom Project**: For providing open-source SS7 implementation
- **Docker Community**: For containerization platform
- **Flask Framework**: For web proxy capabilities

---

**🎉 You now have a complete, production-ready SS7 testing environment!**

- **Monitor**: http://localhost:8888
- **Test SMS**: http://localhost:9999  
- **API Access**: http://localhost:5000
- **Direct VTY**: `telnet localhost 4239`