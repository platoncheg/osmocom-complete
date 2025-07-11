#!/usr/bin/env python3
"""
VTY Proxy Server
HTTP to VTY bridge for Osmocom components
"""

import os
import json
import socket
import time
import threading
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Configuration from environment variables
VTY_HOSTS = {
    'stp': {
        'host': os.getenv('OSMO_STP_HOST', 'osmo-stp'),
        'port': int(os.getenv('OSMO_STP_PORT', '4239')),
        'name': 'OsmoSTP'
    },
    'msc': {
        'host': os.getenv('OSMO_MSC_HOST', 'osmo-msc'),
        'port': int(os.getenv('OSMO_MSC_PORT', '4254')),
        'name': 'OsmoMSC'
    },
    'bsc': {
        'host': os.getenv('OSMO_BSC_HOST', 'osmo-bsc'),
        'port': int(os.getenv('OSMO_BSC_PORT', '4242')),
        'name': 'OsmoBSC'
    },
    'hlr': {
        'host': os.getenv('OSMO_HLR_HOST', 'osmo-hlr'),
        'port': int(os.getenv('OSMO_HLR_PORT', '4258')),
        'name': 'OsmoHLR'
    },
    'mgw': {
        'host': os.getenv('OSMO_MGW_HOST', 'osmo-mgw'),
        'port': int(os.getenv('OSMO_MGW_PORT', '2427')),
        'name': 'OsmoMGW'
    }
}


