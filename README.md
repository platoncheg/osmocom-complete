# osmocom-complete

A dockerized GSM/SS7 lab environment based on the Osmocom open-source stack. Runs a complete GSM core network in containers. Intended for learning, protocol testing, and development. No real radio hardware is required; OsmocomBB acts as a software mobile station emulator.

## Architecture

```
OsmocomBB (MS emulator)
        |
    osmo-bts (virtual BTS)
        |
    osmo-bsc (BSC) ── osmo-mgw (media gateway)
        |                      |
    osmo-msc (MSC/SMSC) ───────┘
        |
    osmo-hlr (HLR, SQLite)
        |
    osmo-stp (SS7 STP)
```

A Flask-based VTY proxy bridges HTTP to the telnet VTY interfaces of all services. A static web dashboard and SMS simulator UI are served via nginx.

Network: `172.20.0.0/24` (Docker bridge)

## Prerequisites

- Docker >= 20.10
- Docker Compose >= 1.29
- Ports 5000, 8888, 9999, 2427, 2775, 2905, 3002, 4222, 4239, 4241, 4242, 4247, 4254, 4258, 14001 available on the host

## Quick Start

```bash
git clone https://github.com/platoncheg/osmocom-complete
cd osmocom-complete
./deploy.sh
```

`deploy.sh` runs `docker-compose down -v`, prunes images, builds with `--no-cache`, and starts all services.

Once running:
- Web dashboard: http://localhost:8888
- SMS simulator: http://localhost:9999
- VTY proxy API: http://localhost:5000

## Services and Ports

| Service        | IP            | VTY Port | Primary Port                          | Role                          |
|----------------|---------------|----------|---------------------------------------|-------------------------------|
| osmo-stp       | 172.20.0.10   | 4239     | 2905/sctp (M3UA), 14001 (SCCP)        | SS7 Signaling Transfer Point  |
| osmo-hlr       | 172.20.0.20   | 4258     | 4222 (GSUP)                           | Home Location Register        |
| osmo-mgw       | 172.20.0.30   | 2427     | 2728 (MGCP), 16000-16099/udp (RTP)    | Media Gateway                 |
| osmo-msc       | 172.20.0.40   | 4254     | 2775 (SMPP)                           | Mobile Switching Center / SMSC|
| osmo-bsc       | 172.20.0.50   | 4242     | 3002 (Abis/IP)                        | Base Station Controller       |
| osmo-bts       | 172.20.0.60   | 4241     | 6700-6710/udp (TRX)                   | Virtual BTS                   |
| osmocom-bb     | 172.20.0.70   | 4247     | —                                     | MS emulator                   |
| vty-proxy      | 172.20.0.100  | —        | 5000 (HTTP)                           | HTTP-to-VTY bridge            |
| web-dashboard  | 172.20.0.110  | —        | 8888 (HTTP)                           | Static dashboard (nginx)      |
| sms-simulator  | 172.20.0.120  | —        | 9999 (HTTP)                           | SMS simulator UI (nginx)      |

## Management Scripts

| Script        | Purpose                                      | Notable Flags                               |
|---------------|----------------------------------------------|---------------------------------------------|
| `deploy.sh`   | Full clean rebuild and start                 | —                                           |
| `startup.sh`  | Start in dependency order with health polling| `--core-only`, `--no-web`, `--force`        |
| `shutdown.sh` | Stop in reverse order                        | `--yes`, `--force`, `--clean`, `--web-only` |
| `status.sh`   | Comprehensive status                         | —                                           |
| `logs.sh`     | View service logs                            | —                                           |
| `restart.sh`  | Restart services                             | —                                           |

## VTY Proxy API

Base URL: `http://localhost:5000`

| Method | Endpoint                  | Description                                  |
|--------|---------------------------|----------------------------------------------|
| GET    | `/health`                 | TCP connectivity check for all services      |
| GET    | `/api/services`           | List configured services                     |
| POST   | `/api/command`            | Send arbitrary VTY command to a service      |
| GET    | `/api/status`             | Run standard status commands on all services |
| GET    | `/api/subscribers`        | `show subscribers` on HLR                   |
| POST   | `/api/subscribers/create` | Create a subscriber in HLR                  |
| POST   | `/api/sms/send`           | Send an SMS via MSC                          |
| GET    | `/api/stats`              | `show stats` on all services                 |

```bash
# Send a VTY command
curl -s -X POST http://localhost:5000/api/command \
  -H 'Content-Type: application/json' \
  -d '{"service": "msc", "command": "show subscribers"}'

# Create a subscriber
curl -s -X POST http://localhost:5000/api/subscribers/create \
  -H 'Content-Type: application/json' \
  -d '{"msisdn": "1001", "imsi": "001010000001001"}'

# Send an SMS
curl -s -X POST http://localhost:5000/api/sms/send \
  -H 'Content-Type: application/json' \
  -d '{"from": "1001", "to": "1002", "message": "hello"}'
```

## Configuration

Key parameters from the shipped config files:

- MCC/MNC: 001/01
- Band: DCS1800, ARFCN 871
- TRX: single TRX, 8 timeslots — 1x CCCH+SDCCH4, 7x TCH/F
- Authentication: optional (disabled by default)
- Encryption: A5/0 (no encryption)
- GPRS: disabled (`gprs mode none`)
- SS7 point codes: STP=0.23.1, MSC=0.23.2, BSC=0.23.3

The HLR SQLite database (`data/hlr.db`) is committed to the repository with pre-provisioned test subscribers.

## Limitations

- **No real radio.** OsmocomBB runs as a software emulator only.
- **No GPRS/data.** Voice and SMS only.
- **No security hardening.** VTY has no auth, encryption is A5/0. Do not expose on an untrusted network.
- **hlr.db is committed to the repo.** It resets on `docker-compose down -v` or a clean deploy.
- **sms_simulator.py duplicates vty_proxy.py.** Known issue.
- **Web UI depends on vty-proxy.** Dashboard and SMS simulator do not function if the proxy is unhealthy.
