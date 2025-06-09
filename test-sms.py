#!/usr/bin/env python3
"""
Real SMS Testing Script for Complete Osmocom Network
Tests SMS through the full stack: SMPP -> SMSC -> MAP -> SS7 -> HLR -> MSC
"""

import smpplib.gsm
import smpplib.client
import smpplib.consts
import time
import argparse
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SMSTestClient:
    def __init__(self, host='localhost', port=2775, system_id='test-sms', password='test123'):
        self.host = host
        self.port = port
        self.system_id = system_id
        self.password = password
        self.client = None
        self.connected = False
        
    def connect(self):
        """Connect to SMSC via SMPP"""
        try:
            self.client = smpplib.client.Client(self.host, self.port, 90)
            
            # Set up event handlers
            self.client.set_message_received_handler(self._message_received_handler)
            self.client.set_message_sent_handler(self._message_sent_handler)
            
            # Connect and bind
            self.client.connect()
            self.client.bind_transceiver(system_id=self.system_id, password=self.password)
            
            self.connected = True
            logger.info(f"✅ Connected to SMSC at {self.host}:{self.port}")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to connect to SMSC: {e}")
            self.connected = False
            return False
    
    def _message_received_handler(self, pdu):
        """Handle incoming SMS"""
        logger.info(f"📨 Received SMS: {pdu.short_message}")
        
    def _message_sent_handler(self, pdu):
        """Handle SMS delivery confirmation"""
        logger.info(f"✅ SMS sent successfully, Message ID: {pdu.message_id}")
    
    def send_sms(self, from_number, to_number, message):
        """Send SMS through the complete SS7 stack"""
        if not self.connected:
            logger.error("❌ Not connected to SMSC")
            return False
            
        try:
            logger.info(f"📱 Sending SMS: {from_number} -> {to_number}")
            logger.info(f"📝 Message: {message}")
            
            # Send SMS via SMPP to SMSC
            # SMSC will then:
            # 1. Query HLR via MAP for routing info
            # 2. Send SMS to MSC via MAP
            # 3. MSC delivers to subscriber
            
            parts, encoding_flag, msg_type_flag = smpplib.gsm.make_parts(message)
            
            for part in parts:
                pdu = self.client.send_message(
                    source_addr_ton=smpplib.consts.ADDR_TON_INTL,
                    source_addr_npi=smpplib.consts.ADDR_NPI_ISDN,
                    source_addr=from_number.replace('+', ''),
                    dest_addr_ton=smpplib.consts.ADDR_TON_INTL,
                    dest_addr_npi=smpplib.consts.ADDR_NPI_ISDN,
                    destination_addr=to_number.replace('+', ''),
                    short_message=part,
                    data_coding=encoding_flag,
                    esm_class=msg_type_flag,
                    registered_delivery=smpplib.consts.REG_DELIVERY_SMSC_BOTH,
                )
                
            logger.info("📡 SMS submitted to SMSC for SS7 delivery")
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to send SMS: {e}")
            return False
    
    def send_bulk_sms(self, from_number, recipients, message_template, count=10):
        """Send bulk SMS for load testing"""
        logger.info(f"📦 Starting bulk SMS test: {count} messages")
        
        success_count = 0
        start_time = time.time()
        
        for i in range(count):
            # Use provided recipients or generate test numbers
            if recipients:
                to_number = recipients[i % len(recipients)]
            else:
                to_number = f"+123456789{i:02d}"
            
            message = message_template.format(
                index=i+1,
                timestamp=datetime.now().strftime('%H:%M:%S'),
                to=to_number
            )
            
            if self.send_sms(from_number, to_number, message):
                success_count += 1
                
            # Rate limiting
            time.sleep(0.1)
        
        end_time = time.time()
        duration = end_time - start_time
        tps = count / duration if duration > 0 else 0
        
        logger.info(f"📊 Bulk SMS completed:")
        logger.info(f"   Total: {count}, Success: {success_count}, Failed: {count - success_count}")
        logger.info(f"   Duration: {duration:.2f}s, TPS: {tps:.2f}")
        
        return success_count
    
    def test_subscriber_lookup(self, msisdn):
        """Test HLR subscriber lookup (via separate VTY connection)"""
        import socket
        
        try:
            # Connect to HLR VTY
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.connect(('localhost', 4258))
            
            # Read welcome message
            sock.recv(1024)
            
            # Send subscriber lookup command
            command = f"subscriber msisdn {msisdn} show\n"
            sock.send(command.encode())
            
            # Read response
            response = sock.recv(4096).decode()
            sock.close()
            
            if "IMSI" in response:
                logger.info(f"✅ Subscriber {msisdn} found in HLR")
                logger.info(f"📋 Details: {response.strip()}")
                return True
            else:
                logger.warning(f"⚠️ Subscriber {msisdn} not found in HLR")
                return False
                
        except Exception as e:
            logger.error(f"❌ HLR lookup failed: {e}")
            return False
    
    def disconnect(self):
        """Disconnect from SMSC"""
        if self.client and self.connected:
            try:
                self.client.unbind()
                self.client.disconnect()
                self.connected = False
                logger.info("🔌 Disconnected from SMSC")
            except:
                pass

