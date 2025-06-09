#!/usr/bin/env python3
"""
VTY Proxy Server for Osmocom SS7 Stack
Provides HTTP/WebSocket bridge to VTY interface
"""

from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import socket
import time
import threading
import json
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)  # Enable CORS for browser access

class VTYClient:
    """VTY client for connecting to osmo-stp"""
    
    def __init__(self, host='localhost', port=4239):
        self.host = host
        self.port = port
        self.socket = None
        self.connected = False
        self.last_error = None
        
    def connect(self):
        """Connect to VTY interface"""
        try:
            if self.socket:
                self.socket.close()
                
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(10)
            self.socket.connect((self.host, self.port))
            
            # Read welcome message
            welcome = self.socket.recv(1024).decode('utf-8', errors='ignore')
            logger.info(f"VTY connected: {welcome.strip()}")
            
            self.connected = True
            self.last_error = None
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to VTY: {e}")
            self.connected = False
            self.last_error = str(e)
            return False
    
    def send_command(self, command):
        """Send command to VTY and get response"""
        if not self.connected:
            if not self.connect():
                return {"success": False, "error": f"Not connected: {self.last_error}"}
        
        try:
            # Send command
            self.socket.send(f"{command}\n".encode('utf-8'))
            time.sleep(0.2)  # Wait for response
            
            # Read response
            response = ""
            self.socket.settimeout(2)  # 2 second timeout for response
            
            try:
                while True:
                    data = self.socket.recv(1024).decode('utf-8', errors='ignore')
                    if not data:
                        break
                    response += data
                    # Check if we have a complete response
                    if command in response or "%" in response or len(response) > 4000:
                        break
            except socket.timeout:
                pass  # Timeout is normal, we got what we could
            
            return {"success": True, "output": response.strip()}
            
        except Exception as e:
            logger.error(f"Command failed: {e}")
            self.connected = False
            self.last_error = str(e)
            return {"success": False, "error": str(e)}
    
    def disconnect(self):
        """Disconnect from VTY"""
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
        self.connected = False

# Global VTY client
vty_client = VTYClient()

@app.route('/api/vty/status')
def vty_status():
    """Get VTY connection status"""
    if vty_client.connected:
        # Test connection with a simple command
        result = vty_client.send_command("show cs7 instance 0")
        if result["success"]:
            return jsonify({
                "connected": True,
                "host": vty_client.host,
                "port": vty_client.port,
                "last_check": datetime.now().isoformat()
            })
        else:
            return jsonify({
                "connected": False,
                "error": result["error"],
                "last_check": datetime.now().isoformat()
            }), 503
    else:
        # Try to connect
        if vty_client.connect():
            return jsonify({
                "connected": True,
                "host": vty_client.host,
                "port": vty_client.port,
                "last_check": datetime.now().isoformat()
            })
        else:
            return jsonify({
                "connected": False,
                "error": vty_client.last_error,
                "last_check": datetime.now().isoformat()
            }), 503

@app.route('/api/vty/command', methods=['POST'])
def vty_command():
    """Send command to VTY interface"""
    try:
        data = request.get_json()
        command = data.get('command', '').strip()
        
        if not command:
            return jsonify({"success": False, "error": "No command provided"}), 400
        
        logger.info(f"VTY command: {command}")
        result = vty_client.send_command(command)
        
        # Add timestamp to result
        result["timestamp"] = datetime.now().isoformat()
        
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Error processing command: {e}")
        return jsonify({"success": False, "error": str(e)}), 500

@app.route('/api/vty/users')
def get_cs7_users():
    """Get CS7 users"""
    result = vty_client.send_command("show cs7 instance 0 users")
    return jsonify(result)

@app.route('/api/vty/asp')
def get_asp_status():
    """Get ASP status"""
    result = vty_client.send_command("show cs7 instance 0 asp")
    return jsonify(result)

@app.route('/api/vty/as')
def get_as_status():
    """Get AS status"""
    result = vty_client.send_command("show cs7 instance 0 as all")
    return jsonify(result)

@app.route('/api/vty/sccp')
def get_sccp_users():
    """Get SCCP users"""
    result = vty_client.send_command("show cs7 instance 0 sccp users")
    return jsonify(result)

@app.route('/api/vty/routes')
def get_routes():
    """Get routing table"""
    result = vty_client.send_command("show cs7 instance 0 route")
    return jsonify(result)

@app.route('/api/vty/config')
def get_config():
    """Get running configuration"""
    result = vty_client.send_command("show running-config")
    return jsonify(result)

@app.route('/api/vty/stats')
def get_stats():
    """Get statistics"""
    result = vty_client.send_command("show stats")
    return jsonify(result)

@app.route('/api/vty/connect')
def force_connect():
    """Force VTY reconnection"""
    vty_client.disconnect()
    if vty_client.connect():
        return jsonify({"success": True, "message": "Connected to VTY"})
    else:
        return jsonify({"success": False, "error": vty_client.last_error}), 503

