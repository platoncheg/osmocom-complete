#!/usr/bin/env python3
"""
SS7 SMS Simulator for Osmocom Stack
Interfaces with osmo-stp via VTY and simulates SMS traffic
"""

import socket
import time
import threading
import json
import random
import argparse
from datetime import datetime
from dataclasses import dataclass
from typing import List, Optional
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('sms_simulator.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class SMSMessage:
    """SMS Message data structure"""
    id: int
    from_number: str
    to_number: str
    text: str
    message_type: str = "SMS-SUBMIT"
    encoding: str = "GSM7"
    smsc: str = "+1234567000"
    priority: str = "normal"
    timestamp: datetime = None
    status: str = "pending"
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()

class VTYConnection:
    """VTY connection handler for osmo-stp"""
    
    def __init__(self, host='localhost', port=4239):
        self.host = host
        self.port = port
        self.socket = None
        self.connected = False
        
    def connect(self):
        """Connect to VTY interface"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.settimeout(10)
            self.socket.connect((self.host, self.port))
            
            # Read welcome message
            response = self.socket.recv(1024).decode('utf-8')
            logger.info(f"VTY connected: {response.strip()}")
            
            self.connected = True
            return True
            
        except Exception as e:
            logger.error(f"Failed to connect to VTY: {e}")
            return False
    
    def send_command(self, command: str) -> str:
        """Send command to VTY and get response"""
        if not self.connected:
            if not self.connect():
                return "ERROR: Not connected"
        
        try:
            self.socket.send(f"{command}\n".encode('utf-8'))
            time.sleep(0.1)  # Small delay for response
            response = self.socket.recv(4096).decode('utf-8')
            return response.strip()
            
        except Exception as e:
            logger.error(f"Command failed: {e}")
            self.connected = False
            return f"ERROR: {e}"
    
    def get_status(self) -> dict:
        """Get SS7 stack status"""
        status = {}
        
        # Get CS7 instance status
        cs7_users = self.send_command("show cs7 instance 0 users")
        status['cs7_users'] = cs7_users
        
        # Get ASP status
        asp_status = self.send_command("show cs7 instance 0 asp")
        status['asp_status'] = asp_status
        
        # Get AS status
        as_status = self.send_command("show cs7 instance 0 as all")
        status['as_status'] = as_status
        
        return status
    
    def disconnect(self):
        """Disconnect from VTY"""
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
        self.connected = False

class SMSSimulator:
    """Main SMS simulator class"""
    
    def __init__(self):
        self.vty = VTYConnection()
        self.messages: List[SMSMessage] = []
        self.message_id = 1
        self.stats = {
            'sent': 0,
            'received': 0,
            'failed': 0,
            'total': 0
        }
        self.running = False
        self.traffic_thread = None
        
        # SMS templates
        self.templates = {
            'welcome': "Welcome to our network! Your account is now active.",
            'otp': "Your verification code is: {code}. Valid for 10 minutes.",
            'promo': "🎉 Special offer! Get 50% off. Use code SAVE50.",
            'alert': "⚠️ System maintenance tonight 2-4 AM EST.",
            'balance': "Account Balance: ${balance}. Last transaction: ${amount}.",
            'unicode': "Test: 你好! Hola! Привет! 😀📱🌍"
        }
    
    def generate_random_number(self, prefix="+1234") -> str:
        """Generate random phone number"""
        suffix = str(random.randint(100000, 999999))
        return f"{prefix}{suffix}"
    
    def create_sms(self, from_num: str, to_num: str, text: str, **kwargs) -> SMSMessage:
        """Create SMS message"""
        sms = SMSMessage(
            id=self.message_id,
            from_number=from_num,
            to_number=to_num,
            text=text,
            **kwargs
        )
        self.message_id += 1
        return sms
    
    def send_sms(self, sms: SMSMessage) -> bool:
        """Simulate sending SMS through SS7 stack"""
        try:
            # Log the SMS attempt
            logger.info(f"Sending SMS {sms.id}: {sms.from_number} -> {sms.to_number}")
            logger.debug(f"Message: {sms.text[:50]}...")
            
            # Simulate network processing time
            time.sleep(random.uniform(0.1, 0.5))
            
            # Simulate success/failure (95% success rate)
            success = random.random() > 0.05
            
            if success:
                sms.status = "sent"
                self.stats['sent'] += 1
                logger.info(f"SMS {sms.id} sent successfully")
                
                # Simulate delivery report
                threading.Timer(
                    random.uniform(1, 3),
                    self._delivery_report,
                    args=[sms.id]
                ).start()
                
            else:
                sms.status = "failed"
                self.stats['failed'] += 1
                logger.warning(f"SMS {sms.id} failed to send")
            
            self.messages.append(sms)
            self.stats['total'] += 1
            
            return success
            
        except Exception as e:
            logger.error(f"Error sending SMS {sms.id}: {e}")
            sms.status = "error"
            self.stats['failed'] += 1
            return False
    
    def _delivery_report(self, message_id: int):
        """Simulate delivery report"""
        self.stats['received'] += 1
        logger.info(f"Delivery report for SMS {message_id}: DELIVERED")
    
    def send_template_sms(self, template_name: str, from_num: str, to_num: str, **placeholders) -> bool:
        """Send SMS using template"""
        if template_name not in self.templates:
            logger.error(f"Template '{template_name}' not found")
            return False
        
        text = self.templates[template_name]
        
        # Replace placeholders
        if placeholders:
            try:
                text = text.format(**placeholders)
            except KeyError as e:
                logger.error(f"Missing placeholder {e} for template '{template_name}'")
                return False
        
        sms = self.create_sms(from_num, to_num, text)
        return self.send_sms(sms)
    
    def send_bulk_sms(self, count: int, from_num: str = None, template: str = 'welcome'):
        """Send bulk SMS messages"""
        logger.info(f"Starting bulk SMS send: {count} messages")
        
        if from_num is None:
            from_num = self.generate_random_number("+1234")
        
        success_count = 0
        for i in range(count):
            to_num = self.generate_random_number("+0987")
            
            if template in self.templates:
                placeholders = {}
                if template == 'otp':
                    placeholders['code'] = str(random.randint(100000, 999999))
                elif template == 'balance':
                    placeholders['balance'] = f"{random.uniform(10, 100):.2f}"
                    placeholders['amount'] = f"{random.uniform(1, 20):.2f}"
                
                if self.send_template_sms(template, from_num, to_num, **placeholders):
                    success_count += 1
            else:
                text = f"Bulk message #{i+1} from SMS simulator"
                sms = self.create_sms(from_num, to_num, text)
                if self.send_sms(sms):
                    success_count += 1
            
            # Small delay between messages
            time.sleep(0.1)
        
        logger.info(f"Bulk SMS completed: {success_count}/{count} successful")
        return success_count
    
    def start_traffic_generator(self, tps: int = 5, duration: int = 60):
        """Start continuous traffic generation"""
        if self.running:
            logger.warning("Traffic generator already running")
            return
        
        logger.info(f"Starting traffic generator: {tps} TPS for {duration} seconds")
        self.running = True
        
        def traffic_worker():
            end_time = time.time() + duration
            interval = 1.0 / tps
            
            while self.running and time.time() < end_time:
                start_time = time.time()
                
                # Generate random SMS
                from_num = self.generate_random_number("+1234")
                to_num = self.generate_random_number("+0987")
                
                # Random template
                template = random.choice(list(self.templates.keys()))
                self.send_template_sms(template, from_num, to_num, 
                                     code=str(random.randint(100000, 999999)),
                                     balance=f"{random.uniform(10, 100):.2f}",
                                     amount=f"{random.uniform(1, 20):.2f}")
                
                # Maintain TPS rate
                elapsed = time.time() - start_time
                sleep_time = max(0, interval - elapsed)
                time.sleep(sleep_time)
            
            self.running = False
            logger.info("Traffic generator stopped")
        
        self.traffic_thread = threading.Thread(target=traffic_worker)
        self.traffic_thread.start()
    
    def stop_traffic_generator(self):
        """Stop traffic generation"""
        if self.running:
            logger.info("Stopping traffic generator...")
            self.running = False
            if self.traffic_thread:
                self.traffic_thread.join(timeout=5)
        else:
            logger.info("Traffic generator not running")
    
    def get_stats(self) -> dict:
        """Get current statistics"""
        total = max(1, self.stats['total'])  # Avoid division by zero
        success_rate = (self.stats['sent'] / total) * 100
        
        return {
            **self.stats,
            'success_rate': f"{success_rate:.1f}%",
            'total_processed': len(self.messages)
        }
    
    def get_ss7_status(self) -> dict:
        """Get SS7 stack status via VTY"""
        if not self.vty.connected:
            self.vty.connect()
        
        return self.vty.get_status()
    
    def export_log(self, filename: str = None):
        """Export message log to file"""
        if filename is None:
            filename = f"sms_log_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        export_data = {
            'metadata': {
                'export_time': datetime.now().isoformat(),
                'total_messages': len(self.messages),
                'statistics': self.get_stats()
            },
            'messages': [
                {
                    'id': msg.id,
                    'from': msg.from_number,
                    'to': msg.to_number,
                    'text': msg.text,
                    'type': msg.message_type,
                    'status': msg.status,
                    'timestamp': msg.timestamp.isoformat()
                } for msg in self.messages
            ]
        }
        
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(export_data, f, indent=2, ensure_ascii=False)
        
        logger.info(f"Log exported to {filename}")
        return filename

def main():
    """Main function with CLI interface"""
    parser = argparse.ArgumentParser(description='SS7 SMS Simulator')
    parser.add_argument('--host', default='localhost', help='VTY host (default: localhost)')
    parser.add_argument('--port', type=int, default=4239, help='VTY port (default: 4239)')
    parser.add_argument('--mode', choices=['interactive', 'bulk', 'traffic'], 
                       default='interactive', help='Operation mode')
    parser.add_argument('--count', type=int, default=10, help='Number of messages for bulk mode')
    parser.add_argument('--tps', type=int, default=5, help='Transactions per second for traffic mode')
    parser.add_argument('--duration', type=int, default=60, help='Duration in seconds for traffic mode')
    parser.add_argument('--template', default='welcome', help='SMS template to use')
    
    args = parser.parse_args()
    
    # Initialize simulator
    simulator = SMSSimulator()
    simulator.vty.host = args.host
    simulator.vty.port = args.port
    
    logger.info("SS7 SMS Simulator starting...")
    
    # Test VTY connection
    if simulator.vty.connect():
        logger.info("Connected to SS7 stack successfully")
        status = simulator.get_ss7_status()
        logger.info("SS7 Status retrieved")
    else:
        logger.warning("Could not connect to SS7 stack, running in simulation mode")
    
    try:
        if args.mode == 'interactive':
            # Interactive mode
            print("\n=== SS7 SMS Simulator ===")
            print("Commands:")
            print("  send <from> <to> <message> - Send single SMS")
            print("  template <name> <from> <to> - Send template SMS")
            print("  bulk <count> [template] - Send bulk SMS")
            print("  traffic <tps> <duration> - Start traffic generator")
            print("  stop - Stop traffic generator")
            print("  stats - Show statistics")
            print("  status - Show SS7 status")
            print("  export - Export log")
            print("  quit - Exit")
            
            while True:
                try:
                    cmd = input("\nsms> ").strip().split()
                    if not cmd:
                        continue
                    
                    if cmd[0] == 'quit':
                        break
                    elif cmd[0] == 'send' and len(cmd) >= 4:
                        from_num, to_num = cmd[1], cmd[2]
                        text = ' '.join(cmd[3:])
                        sms = simulator.create_sms(from_num, to_num, text)
                        simulator.send_sms(sms)
                    elif cmd[0] == 'template' and len(cmd) >= 4:
                        template, from_num, to_num = cmd[1], cmd[2], cmd[3]
                        simulator.send_template_sms(template, from_num, to_num)
                    elif cmd[0] == 'bulk':
                        count = int(cmd[1]) if len(cmd) > 1 else 10
                        template = cmd[2] if len(cmd) > 2 else 'welcome'
                        simulator.send_bulk_sms(count, template=template)
                    elif cmd[0] == 'traffic' and len(cmd) >= 3:
                        tps, duration = int(cmd[1]), int(cmd[2])
                        simulator.start_traffic_generator(tps, duration)
                    elif cmd[0] == 'stop':
                        simulator.stop_traffic_generator()
                    elif cmd[0] == 'stats':
                        stats = simulator.get_stats()
                        print(json.dumps(stats, indent=2))
                    elif cmd[0] == 'status':
                        status = simulator.get_ss7_status()
                        print("SS7 Stack Status:")
                        for key, value in status.items():
                            print(f"{key}: {value}")
                    elif cmd[0] == 'export':
                        filename = simulator.export_log()
                        print(f"Log exported to {filename}")
                    else:
                        print("Invalid command or missing parameters")
                        
                except KeyboardInterrupt:
                    break
                except Exception as e:
                    print(f"Error: {e}")
        
        elif args.mode == 'bulk':
            simulator.send_bulk_sms(args.count, template=args.template)
            
        elif args.mode == 'traffic':
            simulator.start_traffic_generator(args.tps, args.duration)
            
            # Wait for completion
            while simulator.running:
                time.sleep(1)
                if simulator.running:
                    stats = simulator.get_stats()
                    print(f"\rProcessed: {stats['total']}, Success: {stats['sent']}, Failed: {stats['failed']}", end='')
            
            print("\nTraffic generation completed")
    
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
    
    finally:
        simulator.stop_traffic_generator()
        simulator.vty.disconnect()
        
        # Final statistics
        stats = simulator.get_stats()
        logger.info(f"Final statistics: {stats}")
        
        # Auto-export log
        if simulator.messages:
            filename = simulator.export_log()
            logger.info(f"Session log saved to {filename}")

if __name__ == "__main__":
    main()