class VTYConnection:
    def __init__(self, host, port, timeout=5):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.socket = None
        self.connected = False

    def connect(self):
        """Establish VTY connection"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(self.timeout)
            self.socket.connect((self.host, self.port))

            # Read welcome message
            welcome = self.socket.recv(1024).decode('utf-8', errors='ignore')
            self.connected = True
            return True
        except Exception as e:
            print(f"Failed to connect to {self.host}:{self.port}: {e}")
            self.connected = False
            return False

    def send_command(self, command):
        """Send command and get response"""
        if not self.connected:
            if not self.connect():
                return {"error": f"Cannot connect to {self.host}:{self.port}"}

        try:
            # Send command
            self.socket.send(f"{command}\n".encode('utf-8'))

            # Read response
            response = ""
            while True:
                try:
                    data = self.socket.recv(4096).decode('utf-8', errors='ignore')
                    if not data:
                        break
                    response += data

                    # Check for command prompt or timeout
                    if "OpenBSC>" in response or "OsmoMSC>" in response or "OsmoSTP>" in response or "OsmoHLR>" in response or "OsmoMGW>" in response:
                        break
                except socket.timeout:
                    break

            # Clean up response
            lines = response.split('\n')
            # Remove command echo and prompt
            cleaned_lines = []
            for line in lines:
                line = line.strip()
                if line and not line.endswith('>') and line != command:
                    cleaned_lines.append(line)

            return {"output": '\n'.join(cleaned_lines), "success": True}

        except Exception as e:
            self.connected = False
            return {"error": str(e), "success": False}

    def disconnect(self):
        """Close VTY connection"""
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
        self.connected = False


# Global VTY connections
vty_connections = {}


def get_vty_connection(service):
    """Get or create VTY connection for service"""
    if service not in vty_connections:
        if service not in VTY_HOSTS:
            return None

        host_info = VTY_HOSTS[service]
        vty_connections[service] = VTYConnection(host_info['host'], host_info['port'])

    return vty_connections[service]


@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    status = {}
    overall_health = True

    for service, host_info in VTY_HOSTS.items():
        try:
            # Quick TCP connection test
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            result = sock.connect_ex((host_info['host'], host_info['port']))
            sock.close()

            is_healthy = result == 0
            status[service] = {
                'healthy': is_healthy,
                'host': host_info['host'],
                'port': host_info['port'],
                'name': host_info['name']
            }

            if not is_healthy:
                overall_health = False

        except Exception as e:
            status[service] = {
                'healthy': False,
                'error': str(e),
                'host': host_info['host'],
                'port': host_info['port'],
                'name': host_info['name']
            }
            overall_health = False

    return jsonify({
        'status': 'healthy' if overall_health else 'unhealthy',
        'services': status,
        'timestamp': time.time()
    }), 200 if overall_health else 503


@app.route('/api/services', methods=['GET'])
def list_services():
    """List available services"""
    services = []
    for service, host_info in VTY_HOSTS.items():
        services.append({
            'id': service,
            'name': host_info['name'],
            'host': host_info['host'],
            'port': host_info['port']
        })

    return jsonify({'services': services})


@app.route('/api/command', methods=['POST'])
def execute_command():
    """Execute VTY command on specified service"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400

        service = data.get('service', 'stp')
        command = data.get('command', '')

        if not command:
            return jsonify({'error': 'No command provided'}), 400

        # Get VTY connection
        vty = get_vty_connection(service)
        if not vty:
            return jsonify({'error': f'Unknown service: {service}'}), 400

        # Execute command
        result = vty.send_command(command)

        return jsonify({
            'service': service,
            'command': command,
            'result': result,
            'timestamp': time.time()
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/status', methods=['GET'])
def get_status():
    """Get comprehensive status from all services"""
    status = {}

    # Common status commands for each service
    status_commands = {
        'stp': [
            'show cs7 instance 0 users',
            'show cs7 instance 0 asp',
            'show cs7 instance 0 as all'
        ],
        'msc': [
            'show subscribers',
            'show calls',
            'show sms queue',
            'show stats'
        ],
        'bsc': [
            'show bts',
            'show trx',
            'show paging'
        ],
        'hlr': [
            'show subscribers',
            'show stats'
        ],
        'mgw': [
            'show mgcp stats',
            'show stats'
        ]
    }

    for service in VTY_HOSTS.keys():
        service_status = {'connected': False, 'data': {}}

        vty = get_vty_connection(service)
        if vty and vty.connect():
            service_status['connected'] = True

            # Execute status commands
            for cmd in status_commands.get(service, []):
                result = vty.send_command(cmd)
                service_status['data'][cmd] = result

        status[service] = service_status

    return jsonify({
        'status': status,
        'timestamp': time.time()
    })


@app.route('/api/sms/send', methods=['POST'])
def send_sms():
    """Send SMS via MSC - FIXED VERSION"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400

        from_number = data.get('from', '1001')
        to_number = data.get('to', '1002')
        message = data.get('message', 'Test SMS')

        print(f"SMS Request: {from_number} -> {to_number}: {message}")

        # First, check if subscriber exists in HLR
        hlr_vty = get_vty_connection('hlr')
        if hlr_vty:
            subscriber_check = hlr_vty.send_command(f"subscriber show msisdn {to_number}")
            print(f"HLR subscriber check: {subscriber_check}")
            
            if subscriber_check.get('success') and 'No subscriber' in subscriber_check.get('output', ''):
                # Try to create subscriber if not exists
                print(f"Creating subscriber {to_number}")
                imsi = f"001010{to_number.zfill(9)}"  # Generate IMSI
                create_result = hlr_vty.send_command(f"subscriber create imsi {imsi}")
                if create_result.get('success'):
                    # Set MSISDN
                    hlr_vty.send_command(f"subscriber imsi {imsi} update msisdn {to_number}")
                    print(f"Created subscriber {to_number} with IMSI {imsi}")

        # Get MSC VTY connection
        msc_vty = get_vty_connection('msc')
        if not msc_vty:
            return jsonify({'error': 'Cannot connect to MSC'}), 500

        # FIXED: Use correct OsmoMSC SMS command format
        # Try different SMS command formats for OsmoMSC
        sms_commands = [
            f"sms send {to_number} {from_number} {message}",
            f"subscriber msisdn {to_number} sms sender msisdn {from_number} send {message}",
            f"subscriber show msisdn {to_number}"  # Test command to see if subscriber exists
        ]

        result = None
        for cmd in sms_commands:
            print(f"Trying SMS command: {cmd}")
            result = msc_vty.send_command(cmd)
            print(f"SMS command result: {result}")
            
            if result.get('success'):
                # Check if this was the actual SMS send command
                if 'sms send' in cmd.lower() or 'send' in cmd:
                    break
                # If it's a subscriber check and subscriber exists, try to send
                if 'subscriber show' in cmd and 'No subscriber' not in result.get('output', ''):
                    # Subscriber exists, now try to send SMS
                    actual_send = msc_vty.send_command(f"sms send {to_number} {from_number} {message}")
                    if actual_send.get('success'):
                        result = actual_send
                        break

        return jsonify({
            'from': from_number,
            'to': to_number,
            'message': message,
            'result': result,
            'timestamp': time.time()
        })

    except Exception as e:
        print(f"SMS Error: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/api/subscribers', methods=['GET'])
def get_subscribers():
    """Get subscriber list from HLR"""
    try:
        vty = get_vty_connection('hlr')
        if not vty:
            return jsonify({'error': 'Cannot connect to HLR'}), 500

        result = vty.send_command('show subscribers')

        return jsonify({
            'subscribers': result,
            'timestamp': time.time()
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/subscribers/create', methods=['POST'])
def create_subscriber():
    """Create subscriber in HLR"""
    try:
        data = request.get_json()
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400

        msisdn = data.get('msisdn', '')
        imsi = data.get('imsi', '')

        if not msisdn:
            return jsonify({'error': 'MSISDN is required'}), 400

        # Generate IMSI if not provided
        if not imsi:
            imsi = f"001010{msisdn.zfill(9)}"

        hlr_vty = get_vty_connection('hlr')
        if not hlr_vty:
            return jsonify({'error': 'Cannot connect to HLR'}), 500

        # Create subscriber
        create_result = hlr_vty.send_command(f"subscriber create imsi {imsi}")
        if create_result.get('success'):
            # Set MSISDN
            msisdn_result = hlr_vty.send_command(f"subscriber imsi {imsi} update msisdn {msisdn}")
            
        return jsonify({
            'imsi': imsi,
            'msisdn': msisdn,
            'create_result': create_result,
            'timestamp': time.time()
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get statistics from all services"""
    try:
        stats = {}

        for service in VTY_HOSTS.keys():
            vty = get_vty_connection(service)
            if vty and vty.connect():
                result = vty.send_command('show stats')
                stats[service] = result

        return jsonify({
            'stats': stats,
            'timestamp': time.time()
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Endpoint not found'}), 404


@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500


if __name__ == '__main__':
    print("Starting VTY Proxy Server...")
    print("Available services:")
    for service, host_info in VTY_HOSTS.items():
        print(f"  {service}: {host_info['name']} ({host_info['host']}:{host_info['port']})")

    # Clean up connections on exit
    import atexit

    def cleanup():
        for vty in vty_connections.values():
            vty.disconnect()

    atexit.register(cleanup)

    app.run(host='0.0.0.0', port=5000, debug=False)