def main():
    parser = argparse.ArgumentParser(description='Test SMS through complete Osmocom network')
    parser.add_argument('--host', default='localhost', help='SMSC host')
    parser.add_argument('--port', type=int, default=2775, help='SMPP port')
    parser.add_argument('--from', dest='from_number', default='+1234567890', help='Sender number')
    parser.add_argument('--to', dest='to_number', help='Recipient number(s), comma-separated')
    parser.add_argument('--text', default='Test SMS via complete SS7 stack!', help='Message text')
    parser.add_argument('--bulk', type=int, help='Send bulk SMS (specify count)')
    parser.add_argument('--test-hlr', action='store_true', help='Test HLR subscriber lookup')
    parser.add_argument('--system-id', default='test-sms', help='SMPP system ID')
    parser.add_argument('--password', default='test123', help='SMPP password')
    
    args = parser.parse_args()
    
    # Create SMS client
    client = SMSTestClient(args.host, args.port, args.system_id, args.password)
    
    try:
        # Connect to SMSC
        if not client.connect():
            return 1
        
        # Test HLR lookup if requested
        if args.test_hlr:
            test_numbers = ['+1234567890', '+1234567891', '+1234567892']
            if args.to_number:
                test_numbers = args.to_number.split(',')
            
            logger.info("🔍 Testing HLR subscriber lookups...")
            for number in test_numbers:
                client.test_subscriber_lookup(number.strip())
        
        # Send SMS
        if args.bulk:
            # Bulk SMS test
            recipients = args.to_number.split(',') if args.to_number else None
            client.send_bulk_sms(
                args.from_number, 
                recipients, 
                args.text + " (#{index} at {timestamp})",
                args.bulk
            )
        else:
            # Single SMS
            if not args.to_number:
                logger.error("❌ --to number required for single SMS")
                return 1
                
            recipients = args.to_number.split(',')
            for to_number in recipients:
                client.send_sms(args.from_number, to_number.strip(), args.text)
        
        # Wait for delivery reports
        logger.info("⏳ Waiting for delivery reports...")
        time.sleep(5)
        
        logger.info("🎉 SMS test completed!")
        logger.info("📊 Check the following for verification:")
        logger.info("   - SMSC logs: docker-compose logs osmo-smsc")
        logger.info("   - MSC logs: docker-compose logs osmo-msc") 
        logger.info("   - HLR logs: docker-compose logs osmo-hlr")
        logger.info("   - SS7 logs: docker-compose logs osmo-stp")
        
    except KeyboardInterrupt:
        logger.info("🛑 Test interrupted by user")
    except Exception as e:
        logger.error(f"💥 Test failed: {e}")
        return 1
    finally:
        client.disconnect()
    
    return 0

if __name__ == "__main__":
    exit(main())