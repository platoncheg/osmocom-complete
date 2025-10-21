FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg2 \
    git \
    build-essential \
    libtool \
    autoconf \
    automake \
    pkg-config \
    make \
    gcc \
    g++ \
    libfftw3-dev \
    libgsl-dev \
    libusb-1.0-0-dev \
    libtalloc-dev \
    libpcsclite-dev \
    netcat-openbsd \
    telnet \
    && rm -rf /var/lib/apt/lists/*

# Add Osmocom repository
RUN wget -O /etc/apt/trusted.gpg.d/osmocom.asc https://obs.osmocom.org/projects/osmocom/public_key
RUN echo "deb [signed-by=/etc/apt/trusted.gpg.d/osmocom.asc] https://downloads.osmocom.org/packages/osmocom:/latest/xUbuntu_22.04/ ./" > /etc/apt/sources.list.d/osmocom.list

# Install available Osmocom packages
RUN apt-get update && apt-get install -y \
    libosmocore-dev \
    && rm -rf /var/lib/apt/lists/*

# Build missing libosmo-gprs from source
WORKDIR /tmp
RUN git clone https://gitea.osmocom.org/osmocom/libosmo-gprs libosmo-gprs
WORKDIR /tmp/libosmo-gprs
RUN autoreconf -fi && \
    ./configure && \
    make && \
    make install && \
    ldconfig

# Clone OsmocomBB
WORKDIR /opt
RUN git clone https://gitea.osmocom.org/phone-side/osmocom-bb osmocom-bb

WORKDIR /opt/osmocom-bb

# Initialize submodules
RUN git submodule update --init --recursive

# Build OsmocomBB
RUN cd src/host/layer23 && \
    autoreconf -fi && \
    ./configure && \
    make

# Verify mobile binary was built
RUN ls -la /opt/osmocom-bb/src/host/layer23/src/mobile/mobile

# Create directories
RUN mkdir -p /data

# Copy configuration file
COPY config/mobile.cfg /data/mobile.cfg

# Create symlink to mobile binary
RUN ln -sf /opt/osmocom-bb/src/host/layer23/src/mobile/mobile /usr/local/bin/mobile

# Set working directory
WORKDIR /opt/osmocom-bb/src/host/layer23/src/mobile

EXPOSE 4247

# Create volume for persistent data
VOLUME ["/data"]

# Run mobile with config file
CMD ["./mobile", "-c", "/data/mobile.cfg"]