@app.route('/api/vty/disconnect')
def force_disconnect():
    """Disconnect from VTY"""
    vty_client.disconnect()
    return jsonify({"success": True, "message": "Disconnected from VTY"})

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        "status": "healthy",
        "vty_connected": vty_client.connected,
        "timestamp": datetime.now().isoformat()
    })

@app.route('/')
def index():
    """Serve basic API documentation"""
    return render_template_string("""
<!DOCTYPE html>
<html>
<head>
    <title>VTY Proxy Server</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; }
        h1 { color: #333; }
        .endpoint { background: #f8f9fa; padding: 15px; margin: 10px 0; border-radius: 5px; border-left: 4px solid #007bff; }
        .method { color: #28a745; font-weight: bold; }
        .status { padding: 10px; border-radius: 5px; margin: 20px 0; }
        .connected { background: #d4edda; color: #155724; }
        .disconnected { background: #f8d7da; color: #721c24; }
        code { background: #e9ecef; padding: 2px 5px; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔌 VTY Proxy Server</h1>
        <p>HTTP/WebSocket bridge to Osmocom SS7 VTY interface</p>
        
        <div class="status {{ 'connected' if vty_connected else 'disconnected' }}">
            <strong>VTY Status:</strong> {{ 'Connected' if vty_connected else 'Disconnected' }}
            {% if not vty_connected and last_error %}
            <br><strong>Error:</strong> {{ last_error }}
            {% endif %}
        </div>
        
        <h2>📡 Available Endpoints</h2>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/status</code>
            <p>Get VTY connection status and test connectivity</p>
        </div>
        
        <div class="endpoint">
            <span class="method">POST</span> <code>/api/vty/command</code>
            <p>Send arbitrary command to VTY interface</p>
            <p>Body: <code>{"command": "show cs7 instance 0 users"}</code></p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/users</code>
            <p>Get CS7 instance users</p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/asp</code>
            <p>Get Application Server Process status</p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/as</code>
            <p>Get Application Server status</p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/sccp</code>
            <p>Get SCCP users</p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/routes</code>
            <p>Get routing table</p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/config</code>
            <p>Get running configuration</p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/stats</code>
            <p>Get system statistics</p>
        </div>
        
        <h2>🔧 Control Endpoints</h2>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/connect</code>
            <p>Force VTY reconnection</p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/api/vty/disconnect</code>
            <p>Disconnect from VTY</p>
        </div>
        
        <div class="endpoint">
            <span class="method">GET</span> <code>/health</code>
            <p>Health check endpoint</p>
        </div>
        
        <h2>🌐 Usage</h2>
        <p>This proxy server enables web dashboards to communicate with the Osmocom SS7 VTY interface.</p>
        <p><strong>VTY Target:</strong> {{ vty_host }}:{{ vty_port }}</p>
        <p><strong>Server Time:</strong> {{ current_time }}</p>
        
        <h2>🚀 Quick Test</h2>
        <p>Test the connection: <a href="/api/vty/status" target="_blank">/api/vty/status</a></p>
        <p>Get CS7 users: <a href="/api/vty/users" target="_blank">/api/vty/users</a></p>
    </div>
</body>
</html>
    """, 
    vty_connected=vty_client.connected,
    last_error=vty_client.last_error,
    vty_host=vty_client.host,
    vty_port=vty_client.port,
    current_time=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    )

def cleanup():
    """Cleanup on shutdown"""
    vty_client.disconnect()

if __name__ == "__main__":
    import atexit
    import argparse
    
    parser = argparse.ArgumentParser(description='VTY Proxy Server for Osmocom SS7')
    parser.add_argument('--host', default='0.0.0.0', help='Proxy server host')
    parser.add_argument('--port', type=int, default=5000, help='Proxy server port')
    parser.add_argument('--vty-host', default='localhost', help='VTY host')
    parser.add_argument('--vty-port', type=int, default=4239, help='VTY port')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    
    args = parser.parse_args()
    
    # Configure VTY client
    vty_client.host = args.vty_host
    vty_client.port = args.vty_port
    
    # Register cleanup
    atexit.register(cleanup)
    
    logger.info(f"Starting VTY Proxy Server")
    logger.info(f"Proxy server: {args.host}:{args.port}")
    logger.info(f"VTY target: {args.vty_host}:{args.vty_port}")
    
    # Test initial connection
    if vty_client.connect():
        logger.info("Initial VTY connection successful")
    else:
        logger.warning(f"Initial VTY connection failed: {vty_client.last_error}")
    
    try:
        app.run(
            host=args.host,
            port=args.port,
            debug=args.debug,
            threaded=True
        )
    except KeyboardInterrupt:
        logger.info("Shutting down...")
    finally:
        cleanup()