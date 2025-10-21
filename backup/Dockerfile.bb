FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    git \
    build-essential \
    libtool \
    autoconf \
    automake \
    pkg-config \
    libosmocore-dev \
    libfftw3-dev \
    libtalloc-dev \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository for dependencies
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key
RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list

RUN apt-get update && apt-get install -y \
    libosmocore-dev \
    libfftw3-dev \
    libtalloc-dev \
    && rm -rf /var/lib/apt/lists/*

# Clone and build OsmocomBB
RUN git clone https://gitea.osmocom.org/phone-side/osmocom-bb /osmocom-bb
WORKDIR /osmocom-bb


# Create directory for config and data
RUN mkdir -p /data
RUN mkdir -p /tmp

# Copy configuration file
COPY config/mobile.cfg /data/mobile.cfg

EXPOSE 4247

WORKDIR /osmocom-bb/src/host/layer23/src/mobile

# Create volume for persistent data
VOLUME ["/data"]

# Run mobile with config file
CMD ["./mobile", "-i", "eth0", "-c", "/data/mobile.cfg"]