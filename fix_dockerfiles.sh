#!/bin/bash

# Script to completely replace problematic Dockerfiles with working versions in the docker/ directory

echo "🔧 Fixing Dockerfiles in docker/ directory with correct repository configuration..."

# Create docker directory if it doesn't exist
mkdir -p docker

# Remove all existing Dockerfiles to force rebuild
rm -f docker/Dockerfile.* 2>/dev/null || true

# Create STP Dockerfile
cat > docker/Dockerfile.stp << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository with correct URL and GPG key
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key

RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list

RUN apt-get update && apt-get install -y \
    osmo-stp \
    && rm -rf /var/lib/apt/lists/*

COPY /config/osmo-stp.cfg /etc/osmocom/osmo-stp.cfg

EXPOSE 4239 2905 14001

CMD ["osmo-stp", "-c", "/etc/osmocom/osmo-stp.cfg"]
EOF

# Create HLR Dockerfile
cat > docker/Dockerfile.hlr << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository with correct URL and GPG key
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key

RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list

RUN apt-get update && apt-get install -y \
    osmo-hlr \
    && rm -rf /var/lib/apt/lists/*

COPY /config/osmo-hlr.cfg /etc/osmocom/osmo-hlr.cfg

EXPOSE 4258

CMD ["osmo-hlr", "-c", "/etc/osmocom/osmo-hlr.cfg"]
EOF

# Create MGW Dockerfile
cat > docker/Dockerfile.mgw << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository with correct URL and GPG key
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key

RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list

RUN apt-get update && apt-get install -y \
    osmo-mgw \
    && rm -rf /var/lib/apt/lists/*

COPY /config/osmo-mgw.cfg /etc/osmocom/osmo-mgw.cfg

EXPOSE 2427

CMD ["osmo-mgw", "-c", "/etc/osmocom/osmo-mgw.cfg"]
EOF

# Create MSC Dockerfile
cat > docker/Dockerfile.msc << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository with correct URL and GPG key
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key

RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list

RUN apt-get update && apt-get install -y \
    osmo-msc \
    && rm -rf /var/lib/apt/lists/*

COPY /config/osmo-msc.cfg /etc/osmocom/osmo-msc.cfg

EXPOSE 4254

CMD ["osmo-msc", "-c", "/etc/osmocom/osmo-msc.cfg"]
EOF

# Create BSC Dockerfile
cat > docker/Dockerfile.bsc << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository with correct URL and GPG key
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key

RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list

RUN apt-get update && apt-get install -y \
    osmo-bsc \
    && rm -rf /var/lib/apt/lists/*

COPY /config/osmo-bsc.cfg /etc/osmocom/osmo-bsc.cfg

EXPOSE 4242

CMD ["osmo-bsc", "-c", "/etc/osmocom/osmo-bsc.cfg"]
EOF

# Create VTY Proxy Dockerfile
cat > docker/Dockerfile.proxy << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY /scripts/vty_proxy.py /app/

RUN pip install --break-system-packages flask requests

EXPOSE 5000

CMD ["python", "vty_proxy.py"]
EOF

# Create Dashboard Dockerfile
cat > docker/Dockerfile.dashboard << 'EOF'
FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*

COPY /web/dashboard.html /usr/share/nginx/html/index.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

# Create SMS Simulator Dockerfile (no Python to avoid pip issues)
cat > docker/Dockerfile.sms << 'EOF'
FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*

COPY /web/sms_simulator.html /usr/share/nginx/html/index.html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

echo "✅ Created docker/Dockerfile.stp"
echo "✅ Created docker/Dockerfile.hlr"
echo "✅ Created docker/Dockerfile.mgw"
echo "✅ Created docker/Dockerfile.msc"
echo "✅ Created docker/Dockerfile.bsc"
echo "✅ Created docker/Dockerfile.proxy"
echo "✅ Created docker/Dockerfile.dashboard"
echo "✅ Created docker/Dockerfile.sms"
echo ""
echo "🧹 Cleaning Docker cache..."
docker system prune -f 2>/dev/null || true

echo ""
echo "✨ All Dockerfiles fixed in docker/ directory! Now run:"
echo "   docker-compose build --no-cache"
echo "   docker-compose up -d"